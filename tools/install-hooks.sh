#!/usr/bin/env bash
# install-hooks.sh -- install a pre-commit hook that runs tools/lint.sh.
#
#   bash tools/install-hooks.sh               # install (or refresh) the hook
#   bash tools/install-hooks.sh --uninstall   # remove it again
#   bash tools/install-hooks.sh --force       # replace a pre-commit hook this
#                                             # script did not write (backed up
#                                             # into tmp/ first)
#
# Exit 0 = done, 1 = refused (a foreign hook is in the way), 2 = setup error.
#
# WHY A HOOK AS WELL AS CI
#
# CI (.github/workflows/lint.yml) runs the same checks, but only after a push:
# by then the commit exists, and on this repo several machines and agent
# sessions commit in parallel worktrees. The hook stops the commit itself.
# Skip it once with `git commit --no-verify`; CI still runs.
#
# WHERE IT GOES
#
# `git rev-parse --git-path hooks` -- the common .git/hooks, so one install
# covers the main checkout and every worktree under tmp/, and it follows
# core.hooksPath if that is set. The hook runs the lint.sh of whichever
# worktree is committing, and does nothing on a branch that predates lint.sh.
#
# WHAT IT CHECKS
#
# lint.sh reads the tracked file list from the index and the contents from the
# working tree. A partially staged file is therefore checked as it is on disk,
# not as it will be committed -- the usual pre-commit trade-off, and harmless
# here: CI checks the commit exactly.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree" >&2; exit 2; }

MODE=install
case "${1:-}" in
  "") ;;
  --uninstall) MODE=uninstall ;;
  --force) MODE=force ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

MARKER="# installed by tools/install-hooks.sh (pitfall-harness lint)"
HOOKS=$(git rev-parse --git-path hooks) || exit 2
HOOK="$HOOKS/pre-commit"

ours() { [ -f "$HOOK" ] && grep -qxF "$MARKER" "$HOOK"; }

if [ "$MODE" = uninstall ]; then
  if ours; then rm -f "$HOOK" && echo "removed $HOOK"; exit 0; fi
  [ -e "$HOOK" ] && { echo "$HOOK was not written by this script; left alone" >&2; exit 1; }
  echo "no pre-commit hook installed"; exit 0
fi

if [ -e "$HOOK" ] && ! ours; then
  if [ "$MODE" != force ]; then
    echo "$HOOK exists and was not written by this script." >&2
    echo "Read it, then either add 'bash tools/lint.sh || exit 1' to it yourself," >&2
    echo "or rerun with --force to replace it (a backup goes into tmp/)." >&2
    exit 1
  fi
  mkdir -p tmp
  backup="tmp/pre-commit.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$HOOK" "$backup" || exit 2
  echo "backed up the existing hook to $backup"
fi

mkdir -p "$HOOKS" || exit 2
tmpfile="$HOOK.tmp.$$"
cat > "$tmpfile" <<EOF
#!/usr/bin/env bash
$MARKER
# Runs the committing worktree's tools/lint.sh. Skip once: git commit --no-verify
top=\$(git rev-parse --show-toplevel) || exit 0
[ -f "\$top/tools/lint.sh" ] || exit 0    # a branch older than lint.sh
cd "\$top" || exit 0
bash tools/lint.sh || { echo; echo "pre-commit: tools/lint.sh failed; fix the errors above, or commit with --no-verify"; exit 1; }
EOF
chmod +x "$tmpfile" && mv -f "$tmpfile" "$HOOK" || { rm -f "$tmpfile"; exit 2; }
echo "installed $HOOK"
