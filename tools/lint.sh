#!/usr/bin/env bash
# lint.sh -- check the rules in AGENTS.md that otherwise fail silently.
#
#   bash tools/lint.sh                  # check the tracked tree
#   bash tools/lint.sh --base origin/main
#                                       # also warn about bilingual pairs where
#                                       # only one side changed since the base
#
# Exit 0 = no errors (warnings may be printed), 1 = errors, 2 = setup error.
# Every finding is one line: `ERROR <check>: <file>[:<line>]: <message>` or
# `WARN <check>: ...`, so the output greps and diffs cleanly.
#
# WHY THIS EXISTS
#
# AGENTS.md lists "rules that fail silently when broken" and pairs that "must
# change together". Each one was learned the hard way, and until now each one
# was enforced by an agent or a human remembering to read AGENTS.md. This
# script turns the mechanically checkable ones into errors, so a PR that breaks
# one is stopped by CI instead of by the next person who trips over it.
#
# WHAT IT DOES NOT CHECK
#
# Anything that needs judgement: whether a Chinese file is a faithful
# translation, whether a doc is redacted (privacy-gate.sh does the known
# shapes; a human still reads the diff), whether a skill description is good.
# A clean run here is necessary, not sufficient -- same contract as
# privacy-gate.sh.
#
# Only tracked files are checked (git ls-files), so tmp/ is out of scope by
# construction. This file itself is pure ASCII: the one Chinese heading it must
# find is written as UTF-8 byte escapes.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree" >&2; exit 2; }

BASE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) BASE=${2:-}; shift 2 || { echo "--base needs a ref" >&2; exit 2; } ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -n "$BASE" ] && ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
  echo "--base $BASE: no such commit (fetch it first)" >&2; exit 2
fi

errors=0; warnings=0
err()  { echo "ERROR $*"; errors=$((errors + 1)); }
warn() { echo "WARN $*";  warnings=$((warnings + 1)); }

FILES=()
while IFS= read -r -d '' f; do FILES+=("$f"); done < <(git ls-files -z)
MD=()
for f in "${FILES[@]}"; do case "$f" in *.md) [ -f "$f" ] && MD+=("$f") ;; esac; done

# Vendored skills are verbatim upstream copies; this repo's skill rules do not
# apply to them. publish.sh owns the list -- read it from there, not a copy.
VENDORED=$(sed -n 's/^VENDORED=(\([^)]*\)).*/\1/p' tools/publish.sh)
[ -n "$VENDORED" ] || { echo "could not read VENDORED from tools/publish.sh" >&2; exit 2; }
is_vendored() { case " $VENDORED " in *" $1 "*) return 0 ;; esac; return 1; }

SKILLS=()
for d in agent/skills/*/; do d=${d%/}; [ -f "$d/SKILL.md" ] && SKILLS+=("${d##*/}"); done

# ---------------------------------------------------------------------------
# paths-ascii: file and directory names are pure ASCII.
# ---------------------------------------------------------------------------
for f in "${FILES[@]}"; do
  if printf '%s' "$f" | LC_ALL=C grep -q '[^ -~]'; then
    err "paths-ascii: $f: non-ASCII character in path"
  fi
done

