#!/usr/bin/env bash
# Run a command with every proxy environment variable removed, so it connects
# directly on the physical NIC instead of through a local desktop proxy
# (Clash Verge Rev and friends).
#
# Why this exists: a shell that exports all_proxy=socks5h://... makes httpx
# raise ImportError in its constructor, before any request is sent. See
# SKILL.md and references/failure-modes.md.
#
# Paths: this script is scripts/direct-download.sh inside the hf-cn-download
# skill. It runs the same from ~/.agents/skills/, ~/.claude/skills/ or
# ~/.gemini/config/skills/.
#
# Usage:
#   direct-download.sh <command> [args...]
#   direct-download.sh --check [url]
#   direct-download.sh --vars <command> [args...]

set -euo pipefail

# All six. Dropping only the four *_proxy ones still crashes httpx, because
# all_proxy is the variable that triggers the SOCKS import.
readonly PROXY_VARS=(
  http_proxy https_proxy all_proxy
  HTTP_PROXY HTTPS_PROXY ALL_PROXY
)

drop_proxy() {
  local -a unset_args=()
  local v
  for v in "${PROXY_VARS[@]}"; do
    unset_args+=(-u "$v")
  done
  env "${unset_args[@]}" "$@"
}

print_env() {
  local found=0 v
  for v in "${PROXY_VARS[@]}"; do
    if [ -n "${!v:-}" ]; then
      printf '  %-12s %s\n' "$v" "${!v}"
      found=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    printf '  (no proxy variables set)\n'
  fi
}

check_mode() {
  local url="${1:-https://hf-mirror.com}"

  printf 'proxy variables in this shell:\n'
  print_env

  if [ -n "${no_proxy:-}${NO_PROXY:-}" ]; then
    printf '  %-12s %s\n' 'no_proxy' "${no_proxy:-${NO_PROXY}}"
  fi

  # Config files that would reintroduce a proxy for a child process.
  local f
  for f in "$HOME/.wgetrc" "$HOME/.aria2/aria2.conf" "$HOME/.curlrc" /etc/wgetrc; do
    if [ -f "$f" ] && grep -qiE '^[[:space:]]*[a-z_-]*proxy[[:space:]]*=' "$f" 2>/dev/null; then
      printf '  WARNING: %s sets a proxy; child processes will still use it\n' "$f"
    fi
  done

  printf '\nremote_ip with the current environment:\n'
  if command -v curl >/dev/null 2>&1; then
    local ip
    ip="$(curl -sI -o /dev/null -w '%{remote_ip}' --max-time 15 "$url" 2>/dev/null || true)"
    if [ -z "$ip" ]; then
      printf '  (request failed -- could not determine)\n'
    elif [ "$ip" = '127.0.0.1' ] || [ "$ip" = '::1' ]; then
      printf '  %s -- went through the local proxy\n' "$ip"
    else
      printf '  %s -- direct\n' "$ip"
    fi
  else
    printf '  (curl not found)\n'
  fi

  printf '\nremote_ip with the proxy variables dropped:\n'
  if command -v curl >/dev/null 2>&1; then
    local ip
    ip="$(drop_proxy curl -sI -o /dev/null -w '%{remote_ip}' --max-time 15 "$url" 2>/dev/null || true)"
    if [ -z "$ip" ]; then
      printf '  (request failed -- could not determine)\n'
    elif [ "$ip" = '127.0.0.1' ] || [ "$ip" = '::1' ]; then
      printf '  %s -- STILL proxied; something else is injecting a proxy\n' "$ip"
    else
      printf '  %s -- direct\n' "$ip"
    fi
  else
    printf '  (curl not found)\n'
  fi
}

main() {
  case "${1:-}" in
    --check|-c)
      shift
      check_mode "${1:-}"
      ;;
    --vars)
      # After the shift, "$@" is already the command; shifting again would eat
      # its first argument and hand a bare flag to env.
      shift
      print_env
      drop_proxy "$@"
      ;;
    '')
      printf 'usage: %s <command> [args...] | --check [url] | --vars <command> [args...]\n' "$0" >&2
      return 2
      ;;
    *)
      drop_proxy "$@"
      ;;
  esac
}

main "$@"
