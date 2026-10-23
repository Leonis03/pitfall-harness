---
name: hf-cn-download
description: Download models and datasets from China-reachable mirrors such as hf-mirror.com while a local desktop proxy is running. Covers the httpx socksio ImportError caused by all_proxy, why redirect targets escape the Clash DIRECT rule, and how to verify a download really went out on the physical NIC. Use when a model download dies with a SOCKS proxy error, or when the page loads but the file itself is slow.
allowed-tools: Bash Read
---

# Downloading models from a mirror, behind a desktop proxy

On a machine where Clash Verge Rev (or any desktop proxy) is on, an AI agent that runs
`hf_hub_download`, `hf download`, `pip install` or a bare `curl` for a model file gets the
proxy environment by inheritance -- `~/.shell_common` exports it into **every** shell. Two
distinct failures come out of that, and they need different fixes.

Measured on Linux Mint 22, Clash Verge Rev v1.19.10, no TUN device, proxy on
`127.0.0.1:<proxy-port>`.

## The two layers

| | Trigger | Symptom | Blast radius |
| :--- | :--- | :--- | :--- |
| **1. Import crash** | `all_proxy=socks5h://...` present | `ImportError: Using SOCKS proxy, but the 'socksio' package is not installed` -- raised inside `httpx.Client()`, before any packet leaves | anything built on httpx: `huggingface_hub`, and most Python HTTP clients |
| **2. Routing leak** | any proxy variable present | page loads instantly, the file itself is slow: the redirect target matches no rule and falls through to `MATCH,Proxy` | every tool, silently |

**Layer 1 is loud, layer 2 is quiet.** Fixing the crash does not fix the slow download, and
vice versa. Do not stop after the import error goes away.

## The recipe

Strip **all six** variables. Scrubbing only the four `*_proxy` ones still crashes -- `all_proxy`
is the one that triggers the SOCKS import.

```bash
env -u http_proxy -u https_proxy -u all_proxy \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    HF_ENDPOINT=https://hf-mirror.com \
    PYTHONUNBUFFERED=1 \
    uv run --python 3.12 --with huggingface_hub python your_script.py
```

`PYTHONUNBUFFERED=1` keeps the progress bar visible in a captured log.

Or use the wrapper, which does the same thing:

```bash
~/.agents/skills/hf-cn-download/scripts/direct-download.sh --check          # report what is set
~/.agents/skills/hf-cn-download/scripts/direct-download.sh hf download Qwen/Qwen2.5-0.5B-Instruct
```

Paths: `~/.agents/skills/` works, and so does `~/.claude/skills/` or `~/.gemini/config/skills/`,
or a path relative to this SKILL.md. The wrapper is `scripts/direct-download.sh`.

## Per tool

| Tool | How |
| :--- | :--- |
| `huggingface_hub` | the recipe above, plus `HF_ENDPOINT=https://hf-mirror.com` |
| `hfd.sh` (multi-thread, resume) | `--tool aria2c\|wget`, `-x` threads, `-j` jobs. It reads `HF_ENDPOINT` and **contains no proxy logic of its own**, so it inherits whatever the environment says -- `env -u` reaches its `curl`/`aria2c`/`wget` children |
| `curl` | `curl -fL --noproxy '*' -o out <url>`. Note `-L`: the payload comes from a redirect |
| `wget` | `wget --no-proxy -O out <url>`. The flag is `--no-proxy`, not `--noproxy` |

## What not to do

- **`NO_PROXY=hf-mirror.com` alone.** Verified failing. httpx raises in the constructor,
  before it ever consults the per-domain allowlist.
- **`pip install httpx[socks]`.** This does not fix anything -- it converts layer 1 (a crash)
  into layer 2 (a slow download). The proxy was never the right answer.
- **Editing the subscription YAML directly.** The next subscription update overwrites it. Put
  rules in the profile's pre-rules / subscription extension script.
- **Adding a DIRECT rule for the mirror domain only.** See the next section -- it does not reach
  the payload.

## Why a rule for the mirror domain is not enough

