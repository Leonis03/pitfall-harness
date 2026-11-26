# Global Conventions

## Web Search

`bx` (Brave Search CLI) complements the built-in `WebSearch`: it adds publication dates,
freshness windows, non-US/non-English results and site scoping, at ~200 tokens/query. Scan
with `bx`, then `WebFetch` the 2-3 URLs worth reading. Raw output is ~120x larger -- never run
`bx` without the jq filter below; it works for `web`/`news`/`images`/`videos` alike.

```bash
# keep J= in the same Bash call: shell variables do not persist between calls
J='(.web.results // .results // []) | if length == 0 then "NO RESULTS" else .[] | "\(.title)\n  \(.url)  \((.page_age // "")[:10])\n  \((.description // "")[:160])\n" end'

# web or news; optional: --freshness pd|pw|pm|py|YYYY-MM-DDtoYYYY-MM-DD,
# --country CN --search-lang zh-hans, ONE of --include-site X / --exclude-site X / --goggles (else exit 2)
bx news "openssl vulnerability" --freshness pw --country US --count 8 | jq -r "$J"

# search + scrape + extract in one call (~1k tokens); --max-tokens must be >= 1024
bx "Python TypeError cannot unpack non-iterable NoneType" --max-tokens 1024 \
  | jq -r '.grounding.generic[] | "[\(.title)] \(.url)\n\(.snippets | join("\n"))\n"'
```

Read the `bx` skill only for `answers`/`places`, `--extra`/`--offset`, or a non-zero exit.
Do not load the `mcp__brave-search__*` MCP tools.

**Search query language:** default to English keywords unless the target information is
specific to the Chinese internet.

## Python Environment

- **Python & Package Management**: Python and dependencies are managed exclusively via `uv`
  using Python 3.12 (globally pinned in `~/.config/uv/.python-version`).
- **Execution Command**: Always run Python code and scripts using `uv run` or
  `uv run --python 3.12`. Never use the system `/usr/bin/python3` directly (reserved strictly
  for host OS packages), unless the user explicitly requests it. When injecting third-party
  packages, use repeated `--with` flags (e.g. `uv run --python 3.12 --with numpy --with scipy`,
  not `--with numpy,scipy`), and pin exact versions (e.g. `--with numpy==2.5.3`) whenever
  numerical reproducibility is required.
- **Output Buffering (`PYTHONUNBUFFERED=1`)**: `uv run` does not accept the `-u` flag. In
  non-TTY contexts (long-running scripts, background tasks, pipes, redirections) stdout
  defaults to 4 KB block buffering, producing empty or delayed logs. Always prepend
  `PYTHONUNBUFFERED=1` (e.g. `PYTHONUNBUFFERED=1 uv run --python 3.12 ...`) to keep output
  flushing in real time and avoid misdiagnosing a working process as hung.

## Keep These Surfaces Pure ASCII

Non-ASCII in the wrong place fails silently and far from its cause -- across the WSL/Windows
boundary, in archives, in shell and harness parsing. Keep ASCII-only:

- **Directory and file names.** No CJK, no spaces, no accents, no emoji. Applies to repos,
  skills, scripts and generated artifacts alike.
- **System and tool config files, comments included** -- dotfiles, shell rc, `settings.json`,
  `~/.claude/*`, `.reg`, systemd units. Write the comments in English.
- **Every skill's YAML frontmatter, `description` above all.** It is loaded into every
  session and matched against to decide triggering.

Prose docs (`README.md`, `references/*.md`, a skill's body below the frontmatter) may be
Chinese -- the surfaces above may not.

## Installing Skills and Configs

Copy files with `cp`. Do not use `ln -s`, and do not point an entry under `~/.claude/skills/`
at a cloned source repo -- this tree gets moved between machines, filesystems and operating
systems, and symlinks do not survive that. Copy only the files a skill needs at runtime,
not the whole development repo.
