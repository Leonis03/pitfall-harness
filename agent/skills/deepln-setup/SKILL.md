---
name: deepln-setup
description: Connect to and provision a rented DeepLN cloud GPU node over SSH -- any card, not just the Tesla P4. Use when setting up or repairing a PyTorch CUDA environment on a rented box, when a new rental needs the `deepln` SSH alias repointed, when torch/torchvision/numpy are missing or mismatched for the card (silent CPU fallback), or when installing via SJTU/Tsinghua mirrors. Also covers the GPU-less instances (the 1-core data box and the 24-core compute box), a uv Python 3.12 env for CPU-only jobs, and moving data between rentals -- restoring a saved /data share link (tar.zst) and fast in-cluster rsync by pod IP with agent forwarding. Handles the rental lifecycle, conda detection, non-interactive activation, cgroup capacity limits, and fast mirror selection. Carries verified version pins for the Tesla P4 (sm_61, Pascal).
allowed-tools: Bash Read
argument-hint: "[ssh -p PORT user@host | ssh deepln]"
arguments: [ssh]
---

# DeepLN Cloud GPU: Connection & Environment Setup

Provision or repair a PyTorch CUDA environment on a rented **DeepLN** node.

Everything in sections 0-2 and 4-5 is **card-agnostic** -- the SSH alias and rental
lifecycle, the conda-activation trap, cgroup capacity, mirror selection, verification.
Only the **version pins** depend on which GPU you drew; see the table below.

> Renamed from `p4-setup`. The old name made agents skip this skill on non-P4 rentals,
> which meant rediscovering the conda trap from scratch every time. The P4-specific
> parts were always a small minority of the file.

## Version pins by GPU generation

**Check what you actually got before installing anything:**

```bash
ssh deepln 'nvidia-smi --query-gpu=name,compute_cap,memory.total,driver_version --format=csv,noheader'
```

| Compute cap | Generation | Card examples | PyTorch | Status |
| :--- | :--- | :--- | :--- | :--- |
| **sm_61** | Pascal | **Tesla P4**, P40, GTX 10xx | **≤ 2.2.x + cu121/cu118, numpy < 2** | **Verified** (see below) |
| sm_75 / sm_80 / sm_86 | Turing / Ampere | T4, A100, A10, RTX 30xx | Modern torch, no special pin | Not tested here |
| sm_89 | Ada | L4, L40S, RTX 40xx | Modern torch | Not tested here |
| sm_90 / sm_120 | Hopper / Blackwell | H100, **RTX 5090** | **Needs a recent torch + CUDA 12.8+**; old builds will not run | Not tested here |

**Only the sm_61 row is measured on this fleet.** The others are the general PyTorch
support matrix, recorded so you know which way to look -- confirm against the official
install matrix before trusting them, and add a verified row here once you have run a card.

**The rule that generalises**: the pin must bracket the card from *both* sides. Old cards
break on torch that is too new (no sm_61 kernels -> silent CPU fallback); new cards break on
torch that is too old (no sm_120 kernels -> the same silent fallback). `cuda.is_available()`
returning True does not settle it either way -- run the smoke test in `gpu-cuda-checks`.

### The Tesla P4 pin (verified)

The P4 is old hardware: it only works with **PyTorch <= 2.2.x built for cu121 (or cu118)**
and **numpy < 2**. Newer PyTorch (2.3+) either fails to build for sm_61 or silently falls
back to CPU.

## 0. Connect & SSH Config Alias (`deepln`)

### SSH Config Alias
Local `~/.ssh/config` defines the `deepln` alias for direct, key-authenticated connection without retyping port and host:

