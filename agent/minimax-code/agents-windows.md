# Global Conventions -- Windows

Windows 11 IoT Enterprise LTSC. The default shell is PowerShell 7.6.7 Core.
Where this file disagrees with the Linux/WSL global file, **this one wins on this
box**. Anything below that is not labelled "measured" is inherited from the
shared conventions; everything labelled it was verified here.

> **This machine's toolchain drifts, so re-verify instead of trusting a
> remembered baseline.** Several sessions install things in parallel: on
> 2026-10-17 `uv`, `bx`, `jq` and the WSL component all appeared between two
> consecutive checks a few hours apart, and Node.js arrived via an EXE installer
> rather than a package manager. A baseline written yesterday is wrong today in
> ways that are silent -- `Get-Command` still resolves a command that no longer
> works. **Probe before you build a command on top of any of this.** The tables
> below record what was true on 2026-10-17, not a promise.

---

## Verify a Tool Is Real Before You Trust It

On Windows a command name can resolve to an App Execution Alias or a Store stub
instead of a real binary. It is on PATH and `Get-Command` finds it, yet invoking
it either fails or opens a download page. Measured on this machine:

| Command | Resolves to | Reality |
| :--- | :--- | :--- |
| `bash` | `C:\WINDOWS\system32\bash.exe` (86 KB, real) | The WindowsApps alias is **off**; the inbox binary serves instead. Debian 13 trixie on WSL2, works |
| `wsl` | `C:\WINDOWS\system32\wsl.exe` (274 KB, real) | Always resolved here, never via the alias. **Writes UTF-16LE when captured** -- every character is followed by a NUL byte, so no regex matches across it. Strip the NULs before parsing |
| `python3` | `D:\APP\python313\python3.exe` | A **hard link** to `python.exe`, added 2026-10-17 after the Store stub behind the alias opened a download page and exited 9009. Same file, no extra disk. A `.cmd` shim would *not* work: `CreateProcess` does not resolve `.CMD`, so `subprocess.run(['python3', ...])` would fail |
| `python` | `D:\APP\python313\python.exe` (103 KB, real) | 3.13.16 |
| `python3.12` | `%USERPROFILE%\.local\bin\python3.12.exe` | uv-managed, 3.12.15 -- matches what the repo pins |
| `jq` | `%LOCALAPPDATA%\Microsoft\WinGet\Links\jq.exe` | **0 bytes and working** -- a winget portable shim, not a stub |
| `winget` | `%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe` | 0 bytes and working -- `v1.29.290`. **This alias is the only path to the command**; turning it off deletes `winget` |
| `wt` | `%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe` | 0 bytes and working, but `wt --version` prints **nothing** (GUI app). **Also the only path** -- turning it off deletes `wt` |
| `wslconfig` | `C:\WINDOWS\system32\wslconfig.exe` | Alias off; opens a GUI window and never returns |
| `npm` | `D:\APP\nodejs\npm.ps1` | A `.ps1` shim. Under a restrictive execution policy PowerShell will refuse it; call `npm.cmd` |

**App Execution Aliases are a system setting, not a PATH entry.** Turning one off
removes the `WindowsApps` reparse point, so the command either disappears or falls
back to another binary on PATH -- both happen here. Check *which* before flipping
anything: `wt` and `winget` have no fallback. The full procedure, including the
commands you must never probe, is in `agent/windows-agent/ghost-commands.md`.

**File size is a hint, not a verdict.** Both a working 0-byte shim (`jq`) and a
broken 0-byte stub (`bash`) live on this box, and they look identical from the
filesystem. The only test that counts is invoking it:

```powershell
$c = Get-Command <name> -ErrorAction SilentlyContinue
$c.Source; (Get-Item $c.Source).Length      # 0-2 bytes => reparse point, look closer
& $c.Source --version                       # <- this is the actual test
```

Absent here, so do not assume them: `rg`, `fd`, `docker`, `7z`, `make`, `gcc`.
Use the built-in Grep tool instead of `rg`. Present but installed by a parallel
session and therefore worth re-probing: `uv`, `uvx`, `bx`, `jq`, `wsl`,
`python3.12`. Node.js came from an EXE installer into `D:\APP\nodejs` (v24.22.0,
npm 11.21.1), so its `npm` / `npx` are `.ps1` shims.

