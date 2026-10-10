# 端到端两阶段 Debian chroot 自动化部署（Termux 到 Debian）

## 1. 概述与核心架构理念

在已获取 Root 权限的 Android 设备上运行企业级 AI Agent 工作区（如 Claude Code 或 Antigravity CLI），需要通过 `chroot` 容器化搭建基于 glibc 的 Linux 用户态空间。在传统方式下，该环境的搭建需要跨两个不同操作系统环境进行多步人工介入：
1. **Android / Termux 宿主环境**：根文件系统引导（bootstrap）、挂载命名空间（Mount Namespace）隔离及虚拟文件系统桥接。
2. **Debian 容器用户态环境**：配置国内软件源、安装工具链（Node.js、Python、uv）、配置语言时区及设置 Agent 运行时规范。

本文档记录了**两阶段自动化流水线**的设计与实现，支持从宿主引导到容器配置**一口气连续执行完成（"one-go"）**，两阶段之间无需人工交互中断。

---

## 2. 总体流程与跨边界非交互命令透传

```
[阶段一：Termux 宿主编排]
  01-termux-deploy-debian.sh (或 bootstrap-debian-termux.sh)
    │
    ├── 1. 安装宿主依赖 (debootstrap, curl, tar, util-linux)
    ├── 2. 从清华 TUNA 源 debootstrap 极简 Debian Trixie (arm64)
    ├── 3. 继承 Android 系统属性 DNS (getprop net.dns1)
    ├── 4. 部署支持 --exec 的加固启动器 ($HOME/.local/bin/debian)
    ├── 5. 将阶段二脚本复制到 $DEBIAN_ROOT/root/
    └── 6. 无缝交接: exec $HOME/.local/bin/debian --exec /root/setup-debian-env.sh
          │
          ▼
[阶段二：Debian 容器内环境配置]
  02-debian-setup-env.sh (或 setup-debian-env.sh)
    │
    ├── 1. 配置清华 TUNA Debian APT 软件源并更新基础工具
    ├── 2. 安装基础工具库 (ca-certificates, git, jq, locales, tzdata 等)
    ├── 3. 配置 UTF-8 语言环境与 Asia/Shanghai 时区
    ├── 4. 通过 npmmirror 部署 Node.js LTS、npm 与 pnpm
    ├── 5. 通过清华 PyPI 源部署 uv 与 Python 3.12
    ├── 6. 向 Shell 环境文件写入 Agent 规范 (PYTHONUNBUFFERED=1, UTF-8)
    └── 7. 执行容器诊断自检 (/root/verify-chroot-env.sh)
```

### 2.1 传统流程中断陷阱
常规容器部署脚本通常以 `exec chroot $ROOT /bin/bash -l` 结束。这会直接将控制权移交到交互式 TTY 终端，中断自动化脚本流，必须等待人类手动输入并执行后续配置。

### 2.2 解决方案：启动器命令透传机制
增强型 `debian-chroot-launcher.sh` 引入了非交互式命令代理模式（`--exec <cmd>` 或 `-c <cmd>`）：
- 当在 Termux 中以非 root 或普通用户启动且未带 `--root` 时，启动器利用 `printf '%q ' "$@"` 序列化所有参数并通过 `su` 唤醒：
  ```bash
  exec su -c "/system/bin/unshare -m '$LAUNCHER' --root $ESCAPED_ARGS"
  ```
- Android 的 Toybox `su` 将 `-c` 限制为单个字符串参数（多余参数会被误判为用户名）。`printf '%q '` 机制确保了跨 `su` 边界时的参数安全封装。
- 在独立的 Mount Namespace 内，启动器执行 VFS 隔离保护（`mount -o rprivate none /`），配置 `/proc`、`/dev` 与 `/android` 挂载，随后执行：
  ```bash
  exec chroot "$ROOT" /usr/bin/env -i HOME=/root PATH=... /bin/bash -c "$*"
  ```
这使得阶段一可以直接非交互式触发阶段二脚本。

---

## 3. 软件源路由规范

针对国内网络环境，两阶段严格划分镜像源路由：

