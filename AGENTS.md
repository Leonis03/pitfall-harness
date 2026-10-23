# AGENTS.md -- entry point for AI agents working in this repo

## What this repo is

One person's dev-environment config, agent skills, and debugging notes, across several machines:

- Windows 11 + WSL2 (Ubuntu 24.04, migrating to Fedora 44)
- a native Linux desktop (Linux Mint 22)
- Android (Termux root chroot, Honor tablet Linux Lab) -- `honor-linuxlab/` plus skills
- rented cloud GPU boxes (DeepLN) -- covered only by skills

This repo treats the AI agent as a **system operator**. Humans define goals in natural language,
prompting the agent to conduct empirical, vibe-driven exploration in real environments. Once an
operation succeeds, findings are solidified into verifiable, reproducible Markdown, configs,
scripts, and skills so future agents never have to re-explore from scratch:

```text
Natural language goal -> Agent directly operates live system -> Observe symptoms ->
Empirically prove root causes -> Working config/solution -> Solidify into configs,
scripts, READMEs, skills, & checklists -> Future agents reproduce via deterministic knowledge.

One-off Agent Exploration -> Experience -> Structured Conclusions (Config/README/Skill)
-> Executable Specifications -> Future Agent Reuse
```

Markdown is split into **agent-facing** (written in English first, the format agents process best)
and **human-facing** (direct Chinese translations for human reference).

Two kinds of content: **deployable originals** (config files copied to a live location) and
**docs** (conclusions from debugging). This is the private primary repo
(`pitfall-harness-private`). `tools/publish.sh` exports `origin/main` into two public repos:
`pitfall-harness` (the whole tree) and `pitfall-harness-skills` (the skills, minus the
vendored `find-skills`). So everything tracked must be publishable, except `drafts/`, which
stays private (see below).

## Map

| Path | What | Deploys to |
| :--- | :--- | :--- |
| `shell/files/` | four-layer bash/zsh config, shared by WSL and native Linux | `~/.shell_common` `~/.shell_wslfn` `~/.zshenv` `~/.zshrc` `~/.bashrc` `~/.profile` (cp) |
| `wsl/setup/` | WSL rebuild guide; `files/` = WSL-only originals | `/etc/wsl.conf`, `%USERPROFILE%\.wslconfig`, `/etc/fstab` (append), `/etc/systemd/system/`, `~/.local/bin/wslview` |
| `wsl/distro-differences.md` | Ubuntu vs Fedora differences | -- |
| `wsl/uninstall-cleanup.md` | uninstalling WSL, residue cleanup | -- |
| `wsl/gui-ime/` | WSLg GUI apps, fcitx5 | -- |
| `wsl/storage/` | disk guides; `forensics/` = raw evidence from one incident, read-only history | -- |
| `linux-desktop/` | Mint desktop notes (sections 2.x) and `gui-and-ime.md` (Fcitx5, Rime, fonts, tools, pnpm); `files/` = Ghostty, Nemo, fontconfig, pnpm originals | `~/.config/ghostty/config`, `~/.local/share/nemo/actions/`, `/etc/fonts/conf.avail/`, `~/.config/pnpm/` |
| `honor-linuxlab/` | Honor tablet Linux Lab (PRoot): what the vendor docs and the vendor assistant never cover; `docs-gap.md` = unit-by-unit comparison against the bundled guide; `files/` = fingerprint script | -- |
| `windows/` | `setup/` = the LTSC setup runbook (hand the whole file to an agent); `files/` = deployable originals; plus Terminal, PowerShell (incl. Typora close/kill scripts), IME / keyboard layouts, context menu, Windows Update | `$PROFILE` (`Microsoft.PowerShell_profile.ps1`), `.reg` imports |
| `os-install/` | OS installation notes and the contracts that cross the install boundary; `dual-boot-time-sync.md` = the RTC/UTC clock contract between a dual-booted Windows and Linux; `files/` = read-only probe scripts | -- |
| `agent/claude-code/` | `settings.json`, `claude-global.md`, `statusline-command.sh`, `files/claude-wrapper.sh` | `~/.claude/` (`claude-global.md` -> `~/.claude/CLAUDE.md`); `files/claude-wrapper.sh` -> `~/.local/bin/claude` |
| `agent/minimax-code/` | `agents-windows.md` = the Windows global rules, with measured environment facts, the ghost-command table, the three encoding layers, and the read-before-you-run routing | `~/.minimax/AGENTS.md` (`cp`) |
| `agent/windows-agent/` | `agents-additional.md` = what a Windows AGENTS.md should add and why, one measured basis per rule; the design note behind `minimax-code/` | -- |
| `agent/antigravity/` | `agents-brave-uv.md` + agy notes | `~/.gemini/config/AGENTS.md` |
| `agent/brave-search/` | bx CLI and Brave MCP notes; `files/setup-bx-linux.sh` (WSL / Linux) and `files/setup-bx-windows.ps1` = setup scripts | run them (install into `~/.local/bin`, write the `bx` wrapper) |
| `agent/skills/<name>/` | one skill each; install matrix in `agent/skills/README.md` | `~/.claude/skills/`, `~/.gemini/config/skills/`, `~/.agents/skills/` -- **only** via `tools/sync-skills.sh`; also published as `skills/<name>/` in the skills repo |
| `git-github/` | git/gh setup, history email scrub runbook | -- |
| `tools/` | repo scripts `privacy-gate.sh`, `sync-skills.sh`, `publish.sh`; notes `python/`, `remote-ssh.md`, `docker/`, `latex/` | -- |
| `tmp/` | scratch area, gitignored | never committed |
| `drafts/` | private-only: half-finished notes and the to-do list for them; tracked here, **never exported** | `tools/publish.sh` deletes it from the export; promote a draft by moving it into its real directory |