## Web Search

Same CLI as the Linux side. `bx` writes JSON to stdout. Two rules make an
unassisted call safe: **always project through jq** (raw output is ~120x the
tokens -- measured 31 KB for a 3-result query, 9 KB for 2), and **mind the
result path per subcommand** -- `web` puts rows under `.web.results[]`, everything
else under `.results[]`.

Measured on jq 1.8.2, a wrong path is **not** always silent. Iterating a missing
key fails loudly; only a non-iterating access passes quietly:

| Expression | Exit | Output |
| :--- | :---: | :--- |
| `.web.results[].url` | 0 | the URLs |
| `.results[].url` | **5** | `jq: error: Cannot iterate over null (null)` |
| `.web.resultz[].url` | **5** | same error |
| `.results.url` | **0** | `null` -- silent, this is the one to watch |

So check the exit code, and treat a printed `null` as a failed lookup.

```bash
# triage -- URLs only, ~180 tokens
bx web "axum middleware ordering" --include-site docs.rs --count 10 | jq -r '.web.results[].url'

# normal search -- title, url, snippet
bx web "query" --count 5 | jq -r '.web.results[] | "\(.title)\n  \(.url)\n  \(.description)\n"'

# news with publication dates; --freshness pd|pw|pm|py or YYYY-MM-DDtoYYYY-MM-DD
bx news "openssl vulnerability" --freshness pw --count 5 | jq -r '.results[] | "\(.title)\n  \(.url)  [\(.age)]"'

# non-US / non-English (--country, --search-lang; also valid on news/context)
bx web "PaddleOCR" --country CN --search-lang zh-hans --count 5 | jq -r '.web.results[] | "\(.title)  \(.url)"'

# RAG grounding: search + scrape + extract in one call; --max-tokens must be >= 1024
bx "Python TypeError cannot unpack non-iterable NoneType" --max-tokens 2048 \
  | jq -r '.grounding.generic[] | "[\(.title)] \(.url)\n\(.snippets | join("\n"))\n"'
```

Native projection, when you would rather not shell out -- the `.web.results` vs
`.results` split is identical:

```powershell
$raw = bx web "query" --count 5
($raw | ConvertFrom-Json).web.results | ForEach-Object { "$($_.title)  $($_.url)" }
```

Read the `bx` skill for anything past that: `answers` (needs its own `--config`),
`images`/`videos`/`places`, `--goggles`/`--exclude-site`/`--extra`/`--offset`, config or
proxy trouble, or any non-zero exit code. Do not load the `mcp__brave-search__*`
MCP tools; the CLI supersedes them.

**Search query language:** default to English keywords unless the target
information is specific to the Chinese internet.

## Python Environment

- **`uv` is present and is the supported way to run Python.** `uv` / `uvx` live in
  `%USERPROFILE%\.local\bin` (measured: uv 0.13.1). Use `uv run --python 3.12 ...`.
- **Do not copy the Linux paths.** Measured here: `uv python dir` ->
  `%APPDATA%\uv\python`, `uv cache dir` -> `%LOCALAPPDATA%\uv\cache`, binaries in
  `%USERPROFILE%\.local\bin` (which also holds `bx.cmd`). Pin per project with
  `uv python pin 3.12` rather than editing a global dotfile.
- **Three Pythons, and the names do not line up with the versions you expect:**

  | Command | Gives you | Notes |
  | :--- | :--- | :--- |
  | `python3.12` | 3.12.15 | uv-managed, in `.local\bin`. Matches what the rules pin |
  | `python` | 3.13.16 | `D:\APP\python313\python.exe`, a real 103 KB binary |
  | `python3` | **exit 9009** | A 0-byte Store stub. Nothing shadows it -- it is simply broken |

  A 0-byte Store stub of `python` also sits in WindowsApps; `D:\APP` comes first
  on PATH, so the working one wins. That is luck of ordering, not design -- if
  PATH order changes, `python` breaks too.
- **Output Buffering (`PYTHONUNBUFFERED=1`)**: `uv run` does not accept `-u`. In
  non-TTY contexts stdout defaults to 4 KB block buffering, producing empty or
  delayed logs. Always prepend `PYTHONUNBUFFERED=1` to avoid misdiagnosing a
  working process as hung.
