# Failure modes, evidence, and forensics

Everything here was measured on Linux Mint 22, Clash Verge Rev v1.19.10 (mihomo v1.19.10),
no TUN device, proxy listening on `127.0.0.1:<proxy-port>`, proxy variables exported into the
shell by `~/.shell_common`. Addresses below are written as `<jp-address>` and similar -- read
them off your own `dig`; the point is which region they land in, not the digits.

## Symptom to layer

| What you see | Layer | Do this |
| :--- | :--- | :--- |
| `ImportError: Using SOCKS proxy, but the 'socksio' package is not installed` | 1 | `env -u` the six variables |
| `curl: (35) SSL connect error` | 1 or 2 | check `remote_ip`; if `127.0.0.1`, it is layer 2 |
| `429 ... 100000 resolver requests per 5 minutes` | neither | mirror rate limit -- back off, do not change routes |
| page renders instantly, the file crawls | 2 | parallel connections, then rules |
| tiny file fine, large file stalls | 2 | parallel connections |

## Layer 1 -- the import crash

`huggingface_hub` is built on `httpx`. `httpx.Client()` reads the proxy environment in its
constructor and, on seeing a `socks5://` or `socks5h://` URL, immediately tries to build the
SOCKS transport. Without the optional `socksio` dependency that raises `ImportError`.

The decisive detail: **this happens before the request URL is ever evaluated.** So a per-domain
allowlist cannot save you, no matter how the domain is spelled.

Measured, httpx 0.28.1, no socks extras:

| Environment | Result |
| :--- | :--- |
| all six variables set | `ImportError ... 'socksio' package is not installed` |
| + `NO_PROXY='*'` | client built, **zero** proxy mounts |
| + `NO_PROXY='hf-mirror.com'` | `ImportError ... 'socksio' package is not installed` |
| `env -u` the six variables | client built, no crash |
| only the four `*_proxy` stripped, `all_proxy` left | `ImportError ... 'socksio' package is not installed` |

That last row is why the recipe strips six and not four.

## Layer 2 -- the routing leak

Rules actually present in `clash-verge.yaml` that matter here:

| Line | Rule | Effect |
| :--- | :--- | :--- |
| 202 | `DOMAIN-SUFFIX,hf-mirror.com,DIRECT` | the mirror page itself goes direct |
| 1496 | `GEOIP,CN,DIRECT` | catches China-geolocated payloads |
| 1498 | `MATCH,Proxy` | catches everything else -- including foreign CDN payloads |

Where the bytes actually come from:

```text
hf-mirror.com                    -> <jp-address>    JP, SAKURA      rule 202 -> DIRECT
  302 -> cas-bridge.xethub.hf.co -> <us-address>    us-east-1, AWS
     path: /xet-bridge-us/...
```

`cas-bridge.xethub.hf.co` matches no rule, and its US address also fails `GEOIP,CN,DIRECT`, so it
falls to `MATCH,Proxy`. Another repository redirects to `us.aws.cdn.hf.co` instead -- the hostname
varies by backend, the shape does not.

A subscription that already carries a `webnote.cc` DIRECT line plus a hand-added duplicate of the
same line was observed here. That duplication is the signature of a manual edit inside the
subscription YAML, which the next update discards. Put rules in the pre-rules / subscription
extension script instead.

## Throughput

Same repository, same 100 MB range request, same minute:

| Path | Bytes | Time | Speed |
| :--- | :---: | :---: | :---: |
| direct (`env -u`) | 104857600 | 74.1 s | 1.35 MB/s |
| proxied (default env) | 102579763 | 90 s (hit `--max-time`) | 1.09 MB/s |

Two readings worth keeping:

1. Direct is ~24% faster. It is not the order-of-magnitude difference a crash-recovery narrative
   tends to imply.
2. **Both are around 1 MB/s.** The bottleneck is the `us-east-1` endpoint. Switching routes will
   not make a 15 GB model download fast; parallel connections will.