Every top-level directory except `tmp/` has a `README.md` index (`drafts/` too). Read it before editing inside that directory.

## Request -> files to edit

| The user wants to... | Edit | Also |
| :--- | :--- | :--- |
| change an env var, PATH, proxy, or shell helper | `shell/files/shell_common` (Windows interop functions: `shell_wslfn`) | obey the three rules in `shell/README.md`: zsh-only -> `zshrc`, bash-only -> `bashrc`, functions not aliases |
| change WSL VM or distro settings | `wsl/setup/files/*` and the matching step in `wsl/setup/README.md` | the verification checklist (section 4) if behavior changes |
| record an Ubuntu/Fedora difference | `wsl/distro-differences.md` | -- |
| fix or set up something on the Linux desktop | `linux-desktop/README.md` (next 2.x section), configs in `linux-desktop/files/` | pitfall index rows |
| fix or set up something on the Honor tablet Linux Lab | `honor-linuxlab/README.md` (next 2.x section), runbooks in `honor-linuxlab/` | pitfall index rows; check `honor-linuxlab/docs-gap.md` first so you do not rewrite what the vendor guide already covers |
| change Windows-side config | `windows/<area>/`, deployable originals in `windows/files/` | -- |
| configure a fresh Windows machine | `windows/setup/README.md` (the runbook) | it must stay probe-based: no machine-specific paths, profile names or versions -- see the "换机器复现时的差异" table |
| fix a clock or UTC-offset problem on a dual-booted machine | `os-install/dual-boot-time-sync.md`, probes in `os-install/files/` | the RTC convention is a two-sided contract: `RealTimeIsUniversal` on Windows, `LocalRTC` on Linux -- check both before changing either; pitfall index rows in both root READMEs |
| change the proxy port or the proxy environment variables | `shell/files/shell_common` (probes the common ports and exports only the ones that answer a protocol handshake), `windows/files/powershell/set-proxy-env.ps1` | a listening port is not a proxy: the handshake decides, so a web server on 8080 is not picked up; one port per variable, so ALL_PROXY never lands on an HTTP port; a client in TUN mode opens no local port, so the variables stay unset there; background: `agent/skills/android-chroot-debian/references/proxy-and-socket-pitfalls.md` |
| change Claude Code settings, global rules, statusline | `agent/claude-code/*` | keep byte-identical to the live copy; `agent/claude-code/README.md` if a key's rationale changes |
| change Antigravity global rules | `agent/antigravity/agents-brave-uv.md` | not `agents-brave-uv-desktop.md` (another environment) |
| add or change a skill | `agent/skills/<name>/SKILL.md`, `scripts/`, `references/` | see "must change together"; then `bash tools/sync-skills.sh` (check) / `deploy <name>` |
| record a new pitfall | the doc of the area it belongs to | one row in `README.md` pitfall index first, then sync direct translation to `README.zh.md` |
| add notes on git, Python, SSH, Docker, LaTeX | `git-github/`, `tools/python/`, `tools/remote-ssh.md`, `tools/docker/`, `tools/latex/` | -- |
| move, rename, or add a directory | the files (`git mv`) | `git grep` the old path and fix every link; the directory README; both root READMEs; this file |
| publish to the public repos | nothing -- run `bash tools/publish.sh <public clone> <skills clone>` | only after the change is merged to `main`; the user commits and pushes each clone, or explicitly asks you to. Public commit messages carry **no AI `Co-Authored-By` trailer**, whatever your harness defaults to |

## Must change together

