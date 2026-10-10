#!/usr/bin/env bash
# setup-debian-env.sh -- Phase 2: Debian Environment Setup (Tsinghua + npmmirror)
#
# Configures:
#   - APT sources: Tsinghua TUNA mirror
#   - Base packages: ca-certificates, git, jq, curl, procps, etc.
#   - Locales (UTF-8) and timezone (Asia/Shanghai)
#   - Node.js LTS, npm, and pnpm: npmmirror (registry and binary distribution)
#   - uv and Python 3.12: Tsinghua PyPI mirror
#   - Global runtime conventions (PYTHONUNBUFFERED=1, UTF-8)
#
# Rule: Keep pure ASCII in script logic and comments.

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export PATH=/root/.local/bin:/usr/local/bin:$PATH

echo "============================================================"
echo " [Phase 2/2] Debian Container: Environment Setup            "
echo "============================================================"

# 1. Tsinghua APT Mirror & Base Utilities
echo "[1/6] Updating APT repositories from Tsinghua TUNA mirror..."
cat << 'EOF' > /etc/apt/sources.list
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security trixie-security main contrib non-free non-free-firmware
EOF

apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates curl wget git jq locales tzdata \
    procps tar xz-utils bzip2 unzip sudo util-linux tmux zsh

# 2. System Locales & Timezone
echo "[2/6] Configuring UTF-8 locales and Asia/Shanghai timezone..."
mkdir -p /etc
cat << 'EOF' > /etc/locale.gen
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
EOF
locale-gen
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# 3. Node.js LTS via npmmirror
echo "[3/6] Installing Node.js LTS pre-built binary from npmmirror..."
NODE_VER=""
if command -v jq >/dev/null 2>&1; then
    NODE_VER=$(curl -sL --connect-timeout 8 https://npmmirror.com/mirrors/node/index.json 2>/dev/null | jq -r '[.[] | select(.lts != false)][0].version' || true)
fi
if [ -z "$NODE_VER" ] || [ "$NODE_VER" = "null" ]; then
    NODE_VER="v24.21.0"
fi
echo "Selected Node.js LTS version: ${NODE_VER}"

ARCH="$(uname -m)"
case "$ARCH" in
    aarch64|arm64) NODE_ARCH="arm64" ;;
    x86_64|amd64) NODE_ARCH="x64" ;;
    *) echo "Unsupported architecture for pre-built node: $ARCH" >&2; exit 1 ;;
esac

NODE_PKG="node-${NODE_VER}-linux-${NODE_ARCH}.tar.xz"
NODE_URL="https://npmmirror.com/mirrors/node/${NODE_VER}/${NODE_PKG}"
echo "Downloading Node.js from: $NODE_URL"
curl -fsSL "$NODE_URL" -o "/tmp/${NODE_PKG}"
tar -xJf "/tmp/${NODE_PKG}" -C /usr/local --strip-components=1
rm -f "/tmp/${NODE_PKG}"

# 4. Configure npm and pnpm via npmmirror registry
echo "[4/6] Configuring npm and pnpm with npmmirror registry..."
npm config set registry https://registry.npmmirror.com --global
npm install -g pnpm
pnpm config set registry https://registry.npmmirror.com --global

# 5. uv & Python 3.12 via Tsinghua PyPI Mirror
echo "[5/6] Installing uv and Python 3.12 with Tsinghua PyPI mirror..."
mkdir -p /root/.local/bin /root/.config/uv
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/root/.local/bin" sh
fi

cat << 'EOF' > /root/.config/uv/uv.toml
[pip]
index-url = "https://pypi.tuna.tsinghua.edu.cn/simple"

[[index]]
url = "https://pypi.tuna.tsinghua.edu.cn/simple"
default = true
EOF
echo "3.12" > /root/.config/uv/.python-version

# Pre-install Python 3.12 via uv
/root/.local/bin/uv python install 3.12

# 6. Global Shell Conventions & Path Injections
echo "[6/6] Injecting environment defaults into /root/.bashrc..."
if ! grep -qs "PYTHONUNBUFFERED=1" /root/.bashrc; then
    cat << 'EOF' >> /root/.bashrc

# Agent and container environment defaults
export PATH="/root/.local/bin:/usr/local/bin:$PATH"
export PYTHONUNBUFFERED=1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF
fi

if [ -f /root/.profile ] && ! grep -qs "PYTHONUNBUFFERED=1" /root/.profile; then
    cat << 'EOF' >> /root/.profile

export PATH="/root/.local/bin:/usr/local/bin:$PATH"
export PYTHONUNBUFFERED=1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF
fi

echo ""
echo "============================================================"
echo " Diagnostics & Verification Summary                         "
echo "============================================================"
echo "Node.js:  $(node -v 2>/dev/null || echo 'N/A')"
echo "npm:      $(npm -v 2>/dev/null || echo 'N/A')"
echo "pnpm:     $(pnpm -v 2>/dev/null || echo 'N/A')"
echo "uv:       $(/root/.local/bin/uv --version 2>/dev/null || echo 'N/A')"
echo "Python:   $(/root/.local/bin/uv run --python 3.12 python --version 2>/dev/null || echo 'N/A')"
echo "Registries:"
echo "  npm:    $(npm config get registry 2>/dev/null || echo 'N/A')"
echo "  pnpm:   $(pnpm config get registry 2>/dev/null || echo 'N/A')"
echo "  pip:    https://pypi.tuna.tsinghua.edu.cn/simple"

if [ -x /root/verify-chroot-env.sh ]; then
    echo ""
    echo "Running container diagnostic suite (/root/verify-chroot-env.sh)..."
    /root/verify-chroot-env.sh || true
fi

echo ""
echo "=== Phase 2 completed successfully! Container is fully operational. ==="
