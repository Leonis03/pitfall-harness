#!/usr/bin/env bash
# verify-change.sh -- the mechanical checks for a repo change, so they are not
# retyped (and mis-typed) each time.
#
#   bash scripts/verify-change.sh            # only what changed vs HEAD
#   bash scripts/verify-change.sh --all      # every tracked file
#   bash scripts/verify-change.sh REF        # only what changed vs REF
#
# It answers "is this change shippable", never "is the finding true". Reading the
# diff is still your job, and privacy-gate.sh passing is necessary, not sufficient.
#
# Exit status is the number of failed checks (capped at 100); 0 means clean.
#
# Two bugs this script has already had, kept in mind while writing it:
#   - `git ls-files --exclude-dir=...` is not a thing (that is git grep's
#     option). The command failed, 2>/dev/null ate the error, and every check
#     reported ok while checking nothing.
#   - `git grep -Il $'\r$'` loses the CR when the script is invoked through
#     another shell, the pattern degrades to `$`, and every file matches.
# Line endings are therefore read with `git ls-files --eol`, which needs no
# shell quoting at all.

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$here
while [ "$root" != "/" ] && [ ! -f "$root/tools/privacy-gate.sh" ]; do root=$(dirname "$root"); done
if [ ! -f "$root/tools/privacy-gate.sh" ]; then
    echo "verify-change.sh: cannot find the repo root (no tools/privacy-gate.sh above $here)" >&2
    exit 2
fi
cd "$root" || exit 2

SCOPE_SINCE="HEAD"; SCOPE_ALL=0
case "${1:-}" in
    --all) SCOPE_ALL=1; SCOPE_SINCE="" ;;
    "")    ;;
    *)     SCOPE_SINCE="$1" ;;
esac

fail=0
note() { printf '  %-5s %s\n' "$1" "$2"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
list() { if [ "$SCOPE_ALL" -eq 1 ]; then git ls-files -- "$@"; else git diff --name-only "$SCOPE_SINCE" -- "$@"; fi; }

# Files in scope, one per line. Untracked files count: a brand-new skill is the
# most likely thing to have a broken link or a bad description, and
# `git diff` alone would not see it.
scope_files() {
    if [ "$SCOPE_ALL" -eq 1 ]; then git ls-files
    else
        { git diff --name-only "$SCOPE_SINCE"
          git diff --cached --name-only
          git ls-files --others --exclude-standard
        } | sort -u
    fi | grep -v '^\.git' | grep -v '^tmp/'
}

n_scope=$(scope_files | wc -l | tr -d ' ')
echo "== scope =="
if [ "$n_scope" -eq 0 ]; then
    echo "  nothing changed against ${SCOPE_SINCE:-HEAD}."
    echo "  The tree is clean, which is a pass -- but if you meant to check your"
    echo "  last commit, name it:  bash scripts/verify-change.sh HEAD~1"
    echo "  To sweep the whole tree instead:  bash scripts/verify-change.sh --all"
    exit 0
fi
note ok "$n_scope file(s) $([ "$SCOPE_ALL" -eq 1 ] && echo '(whole tree)' || echo "changed vs ${SCOPE_SINCE:-HEAD}")"

# ---------------------------------------------------------------- line endings
echo "== line endings =="
crlf=0
while read -r f; do
    [ -f "$f" ] || continue
    case "$f" in *.bat|*.cmd|*.reg) continue ;; esac
    # w/crlf means the file on disk has CRLF; the repository copy is still LF.
    w=$(git ls-files --eol -- "$f" 2>/dev/null | awk '{print $2}')
    [ "$w" = "w/crlf" ] && { bad "$f is CRLF on disk; this repo works in LF"; crlf=$((crlf + 1)); }
done <<EOF
$(scope_files)
EOF
[ "$crlf" -eq 0 ] && note ok "no CRLF in scope (.bat/.cmd/.reg exempt by .gitattributes)"

# ------------------------------------------------------------------- pure ASCII
# Names, config files and skill FRONTMATTER are ASCII; a skill body may be
# Chinese, so the frontmatter check reads only the header.
echo "== pure ASCII =="
afail=0
for f in $(scope_files | grep -E '\.(ps1|sh|reg|service|timer|yaml|yml|json)$'; echo AGENTS.md); do
    [ -f "$f" ] || continue
    if LC_ALL=C grep -q '[^ -~	]' -- "$f" 2>/dev/null; then
        bad "$f has non-ASCII (config files are ASCII, comments included)"; afail=1
    fi
done
for f in $(scope_files | grep -E '/SKILL\.md$'); do
    if head -n 5 -- "$f" | LC_ALL=C grep -q '[^ -~	]'; then
        bad "$f has non-ASCII in its frontmatter (the body may be Chinese)"; afail=1
    fi
done
[ "$afail" -eq 0 ] && note ok "config files and skill frontmatter are ASCII"

# ------------------------------------------------------------ skill descriptions
# An unquoted YAML description containing ": " makes strict parsers drop the
# skill silently. See agent/skills/README.md.
echo "== skill descriptions =="
sfail=0
for f in $(scope_files | grep -E '/SKILL\.md$'); do
    v=$(sed -n 's/^description: *//p' -- "$f" 2>/dev/null | head -n 1)
    [ -n "$v" ] || continue
    if printf '%s' "$v" | grep -q ': \| #'; then
        bad "$f: description contains ': ' or ' #' -- write ' -- ' instead"; sfail=1
    fi
done
[ "$sfail" -eq 0 ] && note ok "descriptions are safe for strict parsers"

# --------------------------------------------------------------- relative links
echo "== relative links =="
tmp=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/verify-change.$$")
: > "$tmp"
for f in $(scope_files | grep '\.md$'); do
    d=$(dirname "$f")
    grep -oE '\]\(\.{1,2}/[^)#[:space:]]+\)' -- "$f" 2>/dev/null | while IFS= read -r m; do
        t=${m#](}; t=${t%)}
        [ -e "$d/$t" ] || printf '%s -> %s\n' "$f" "$t" >> "$tmp"
    done
done
if [ -s "$tmp" ]; then
    while IFS= read -r l; do bad "broken link: $l"; done < "$tmp"
else
    note ok "relative links resolve"
fi
rm -f "$tmp"

# ----------------------------------------------------------------- privacy gate
echo "== privacy gate =="
out=$(bash tools/privacy-gate.sh 2>&1)
if printf '%s' "$out" | grep -q '^RESULT:.*findings'; then
    printf '%s\n' "$out" | grep -E '^\[FAIL\]' | head -20 | while IFS= read -r l; do
        printf '  FAIL  %s\n' "$l"
    done
    fail=$((fail + 1))
else
    note ok "no known pattern matched"
fi
printf '%s' "$out" | grep -qi 'SKIP' && \
    printf '  WARN  a check was skipped -- tools/.privacy-names is missing\n'

# --------------------------------------------------------------------- verdict
echo
if [ "$fail" -eq 0 ]; then
    echo "RESULT: mechanically clean. Now read the diff."
    exit 0
fi
echo "RESULT: $fail check(s) failed."
exit $([ "$fail" -gt 100 ] && echo 100 || echo "$fail")
