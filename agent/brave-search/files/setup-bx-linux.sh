#!/bin/sh
# Set up the Brave Search CLI (bx) on WSL / Linux so that it works behind a local proxy.
#
# Steps (each is skipped when already done, so re-running is safe):
#   1. jq        installed through apt / dnf / pacman when missing (needs sudo).
#   2. bx-bin    the real binary, from the official install.sh. It is installed into a
#                temp dir first and copied to bx-bin, so the wrapper is never overwritten
#                (install.sh writes to <dir>/bx, which is the wrapper's name).
#   3. wrapper   <dir>/bx, a sh script that clears ALL_PROXY for the bx process only.
#   4. API key   `bx config set-key` (interactive, keeps the key out of shell history),
#                only when no key is configured and BRAVE_SEARCH_API_KEY is unset.
#   5. verify    one search piped through jq.
#
# Why a wrapper: bx's HTTP client (ureq) cannot parse ALL_PROXY=socks5h://..., falls back
# to a direct connection and fails with "error: io: Connection refused" (exit 5) although
# the proxy is up. Clearing ALL_PROXY makes it use HTTPS_PROXY / HTTP_PROXY; curl and git
# keep the socks5h setting because the clearing is local to the wrapper.
# Background: agent/brave-search/bx-cli.md section 3.
#
# Usage:  sh setup-bx-linux.sh [--upgrade] [--skip-key] [--dir DIR]
#   --upgrade   fetch the latest bx even if bx-bin already exists
#   --skip-key  do not prompt for an API key
#   --dir DIR   install directory (default: $HOME/.local/bin)
set -eu

DIR=$HOME/.local/bin
UPGRADE=0
SKIP_KEY=0
while [ $# -gt 0 ]; do
    case $1 in
        --upgrade)  UPGRADE=1 ;;
        --skip-key) SKIP_KEY=1 ;;
        --dir)      shift; DIR=${1:?--dir needs a value} ;;
        -h|--help)  sed -n '2,/^set -eu/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

step() { printf '[STEP] %s\n' "$1"; }
ok()   { printf '[ OK ] %s\n' "$1"; }
info() { printf '[INFO] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }

mkdir -p "$DIR"

# 1. jq
step jq
if command -v jq >/dev/null 2>&1; then
    ok "jq present: $(command -v jq)"
else
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y jq
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm jq
    else
        warn "no known package manager; install jq by hand."
    fi
    command -v jq >/dev/null 2>&1 && ok "jq installed" || warn "jq still missing"
fi

# 2. real binary
step "bx binary"
if [ -x "$DIR/bx-bin" ] && [ "$UPGRADE" -eq 0 ]; then
    ok "bx-bin present ($("$DIR/bx-bin" --version 2>/dev/null || echo unknown))"
else
    # A bx that is a real binary (not a sh script) is what a bare install.sh leaves behind.
    if [ -x "$DIR/bx" ] && [ ! -x "$DIR/bx-bin" ] && [ "$(head -c 2 "$DIR/bx")" != '#!' ]; then
        mv "$DIR/bx" "$DIR/bx-bin"
        info "existing bx binary renamed to bx-bin"
    else
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        BX_INSTALL_DIR=$tmp sh -c 'curl -fsSL https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.sh | sh'
        [ -x "$tmp/bx" ] || { echo "install.sh did not produce $tmp/bx" >&2; exit 1; }
        install -m 755 "$tmp/bx" "$DIR/bx-bin"
        ok "installed $("$DIR/bx-bin" --version)"
    fi
fi

# 3. wrapper
step "proxy wrapper"
cat > "$DIR/bx" <<'WRAPPER'
#!/bin/sh
# bx wrapper for proxy environments (WSL / Linux).
# bx-bin's HTTP client cannot parse ALL_PROXY=socks5h://...; clear it for this process
# only so HTTPS_PROXY / HTTP_PROXY are used.
SELF=$0
case "$SELF" in
    */*) ;;
    *)   SELF=$(command -v bx) ;;
esac
DIR=$(CDPATH= cd -- "$(dirname -- "$SELF")" && pwd)
if [ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}${https_proxy:-}${http_proxy:-}" ]; then
    export ALL_PROXY=
    export all_proxy=
fi
exec "$DIR/bx-bin" "$@"
WRAPPER
chmod 755 "$DIR/bx"
ok "wrote $DIR/bx"
case ":$PATH:" in
    *":$DIR:"*) ;;
    *) warn "$DIR is not on PATH." ;;
esac

# 4. API key
step "API key"
cfg=$("$DIR/bx" config path 2>/dev/null | head -n 1 || true)
if [ -n "${BRAVE_SEARCH_API_KEY:-}" ] || { [ -n "$cfg" ] && [ -f "$cfg" ] && grep -q '"api_key"[[:space:]]*:[[:space:]]*"[^"]\+"' "$cfg"; }; then
    ok "API key already configured"
elif [ "$SKIP_KEY" -eq 1 ]; then
    warn "no API key and --skip-key given. Run later: bx config set-key"
elif [ -t 0 ]; then
    info "no API key found; paste it at the prompt (not stored in shell history)"
    "$DIR/bx" config set-key
else
    warn "no API key and stdin is not a terminal. Run later: bx config set-key"
fi

# 5. verify
step verify
if ! command -v jq >/dev/null 2>&1; then
    warn "jq missing; skipping the search check."
    exit 0
fi
title=$("$DIR/bx" web 'brave search cli' --count 1 2>/dev/null | jq -r '.web.results[0].title' 2>/dev/null || true)
if [ -n "$title" ] && [ "$title" != null ]; then
    ok "search works: $title"
else
    warn "search failed. See agent/brave-search/bx-cli.md section 10."
fi
