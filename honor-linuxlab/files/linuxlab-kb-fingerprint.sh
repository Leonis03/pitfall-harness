#!/usr/bin/env bash
# Fingerprint the Linux Lab user guide that ships inside YOYO Claw, so a silent
# re-seed by the vendor shows up as a diff instead of going unnoticed.
#
# WHY NOT THE PLATFORM'S OWN DIGEST: `.magicore-seed-manifest.json` records
# `current_sha256`, but that value matches neither the file on disk nor any plain
# concatenation of the skill files (verified 2026-10-14). It can be read but not
# reproduced, so it is useless for independent change detection. The file's own
# sha256sum plus its mtime are the usable fingerprint.
#
# Usage:
#   bash linuxlab-kb-fingerprint.sh           # print the current fingerprint
#   bash linuxlab-kb-fingerprint.sh --save    # write/update the baseline here
#   bash linuxlab-kb-fingerprint.sh --check   # diff against the baseline; exit 1 on drift
#
# The account UUID is never printed: it is a per-install session identifier and the
# repo bans real identifiers in tracked files (AGENTS.md, redaction.md). Only its
# length is reported, which is still enough to notice a multi-account setup.
#
# Set LINUXLAB_CLAW_ROOT if YOYO Claw does not live under /tablet.
set -uo pipefail

KB_SKILL="linuxlab-user-guide"
CLAW_ROOT="${LINUXLAB_CLAW_ROOT:-/tablet/Honor/YOYOClaw/accounts}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASELINE="${SELF_DIR}/linuxlab-kb-baseline.txt"
ACTION="${1:-print}"

# Keywords the guide is expected to keep not covering. A non-zero hit means the
# vendor added material: read it before trusting docs-gap.md.
KEYWORDS=(proot snap ubuntu-ports zink proxy 命名空间 adb 换源 wine fcitx)

fingerprint() {
  local acc kb guide
  acc="$(find "$CLAW_ROOT" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
         -exec test -d "{}/skills/${KB_SKILL}" \; -print 2>/dev/null | head -1)"
  if [ -z "$acc" ]; then
    echo "ERROR: no account under $CLAW_ROOT ships $KB_SKILL" >&2
    echo "       set LINUXLAB_CLAW_ROOT if YOYO Claw lives elsewhere" >&2
    return 1
  fi

  kb="${acc}/skills/${KB_SKILL}"
  guide="${kb}/references/${KB_SKILL}.md"
  [ -f "$guide" ] || { echo "ERROR: $guide not found" >&2; return 1; }

  echo "# linuxlab user guide fingerprint"
  echo "captured_at:   $(date -Iseconds)"
  echo "account_hex:   <masked, $(basename "$acc" | tr -cd '[:xdigit:]' | wc -c) chars>"
  echo "guide_sha256:  $(sha256sum "$guide" | cut -d' ' -f1)"
  echo "guide_mtime:   $(stat -c %y "$guide" | cut -d. -f1)"
  echo "guide_lines:   $(wc -l < "$guide")"
  echo "guide_bytes:   $(wc -c < "$guide")"
  echo "h2_sections:   $(grep -c '^## ' "$guide")"
  echo "h3_units:      $(grep -c '^### ' "$guide")"
  local k
  for k in "${KEYWORDS[@]}"; do
    printf 'kw_%-14s%s\n' "${k}:" "$(grep -ic -- "$k" "$guide")"
  done
}

case "$ACTION" in
  --save)
    fingerprint > "$BASELINE" || exit 1
    echo "baseline written: $BASELINE"
    ;;
  --check)
    [ -f "$BASELINE" ] || {
      echo "no baseline yet; run with --save first" >&2
      exit 1
    }
    current="$(mktemp)"; base_clean="$(mktemp)"
    # captured_at changes on every run by construction; drop it or --check would
    # report drift on a pristine knowledge base.
    grep -v '^captured_at:' "$BASELINE" > "$base_clean"
    fingerprint | grep -v '^captured_at:' > "$current"
    if diff -u "$base_clean" "$current"; then
      echo "OK: knowledge base unchanged since baseline"
    else
      echo
      echo "CHANGED: re-read the guide before trusting docs-gap.md" >&2
      rm -f "$current" "$base_clean" >/dev/null 2>&1
      exit 1
    fi
    rm -f "$current" "$base_clean" >/dev/null 2>&1
    ;;
  *)
    fingerprint || exit 1
    ;;
esac