```ssh-config
Host deepln
    HostName <instance-domain>.deepln.com
    Port <ssh-port>
    User root
    IdentityFile ~/.ssh/id_ed25519
    KexAlgorithms curve25519-sha256,diffie-hellman-group-exchange-sha256,ecdh-sha2-nistp256
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

- **Direct Alias Usage**: You can connect directly via `ssh deepln` once configured.
- **Instance Rental Lifecycle**: DeepLN creates dynamic domain names and ports on each rental. Whenever a new instance is launched (e.g. `ssh -p <ssh-port> root@<instance>.deepln.com`), update `HostName` and `Port` under `Host deepln` in `~/.ssh/config` after verifying the environment. Subsequent commands and automation should use `ssh deepln`.
- **Never add a `*.deepln.com` wildcard to that `Host` line.** A wildcard makes the stanza match every deepln hostname you type while `HostName` still forces the one hardcoded below it, so `ssh -p NEW root@new-instance.deepln.com` silently connects to the *old* box. Symptoms look like a dead rental or a wiped environment. Keep the stanza to the bare alias.
- **A stopped or re-rented instance's address can answer with another host key.** `ssh` then refuses with `REMOTE HOST IDENTIFICATION HAS CHANGED` (seen 2026-10-04 on a data instance the user had shut down from the console). It is expected after a shutdown or a re-rental, but do not delete the old key on reflex: confirm in the console that the instance really was stopped or replaced, then run `ssh-keygen -R '[<instance-domain>.deepln.com]:<ssh-port>'` and connect again (after repointing the alias if it is a new rental).

**Use the bundled script instead of hand-editing** — it parses the rental string, verifies the box is reachable and really is a P4 with a working torch env, backs up `~/.ssh/config`, and rewrites only `HostName`/`Port`/`User` inside the `Host deepln` stanza (other hosts untouched). It refuses to write if verification fails, so the alias never points at a dead or wrong machine.

```bash
scripts/set-deepln.sh 'ssh -p <ssh-port> root@abc123.deepln.com'   # paste the rental string verbatim
scripts/set-deepln.sh --show                                  # current target + live status + GPU
scripts/set-deepln.sh --help                                  # other input forms and flags
```

### Connection & Retry Loop

```!
echo "SSH argument: $ssh"
```

If no SSH argument is given, check whether `ssh deepln` connects. Otherwise, ask for `ssh -p PORT user@host` (or `ssh deepln`). The box's DNS can be flaky from some networks — wrap connections in a retry loop:

```bash
# Using alias:
for i in $(seq 1 8); do ssh deepln 'echo OK' && break; echo "retry $i"; sleep 4; done

# Using explicit host/port:
for i in $(seq 1 8); do ssh -p PORT user@host 'echo OK' && break; echo "retry $i"; sleep 4; done
```

### Node capacity: `nproc` and `MemTotal` are NOT what you get

These boxes are containers. `nproc`, `/proc/cpuinfo` and `/proc/meminfo` report the
**host's** hardware; what you may actually consume is the **cgroup quota**. Read the
quota before sizing any worker pool, `-j` flag or batch:

```bash
ssh deepln 'awk "{printf \"CPU: %.2f cores\n\", \$1/\$2}" /sys/fs/cgroup/cpu.max
            awk "{printf \"MEM: %.1f GiB\n\", \$1/1073741824}" /sys/fs/cgroup/memory.max'