- `README.md` <-> `README.zh.md`, `conventions.md` <-> `conventions.zh.md`, `redaction.md` <-> `redaction.zh.md`. English first (agent baseline), Chinese direct translation (human reference).
- `SKILL.md` <-> `SKILL.zh.md` in `antigravity-cli`, `docx-to-md`, `pdf-to-md`, `linux-cjk-font`; `TROUBLESHOOTING.md` <-> `TROUBLESHOOTING.zh.md` in `antigravity-cli`. The harness loads the English file.
- A new skill -> a row in both tables in `agent/skills/README.md`: the platform table (`if` / `only if`
  Windows / WSL / Linux / Android) and the per-machine install matrix. Install it with `mkdir` plus
  `sync-skills.sh deploy <name>`, never `cp`.
- A layout change, a new deploy target, or a new pair above -> this file, in the same commit.
- Repo original <-> live copy: editing the repo does not deploy. Deploy (cp, or `sync-skills.sh deploy`) only when the user asks, and back up the live file into `tmp/` first.

## Rules that fail silently when broken

- **ASCII only** in file and directory names, config files (comments included), skill YAML frontmatter, and this file.
- **LF line endings, in the repository and in the working tree.** `.gitattributes` pins this
  (`* text=auto eol=lf`; `.bat`, `.cmd` and `.reg` stay CRLF in the working tree only), so no
  machine's `core.autocrlf` decides for everyone. On Windows, write files with a tool that emits
  the bytes you hand it and put `\n` in the content -- `[IO.File]::WriteAllText($path, $content)`.
  `Set-Content`, `Out-File` and `[IO.File]::WriteAllLines` go through `Environment.NewLine` and
  emit CRLF. A substring-replace edit normalizes to the file's existing line ending, so converting
  one means rewriting it whole, not patching it. Details: `conventions.md`.
- **No `@path` forwarding in a tracked file.** A root `CLAUDE.md` once held nothing but
  `@AGENTS.md`, relying on one harness's import syntax: another harness sees an 11-byte
  file, and the link dangles in the public repos. Ship the original as a whole file.
- A skill calls its own scripts as `~/.agents/skills/<name>/scripts/...`, never a harness-specific directory,
  with a "Paths" note at the first use saying `~/.claude/skills/`, `~/.gemini/config/skills/` or a path relative
  to the SKILL.md work as well. Only Claude Code hook config keeps `~/.claude/skills/`.
- An unquoted skill `description` must not contain `: ` or ` #` (write ` -- `): Claude Code loads it anyway, strict parsers such as `npx skills` drop the skill silently.
- Markdown filenames are lowercase kebab-case; point-in-time records end in `-YYYYMMDD`.
- **No `AGENTS.md` or `CLAUDE.md` below the root**: harnesses load them as instructions. Originals get other names (see Map).
- **No real identifiers** in tracked files: usernames, hostnames, IPs, ports, emails, tokens, session IDs.
  Write `$HOME` where a shell expands it, detect at runtime where possible, else use a placeholder
  (`<your-home>`, `<your-linux-user>`, `<your-windows-user>`, `<proxy-port>`, `<ssh-port>`, `<instance-domain>`). Details: `redaction.md`.
- Skills are deployed with `tools/sync-skills.sh`, never `cp` or `ln -s`: the repo copy is redacted.
- Vendored skills (`find-skills`, `skill-creator`) are verbatim upstream copies: do not apply this repo's skill
  rules to them, update by re-copying the whole directory, credit them in the README's third-party section.
  `publish.sh` leaves them out of the skills repo (its `VENDORED` list).
- Python runs through `uv run --python 3.12`, never the system `python3`.
- Scratch files, raw command output, and backups go in `tmp/`, not the repo root or `/tmp`.

## Before committing

1. `bash tools/privacy-gate.sh` -- needs account names from `tools/.privacy-names` (gitignored, per machine) or as arguments;
   without them the literal-name check is skipped. Hits on the public author name in `LICENSE` and copyright lines are expected.
   A pass covers known shapes only: also read your diff, and read anything under `wsl/storage/forensics/` line by line.
2. Check that the relative links you touched resolve.

## Git workflow

- Several machines push to this repo, and another agent session may be using the same checkout.
  `git fetch` first; if the working tree changes under you, work in `git worktree add tmp/<name>`.
- Work on a branch and open a PR against `main`. Merge only when the user asks, with a merge commit (`gh pr merge --merge`).
- Never force-push `main` of this repo. The public repos are updated only through `tools/publish.sh`, never
  with `cp -r`, with normal commits.
- Public repos: no AI `Co-Authored-By` trailer in any commit -- GitHub lists co-authors under Contributors. The
  clones' commit-msg hook (installed by `publish.sh`) rejects one. Rewriting public history and force-pushing is
  allowed only to remove such a trailer, private data or a credential, or a comparable special case: keep a local
  backup branch first, push with `--force-with-lease=main:<old SHA>`, then rename the default branch away and back
  so GitHub rebuilds its cached Contributors box. `agent/skills/github-coauthor-scrub/` scripts every step
  (`scan`, `rewrite`, `refresh`, `verify`, `hook`); see `conventions.md`.
