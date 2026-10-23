#!/bin/sh
# Claude Code launcher -- per-session cross-session messaging socket.
#
# Why this wrapper exists:
# The cross-session messaging socket directory is validated by walking every
# component of the path and requiring each one to be owned by root (or us) and
# not group/other-writable. On this Android Debian chroot "/" is owned by the
# Termux app's uid and lives on emulated storage, where chown is silently
# ignored -- so every auto-derived socket directory is rejected and the CLI
# falls back to "no cross-session messaging" instead.
#
# Passing --messaging-socket-path explicitly skips that check. The socket is
# placed in a private 0700 root-owned directory.
#
# The socket path must be UNIQUE PER SESSION:
#   - A fixed path makes a second instance fail with "--messaging-socket-path
#     points to a live socket ... Another process is listening there."
#   - Worse, every session then shares one socket, so peer notifications
#     (notify_when_idle) from a session you are not looking at land in the
#     session that happens to hold the path, and another terminal appears to
#     be flooded with messages.
# The CLI's own convention is one socket file per session inside a cc-socks
# directory, discovered by scanning that directory, so follow it.
#
# The real CLI lives in the pnpm bin dir; exec it by absolute path so this
# wrapper can never recurse into itself.
#
# Install: cp claude-wrapper.sh <local-bin-dir>/claude && chmod 755
# Background: agent/skills/android-chroot-debian/references/proxy-and-socket-pitfalls.md

REAL_CLAUDE="${CLAUDE_REAL_BIN:-$HOME/.local/share/pnpm/bin/claude}"
SOCKET_DIR="${CLAUDE_SOCKET_DIR:-$HOME/.claude/run/cc-socks}"

mkdir -p "$SOCKET_DIR" 2>/dev/null
chmod 700 "$SOCKET_DIR" 2>/dev/null

# Per-session socket name. The CLI matches socket file names against
# ^[0-9a-f]{1,16}\.sock$ and discovers peers by scanning the directory, so the
# name must be hex only -- no dash, no PID in decimal. $$ padded to 8 hex digits
# plus 3 random bytes gives 14 hex characters: unique per process, unique per
# second even if the PID repeats.
SOCKET_PATH="$SOCKET_DIR/$(printf '%08x' "$$")$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n').sock"

# Honor an explicit override: an outer caller may already know the path it
# wants this instance to use. This env var also OUTRANKS the command-line
# flag inside the CLI, so it must be handled here rather than assumed away.
if [ -n "${CLAUDE_CODE_MESSAGING_SOCKET:-}" ]; then
    SOCKET_PATH="$CLAUDE_CODE_MESSAGING_SOCKET"
fi

exec "$REAL_CLAUDE" --messaging-socket-path "$SOCKET_PATH" "$@"