```

Measured on the deepln P4 node (2026-09-20; the CPU figure matches a 2026-05 reading,
so it is stable across rentals):

| | `nproc` / `MemTotal` says | cgroup quota | overstated by |
| :--- | :--- | :--- | ---: |
| CPU | 64 | **8.83 cores** (`cpu.max 883300 100000`) | 7.2x |
| RAM | 125.8 GB | **18 GiB** (`memory.max 19327352832`) | 7.0x |

Rest of the node: Xeon E5-2683 v4 @ 2.10GHz, Tesla P4 8192 MiB (sm_61, driver 550.54.15),
`/data` 50G, `/` 30G.

- **Start at `-j 8`, never `-j 48`.** Oversubscribing the CPU quota is how a 3 s batch
  became 680 s (see `tools/remote-ssh.md` section 3).
- **The RAM lie is the dangerous one.** Sizing a job against 125 GB gets it OOM-killed at
  18 GiB, usually leaving nothing but exit code 137. Check with `dmesg | grep -i oom`.
- **Re-measure on every new rental.** A sibling node in the same fleet reported `nproc`
  256 while granting only 24 cores -- a CPU compute instance, see section 5.1.
- **The CPU data instance is the extreme case** (section 5, measured 2026-09-27): `nproc` 80
  and `MemTotal` 251 GB, but `cpu.max 100000 100000` = **1 core** and `memory.max` =
  **2 GiB** -- overstated 80x and 125x. `/` is only 2 GB, `/data` 400 GB. Size anything you
  run there against 1 core / 2 GiB.

> `/data` is the only path that can survive a rental, and only if you choose **Save data**
> (「保存数据」) when releasing the instance: it is then kept 30 days by default and can be
> mounted by a later rental of another machine type in the same cluster. Everything else is
> wiped -- including `/root/.cache`, where the Hugging Face and torch hub caches live by
> default, so downloaded weights are fetched again next rental unless `HF_HOME` points into
> `/data`. Put datasets and checkpoints in `/data`, never in `/root`. The instance banner
> says `/data` defaults to 60G and can be expanded up to 1000G per step.

## 1. Find conda and activate the env (CRITICAL)

**A non-interactive `ssh 'command'` does NOT source conda.** `pip`/`python` then resolve to the *system* `/usr/bin` (no torch), so anything you install lands in the wrong interpreter. The interactive prompt shows `(envname)` only because `~/.bashrc` activates it.

Discover the real conda path and env, then always activate explicitly:

```bash
ssh ... 'grep -iE "conda|activate" ~/.bashrc | head'   # reveals conda.sh path + env name
```

Common location is `/data/miniconda` (deepln images) or `/opt/conda`, `~/miniconda3`. Activate before every command:

```bash
source /data/miniconda/etc/profile.d/conda.sh && conda activate torch
which pip python && python --version
```

If there is **no conda at all**, just use system `python3`/`pip` — but then the whole machine is your "env"; the version rules below still apply.

## 2. Check what's already installed

Many cloud images (e.g. `ubuntu2204-py310-cu121-pytorch2.2.1`) ship the correct versions pre-installed — **check before downloading anything**:

```bash
python -c "import torch,torchvision,numpy as np; print('torch',torch.__version__,'tv',torchvision.__version__,'numpy',np.__version__,'cuda',torch.cuda.is_available(),torch.version.cuda)"
```

Decision table:

| Result | Action |
|---|---|
| `2.2.1+cu121`, `0.17.1+cu121`, numpy `1.26.x`, cuda `True` | **Done — install nothing.** Go verify (step 4). |
| torch missing / ModuleNotFound | Install (step 3). |
| torch ≥ 2.3 or no `+cuXXX` tag, or `cuda False` | Wrong/too-new — reinstall pinned (step 3). |
| numpy ≥ 2 | `pip install "numpy<2" -i https://pypi.tuna.tsinghua.edu.cn/simple` |

## 3. Install the pinned old versions

**numpy first** (Tsinghua PyPI, ~50 MB/s):

```bash
pip install "numpy<2" -i https://pypi.tuna.tsinghua.edu.cn/simple
```

**torch + torchvision** — use SJTU find-links AND pin the explicit `+cu121` local version:

```bash
pip install torch==2.2.1+cu121 torchvision==0.17.1+cu121 -f https://mirror.sjtu.edu.cn/pytorch-wheels/cu121/
```

> ⚠️ The `+cu121` suffix is mandatory. With a bare `torch==2.2.1`, pip considers the PyPI `manylinux1` wheel an equal match and often downloads *that* from pypi.org at **~130 KB/s** (and it stalls), pulling extra `nvidia-*-cu12` deps. Pinning `+cu121` forces the self-contained SJTU wheel at full speed. Use `-f` (find-links), **not** `--index-url`.

### Mirror speed reference (tested 2026-05, deepln cloud)

| Mirror | URL | Speed | Note |
|---|---|---|---|
| **上海交大** | `mirror.sjtu.edu.cn/pytorch-wheels/cu121/` | **~35 MB/s** | 首选；301 跳转到 jcloud S3，正常 |
| 官方 | `download.pytorch.org/whl/cu121` | ~2 MB/s | `--index-url` 备用 |
| 阿里云 | `mirrors.aliyun.com/pytorch-wheels/cu121/` | ~0.4 MB/s | 不推荐 |
| 清华 | `pypi.tuna.tsinghua.edu.cn` | — | **只有 CPU 版 torch**，非 PyPI 包用它，CUDA torch 不能用 |