- **Third-party packages** go in as repeated `--with` flags, pinned exactly when
  reproducibility matters: `uv run --python 3.12 --with numpy --with scipy ...`.

## Windows Shell: Quotes and Escapes

- **Single-quote any argument containing `$`.** In double quotes `$SQL2016` expands
  to empty and the account name silently becomes wrong.
- PowerShell's escape character is the backtick, not the backslash. Inside double
  quotes `` `n `` is a newline and a backtick before `$` suppresses expansion.
- In Git Bash, `"$D\\$f.sql"` is a triple trap: `\\` eats the backslash *and* the
  `$` suppresses expansion, so you get a literal path with no separator.
- GNU `printf` expands `\E` to ESC, turning a Windows path into
  `D:\SQLData<ESC>3.sql` without any error. Use a quoted heredoc
  (`<<'EOF'`), never `printf`, for Windows paths.
- Pipe through `Select-Object -First N` rather than `head` when you are in
  PowerShell; and remember a pipeline changes an exe's exit code --
  `$LASTEXITCODE` after a pipe is the *last* command's, not the first's.

## Paths

- **A forward slash is an option prefix to many Windows CLIs.** `sqlcmd -i
  "D:/data/x.sql"` makes sqlcmd read `/U` as `-U` and fail with "The -E and
  the -U/-P options are mutually exclusive". Use backslashes, or `Join-Path`.
- Use `$env:USERPROFILE` / `$env:LOCALAPPDATA`, not `~`, when the string must be
  literal. PowerShell expands `~` to `$HOME`, which on Windows is the same
  directory but reads as if it were a POSIX path.
- Relative paths resolve against the tool's working directory, which may differ
  from your prompt's. Prefer absolute paths or `-C`/`--repo`-style options.
- In a worktree `.git` is a *file* holding a gitdir pointer, not a directory, so
  scripts that walk `.git` need `--exclude` as well as `--exclude-dir`.

## Encoding, Console and Text

Three independent layers. Diagnose the right one; changing another achieves
nothing.

| Layer | Set by | Was, measured |
| :--- | :--- | :--- |
| Console code page | `chcp`, `[Console]::OutputEncoding` | **936** |
| .NET / file encoding | `$OutputEncoding`, `Get-Content` | UTF-8 |
| Error message language | `CurrentUICulture` | **zh-CN** |

- **The console code page belongs to the console, not the process.** Measured: a
  child running `chcp 936` changes what the parent sees immediately, and back.
  So a tool that leaves it dirty corrupts the *next* command, and "the same
  command failed once then worked" is a real symptom -- look for leftover state
  before you look for a bug in your code.
- **Encoding is not language.** Mojibake is the first; a Chinese error message is
  the second. Changing the code page never makes a message English.
- **To pin messages to English, set the thread UI culture**:
  `[Threading.Thread]::CurrentThread.CurrentUICulture =
  [Globalization.CultureInfo]::GetCultureInfo('en-US')`. Measured on 7.6.7:
  `$PSUILanguage = 'en-US'` changes the variable and changes no message -- it is
  not the switch. Pinning the UI culture leaves the encoding untouched.
- **Never pipe non-ASCII into a native exe.** Measured: a round trip through
  `cmd`/`findstr` adds a U+FEFF, so 5 characters come back as 6. And
  `.Trim()` eats U+FEFF as whitespace, so a plain `-eq` comparison reports a
  **false pass**. Hand the program a path and let it open the file.
- **Writing files: only `[IO.File]::WriteAllText($p, $s)` with explicit `\n`
  yields LF.** `Set-Content`, `Out-File` and `[IO.File]::WriteAllLines` all go
  through `Environment.NewLine` and emit CRLF. Measured.
- **A substring-replace editor normalizes the replacement to the file's existing
  line ending.** Editing a CRLF file line by line keeps it CRLF indefinitely;
  converting line endings means rewriting the whole file.
- **BOM requirements are opposite across consumers.** Python `json.load()`
  crashes on a BOM-prefixed file; `sqlcmd -i` *prefers* one. Ask who reads the
  file before writing it.
- `Get-Content` on pwsh 7 decodes a GBK file as UTF-8 and returns mojibake.
  Windows PowerShell 5.1 does the opposite. Pass `-Encoding` explicitly whenever
  the file is not known-ASCII.

## Git on Windows

- **No `core.autocrlf` setting changes what is stored.** All three installer
  options leave the repository in LF; they differ only in the working tree.
  `true` = CRLF on checkout, `input` = LF both ways, `false` = no conversion --
  and `false` plus a CRLF working tree is the one path that permanently poisons
  history.
- **`.gitattributes` outranks `core.autocrlf`.** With `* text=auto` present, an
  add under `autocrlf=false` normalizes to LF and `git status` reports nothing to
  commit. Measured.
- **Changing the setting does not rewrite the working tree, and
  `git checkout -f`, `checkout-index -a -f` and `reset --hard` all fail to do
  it** -- git skips paths it considers unchanged and never re-runs the filter.
  What works: `git rm -r -q -f . && git checkout -q HEAD -- .`, after which
  `git status` stays empty.
- Use a noreply address for `user.email`, or the real one is baked into history.
- `gh` may need `gh auth setup-git` before `git push` over HTTPS works.

## Read Before You Run

On Windows **"it ran" does not mean "it ran correctly"**. A command can exit 0
and still have produced wrong bytes, the wrong language, or the wrong line
endings. Stop and read when the command touches any of these:

| The command touches | Read first |
| :--- | :--- |
| `wsl.exe`, `/mnt/c`, driving Windows from Linux | skill `wsl-windows-command` |
| `sqlcmd`, `.sql` files, anything SQL Server | skill `run-sql-file` |
| Registry `.reg` import/export, right-click menus | `windows/context-menu/README.md` |
| Appx side-loading, `winget`, `wt.exe` | `windows/terminal/winget-and-terminal-without-store.md` |
| Multi-line PowerShell, any encoding or CJK question | `windows/powershell/cjk-command-io.md` |
| Git line endings, `.gitattributes`, CRLF | `git-github/crlf-and-diffing.md` |
| WeChat / QQ data export | skills `export-wechat-chat`, `export-qq-chat` |
| A command is on PATH but fails, or opens the Store | `agent/windows-agent/ghost-commands.md` |

And three checks that apply to everything else: never pipe non-ASCII into a
native exe; verify by bytes rather than by string equality; single-quote any
Windows argument containing `$`.

## Verify, Do Not Assume

- **"It exited 0" is not verification.** Keyword-search the output for something
  you know is in it, count what you expect to count, compare bytes.
- **Interactive and GUI commands are meaningless in an agent shell.** Measured:
  `wt --version` returns nothing at all. Check existence and version with
  `Get-Command` / `where.exe` / `--help`, never by launching the app.
- **Compare byte counts, not string equality**, when anything could have added a
  BOM or normalized a newline. Print the first bytes:
  `(Get-Item $p) | ForEach-Object { $b=[IO.File]::ReadAllBytes($_.FullName); ($b[0..7] | ForEach-Object { $_.ToString('X2') }) -join ' ' }`
- **Deletion is not reversible from the agent shell** and the harness may gate
  it. Copy what you are about to remove into a scratch directory first.

## Keep These Surfaces Pure ASCII

Non-ASCII in the wrong place fails silently and far from its cause -- across the
WSL/Windows boundary, in archives, in shell and harness parsing. Keep ASCII-only:

- **Directory and file names.** No CJK, no spaces, no accents, no emoji. Applies
  to repos, skills, scripts and generated artifacts alike.
- **System and tool config files, comments included** -- dotfiles, shell rc,
  `settings.json`, `~/.claude/*`, `.reg`, systemd units. Write the comments in
  English. This file is one of them.
- **Every skill's YAML frontmatter, `description` above all.** It is loaded into
  every session and matched against to decide triggering. An unquoted value
  containing `: ` makes strict parsers drop the skill without an error.

Prose docs (`README.md`, `references/*.md`, a skill's body below the
frontmatter) may be Chinese -- the surfaces above may not.

## Installing Skills and Configs

Copy files with `Copy-Item`. Do not use a symlink, and do not point an entry
under `~/.claude/skills/` at a cloned source repo -- this tree gets moved between
machines, filesystems and operating systems, and links do not survive that. Copy
only the files a skill needs at runtime, not the whole development repo.