# ---------------------------------------------------------------------------
# md-names: Markdown filenames are lowercase kebab-case, except the protocol
# filenames that tools look up literally (conventions.md).
# ---------------------------------------------------------------------------
for f in "${MD[@]}"; do
  b=${f##*/}
  case "$b" in README.md|README.zh.md|SKILL.md|SKILL.zh.md|AGENTS.md|CLAUDE.md|TROUBLESHOOTING.md|TROUBLESHOOTING.zh.md) continue ;; esac
  # Vendored skills keep upstream's names.
  case "$f" in agent/skills/*/*) is_vendored "$(cut -d/ -f3 <<<"$f")" && continue ;; esac
  printf '%s' "$b" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*(\.zh)?\.md$' \
    || err "md-names: $f: Markdown filename is not lowercase kebab-case"
done

# ---------------------------------------------------------------------------
# eol: LF in the index for everything; LF in the working tree for everything
# except .bat/.cmd/.reg (CRLF there by .gitattributes). A CRLF that reaches the
# working tree on Windows is caught here before it is committed.
# ---------------------------------------------------------------------------
# Format: "i/lf    w/lf    attr/text=auto eol=lf <TAB>path" -- the attr column
# can hold spaces, so split on the tab first.
while IFS=$'\t' read -r meta path; do
  read -r idx wt _ <<<"$meta"
  case "$idx" in i/crlf|i/mixed) err "eol: $path: $idx in the index (must be LF)" ;; esac
  case "$path" in *.bat|*.cmd|*.reg) continue ;; esac
  case "$wt" in w/crlf|w/mixed) err "eol: $path: $wt in the working tree (rewrite the file with LF)" ;; esac
done < <(git ls-files --eol)

# ---------------------------------------------------------------------------
# root-only-agents: AGENTS.md / CLAUDE.md only at the root. Harnesses load
# them from subdirectories as instructions.
# ---------------------------------------------------------------------------
for f in "${FILES[@]}"; do
  case "$f" in */AGENTS.md|*/CLAUDE.md) err "root-only-agents: $f: harnesses load this name as instructions; give the original another name" ;; esac
done

# ---------------------------------------------------------------------------
# top-readme: every top-level directory except tmp/ and dot-directories has a
# README.md index. (.github/ deliberately has none: GitHub would show a
# .github/README.md as the repository's front page instead of the root one.)
# ---------------------------------------------------------------------------
for d in $(printf '%s\n' "${FILES[@]}" | grep / | cut -d/ -f1 | sort -u); do
  case "$d" in tmp|.*) continue ;; esac
  [ -f "$d/README.md" ] || err "top-readme: $d/: top-level directory has no README.md"
done

# ---------------------------------------------------------------------------
# agents-map: the Map table in AGENTS.md is the entry point every agent reads
# first. Every path in its first column exists (placeholders like <name> are
# skipped), and every top-level directory appears in it.
# ---------------------------------------------------------------------------
MAP=$(awk '/^## Map/ { p = 1; next } p && /^## / { exit } p && /^\| `/ { split($0, c, "|"); print c[2] }' AGENTS.md \
      | grep -o '`[^`]*`' | tr -d '`')
if [ -z "$MAP" ]; then
  err "agents-map: AGENTS.md: no '## Map' table found; heading renamed?"
else
  while IFS= read -r m; do
    case "$m" in *"<"*) continue ;; esac
    [ -e "$m" ] || err "agents-map: AGENTS.md: Map names $m, which does not exist"
  done <<<"$MAP"
  for d in $(printf '%s\n' "${FILES[@]}" | grep / | cut -d/ -f1 | sort -u); do
    case "$d" in .*) [ "$d" = .github ] || continue ;; esac
    grep -q "^$d/" <<<"$MAP" || err "agents-map: AGENTS.md: top-level directory $d/ is missing from the Map table"
  done
fi

# ---------------------------------------------------------------------------
# ascii-content: AGENTS.md, every skill's YAML frontmatter, and the deployable
# config originals (anything under a files/ directory that is not Markdown)
# are pure ASCII, comments included.
#
# ASCII_EXEMPT lists the originals where the non-ASCII bytes are DATA the
# config needs, not prose: each entry says why. Adding an entry is a decision;
# say why in the same line.
# ---------------------------------------------------------------------------
ASCII_EXEMPT=(
  "linux-desktop/files/nemo/actions/open_in_ghostty.nemo_action"     # Name[zh_CN]/Comment[zh_CN] localization keys
  "linux-desktop/files/nemo/actions/open_in_ghostty_bg.nemo_action"  # same
  "honor-linuxlab/files/linuxlab-kb-fingerprint.sh"                  # Chinese search keywords matched against the vendor KB
  "honor-linuxlab/files/linuxlab-kb-baseline.txt"                    # captured vendor KB output, data
)
is_ascii_exempt() { local e; for e in "${ASCII_EXEMPT[@]}"; do [ "$e" = "$1" ] && return 0; done; return 1; }