Fallback if SJTU is down: `pip install torch==2.2.1 torchvision==0.17.1 --index-url https://download.pytorch.org/whl/cu121`

## 4. Verify with REAL GPU compute

`cuda.is_available()` alone is not enough — run an actual kernel:

```bash
python - <<'EOF'
import torch
print("torch", torch.__version__, "| cuda build", torch.version.cuda)
print("device:", torch.cuda.get_device_name(0), "| cap", torch.cuda.get_device_capability(0))
x = torch.randn(2048,2048,device="cuda",requires_grad=True)
y = (x @ torch.randn(2048,2048,device="cuda")).relu().sum()
y.backward()
with torch.cuda.amp.autocast():
    _ = (x @ x).float().mean()
print("matmul+backward+amp OK, grad on cuda:", x.grad.is_cuda)
EOF
```

Expect `cap (6, 1)` for the P4 and `OK`. See the `gpu-cuda-checks` skill for runtime gotchas (AMP API, no Tensor Cores).

## 5. Data instances and moving data between rentals

Measured 2026-09-27 with a CPU "data upload" instance next to a Tesla P4 rental in the same
cluster.

### 5.1 The CPU instances: data box and compute box

DeepLN rents two kinds of GPU-less instance, and nothing in the rental string tells them
apart -- read the cgroup quota (section 0) before sizing anything:

| | data instance (measured 2026-09-27) | compute instance (measured 2026-10-04) |
| :--- | :--- | :--- |
| cgroup CPU / RAM | 1 core / 2 GiB | **24 cores / 47 GiB** |
| `nproc` says | 80 | 256 |
| `/data` | 400 G | 60 G |
| Python | system 3.10, no conda | conda in `/data/miniconda`, env `default` (Python 3.10.15, numpy 1.26.4), no torch |
| Use | transfer and storage | CPU-bound jobs (section 6): 2.7x the cores of a P4 node, and the GPU box stays free for training |

**Data instance.** No GPU (`nvidia-smi` is missing), system Python 3.10, no conda, no `bc`; cloud-drive tools
come preinstalled under `/data` (`.bypy`, `.tickstep/adrive`, `alistdata`). Capacity is
1 core / 2 GiB whatever `nproc` says (section 0). It is a transfer box, not a compute box.

Give each instance its **own stanza**, named by role, instead of repointing `deepln` (for
example `deepln-data` and `deepln-cpu` next to the GPU alias), with `ForwardAgent yes` on the
ones that pull data in 5.3:

