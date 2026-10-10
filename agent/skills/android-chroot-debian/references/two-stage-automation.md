# End-to-End Two-Stage Debian Chroot Automation (Termux to Debian)

## 1. Overview and Core Architectural Thesis

Running an enterprise-grade AI Agent workspace (such as Claude Code or Antigravity CLI) on rooted Android hardware requires a glibc-based Linux userspace containerized via `chroot`. Traditionally, provisioning this environment requires multi-step manual intervention across two distinct operating environments:
1. **The Android / Termux Host Environment**: bootstrapping rootfs filesystems, managing mount namespace isolation, and creating virtual filesystem bridges.
2. **The Debian Container Userspace**: updating software mirrors, installing toolchains (Node.js, Python, uv), configuring locale/timezones, and setting agent runtime conventions.

This reference documents the **two-stage automated pipeline** designed to execute end-to-end in **one continuous pass ("one-go")**, without human interactive pauses between host bootstrap and container configuration.

---

## 2. High-Level Flow and Non-Interactive Boundary Pass-Through

```
[Phase 1: Termux Host Orchestration]
  01-termux-deploy-debian.sh (or bootstrap-debian-termux.sh)
    │
    ├── 1. Install host prerequisites (debootstrap, curl, tar, util-linux)
    ├── 2. debootstrap minimal Debian Trixie (arm64) from Tsinghua TUNA mirror
    ├── 3. Inherit DNS from Android system properties (getprop net.dns1)
    ├── 4. Deploy hardened launcher ($HOME/.local/bin/debian) with --exec support
    ├── 5. Stage Phase 2 scripts into $DEBIAN_ROOT/root/
    └── 6. Seamless Hand-off: exec $HOME/.local/bin/debian --exec /root/setup-debian-env.sh
          │
          ▼
[Phase 2: Debian In-Container Provisioning]
  02-debian-setup-env.sh (or setup-debian-env.sh)
    │
    ├── 1. Update Debian APT repositories via Tsinghua TUNA mirror
    ├── 2. Install base utilities (ca-certificates, git, jq, locales, tzdata, etc.)
    ├── 3. Configure UTF-8 locales and Asia/Shanghai timezone
    ├── 4. Deploy Node.js LTS, npm, and pnpm via npmmirror
    ├── 5. Deploy uv & Python 3.12 via Tsinghua PyPI mirror
    ├── 6. Inject Agent conventions (PYTHONUNBUFFERED=1, UTF-8) into shell profiles
    └── 7. Execute automated health check (/root/verify-chroot-env.sh)
```

### 2.1 The Traditional Interruption Trap
In naive container setups, bootstrap scripts culminate in `exec chroot $ROOT /bin/bash -l`. This transfers control directly to an interactive TTY, breaking scripted workflows and requiring a human operator to paste subsequent configuration commands.

### 2.2 The Solution: Launcher Command Pass-Through
The enhanced `debian-chroot-launcher.sh` introduces non-interactive command delegation (`--exec <cmd>` or `-c <cmd>`):
- When called from Termux as an unprivileged or root process without `--root`, it serializes arguments with `printf '%q ' "$@"` and invokes:
  ```bash
  exec su -c "/system/bin/unshare -m '$LAUNCHER' --root $ESCAPED_ARGS"
  ```
- Android's Toybox `su` restricts `-c` to a single string payload (interpreting extra arguments as usernames). The `printf '%q '` mechanism safely bundles the command line across the `su` boundary.
- Inside the private mount namespace, the launcher isolates the VFS tree (`mount -o rprivate none /`), prepares `/proc`, `/dev`, and `/android`, then executes:
  ```bash
  exec chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=... /bin/bash -c "$*"
  ```
This allows Stage 1 to trigger Stage 2 directly and non-interactively.

---

## 3. Mirror Routing Specification

Network latency and stability within mainland China require deliberate mirror separation:

| Component | Upstream Source | Configured Mirror | Rationale |
| :--- | :--- | :--- | :--- |
| **Node.js Binaries** | `nodejs.org/dist` | `https://npmmirror.com/mirrors/node/` | Official pre-built `linux-arm64` tarballs, zero compilation, high throughput. |
| **npm Registry** | `registry.npmjs.org` | `https://registry.npmmirror.com` | Official Alibaba Cloud mirror for npm packages. |
| **pnpm Registry** | `registry.npmjs.org` | `https://registry.npmmirror.com` | Fast package dependency resolution. |
| **Debian APT** | `deb.debian.org` | `https://mirrors.tuna.tsinghua.edu.cn/debian` | Tsinghua TUNA mirror for main, updates, and security repositories. |
| **Python / PyPI** | `pypi.org/simple` | `https://pypi.tuna.tsinghua.edu.cn/simple` | High-speed Python package index configured in `~/.config/uv/uv.toml`. |

---

## 4. Phase 1 Implementation Details (`01-termux-deploy-debian.sh`)

1. **Bootstrap Prerequisites**:
   Installs `debootstrap`, `gnupg`, `debian-archive-keyring`, `curl`, and `tar` inside the Termux host environment.
2. **Keyring Resolution**:
   Locates host keyrings or downloads `archive-key-13.asc` for Debian 13 (Trixie).
3. **Target Rootfs Verification**:
   Checks whether `$DEBIAN_ROOT/bin/bash` exists. If not, runs `debootstrap --variant=minbase --arch=arm64`.
4. **Network and DNS Inheritance**:
   Inspects Android system property `getprop net.dns1` (with fallback to `1.1.1.1`) and writes `/etc/resolv.conf` and `/etc/hosts`.
5. **Launcher Installation**:
   Copies `debian-chroot-launcher.sh` to `$HOME/.local/bin/debian`, ensuring full mount namespace isolation (`unshare -m`).
6. **Script Injection and Chaining**:
   Copies Phase 2 scripts into `$DEBIAN_ROOT/root/`, grants `chmod 755`, and executes:
   ```bash
   exec "$HOME/.local/bin/debian" --exec "/root/setup-debian-env.sh"
   ```

---

## 5. Phase 2 Implementation Details (`02-debian-setup-env.sh`)

1. **APT Configuration and Core Packages**:
   Writes Tsinghua sources list (`trixie`, `trixie-updates`, `trixie-security`), executes non-interactive `apt-get update`, and installs essential runtime packages (`ca-certificates`, `git`, `jq`, `locales`, `procps`, `tar`, `xz-utils`, `sudo`, `zsh`, `tmux`).
2. **Locale & Timezone**:
   Generates `en_US.UTF-8` and `zh_CN.UTF-8`, exports `LANG=en_US.UTF-8`, and links `/usr/share/zoneinfo/Asia/Shanghai` to `/etc/localtime`.
3. **Node.js, npm, and pnpm via npmmirror**:
   - Queries `https://npmmirror.com/mirrors/node/index.json` for the active LTS release (e.g. `v24.x` / `v22.x`).
   - Downloads `node-${NODE_VER}-linux-arm64.tar.xz` directly from npmmirror and unpacks into `/usr/local`.
   - Executes `npm config set registry https://registry.npmmirror.com --global`.
   - Installs `pnpm` globally via npm and sets its registry to npmmirror.
4. **uv and Python 3.12 via Tsinghua PyPI**:
   - Installs Astral `uv` into `/root/.local/bin/uv`.
   - Generates `/root/.config/uv/uv.toml` with default `index-url = "https://pypi.tuna.tsinghua.edu.cn/simple"`.
   - Pins `echo "3.12" > /root/.config/uv/.python-version`.
   - Pre-installs Python 3.12 runtime with `uv python install 3.12`.
5. **Runtime Conventions**:
   Appends `PYTHONUNBUFFERED=1` and `/root/.local/bin` to `/root/.bashrc` and `/root/.profile` to guarantee real-time stdout streaming during agent executions.
6. **Self-Verification**:
   Invokes `/root/verify-chroot-env.sh` to validate Linux capabilities (all 41 active), `/proc/self/exe` resolution, and UNIX 98 PTY `/dev/pts` device availability.

---

## 6. Verification and Quick Start

To execute the entire two-stage deployment in one pass from a fresh Termux session:

```bash
# In Termux (with root privileges):
cd /path/to/android-chroot-debian/scripts
bash 01-termux-deploy-debian.sh
```

To run Phase 1 only (e.g., in headless test environments):
```bash
bash 01-termux-deploy-debian.sh --bootstrap-only
```

Once completed, normal interactive container access is achieved with:
```bash
debian
```