first_non_ascii() { LC_ALL=C grep -n -m1 '[^[:print:][:space:]]' "$1" | cut -d: -f1; }

n=$(first_non_ascii AGENTS.md); [ -n "$n" ] && err "ascii-content: AGENTS.md:$n: non-ASCII byte (AGENTS.md is pure ASCII)"
for f in "${FILES[@]}"; do
  case "$f" in */files/*) ;; *) continue ;; esac
  case "$f" in *.md) continue ;; esac
  [ -f "$f" ] || continue
  is_ascii_exempt "$f" && continue
  n=$(first_non_ascii "$f")
  [ -n "$n" ] && err "ascii-content: $f:$n: non-ASCII byte in a config original (or add it to ASCII_EXEMPT with a reason)"
done
for e in "${ASCII_EXEMPT[@]}"; do
  [ -f "$e" ] || err "ascii-content: ASCII_EXEMPT names $e, which is not tracked any more; drop the entry"
done

# ---------------------------------------------------------------------------
# skill-frontmatter: each non-vendored SKILL.md opens with YAML frontmatter
# holding name (= directory name) and description; the frontmatter is ASCII;
# an unquoted plain description has no ": " and no " #" (strict parsers such
# as `npx skills` drop the skill silently).
# ---------------------------------------------------------------------------
for s in "${SKILLS[@]}"; do
  is_vendored "$s" && continue
  f=agent/skills/$s/SKILL.md
  fm=$(awk 'NR==1 { if ($0 != "---") exit 1; next } $0 == "---" { found=1; exit } { print } END { if (!found) exit 1 }' "$f") \
    || { err "skill-frontmatter: $f: no YAML frontmatter delimited by --- lines"; continue; }
  if printf '%s' "$fm" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then
    err "skill-frontmatter: $f: non-ASCII byte in frontmatter"
  fi
  name=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1 | tr -d "\"'")
  [ "$name" = "$s" ] || err "skill-frontmatter: $f: name '$name' does not match directory '$s'"
  desc=$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)
  if [ -z "$desc" ]; then
    err "skill-frontmatter: $f: no description"
  else
    case "$desc" in
      \"*|\'*|\>*|\|*) ;;   # quoted or block scalar: the parser is not confused
      *": "*|*" #"*) err "skill-frontmatter: $f: unquoted description contains ': ' or ' #' (write ' -- ' instead)" ;;
    esac
  fi
done

# ---------------------------------------------------------------------------
# skill-paths: a skill calls its own scripts as ~/.agents/skills/<name>/...,
# never through one harness's directory. Two kinds of line may still name a
# harness directory: one that lists ~/.agents/skills/ alongside it (an
# allowed-tools entry covering every install location), and Claude Code hook
# config ("command": ...), which AGENTS.md lets keep ~/.claude/skills/.
# ---------------------------------------------------------------------------
for s in "${SKILLS[@]}"; do
  is_vendored "$s" && continue
  for f in agent/skills/$s/SKILL.md agent/skills/$s/SKILL.zh.md; do
    [ -f "$f" ] || continue
    hits=$(grep -nE '(~|\$HOME)/(\.claude/skills|\.gemini/config/skills)/[A-Za-z0-9_-]+/(scripts|references)/' "$f" \
           | grep -v -e '\.agents/skills/' -e '"command":' | cut -d: -f1 | tr '\n' ' ')
    [ -n "$hits" ] && err "skill-paths: $f:${hits%% *}: harness-specific skill path on line(s) ${hits% }; use ~/.agents/skills/$s/... plus a Paths note"
  done
done

# ---------------------------------------------------------------------------
# links: relative Markdown links resolve, and so does their #fragment when it
# points into a Markdown file ("see 3.2" links rot silently when a heading is
# renamed). Code spans and fenced blocks are skipped; URLs and Windows drive
# paths (/C:/...) are not repository links.
#
# Heading slugs follow GitHub: drop markup, lowercase ASCII, delete
# punctuation and symbols, one '-' per space, '-1', '-2' ... for repeats.
# mawk and gawk both work on bytes, so non-ASCII punctuation is deleted from
# an explicit list (UTF-8 written as octal escapes to keep this file ASCII);
# a heading using a symbol not on the list yields a false "no such anchor" --
# add the symbol to PUNCT below.
# ---------------------------------------------------------------------------
SLUGS=$(awk '
  BEGIN {
    PUNCT = "\357\274\210|\357\274\211|\357\274\232|\357\274\214|\357\274\233|\357\274\201|\357\274\237"  # fullwidth ( ) : , ; ! ?
    PUNCT = PUNCT "|\343\200\202|\343\200\201|\343\200\214|\343\200\215|\343\200\216|\343\200\217"       # CJK . , and corner brackets
    PUNCT = PUNCT "|\343\200\212|\343\200\213|\343\200\220|\343\200\221"                                  # CJK angle and lenticular brackets
    PUNCT = PUNCT "|\342\200\234|\342\200\235|\342\200\230|\342\200\231|\342\200\224|\342\200\223|\342\200\246"  # curly quotes, dashes, ellipsis
    PUNCT = PUNCT "|\302\267|\342\206\222|\342\206\220|\342\234\205|\342\235\214|\342\232\240|\357\270\217"      # middle dot, arrows, check/cross/warning
  }
  FNR == 1 { fence = 0; delete seen }
  /^[ \t]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^#+[ \t]/ {
    h = $0
    sub(/^#+[ \t]+/, "", h); sub(/[ \t]+#+[ \t]*$/, "", h); sub(/[ \t]+$/, "", h)
    while (match(h, /!?\[[^]]*\]\([^)]*\)/)) {           # [text](url) -> text
      l = substr(h, RSTART, RLENGTH); sub(/^!?\[/, "", l); sub(/\]\(.*$/, "", l)
      h = substr(h, 1, RSTART - 1) l substr(h, RSTART + RLENGTH)
    }
    gsub(/<[^>]*>/, "", h)                               # inline HTML
    h = tolower(h)
    gsub(PUNCT, "", h)
    gsub(/[!-,.\/:-@[-^`{-~]/, "", h)                    # ASCII punctuation except - and _
    gsub(/[*]/, "", h)
    gsub(/ /, "-", h)
    s = h; if (h in seen) s = h "-" seen[h]; seen[h]++
    print FILENAME "\t" s
  }
  { while (match($0, /<a (id|name)="[^"]+"/)) { a = substr($0, RSTART, RLENGTH); sub(/^<a (id|name)="/, "", a); sub(/"$/, "", a); print FILENAME "\t" a; $0 = substr($0, RSTART + RLENGTH) } }
' "${MD[@]}")

while IFS=$'\t' read -r f n t; do
  case "$t" in http://*|https://*|mailto:*|\<*) continue ;; esac
  p=${t%%#*}; p=${p%%\?*}
  frag=""; case "$t" in *\#*) frag=${t#*#} ;; esac
  printf '%s' "$p" | grep -Eq '^/[A-Za-z]:/' && continue
  if [ -n "$p" ]; then
    p=$(printf '%b' "${p//%/\\x}")   # %20 and friends
    case "$p" in /*) r=".$p" ;; *) r="$(dirname "$f")/$p" ;; esac
    [ -e "$r" ] || { err "links: $f:$n: broken relative link -> $t"; continue; }
    r=$(realpath -m --relative-to=. "$r")
  else
    r=$f
  fi
  [ -n "$frag" ] || continue
  case "$r" in *.md) ;; *) continue ;; esac    # only Markdown headings are known
  frag=$(printf '%b' "${frag//%/\\x}" | tr 'A-Z' 'a-z')
  grep -qxF "$r"$'\t'"$frag" <<<"$SLUGS" || err "links: $f:$n: no heading for #$frag in $r"
done < <(awk '
  FNR == 1 { fence = 0 }
  /^[ \t]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  {
    line = $0
    gsub(/`[^`]*`/, "", line)
    while (match(line, /\]\([^) ]+( "[^"]*")?\)/)) {
      t = substr(line, RSTART + 2, RLENGTH - 3); line = substr(line, RSTART + RLENGTH)
      sub(/ ".*$/, "", t)
      print FILENAME "\t" FNR "\t" t
    }
  }' "${MD[@]}")

# ---------------------------------------------------------------------------
# at-forward: no tracked file that is nothing but `@path` import lines. Another
# harness sees an 11-byte file; the link dangles in the public repos.
# ---------------------------------------------------------------------------
for f in "${MD[@]}"; do
  if [ -s "$f" ] && ! grep -qvE '^[[:space:]]*(@[^[:space:]]+)?[[:space:]]*$' "$f" && grep -q '@' "$f"; then
    err "at-forward: $f: file is only @path imports; ship the original as a whole file"
  fi
done

# ---------------------------------------------------------------------------
# pairs: bilingual pairs exist. Every x.zh.md has its x.md; the pairs AGENTS.md
# names explicitly exist on both sides. With --base, a pair where only one side
# changed is a warning (a typo fix on one side can be legitimate).
# ---------------------------------------------------------------------------
REQUIRED_PAIRS=(
  README.md conventions.md redaction.md linux-bootstrap/README.md
  agent/skills/antigravity-cli/SKILL.md agent/skills/antigravity-cli/TROUBLESHOOTING.md
  agent/skills/docx-to-md/SKILL.md agent/skills/pdf-to-md/SKILL.md agent/skills/linux-cjk-font/SKILL.md
)
for en in "${REQUIRED_PAIRS[@]}"; do
  zh=${en%.md}.zh.md
  [ -f "$en" ] || err "pairs: $en: missing (AGENTS.md names it as half of a pair)"
  [ -f "$zh" ] || err "pairs: $zh: missing (AGENTS.md names it as half of a pair)"
done
for f in "${MD[@]}"; do
  case "$f" in *.zh.md) [ -f "${f%.zh.md}.md" ] || err "pairs: $f: Chinese translation without its English original ${f%.zh.md}.md" ;; esac
done
if [ -n "$BASE" ]; then
  mb=$(git merge-base "$BASE" HEAD) || { echo "no merge base with $BASE" >&2; exit 2; }
  changed=$(git diff --name-only "$mb" -- ; git diff --name-only --cached "$mb" --)
  changed=$(printf '%s\n' "$changed" | sort -u)
  for f in "${MD[@]}"; do
    case "$f" in *.zh.md) continue ;; esac
    zh=${f%.md}.zh.md
    [ -f "$zh" ] || continue
    a=0; b=0
    grep -qxF "$f" <<<"$changed" && a=1
    grep -qxF "$zh" <<<"$changed" && b=1
    [ "$a" != "$b" ] && warn "pairs: $( [ $a = 1 ] && echo "$f changed, $zh did not" || echo "$zh changed, $f did not" ) since $BASE"
  done
fi

# ---------------------------------------------------------------------------
# pitfall-parity: the pitfall index has the same number of rows in README.md
# and README.zh.md. A row added on one side only is the usual drift.
# ---------------------------------------------------------------------------
count_rows() { awk -v h="$2" '$0 == h { p = 1; next } p && /^## / { exit } p && /^\| / { n++ } END { print (n > 2 ? n - 2 : 0) }' "$1"; }
en_rows=$(count_rows README.md '## Pitfall index')
zh_rows=$(count_rows README.zh.md "$(printf '## \xe8\xb8\xa9\xe5\x9d\x91\xe7\xb4\xa2\xe5\xbc\x95')")
if [ "$en_rows" = 0 ] || [ "$zh_rows" = 0 ]; then
  err "pitfall-parity: could not find the pitfall index table (README.md: $en_rows rows, README.zh.md: $zh_rows rows); heading renamed?"
elif [ "$en_rows" != "$zh_rows" ]; then
  err "pitfall-parity: README.md has $en_rows pitfall rows, README.zh.md has $zh_rows"
fi

# ---------------------------------------------------------------------------
# proxy-mirror: the proxy probe in the Fedora bash-only copy is verbatim from
# shell_common section 5. The one sanctioned difference is the clean-slate
# block (the Fedora copy has it above its section 5), which is cut out of the
# canonical side before comparing.
# ---------------------------------------------------------------------------
CANON=shell/files/shell_common
MIRROR=linux-desktop/fedora/files/bashrc.d/50-proxy.sh
if [ -f "$CANON" ] && [ -f "$MIRROR" ]; then
  a=$(awk '/^# 5\. Proxy/ { p = 1 } p && /^# 6\. / { exit } p' "$CANON" \
      | awk '/^# Start from a clean slate/ { skip = 1 } skip && /^unset http_proxy/ { skip = 2; next } skip == 2 && /^$/ { skip = 0; next } !skip' \
      | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | sed '/^# -\{20,\}$/{$d}')
  b=$(awk '/^# 5\. Proxy/ { p = 1 } p' "$MIRROR" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
  a=$(printf '%s\n' "$a" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
  if [ -z "$a" ] || [ -z "$b" ]; then
    err "proxy-mirror: could not find '# 5. Proxy' in $CANON or $MIRROR; section renamed?"
  elif [ "$a" != "$b" ]; then
    err "proxy-mirror: $MIRROR section 5 differs from $CANON section 5 (diff them; edit the canonical file, then mirror)"
    diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -20 | sed 's/^/    /'
  fi
else
  err "proxy-mirror: $CANON or $MIRROR is missing; update this check and AGENTS.md together"
fi

# ---------------------------------------------------------------------------
# skills-tables: every skill directory has a row in both tables of
# agent/skills/README.md -- the platform table and the per-machine install
# matrix (the two tables whose header starts with "| skill |") -- and no row
# names a skill that does not exist.
# ---------------------------------------------------------------------------
SR=agent/skills/README.md
tables=$(awk '/^\| skill \|/ { t++ } /^$/ { if (t) intable = 0 } /^\| skill \|/ { intable = 1; next } intable && /^\| `/ {
  split($0, cell, "|"); first = cell[2]
  while (match(first, /`[a-z0-9-]+`/)) { print t "\t" substr(first, RSTART + 1, RLENGTH - 2); first = substr(first, RSTART + RLENGTH) }
}' "$SR")
ntables=$(printf '%s\n' "$tables" | cut -f1 | sort -u | grep -c .)
if [ "$ntables" != 2 ]; then
  err "skills-tables: $SR: expected 2 tables headed '| skill |', found $ntables"
else
  for s in "${SKILLS[@]}"; do
    for t in 1 2; do
      label=$([ $t = 1 ] && echo "platform table" || echo "install matrix")
      grep -qxF "$t"$'\t'"$s" <<<"$tables" || err "skills-tables: $SR: skill '$s' has no row in the $label"
    done
  done
  while IFS=$'\t' read -r t s; do
    [ -d "agent/skills/$s" ] || err "skills-tables: $SR: table $t names '$s', which is not a skill directory"
  done <<<"$tables"
fi
count_said=$(sed -n '1,5p' "$SR" | grep -oE '^[0-9]+ ' | head -1 | tr -d ' ')
if [ -n "$count_said" ] && [ "$count_said" != "${#SKILLS[@]}" ]; then
  err "skills-tables: $SR:3: says $count_said skills, there are ${#SKILLS[@]}"
fi

# ---------------------------------------------------------------------------
echo
if [ "$errors" -gt 0 ]; then
  echo "RESULT: $errors error(s), $warnings warning(s)."
  exit 1
fi
echo "RESULT: no errors, $warnings warning(s). Necessary, not sufficient: read the diff."
exit 0
