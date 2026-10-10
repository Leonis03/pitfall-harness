#!/data/data/com.termux/files/usr/bin/bash
# bootstrap-debian-termux.sh -- Phase 1: Bootstrap Debian Trixie and deploy container
#
# Usage (run inside Termux):
#   bash bootstrap-debian-termux.sh                  # Complete end-to-end setup (Phase 1 + Phase 2)
#   bash bootstrap-debian-termux.sh --bootstrap-only # Phase 1 only (skip in-container Phase 2)
#
# Rule: Keep pure ASCII in script logic and comments.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${DEBIAN_ROOT:-$HOME/debian-trixie-minbase-install}"
SUITE="trixie"
MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
KEYRING_DIR="$HOME/.cache/debian-keyrings"
LAUNCHER_DEST="$HOME/.local/bin/debian"
BOOTSTRAP_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --bootstrap-only|--skip-phase2)
            BOOTSTRAP_ONLY=1
            ;;
    esac
done

echo "============================================================"
echo " [Phase 1/2] Termux Host: Bootstrapping Debian $SUITE (arm64)"
echo "============================================================"

echo "[1/7] Installing bootstrap prerequisites in Termux..."
pkg install -y debootstrap gnupg debian-archive-keyring curl tar util-linux 2>/dev/null || \
    pkg install -y debootstrap gnupg curl tar

echo "[2/7] Preparing Debian archive keyrings..."
mkdir -p "$KEYRING_DIR"
if [ -f "$PREFIX/etc/apt/trusted.gpg.d/debian-archive-keyring.gpg" ]; then
    KEYRING="$PREFIX/etc/apt/trusted.gpg.d/debian-archive-keyring.gpg"
elif [ -f "$PREFIX/share/keyrings/debian-archive-keyring.gpg" ]; then
    KEYRING="$PREFIX/share/keyrings/debian-archive-keyring.gpg"
else
    KEYRING="$KEYRING_DIR/debian-archive-keyring.gpg"
    if [ ! -f "$KEYRING" ]; then
        curl -fsSL "https://ftp-master.debian.org/keys/archive-key-13.asc" -o "$KEYRING_DIR/archive-key-13.asc" || true
        if [ -f "$KEYRING_DIR/archive-key-13.asc" ]; then
            gpg --dearmor < "$KEYRING_DIR/archive-key-13.asc" > "$KEYRING"
        fi
    fi
fi

KEYRING_ARG=""
if [ -f "$KEYRING" ]; then
    KEYRING_ARG="--keyring=$KEYRING"
fi

echo "[3/7] Running debootstrap minbase (arm64) from Tsinghua mirror..."
mkdir -p "$ROOT"
if [ ! -f "$ROOT/bin/bash" ]; then
    debootstrap --verbose --arch=arm64 --variant=minbase $KEYRING_ARG "$SUITE" "$ROOT" "$MIRROR"
else
    echo "Existing Debian base found in $ROOT, skipping debootstrap."
fi

echo "[4/7] Configuring DNS resolution and network hosts..."
mkdir -p "$ROOT/etc"
DNS_IP="$(getprop net.dns1 2>/dev/null || true)"
if [ -z "$DNS_IP" ]; then
    DNS_IP="1.1.1.1"
fi
printf "nameserver %s\nnameserver 8.8.8.8\n" "$DNS_IP" > "$ROOT/etc/resolv.conf"
printf "127.0.0.1 localhost\n::1 localhost\n" > "$ROOT/etc/hosts"

echo "[5/7] Setting standard file permissions..."
chmod 1777 "$ROOT/tmp"
chmod 644 "$ROOT/etc/resolv.conf" "$ROOT/etc/hosts"

echo "[6/7] Writing Tsinghua mirror APT sources..."
cat << 'EOF' > "$ROOT/etc/apt/sources.list"
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security trixie-security main contrib non-free non-free-firmware
EOF

echo "[7/7] Deploying launcher and stage 2 provisioning scripts..."
mkdir -p "$HOME/.local/bin" "$ROOT/root"
if [ -f "$SCRIPT_DIR/debian-chroot-launcher.sh" ]; then
    cp "$SCRIPT_DIR/debian-chroot-launcher.sh" "$LAUNCHER_DEST"
    chmod 755 "$LAUNCHER_DEST"
fi

if [ -f "$SCRIPT_DIR/setup-debian-env.sh" ]; then
    cp "$SCRIPT_DIR/setup-debian-env.sh" "$ROOT/root/setup-debian-env.sh"
    chmod 755 "$ROOT/root/setup-debian-env.sh"
fi

if [ -f "$SCRIPT_DIR/verify-chroot-env.sh" ]; then
    cp "$SCRIPT_DIR/verify-chroot-env.sh" "$ROOT/root/verify-chroot-env.sh"
    chmod 755 "$ROOT/root/verify-chroot-env.sh"
fi

echo ""
echo "=== Phase 1 completed successfully ==="
echo "Target rootfs: $ROOT"
echo "Launcher:      $LAUNCHER_DEST"

if [ "$BOOTSTRAP_ONLY" -eq 1 ]; then
    echo "Bootstrap-only flag set. Skipping Phase 2."
    echo "You can launch Debian manually via: $LAUNCHER_DEST"
    exit 0
fi

if [ ! -f "$ROOT/root/setup-debian-env.sh" ]; then
    echo "setup-debian-env.sh not found inside container rootfs. Cannot auto-chain Phase 2."
    exit 0
fi

echo ""
echo "============================================================"
echo " [Chain] Triggering Phase 2 inside container in one go...   "
echo "============================================================"
exec "$LAUNCHER_DEST" --exec "/root/setup-debian-env.sh"
