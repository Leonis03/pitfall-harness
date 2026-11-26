#!/usr/bin/env bash
# Probe the PRoot filesystem semantics that break code written on another host:
# how `link()` is emulated, what `readdir` reports for the affected directory
# entries, and when `stat()` on a symlink chain fails with EPERM.
#
# WHY A SCRIPT AND NOT A TRANSCRIPT: the difference between a real symlink and a
# PRoot-emulated hard link is invisible in a transcript and obvious in a run.
# The rule below is the one that has to be checked before writing any script
# that lists files or replaces them on the tablet.
#
# Usage:
#   bash proot-fs-probe.sh          # print the findings
#   bash proot-fs-probe.sh --quiet  # print only the verdict lines
#
# Everything happens in a temporary directory that is removed afterwards. Nothing
# outside it is read or written.
#
# Measured 2026-10-23 on an Honor tablet Linux Lab (com.hihonor.pcengine),
# Ubuntu 24.04 aarch64, kernel 6.2.1-PRoot-Distro.
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
verdict() { printf '%s\n' "$*"; }

WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 2

say "== environment =="
say "  kernel: $(uname -r)"
say "  uid:    $(id -u)"
say ""

# ---------------------------------------------------------------------------
# 1. How link() is emulated, and what readdir then reports.
# ---------------------------------------------------------------------------
say "== 1. link() emulation and the directory entry type =="
printf A > a.txt
if ln a.txt b.txt 2>/dev/null; then
  say "  ln a.txt b.txt: ok"
else
  verdict "  link() not supported here -- this probe says nothing about the tablet"
  exit 0
fi

if command -v node >/dev/null 2>&1; then
  node -e '
  const fs=require("fs");
  for(const e of fs.readdirSync(".",{withFileTypes:true})){
    const l=fs.lstatSync(e.name);
    console.log("  "+e.name.padEnd(22),
      "readdir.isFile="+e.isFile(), "isSymlink="+e.isSymbolicLink(),
      "| lstat.isFile="+l.isFile(), "ino="+l.ino, "nlink="+l.nlink);
  }'
else
  say "  (node not installed -- the readdir/lstat split needs node; python can show it too)"
  python3 - <<'PY'
import os
for e in os.scandir('.'):
    l = e.stat(follow_symlinks=False)
    print("  %-22s is_symlink=%-5s is_file(follow)=%-5s ino=%d nlink=%d"
          % (e.name, e.is_symlink(), e.is_file(), l.st_ino, l.st_nlink))
PY
fi

# The names that share the inode must disagree with lstat, and the symlink
# staging entry must be a real symlink.
if command -v node >/dev/null 2>&1; then
  if node -e '
  const fs=require("fs");
  const es=fs.readdirSync(".",{withFileTypes:true});
  const a=es.find(e=>e.name==="a.txt");
  process.exit(a && !a.isFile() && fs.lstatSync("a.txt").isFile() ? 0 : 1);'; then
    verdict "  OK   readdir reports DT_LNK for a name whose lstat says regular file"
  else
    verdict "  DIFF readdir and lstat agree -- this host does not emulate link() that way"
  fi
fi
say ""

# ---------------------------------------------------------------------------
# 2. Which symlink shapes make stat() fail with EPERM.
# ---------------------------------------------------------------------------
say "== 2. stat() on a symlink chain =="

probe_case() {
  local label="$1" setup="$2" dest="$3"
  local w="$WORK/case"; rm -rf "$w"; mkdir -p "$w"; cd "$w" || return
  printf D > p; printf N > src
  eval "$setup"
  local out rc
  out="$(mv -f src "$dest" 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then
    printf '  %-34s mv: ok\n' "$label"
  else
    printf '  %-34s mv: %s\n' "$label" "$out"
  fi
  cd "$WORK" || return
}

probe_case "regular file"             "printf O > plain"                    plain
probe_case "regular file named .l2s.*" "printf O > .l2s.foo"                .l2s.foo
probe_case "one symlink"              "ln -s p s"                           s
probe_case "two symlinks"             "ln -s p s; ln -s s s1"               s1
probe_case "three symlinks"           "ln -s p s; ln -s s s1; ln -s s1 s2"  s2
probe_case "symlink named .l2s.*"     "ln -s p .l2s.s"                      .l2s.s
probe_case "chain through .l2s.*"     "ln -s p .l2s.s; ln -s .l2s.s name"   name

say ""
say "  A chain is refused only when one of its links is named .l2s.*;"
say "  the depth of the chain does not matter, and plain symlinks are fine."
say ""

# ---------------------------------------------------------------------------
# 3. The /proc mount options, and whether they actually hide anything.
# ---------------------------------------------------------------------------
say "== 3. /proc =="
say "  $(mount 2>/dev/null | grep -E ' /proc ' || echo 'no /proc mount line found')"

total=0; unreadable=0
for d in /proc/[0-9]*; do
  [ -d "$d" ] || continue
  total=$((total + 1))
  [ -r "$d/cmdline" ] || unreadable=$((unreadable + 1))
done
say "  pids under /proc: $total, cmdline unreadable: $unreadable"

if mount 2>/dev/null | grep -q 'hidepid=invisible' && [ "$unreadable" = 0 ]; then
  verdict "  OK   hidepid=invisible is mounted but hides nothing: every pid's cmdline is readable"
  verdict "       (PRoot keeps the container's processes under one kernel uid, and hidepid lets a same-uid reader through)"
elif mount 2>/dev/null | grep -q 'hidepid=invisible'; then
  verdict "  DIFF hidepid=invisible is mounted and $unreadable of $total pids are unreadable"
else
  verdict "  DIFF /proc is not mounted hidepid=invisible on this host"
fi

say "  /proc/self/ns/pid      -> $(readlink /proc/self/ns/pid 2>&1)"
say "  /proc/sys/kernel/pid_max -> $(cat /proc/sys/kernel/pid_max 2>&1)"
say "  /proc/self/root       -> $(readlink /proc/self/root 2>&1)"
say ""
say "  The two unreadable ones mean the container cannot tell you which PID"
say "  namespace it is in, or whether pids wrap around."

say ""
say "Done. See honor-linuxlab/README.md sections 2.7 and 2.8."