`DOMAIN-SUFFIX,hf-mirror.com,DIRECT` covers that one tree. The bytes come from somewhere else:

```text
hf-mirror.com                       -> <jp-address>    (rule matches -> DIRECT, page is fast)
  302 -> cas-bridge.xethub.hf.co    -> <us-address>    (us-east-1, no rule)
```

`cas-bridge.xethub.hf.co` has no rule, and its US address also misses `GEOIP,CN,DIRECT`, so it
lands on the catch-all `MATCH,Proxy` and gets tunnelled. **Enumerate the domain you clicked, not
the domain actually carrying the bytes.**

This is also why a per-domain `no_proxy` is the wrong granularity here: the payload domains come
from redirects and cannot be known in advance. For a mirror download, bypass the proxy for the
whole command.

## Verify, do not assume

After a download, confirm it left on the physical NIC:

```bash
lsof -p <PID> | grep TCP
# want: <lan-ip>:<local-port> -> <mirror-host>:https (ESTABLISHED)
# NOT:  <lan-ip>:<local-port> -> 127.0.0.1:<proxy-port> (ESTABLISHED)
```

Cheaper, without a running process:

```bash
curl -sI -o /dev/null -w '%{remote_ip}\n' https://hf-mirror.com
```

`127.0.0.1` means it went through the proxy. A routable address means direct.

In the Clash log or the `connections` panel, look at the domain that actually **transferred** --
the `us.aws.cdn.hf.co` / `cas-bridge.xethub.hf.co` entries -- not the one in the address bar.

## Speed: bypassing the proxy is not the lever

Measured on the same file, 100 MB via HTTP range, direct versus proxied:

| Path | Throughput |
| :--- | :--- |
| direct (`env -u`) | 1.35 MB/s |
| via the proxy node | 1.09 MB/s |

Direct is about 24% faster -- **not** the difference a crash-recovery report implies. Both sit
around 1 MB/s, because the bottleneck is the `us-east-1` endpoint, not the local proxy.

The real lever is **parallel connections**, which is why `hfd.sh` defaults to `aria2c -x 4 -j 5`.
Reach for it before concluding that a mirror is slow.

Still unverified here, and the reason is worth recording: the two attempts to measure it both ran
into `429` from the shared quota described above, the second one at `r=0`. Treat `aria2c -x 4 -j 5`
as the expected fix, not a measured one -- and do not read a failed parallel benchmark as a slow
mirror.

## The durable fix

Per-command `env -u` is the reliable answer for an agent. To fix it once for every tool,
including the browser, add rules to the profile's **pre-rules / subscription extension script**:

```yaml
prepend-rules:
  - DOMAIN-SUFFIX,hf-mirror.com,DIRECT
  - DOMAIN-SUFFIX,xethub.hf.co,DIRECT
  - DOMAIN-SUFFIX,cdn.hf.co,DIRECT
```

Cover the redirect targets too, or the rule only fixes the page.

## Notes and caveats

- `NO_PROXY='*'` **does** work for httpx 0.28.1 -- verified, the client builds no proxy mounts at
  all. It is still not the recommendation, because it is per-client behaviour: it only removes the
  variables for clients that honour the wildcard, and `no_proxy` wildcard handling is known to be
  inconsistent across tools. `env -u` removes them for everything.
- `no_proxy` / `NO_PROXY` may survive `env -u` (they are not in the list above). That is harmless --
  they only exclude.
- Verified there is no `~/.wgetrc`, `~/.aria2/aria2.conf` or `~/.curlrc` on this machine, so
  `env -u` genuinely reaches every download backend. A machine that has one of those with a proxy
  line set needs it removed as well.
- Mirrors rate-limit hard, and **the quota is shared by every user of the mirror**, so a `429` says
  nothing about your route or your account. Read the `ratelimit` response header before a big
  download -- it carries the remaining count and the seconds until the window resets. `references/failure-modes.md`
  has the measurements.

## More

`references/failure-modes.md` -- the symptom-to-layer decision table, the socket and Clash
forensics, and the exact evidence behind every number quoted above.