```ssh-config
Host deepln-data
    HostName <instance-domain>.deepln.com
    Port <ssh-port>
    User root
    IdentityFile ~/.ssh/id_ed25519
    ForwardAgent yes
    KexAlgorithms curve25519-sha256,diffie-hellman-group-exchange-sha256,ecdh-sha2-nistp256
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Write that stanza by hand once, then repoint it on each rental with the same script:

```bash
DEEPLN_ALIAS=deepln-data scripts/set-deepln.sh 'ssh -p <ssh-port> root@<instance-domain>.deepln.com'
```

It warns `no nvidia-smi output` and `torch env not ready` -- expected on this image; it still
verifies reachability and writes. If the stanza does not exist yet, the script appends a fresh
one with the Tesla P4 comment and **without** `ForwardAgent`, so create it by hand first.

### 5.2 Restoring saved `/data` from a share link

The console's share link streams `<instance>-data.tar.zst`: a tar of the **whole** old
`/data`, every member prefixed `data/` (`data/coding/...`, `data/alistdata/...`,
`data/.bypy/...`). The obvious command therefore nests one level too deep:

```bash
wget -c -4 -qO- "$URL" | pzstd -dc | tar xvf - -C /data/coding   # WRONG: /data/coding/data/coding/...
```

**The fix is one space.** Extract at `/` and name the directory you want, so the stored path
`data/coding/...` lands exactly at `/data/coding/...` and nothing else in the archive is written:

```bash
wget -c -4 -qO- "$URL" | pzstd -dc | tar xvf - -C / data/coding    # RIGHT: note the space after -C /
```

| Goal | End of the command |
| :--- | :--- |
| Only the project | `-C / data/coding` |
| Look first, write nothing | `tar tvf - \| head` |
| The conda env of a GPU-instance snapshot, on a fresh instance | `-C / data/miniconda` (not tested) |
| Everything, on a fresh instance only | `-C /` -- overwrites same-name files: the new instance's own `/data/alistdata` config and database, a live `/data/miniconda` |

`-C /data/coding --strip-components=2 data/coding` is equivalent. If a later snapshot uses another
prefix, the member name does not match and tar fails with `Not found in archive` instead of
writing to the wrong place.

- **Snapshots differ by instance type -- list before extracting.** A data instance's `/data`
  holds the project (dataset, code). A GPU instance's holds mostly `miniconda/` (8.7 GB, the
  torch env), `model/`, `.rootcache/` (uv cache) and `.code-server/`, and only the image's
  default `README.md` and `coding.code-workspace` in `coding/`.
- **Measured 2026-09-27** on a P4 after emptying `/data/coding`: both kinds imported with
  `-C / data/coding` without nesting -- a 2.7 GB data snapshot (13.5k JPEGs plus a 1.4 GB tar)
  in 6-19 s, and a 9.3 GB GPU snapshot streamed in 14-16 s to extract its two `coding/` files.
  `/data/miniconda` was left untouched.
- **Nesting leaves debris that is easy to miss.** An earlier `-C /data/coding` import had left
  `/data/coding/data/{alistdata,.bypy,.tickstep,adrive}` -- the old instance's tools, including
  the alist config with its JWT secret -- inside the project directory, where a later sync can
  carry it along.
- The link is a presigned S3 URL carrying a temporary token (`X-Amz-Expires=43200`, 12 h).
  Keep it in a file, or feed it on stdin (`ssh host 'read -r URL; wget ... "$URL" | ...' < url.txt`),
  so it never lands in command lines, logs or commits.
- Run it detached for anything big (5.4).

### 5.3 Instance to instance: pod IP plus agent forwarding

- **The public `<instance-domain>.deepln.com:<ssh-port>` is not reachable from inside the
  cluster.** TCP to it times out in both directions (GPU box -> data box and back); from
  inside, the domain resolves to a public address. The pod's IPv6 address is blocked as well.
- **The pod IPv4 address works**: `ssh deepln hostname -I` prints `10.230.x.x`; sshd listens
  on port **22** there; RTT ~0.3 ms.
- **Authenticate with the local key through agent forwarding**, so no private key is copied to
  a rented box and nothing is added to `authorized_keys`:

  ```bash
  ssh deepln hostname -I        # GPU pod IP -- changes with every rental, re-read it each time
  ssh deepln-data 'rsync -a root@<gpu-pod-ip>:/data/coding/<path> /data/coding/<path>'
  ```

  The first contact needs `-o StrictHostKeyChecking=accept-new` (or answering the prompt).
  The entries are stored hashed (`|1|...`), so `grep <ip> ~/.ssh/known_hosts` finds nothing --
  check with `ssh-keygen -F <ip>`.
- **Measured**: a 160 MB run dir in 1.1 s (145 MB/s), a 1.4 GB tar in 6.5 s (204 MB/s), md5
  verified. The same box from a home uplink: ~1.9 MB/s. **Move bulk data server to server;
  upload from the laptop only code, text and small artifacts.**
- **Measured again 2026-10-04**: 15.9 GB in 2242 files (a project with its datasets and run
  outputs), pulled from a P4 box by two receivers at once -- 76 s on a data instance and 91 s
  on a compute instance, about 209 and 175 MB/s. The file lists (path and size, hashed) and the
  md5 of sampled files matched on all three boxes. If you check this from a local script, give
  every `ssh` `-n` (`tools/remote-ssh.md` section 8).
- Agent forwarding only works while a local session is open. An unattended sync (e.g. cron
  on the data box) needs its own key on the data instance, added to the GPU box's
  `authorized_keys` -- not set up or tested here.
- While a session is open, root on the rented box can use the forwarded agent to
  authenticate as you. Forward only to instances you rent.

### 5.4 Remote shell traps met on the way

General cases are in `tools/remote-ssh.md` (this repo); these are the variants that cost
time here.

- **`setsid nohup ... &` at the end of an `&&` list still hangs ssh** (remote-ssh.md
  section 1): in `ssh host 'cd X && rm -f Y && setsid nohup job > log 2>&1 < /dev/null &'` the
  `&` backgrounds the whole list in a subshell that keeps ssh's stdout open, although the job's
  own output is redirected. ssh returns only at its timeout (the job survives). Make the
  detached job a simple command of its own: `ssh host 'cd X; setsid nohup job > log 2>&1 < /dev/null &'`.
- **A `pgrep -f` wait loop never ends** (remote-ssh.md section 2 is the `pkill` side):
  `ssh host 'while pgrep -f "job.py"; do sleep 5; done'` matches the remote shell running the
  loop, whose command line contains `job.py`. Use `pgrep -f "[j]ob.py"`.
- **`find -size -1M` matches only empty files**: find rounds sizes up to whole units, so "less
  than 1 MiB" means "zero units". Use `-size -1024k`.
- **awk inside `ssh '...'` with escaped double quotes printed nothing, without an error.**
  Push multi-line remote logic as a file (`ssh host 'cat > run.sh' <<'EOF' ... EOF`, then
  `ssh host bash run.sh`) instead of nesting quotes.
- **No `bc` on the data image**: use shell arithmetic, `$(( ... ))`.

## 6. CPU-only jobs: uv and Python 3.12 on a compute instance

Jobs that need no torch (replays, evaluation, onnxruntime inference) run better on a compute
instance (section 5.1) with a Python of their own than inside the GPU box's pinned env.
Measured 2026-10-04 on a pure-Python replay: Python 3.12 was 1.4x faster than the image's 3.10,
numpy 2.5.3 against 1.26.4 made no difference, and the outputs were byte-identical
(`tools/python/README.md` section 3).

Keep everything uv owns under `/data`, the only path that survives a rental:

```bash
export UV_PYTHON_INSTALL_DIR=/data/uv/python UV_CACHE_DIR=/data/uv/cache PATH=/data/uv/bin:$PATH
/data/miniconda/envs/<env>/bin/pip install uv -i https://pypi.tuna.tsinghua.edu.cn/simple   # uv into the image's conda env (under /data)
mkdir -p /data/uv/bin && ln -sf /data/miniconda/envs/<env>/bin/uv /data/uv/bin/uv
uv python install 3.12                 # python-build-standalone from GitHub: fast from the cluster on 2026-10-04
uv venv --python 3.12 /data/uv/venvs/<name>
VIRTUAL_ENV=/data/uv/venvs/<name> uv pip install -r requirements-cpu.txt
```

- **Point uv at the TUNA mirror in its user config, and rewrite it on every setup.**
  `~/.config` is not under `/data`, so the file is gone after a re-rental and `uv pip install`
  quietly goes back to PyPI. A per-command `UV_INDEX_URL=...` covers only that one command.

  ```bash
  mkdir -p ~/.config/uv
  printf '%s\n' '[[index]]' 'url = "https://pypi.tuna.tsinghua.edu.cn/simple"' 'default = true' > ~/.config/uv/uv.toml
  uv pip install --dry-run -p /data/uv/venvs/<name> requests -v 2>&1 | grep -o 'https://[a-z.]*/simple' | sort -u
  ```

- **Non-interactive `ssh` activates nothing** (section 1): call the venv's interpreter by path
  (`/data/uv/venvs/<name>/bin/python`) or `source /data/uv/venvs/<name>/bin/activate` inside
  the remote command.
- **Keep the image's conda env** for tools that need Python <= 3.11 (CANN 8.0, for one, supports
  3.7-3.11). Installing `onnxruntime` into it with `pip` left its numpy 1.26.4 alone.
- **Before trusting numbers from the new env, compare outputs** with the old one on the same job
  (hash the result arrays). Do it again after every version bump.