| 组件 | 上游源 | 配置镜像源 | 设计考量 |
| :--- | :--- | :--- | :--- |
| **Node.js 二进制包** | `nodejs.org/dist` | `https://npmmirror.com/mirrors/node/` | 官方预编译 `linux-arm64` tar 包，零编译，高吞吐下载。 |
| **npm Registry** | `registry.npmjs.org` | `https://registry.npmmirror.com` | 阿里云官方维护的 npm 镜像注册表。 |
| **pnpm Registry** | `registry.npmjs.org` | `https://registry.npmmirror.com` | 快速包依赖解析与高速缓存下载。 |
| **Debian APT** | `deb.debian.org` | `https://mirrors.tuna.tsinghua.edu.cn/debian` | 清华 TUNA 镜像源（覆盖 main、updates 与 security 仓库）。 |
| **Python / PyPI** | `pypi.org/simple` | `https://pypi.tuna.tsinghua.edu.cn/simple` | 在 `~/.config/uv/uv.toml` 中配置的高速 PyPI 镜像源。 |

---

## 4. 阶段一实现要点 (`01-termux-deploy-debian.sh`)

1. **Termux 引导依赖**：安装 `debootstrap`、`gnupg`、`debian-archive-keyring`、`curl` 与 `tar`。
2. **密钥环处理**：定位本地密钥或自动下载 Debian 13 (Trixie) 的 `archive-key-13.asc`。
3. **根文件系统引导**：探测 `$DEBIAN_ROOT/bin/bash` 是否存在，若不存在则调用 `debootstrap --variant=minbase --arch=arm64`。
4. **网络与 DNS 继承**：通过 `getprop net.dns1` 提取 Android 宿主 DNS（缺省回退到 `1.1.1.1`）并写入 `/etc/resolv.conf`。
5. **部署启动器**：将 `debian-chroot-launcher.sh` 安装至 `$HOME/.local/bin/debian`，开启 Mount Namespace 隔离。
6. **脚本注入与串联触发**：将阶段二脚本复制到 `$DEBIAN_ROOT/root/`，授予执行权限后执行：
   ```bash
   exec "$HOME/.local/bin/debian" --exec "/root/setup-debian-env.sh"
   ```

---

## 5. 阶段二实现要点 (`02-debian-setup-env.sh`)

1. **APT 源与核心包**：写入清华源，执行非交互更新并安装基础工具（`ca-certificates`、`git`、`jq`、`locales`、`procps`、`tar`、`xz-utils`、`sudo`、`zsh`、`tmux`）。
2. **语言环境与时区**：生成 `en_US.UTF-8` 与 `zh_CN.UTF-8`，导出 `LANG=en_US.UTF-8`，链接 `Asia/Shanghai` 时区。
3. **通过 npmmirror 部署 Node.js、npm 与 pnpm**：
   - 动态查询 `https://npmmirror.com/mirrors/node/index.json` 获取活跃 LTS 版本。
   - 从 npmmirror 下载 `node-${NODE_VER}-linux-arm64.tar.xz` 并解压至 `/usr/local`。
   - 执行 `npm config set registry https://registry.npmmirror.com --global`。
   - 通过 npm 全局安装 `pnpm` 并同步配置 npmmirror 注册表。
4. **通过清华源部署 uv 与 Python 3.12**：
   - 安装 Astral `uv` 至 `/root/.local/bin/uv`。
   - 生成 `/root/.config/uv/uv.toml` 并配置清华 PyPI 索引。
   - 固定 `echo "3.12" > /root/.config/uv/.python-version`。
   - 调用 `uv python install 3.12` 预装 Python 3.12。
5. **注入 Agent 环境规范**：
   向 `/root/.bashrc` 和 `/root/.profile` 注入 `PYTHONUNBUFFERED=1` 与 `/root/.local/bin` PATH，确保 Agent 执行命令时无缓冲实时捕获输出。
6. **自动化自检**：
   调用 `/root/verify-chroot-env.sh` 核验 41 项内核权能、`/proc/self/exe` 自省以及 UNIX 98 PTY 设备正常。

---

## 6. 验证与快速启动

在全新的 Termux 终端中执行一键完整部署：

```bash
# 在 Termux 终端中执行（需已获取 root 权限）:
cd /path/to/android-chroot-debian/scripts
bash 01-termux-deploy-debian.sh
```

如仅需执行阶段一（如无交互测试场景）：
```bash
bash 01-termux-deploy-debian.sh --bootstrap-only
```

部署完成后，日常交互进入容器：
```bash
debian
```