A small-file sample cannot show this. A 454 KB test file finishes in about a second either way
and tells you nothing about sustained throughput -- a sample that size measures connection setup,
not bandwidth.

Concurrency was not measured here: the mirror started returning `429` during that test. Treat
`aria2c -x 4 -j 5` (the `hfd.sh` default) as the expected fix, not as a verified one.

## Socket forensics

The strongest evidence that a download really went direct, and worth one line of output:

```bash
lsof -p <PID> | grep TCP
```

Direct:

```text
python <pid> <username> 4u IPv4 TCP <lan-ip>:<local-port> -> <mirror-host>:https (ESTABLISHED)
```

Proxied (the shape to watch for):

```text
python <pid> <username> 4u IPv4 TCP <lan-ip>:<local-port> -> 127.0.0.1:<proxy-port> (ESTABLISHED)
```

The source address is the physical NIC; the peer is the mirror host. Both facts have to hold.

Without a running process:

```bash
curl -sI -o /dev/null -w '%{remote_ip}\n' https://hf-mirror.com
```

`127.0.0.1` = went through the proxy. A routable address = direct.

## Redirect inspection

To see the payload host before committing to a long download:

```bash
curl -sL --noproxy '*' -o /dev/null -r 0-1 \
  -w 'final: %{url_effective}\nhops:  %{num_redirects}\npeer:  %{remote_ip}\n' "$URL"
```

`%{url_effective}` names the CDN that will actually serve the bytes -- that is the domain to write
a rule for.

## Rate limiting -- a shared pool, not your account

A `429` from this mirror is almost never caused by your own traffic. Two response headers explain
the whole mechanism:

```text
ratelimit: "resolvers";r=65094;t=220
ratelimit-policy: "fixed window";"resolvers";q=100000;w=300
server: hf-mirror
x-powered-by: huggingface-moon
```

- `q=100000` quota, `w=300` a **five-minute fixed window** (not sliding -- it resets on a wall-clock
  boundary, so `t` counts down to it)
- `r` remaining, `t` seconds until reset
- `x-powered-by: huggingface-moon` -- the counter belongs to **HuggingFace upstream**, keyed to
  **hf-mirror's own egress IP**, and hf-mirror passes the header through

So every hf-mirror user shares one bucket. Measured directly, issuing a single request and reading
the header two seconds later:

| Reading | `r` before | `r` after | consumed |
| :--- | ---: | ---: | ---: |
| 1 | 21996 | 20370 | 1626 |
| 2 | 18798 | 17240 | 1558 |
| 3 | 16671 | 14587 | 2084 |

One request cannot cost 1600 units. The pool is being drained by other people at roughly that rate,
and over a 28-minute stretch it went from 65094 to `0` (`t=55`). **This is luck of the draw, not a
consequence of anything you did.**

**Logging in does not help.** The upstream request is made with hf-mirror's identity, not yours. The
advice in the error body --

```text
We had to rate limit you, you hit the quota of 100000 resolvers requests per 5 minutes period.
Enable "Higher Hub rate limits" in your organization's Network Security settings ...
```

-- is addressed to people hitting `huggingface.co` directly. Through a mirror you have no org and no
handle on the limit.

A local desktop proxy does not hide you either: Clash Verge runs on this machine, so the mirror sees
the same public IP either way.

### What to do about it

Probe the header before starting a large download, rather than discovering the limit 90 seconds in:

```bash
curl -sI --noproxy '*' "https://hf-mirror.com/<repo>/resolve/main/<file>" | grep -i '^ratelimit'
```

If `r` is small, wait for `t`. A `429` is **never** evidence about routing -- it arrives on the
direct and the proxied path alike, which is exactly how it invalidated two bandwidth measurements
during the work behind this skill.

Single requests are not as cheap as they look either. Weights are stored in **Xet**, chunked,
content-addressed storage: one `resolve` fans out into many internal chunk lookups. A handful of
range requests against a large `.safetensors` is enough to move the counter by tens of thousands.

For the same reason, treat a bandwidth number measured during a `429` episode as void, and do not
conclude anything about the route from a failed download.
