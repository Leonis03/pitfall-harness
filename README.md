# pitfall-harness

*English · [中文](README.zh.md)*

Pitfalls met while setting up machines for AI coding agents -- each with its symptom, its root
cause, and how that cause was proven. The configs are the fish; the debugging method is the
rod. It all comes from one person's several machines, driven mainly by Claude Code and the
Antigravity CLI, with networking through a local proxy. The skills are also published on their
own, ready to install: [pitfall-harness-skills](https://github.com/Leonis03/pitfall-harness-skills).

---

## Philosophy: The Agent as System Operator & Closed-Loop Distillation

This project treats the AI agent as a real-world **system operator**. Humans define goals in natural language, prompting the agent to conduct empirical, vibe-driven exploration in live OS and development environments. Once an operational path succeeds, findings are solidified into verifiable, reproducible, and deployable Markdown, configs, scripts, and skills, ensuring future agents never have to re-explore from scratch.

```text
Natural language goal → Agent directly operates live system & executes commands → Observe symptoms → Pinpoint & empirically prove root causes → Working config/procedure → Solidify into configs, scripts, READMEs, skills, & checklists → Future agents reproduce via deterministic knowledge.

One-off Agent Exploration
            ↓
        Experience
            ↓
   Structured Conclusions
      ↙     ↓      ↘
  Config  README   Skill
      ↘     ↓      ↙
  Executable Specifications
            ↓
    Future Agent Reuse
```

### Documentation Audience & Language Conventions

Markdown files in this repository are strictly divided by audience:
- **Agent-Facing**: Written in the format most natural, context-dense, and unambiguous for LLMs -- **English**.
- **Human-Facing**: Chinese versions serve as human reference, produced via **direct translation** sufficient for human comprehension.
- **English First**: When editing or authoring documentation, **always write the agent-facing English version first**, then directly translate it into Chinese. The former "Chinese canonical first" requirement is eliminated.

---

| Environment | Where |
| :--- | :--- |
| Windows 11 + WSL2 (Ubuntu 24.04; Fedora 44 was tried and abandoned) | [`wsl/`](wsl/) · [`windows/`](windows/) |
| Windows 11 + a Linux distribution on the same machine (dual boot) | [`os-install/`](os-install/) |
| Native Linux desktop (Linux Mint 22; Fedora 44 / KDE was tried and abandoned) | [`linux-desktop/`](linux-desktop/) |
| The four-layer bash / zsh config both of the above share | [`shell/`](shell/) |
| Android (Termux root chroot, Honor tablet Linux Lab) | the `android-chroot-debian` and three sibling skills under [`agent/skills/`](agent/skills/) |
| Rented cloud GPUs (DeepLN) | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) · [`gpu-cuda-checks/`](agent/skills/gpu-cuda-checks/) |

> **AI agents: read [`AGENTS.md`](AGENTS.md) first** -- the directory map, a "to do X, edit
> these files" table, the files that must change together, and the pre-commit checks.

Two kinds of content live here: **config files you can deploy as-is**, and **conclusions left
behind by debugging** -- the latter is usually worth more than the config itself, because it
records *why* things are the way they are.

> **Fedora 44 was tried and abandoned -- in WSL and on the desktop.** For a while day-to-day WSL
> work moved to a Fedora 44 distro next to **Ubuntu 24.04**, and the desktop's SSD ran Fedora 44
> with KDE Plasma on Wayland. Both were given up in 2026-11; Ubuntu 24.04 is the WSL reference.
> What was measured in the meantime stays as a record: the WSL comparison, split into what is
> avoidable and what is not, in [`wsl/distro-differences.md`](wsl/distro-differences.md), and the
> desktop in [`linux-desktop/fedora/`](linux-desktop/fedora/).
>
> Most references to Ubuntu elsewhere in these docs hold; where they do not, the difference is
> recorded in `wsl/distro-differences.md`.

> Every path, username, machine identifier, port and timestamp is redacted (`$HOME`,
> `<your-linux-user>`, `<your-windows-user>`, `<vm-1>`, `<proxy-port>`, `<ssh-port>`, `<t-created>`), and email
> addresses are written as `your-old-email@example.com`. Substitute your own before
> deploying.
>
> The `<t-...>` tokens under `wsl/storage/forensics/` are **stable** placeholders: the same token means
> the same instant wherever it appears, so timestamp columns can still be compared across
> forensic blocks. Intervals between events are spelled out in prose.

---

## Start here

| What you want | Where |
| :--- | :--- |
| **Rebuild the WSL environment on a new Windows machine** | [`wsl/setup/`](wsl/setup/) -- the rebuild guide; you can hand the whole file to an agent |
| **Configure a freshly installed Windows LTSC machine** | [`windows/setup/`](windows/setup/) -- the same shape, for the Windows side |
| **Install a second OS next to Windows and keep both clocks in agreement** | [`os-install/`](os-install/) -- the contracts that cross the install boundary; today: the RTC/UTC clock contract of a dual boot |
| Rebuild on a native Linux desktop | [`linux-desktop/`](linux-desktop/), with the shell config from [`shell/`](shell/) |
| **Provision a freshly installed Linux machine** | [`linux-bootstrap/`](linux-bootstrap/) -- the machine-agnostic bootstrap script, and the shell histories it was mined from |
| Set up Git and GitHub (including the privacy email) | [`git-github/`](git-github/) |
| Set up Claude Code | [`agent/claude-code/`](agent/claude-code/) |
| Find a ready-made skill, or sync skills to this machine | [`agent/skills/`](agent/skills/) -- deploy with `tools/sync-skills.sh`, not `cp` |
| Look up one specific trap | See the pitfall index below |
| Have an AI agent change something in this repo | [`AGENTS.md`](AGENTS.md) -- the agent-facing entry point |
| Understand the writing and publishing rules here | [`conventions.md`](conventions.md) -- ASCII boundaries, naming, `tmp/`, the pre-publish gate, the two-repo sync |
| Understand the placeholder scheme: no real usernames in the repo, yet everything resolves on deploy | [`redaction.md`](redaction.md) -- the three classes of value and the two pipelines |

---

## Layout

Every top-level directory except `tmp/` and `.github/` has a `README.md` index. Where a directory has a `files/`
subdirectory, `files/` holds the deployable originals and everything else is documentation.

### [`shell/`](shell/) -- four-layer bash / zsh config (shared by WSL and native Linux)

`~/.zshenv` -> `~/.shell_wslfn` -> `~/.shell_common` <- `~/.zshrc` / `~/.bashrc`. The README
explains the split and its three hard rules (the shared file holds only what is valid in both
shells, `conda init` is never shared, functions instead of aliases); the originals are in
`files/`. The WSL-only interop functions skip themselves on native Linux via a `/proc/version`
check.

### [`wsl/`](wsl/) -- WSL2

| Directory | Contents |
| :--- | :--- |
| [`setup/`](wsl/setup/) | **The rebuild guide.** `.wslconfig`, `/etc/wsl.conf`, fstab, the binfmt and `/mnt/wsl` guards, apt mirrors, toolchain. `files/` holds the WSL-only originals |
| [`distro-differences.md`](wsl/distro-differences.md) | How Ubuntu 24.04 and Fedora 44 differ |
| [`gui-ime/`](wsl/gui-ime/) | WSLg GUI apps and the fcitx5 Chinese input method |
| [`uninstall-cleanup.md`](wsl/uninstall-cleanup.md) | Removing one distro or WSL entirely, residue, verification, reinstall |
| [`storage/`](wsl/storage/) | Moving a distro off the system drive, pnpm/npm disk cleanup; `forensics/` holds the raw evidence from one `E_ACCESSDENIED` failure |

The core idea is **`appendWindowsPath=false` plus explicit function bridging**: do not inject
Windows' several hundred PATH entries -- wrap only the handful of `.exe`s you actually need in
shell functions.

### [`windows/`](windows/) -- the Windows side

[`setup/`](windows/setup/) (the LTSC setup runbook; hand the whole file to an agent) ·
[`files/`](windows/files/) (deployable originals) ·
[`terminal/`](windows/terminal/) (Windows Terminal config) ·
[`powershell/`](windows/powershell/) (PowerShell 7 profile, PSReadLine, closing every File
Explorer window without killing the shell, closing or killing Typora) ·
[`ime-keyboard/`](windows/ime-keyboard/) (stray keyboard layouts after uninstalling languages,
first-Pinyin-letter-leaks-as-Latin checklist) ·
[`context-menu/`](windows/context-menu/) (diagnosing and trimming context-menu entries) ·
[`windows-update/`](windows/windows-update/) (pin feature updates to 24H2 while keeping
updates visible)

### [`os-install/`](os-install/) -- system installation

Topics that exist only because two operating systems share the machine. Today: the **clock
contract** between a dual-booted Windows and Linux -- the RTC convention, the 8-hour signature,
automatic correction vs. deliberate drift, and the fast-startup interaction. The read-only
probes in `files/` report the state of both sides; every fix is a command written next to the
measurement that justified it.

### [`linux-desktop/`](linux-desktop/) -- native Linux desktop

Rebuild notes for Linux Mint 22 (Ubuntu 24.04 noble base): mirrors, the proxy and `sudo`,
`chsh`, fcitx5, the clipboard, Ghostty and a Nemo context-menu action, merging shell history
from several machines. `files/` holds the Ghostty config and the Nemo action originals.

[`wayland-fcitx5-rime.md`](linux-desktop/wayland-fcitx5-rime.md) and
[`wayland-clipboard-automation.md`](linux-desktop/wayland-clipboard-automation.md) record what a
Plasma Wayland session needed for the input method and what it could not do for the clipboard
and automation.

[`linux-desktop/fedora/`](linux-desktop/fedora/) is the same job on a **Fedora 44 / KDE Plasma /
Wayland** install -- tried on the desktop's SSD and abandoned in 2026-11, kept as a record --
where almost every actor differs: dnf5 instead of apt, Dolphin instead of
Nemo, Konsole instead of GNOME Terminal, `wl-clipboard` instead of `xclip`, and a desktop whose
proxy settings are split across two stores that neither feed the CLI.

### [`honor-linuxlab/`](honor-linuxlab/) -- Honor tablet Linux Lab

The third environment, and the one most easily misconfigured: a PRoot container whose
`127.0.0.1` is the container itself, where no proxy software runs at all. Covers what the
vendor's bundled guide and its in-product assistant never do -- the terminal proxy variable
layer, locale versus the input method, and a unit-by-unit gap analysis in
[`docs-gap.md`](honor-linuxlab/docs-gap.md). The executable procedures live in
[`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/).

### [`linux-bootstrap/`](linux-bootstrap/) -- provisioning a fresh machine

The machine-agnostic bootstrap: mirrors, the base package set, the node and python
toolchains, zsh with oh-my-zsh and the two plugins, and the four-layer shell config.
It was mined from the real shell histories of six machines -- `history-inventory.md`
records the provenance and, just as importantly, what was left out. `files/` holds the
script and a read-only probe of the result.

### [`agent/`](agent/) -- AI toolchain

| Directory | Contents |
| :--- | :--- |
| [`claude-code/`](agent/claude-code/) | `settings.json`, the global-instructions original `claude-global.md` (deployed as `~/.claude/CLAUDE.md`), the statusline script |
| [`skills/`](agent/skills/) | Every skill, serving both `~/.claude/` and `~/.gemini/config/`. The repo copy is redacted; deploy and verify through [`tools/sync-skills.sh`](tools/sync-skills.sh) |
| [`antigravity/`](agent/antigravity/) | The `~/.gemini/config/AGENTS.md` original (which forces `bx`), plus `agy` CLI usage and image handoff |
| [`brave-search/`](agent/brave-search/) | The `bx` CLI and the Brave Search MCP integration |

### [`git-github/`](git-github/) · [`tools/`](tools/) · `tmp/`

Git privacy configuration and a history-scrubbing runbook (including GitHub's four file-size
thresholds); Python and remote-execution pitfalls; Docker;
[`tools/latex/`](tools/latex/) (the VS Code LaTeX Workshop toolchain, and why ChkTeX has to be
off for Chinese documents); and five scripts that maintain this repo --
[`tools/lint.sh`](tools/lint.sh) (the silent-failure rules from `AGENTS.md`, also run by CI on every PR),
[`tools/install-hooks.sh`](tools/install-hooks.sh) (runs `lint.sh` as a pre-commit hook),
[`tools/privacy-gate.sh`](tools/privacy-gate.sh) (the pre-publish redaction gate),
[`tools/sync-skills.sh`](tools/sync-skills.sh) (rendered skill deployment and verification) and
[`tools/publish.sh`](tools/publish.sh) (export to the two public repos).
[`tools/README.md`](tools/README.md) keeps the two kinds apart.

`tmp/` is a **scratch area**, gitignored. Every temporary edit, trial script run, and
pre-overwrite backup happens in there. All three are covered in [`conventions.md`](conventions.md).

---

## Pitfall index

Entries that took real time to diagnose and whose conclusion is not obvious.

| Pitfall | Symptom | Where |
| :--- | :--- | :--- |
| **Non-interactive shells do not expand aliases** | Scripts and AI agents get `command not found` while the same command works when you type it | [`shell/`](shell/) hard rules |
| **wslu misreports under systemd** | `WSL Interoperability is disabled`, even though `wsl.conf` is plainly correct | [`git-github/README.md`](git-github/README.md) 2.3 |
| **`filter-repo` silently destroys changes** | Uncommitted modifications to tracked files vanish after a history rewrite, with no warning | [`git-github/email-scrub-runbook.md`](git-github/email-scrub-runbook.md) section 2 |
| **`apt`'s `gh` is a 2024 build** | `gh --version` reports 2.46.0, and the date in parentheses is the Debian *build* date, not the release date: upstream shipped 2.46.0 in March 2024, and 80 releases have landed since. Fedora's `dnf` copy is only 9 releases behind, so the fix is distro-specific | [`git-github/README.md`](git-github/README.md) section 3 |
| **A fine-grained PAT's permissions are not scopes** | `gh auth status` prints no scope list, so a missing permission only shows up as `HTTP 403: Resource not accessible by personal access token` on one command -- and re-logging in never fixes it | [`git-github/README.md`](git-github/README.md) section 3 |
| **`no_proxy` wildcards do not work** | A request to a local service goes through the proxy anyway and returns an empty 502 that looks like "the request failed" | [`tools/python/`](tools/python/) section 1 |
| **f-string quoting rules** | `invalid syntax`, and 3.10 behaves differently from 3.12 | [`tools/python/`](tools/python/) section 2 |
| **numpy 2 does not speed up pure-Python loops** | Upgrading numpy for speed changes nothing when the hot loop is Python; moving from 3.10 to 3.12 gave 1.4x on the same job, outputs byte-identical | [`tools/python/`](tools/python/) section 3 |
| **`uv run` hangs without a word** | No output, no error, minutes, on a command that normally takes seconds: a network check while resolving. `--offline` when everything is cached | [`tools/python/`](tools/python/) section 4 |
| **`pkill -f` kills itself** | Returns 255, which looks like the SSH connection dropped | [`tools/remote-ssh.md`](tools/remote-ssh.md) section 2 |
| **Setting thread counts too late in Python** | BLAS is already initialised; 48 workers spawn 3077 threads and run 227x slower | [`tools/remote-ssh.md`](tools/remote-ssh.md) section 3 |
| **`ssh` in a heredoc script swallows the rest of it** | Every command after the first `ssh` silently does not run, exit 0: `ssh` forwards stdin, and in a heredoc stdin is the script. Use `ssh -n` | [`tools/remote-ssh.md`](tools/remote-ssh.md) section 8 |
| **`set -e` plus `\| grep` stops on no match** | A script halts right after a command that succeeded: the filtering `grep` found nothing and returned 1 | [`tools/remote-ssh.md`](tools/remote-ssh.md) section 9 |
| **An `rsync` pull overwrites newer local files** | A report regenerated locally quietly reverts to the remote's older copy. Preview with `-n --itemize-changes`; `--ignore-existing` or `--update` | [`tools/remote-ssh.md`](tools/remote-ssh.md) section 10 |
| **Drive-letter paths never exist in WSL** | `C:/Windows/Fonts/...` finds no font; you get silent tofu squares and no error | [`agent/skills/linux-cjk-font/`](agent/skills/linux-cjk-font/) |
| **A hardcoded Windows account name expires** | Tofu squares again, silently: `/mnt/c/Users/<the old machine's account>/...` does not exist here. WSL has no `%USERPROFILE%`; use `glob("/mnt/c/Users/*/...")` | [`agent/skills/README.md`](agent/skills/README.md) |
| **drvfs case-insensitivity hides a hardcoded account name** | Nastier than the row above: the Windows account name and `$USER` here differ only in case, so the string comparison is false while `/mnt/c/Users/$USER/...` still stats successfully. "Build the Windows home directory from `$USER`" is therefore **always passing** on this machine, and only fails -- silently -- on a machine where the names really differ | [`wsl/setup/`](wsl/setup/) FAQ |
| **zsh aborts the whole file on an unmatched glob in a `for` list** | One `~/.shell_common` is shared by bash and zsh; bash passes the literal through, zsh exits with `no matches found` and everything after it never runs | [`wsl/setup/`](wsl/setup/) FAQ |
| **`echo ======` fails in zsh** | `zsh: = not found`, and the rest of the line does not run: a word starting with `=` is expanded to a command path. Quote it | [`shell/`](shell/) |
| **Non-interactive bash has no equivalent of `.zshenv`** | The interop functions reach scripts and agents on the zsh side but not on the bash side: `bash -c` and `#!/bin/bash` read neither startup file. The verification checklist historically said `bash -ic`, and the `-i` happened to paper over the gap. The way out is `BASH_ENV` | [`wsl/setup/`](wsl/setup/) checklist item 3 |
| **A pnpm global CLI can be installed correctly and still not start** | `Cannot find module '\\wsl.localhost\...'` for a file that plainly exists: pnpm's shim picks the interpreter at runtime, and on WSL2 it hands the script to Windows node, which cannot follow pnpm's symlinks over the UNC path | [`wsl/`](wsl/pnpm-shim-wsl2-node-path.md) |
| **`PROFILE=/dev/null` defers activation to a step that may never run** | nvm sits on disk and `nvm alias default 24` is set, but `command -v node` is empty in every shell: the line that would source `nvm.sh` was never written to any rc file | [`wsl/`](wsl/pnpm-shim-wsl2-node-path.md) |
| **A verification that runs in a hand-built PATH is not a verification** | `--version` answers happily inside the install script that exported `NVM_DIR` itself, and answers `MODULE_NOT_FOUND` in the terminal the user types in | [`wsl/`](wsl/pnpm-shim-wsl2-node-path.md) |
| **The live `/etc/wsl.conf` is not the repo original** | A `wsl.conf` written by a Windows-side installer carries only `[boot] systemd=true`, so the Windows PATH gets appended and every `find`/`sort`/`curl` loses to the Windows one | [`wsl/`](wsl/pnpm-shim-wsl2-node-path.md) |
| **A `command -v` guard that runs before its PATH entry** | On a distro without wslu (Debian, Fedora), `BROWSER` is empty in every new terminal and `gh auth login` cannot open the browser, yet the check passes: `~/.local/bin/wslview` was probed before `~/.local/bin` joined PATH, and any shell started from an open terminal inherits that PATH. Verify from `env -i ... bash -lic` | [`wsl/distro-differences.md`](wsl/distro-differences.md) 4.7 |
| **`.gitattributes` does not reach inside a zip** | The entire file is reported as rewritten and the real change drowns in a fake diff | [`git-github/crlf-and-diffing.md`](git-github/crlf-and-diffing.md) |
| **`/reg:64` redirection** | A registry key "cannot be found" even though it plainly exists | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **`binfmt_misc` is global across distros** | After starting or stopping another distro, Windows commands suddenly fail with `exec format error`, with no visible connection -- and you cannot use interop to rescue interop | [`wsl/setup/`](wsl/setup/) step 1.3 |
| **`accept4 110` has two distinct causes** | Applying the usual "swap the socket" prescription fails on every socket alike, burning an hour | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **The `*` in `wsl -l -v` marks the default, not the current distro** | Read it as "you are here" and `-d <other>` silently re-enters the one you are already in. Write a marker into "the other distro" and read it back and the test passes perfectly -- it is your own file. Only `stat -c %d` gives it away. The authority is `$WSL_DISTRO_NAME` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) section 1 |
| **Moving files between distros by way of Windows** | It works, but the same file set is 23x slower (0.97 s vs 22.5 s). `/mnt/wsl` is a shared tmpfs; bind-mount under it for a direct path instead of going through 9p on `\\wsl.localhost` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) section 2 |
| **`--terminate` does not release a disk another distro has bind-mounted** | `wsl -l -v` says `Stopped` while the other distro keeps writing to its ext4, and the writes are there at next boot. The VHDX stays attached too, so compaction requires `--shutdown` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) section 5 |
| **systemd >= 256 cannot start a user session under WSL** | `Failed to spawn executor: Device or resource busy`. Ubuntu's 255 is fine; Fedora's 259 always breaks | [`wsl/distro-differences.md`](wsl/distro-differences.md) |
| **cmd.exe refuses a UNC working directory** | It falls back to `C:\Windows` silently, so every path-relative operation is wrong without any error | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **WSL does not update through Windows Update** | Windows is version-pinned, so you assume WSL is pinned too; in fact the two channels are unrelated | [`wsl/setup/`](wsl/setup/) maintenance section |
| **Leave `.wslconfig` out of the repo and the proxy is guaranteed to break** | `host_ip="127.0.0.1"` is only correct under `networkingMode=mirrored`. Miss that Windows-side file during a rebuild, WSL falls back to NAT, `127.0.0.1` points at WSL itself, and every proxied request is refused -- far from the cause, with nothing in `~/.shell_common` pointing at it | [`wsl/setup/`](wsl/setup/) step 0.1 |
| **A new distro's default user is root until the prompt is answered** | `wsl -d <Name> -- whoami` prints `root` and `HOME=/root`, so the first-run setup looks finished when it is not, and an agent writes its config into `/root` instead of the real home. The username prompt only fires on an *interactive* launch: `--no-launch` never consumes it, and a non-interactive probe never triggers it | [`wsl/storage/wsl-distro-move-to-d-drive.md`](wsl/storage/wsl-distro-move-to-d-drive.md) |
| **ChkTeX floods Chinese documents with false positives** | `Use "'" (ASCII 39) instead of "´"` fills the output and buries the real errors. It scans bytes rather than decoding UTF-8, so a continuation byte of a Chinese character landing on `´` (0xB4) reads as a typography mistake. No rule tweak helps; turn it off | [`tools/latex/`](tools/latex/) |
| **`-Source` given, still goes online** | Installing the Windows Chinese font package offline fails even with the ISO mounted -- `Add-WindowsCapability` contacts Windows Update first unless `-LimitAccess` is also passed | [`tools/latex/`](tools/latex/) · [`agent/skills/linux-cjk-font/`](agent/skills/linux-cjk-font/) |
| **pnpm blocks postinstall without saying so** | `pnpm update -g --latest` exits 0 and looks installed, but the command will not run -- pnpm 10+ skips lifecycle scripts by default. Allow them per package with `--allow-build=<name>` | [`wsl/storage/pnpm-npm-cleanup-20260920.md`](wsl/storage/pnpm-npm-cleanup-20260920.md) 3.2 |
| **A redaction placeholder borrowed `$HOME`** | One token meant both "a home directory awaiting substitution" and a genuine shell variable. Rendering it hardcoded the local path into `set-deepln.sh`, so the script was wrong everywhere on a rented GPU box. The test should be "will a shell expand this", not what kind of file it is | [`agent/skills/README.md`](agent/skills/README.md) |
| **DeepLN instances cannot reach each other's public domain** | `ssh`/`rsync` from one rental to another's `<instance>.deepln.com:<port>` times out, in both directions. Inside the cluster use the pod IPv4 (`hostname -I`) on port 22, with `ssh -A` to borrow the local key: 145-204 MB/s measured, about 100x a home uplink | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) section 5.3 |
| **A DeepLN saved-data snapshot has an extra `data/` level** | The usual `tar xvf - -C /data/coding` lands files in `/data/coding/data/coding/...`: the archive is the whole `/data`. Add one space after `-C /`, making it `-C / data/coding`: only the project, no nesting. Extracting all of it at `/` overwrites the new instance's own alist config | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) section 5.2 |
| **DeepLN CPU instances come in two sizes** | A GPU-less rental is either a 1-core / 2 GiB transfer box or a 24-core / 47 GiB compute box, and `nproc` (80 or 256) tells you neither. Sized for the wrong one, a job is either starved or wastes the box. Read the cgroup quota | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) section 5.1 |
| **uv settings vanish with the rental** | After a re-rental `uv pip install` is slow again: the TUNA index lived in `~/.config/uv/uv.toml`, which is not under `/data`. Keep uv's Python, cache and venvs under `/data` and rewrite the config in the setup script | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) section 6 |
| **A stopped DeepLN instance answers with another host key** | `REMOTE HOST IDENTIFICATION HAS CHANGED` after the instance was shut down or re-rented. Expected then, but confirm in the console before `ssh-keygen -R` -- never accept it on reflex | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) section 0 |
| **A `: ` in a skill's `description` makes strict parsers drop the skill silently** | Fine in Claude Code, but `npx skills add --list` shows two fewer skills and no error. An unquoted YAML value may not contain `: `; Claude Code tolerates it, strict parsers skip the skill. Use ` -- ` or quote the value | [`agent/skills/README.md`](agent/skills/README.md) conventions |
| **A wrong jq path silently yields 0 rows** | Using `.web.results[]` against `bx news` exits 0 with no error and looks like "no results for this topic" | [`agent/brave-search/bx-cli.md`](agent/brave-search/bx-cli.md) section 6 |
| **A search-gating skill became a fixed tax** | `CLAUDE.md` is resident every session while a skill body loads on demand; making a 2.2k skill a prerequisite for `bx` inverts the cost structure | [`agent/claude-code/README.md`](agent/claude-code/README.md) |
| **Force-pushed the `Co-Authored-By` away, Contributors still shows Claude** | The remote history is clean and a further push changes nothing; the REST contributors endpoint lists authors only and never showed Claude, while the page kept doing so. The box is a cache, rebuilt when the default branch is renamed away and back | [`agent/skills/github-coauthor-scrub/`](agent/skills/github-coauthor-scrub/) |
| **Redaction regexes keep leaking** | The same value rendered differently (case, column alignment, another command's output format, a label in another language) slips past the check. Five rounds in a row failed here | [`tools/privacy-gate.sh`](tools/privacy-gate.sh) header comment |
| **The input method will not bind under Wayland** | An Electron app runs fine but cannot type Chinese, and no flag helps. Weston reserves `input_method` for its own IME client and WSLg does not run one; worse, fcitx5 hitting error 71 **exits the whole process**, taking the X11-side input method with it | [`wsl/gui-ime/`](wsl/gui-ime/) sections 1 and 9 |
| **`wmctrl` is useless under WSLg** | Window-placement scripts silently do nothing. The Weston WM does not export `_NET_CLIENT_LIST`, so `wmctrl -l` always fails -- and the script uses exactly that to find windows | [`wsl/gui-ime/`](wsl/gui-ime/) section 8 |
| **The machine changed, the document did not** | A "deployment summary" whose display parameters, file roles and fixes all disagree with this machine. Comparing first-run traces (`Crashpad/client_id`) against the document's own date proves it was never written on this machine at all | [`wsl/gui-ime/`](wsl/gui-ime/) sections 5 and 8 |
| **PRoot xrdb locks up without timeout** | Honor Tablet Linux Lab permanently hangs on "Loading..." when switching to Debian: `xrdb -merge` blocks forever and suppresses the `StartFinished` handshake. Direct edits to `start` trigger `AssetsPatcher` hash overwrite; intercept via binary wrapper instead | [`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/) |
| **Ubuntu ARM64 mirrors require ubuntu-ports** | `apt update` fails with 404 for `binary-arm64/Packages` after switching to Tsinghua mirror because non-x86 architectures live under a separate repository path | [`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/) |
| **Honor tablet: proxy vars point at a dead port** | `pnpm` reports `tunnel error ... connection refused (os error 111)` and `npm` hangs, while the browser and `apt` work fine -- `~/.shell_common` exports proxy vars at a local port nothing listens on, and the browser keeps its own settings and ignores them. Probe the port first: refused means clear the vars, open means leave them | [`honor-linuxlab/`](honor-linuxlab/) 2.1 |
| **Honor tablet: fcitx5 produces no candidates** | `Ctrl+Space` toggles but nothing appears. Two causes stack: `~/.config/fcitx5/profile` has `keyboard-us` as the first item of the active group instead of `pinyin`, and a missing `~/.config/fcitx5/config` leaves only the factory `Ctrl+Space`, which the Android host swallows on a physical keyboard. **Not the locale** -- that change came 20 minutes *after* the report, and only looked causal because the next question asked about it | [`honor-linuxlab/`](honor-linuxlab/) 2.2 |
| **Honor tablet: some key combinations never reach the container** | Input crosses three layers -- Android/MagicOS host, X server, app -- and the host reserves certain combinations. `Ctrl+Shift+V` is dead on a physical keyboard (even a Qt shortcut editor never sees the event) while `Ctrl+Shift+C` and the other letters work fine. `xdotool key` works, which is how you tell layer 1 apart from layers 2-3. Rebind to a free letter; no container-side config can fix layer 1 | [`honor-linuxlab/`](honor-linuxlab/) 2.3 |
| **Honor tablet: `readdir` calls a hard-linked file a symlink** | PRoot emulates `link()` with a staging pair and a magic `.l2s.` namespace. The inode is fine and `lstat` still says regular file, but every directory entry sharing that inode comes back from `readdir` as `DT_LNK`, and a symlink chain through a `.l2s.` entry makes `stat()` fail with EPERM -- so `mv -f` reports "cannot stat" and never reaches the rename at all. Filter by `lstat` or by name, never by entry type | [`honor-linuxlab/`](honor-linuxlab/) 2.7 |
| **Honor tablet: `/proc` says `hidepid=invisible` and hides nothing** | The mount option is there and every container process shares one kernel uid, so `hidepid` lets them all through -- all 62 pids under `/proc` have a readable `cmdline`. Meanwhile `ps` lists pids that have no `/proc` entry at all, and the container cannot read `/proc/self/ns/pid` or `pid_max`, so it cannot tell you which namespace it is in. Read the mount option as a claim, not as behaviour | [`honor-linuxlab/`](honor-linuxlab/) 2.8 |
| **`execve` is decoupled from `/proc/self/exe`** | Command runner fails with `readlink /proc/self/exe: no such file`, mistaken for kernel fork failure. Linux `execve(2)` does not need `/proc`; modern Go/CLI runtimes query it for self-inspection. Mounting `/proc` satisfies runtime dependencies, not privilege escalation | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Tsinghua mirrors PyPI but not the interpreter** | `pypi.tuna.tsinghua.edu.cn/simple` is 200, while `github-release/astral-sh/python-build-standalone` is 404, so `python-install-mirror` cannot point at TUNA -- it is absent, not slow. Also `python-install-mirror` must be a bare string: a `[python-install-mirror]` table is rejected with `invalid type: map, expected a string` and invalidates the whole `uv.toml`, index included | [`tools/python/`](tools/python/) section 5 |
| **A new CPython patch needs a newer uv first** | CPython 3.12.15 shipped 2026-09-30, but uv 0.12.18 (built 2026-09-22) lists at most 3.12.14: the download manifest is compiled into the binary, not queried at run time. "Released upstream" does not mean "installable here" | [`tools/python/`](tools/python/) section 5 |
| **`unshare -m` isolates mounts from running peer sessions** | Mounts fixed on host and `--check` passes, yet running agent still fails with `open /dev/ptmx: no such device`. `unshare -m` creates a private Mount Namespace; restarting the agent inside the existing un-exited `bash` keeps it trapped in the stale namespace | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Android Termux reports `required file not found`** | Executing a freshly installed CLI binary fails with file not found even though `ls` confirms it exists. `readelf -l` reveals `PT_INTERP` requests `/lib/ld-linux-aarch64.so.1`, but Android runs Bionic libc (`/system/bin/linker64`); the kernel cannot find the glibc linker and returns ENOENT. A glibc chroot container is required | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Proxy vars point at a port that disappears** | The proxy is an Android *app* on the host, and the chroot shares its network namespace, so `127.0.0.1:<port>` reaches it -- only while the app runs. Stop it and every proxied request is refused, even though a direct connection works. Worse, in TUN mode the port stays closed *while the proxy is working*, so the port probe reports "refused" for a live proxy: test whether the request works before touching the port | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **One port cannot serve both HTTP and SOCKS** | `ALL_PROXY=socks5h://...:<p>` fails with "Connection reset by peer" while `HTTP_PROXY` on the same port works. The WSL original used one mixed port, but this proxy app listens on two: HTTP on one, SOCKS5 on another (`05 00` handshake vs `HTTP/1.1 200 Connection established`). One port per variable, always | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **A fixed messaging socket path makes sessions evict each other** | A second instance dies with "--messaging-socket-path points to a live socket", and peer notifications land in the session holding that path, so another Termux session looks flooded with messages. The CLI's own convention is one socket file per session inside a `cc-socks` directory, discovered by scanning it; a hardcoded name breaks both. `CLAUDE_CODE_MESSAGING_SOCKET` also outranks the command-line flag | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **`${PATH#...}` deletes more than the segment it names** | Reordering `PATH` to put one directory first silently drops another: `#` strips the *shortest* prefix, so the entry ahead of the match goes with it. Here the whole pnpm bin dir vanished and `mcode`, `mcode-tools`, `pnpm` and `pnpx` disappeared with it. Rebuild the list segment by segment instead | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Android SELinux MCS blocks symlinks created inside root chroot** | Soft-linking `Debian -> debian` inside root container fails in Termux with `No command Debian found`: symlink is owned by `root:root` and lacks app MCS category labels (`:c250,c256...`), so Termux (`untrusted_app`) hits kernel `EACCES` and falls back to `command-not-found`. Deploy an owned regular file or match SELinux context with `chcon --reference` | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Toybox `chroot` leaves cwd at `/` instead of `~`** | Entering the container drops the interactive shell into `/` instead of `/root` (`~`), polluting rootfs on scratch files. Toybox `chroot` resets working directory to `/` and login shells inherit it; launch via GNU `env -i -C /root` to atomically set cwd | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Claude Code refuses `--dangerously-skip-permissions` under root** | Running Claude Code in root chroot with `bypassPermissions` fails with `cannot be used with root/sudo privileges for security reasons`. A `getuid() === 0` check (CLI 2.1.325) refuses permission skips unless marked as a container: set `"IS_SANDBOX": "1"` in the container's own `~/.claude/settings.json`, never in the shared `agent/claude-code/settings.json` | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Hotplugged USB drives are invisible in chroot** | Connecting an external drive after starting the Debian container leaves `/android/mnt/media_rw` empty even though Android recognizes it. `unshare -m` and `rprivate` block mount propagation; bridge mounts dynamically via `nsenter -t 1 -m` | [`agent/skills/termux-debian-external-drive/`](agent/skills/termux-debian-external-drive/) |
| **NTFS permission masking breaks SSH key authentication** | Running `chmod 600` on private keys stored directly on NTFS exits 0 but the underlying FUSE driver fixes modes to `770`, triggering OpenSSH protection blocks; store keys in `.tar` archives and unpack to native Linux storage | [`agent/skills/termux-debian-external-drive/`](agent/skills/termux-debian-external-drive/) |
| **Android Bionic Linker namespace fracture and Magisk tmpfs stub collision** | Calling host `/system/bin/settings` inside Debian chroot fails with `cannot execute` or dynamic linker crash (`file offset for libutils.so >= file size: 0 >= 0`). Magisk tmpfs overrides libraries with 0-byte stubs and the linker lacks container runtime topology; execute via targeted Mount Namespace penetration (`nsenter -t 1 -m`) | [`agent/skills/android-miui-settings/`](agent/skills/android-miui-settings/) |
| **MIUI proprietary refresh rate vote overrides AOSP settings** | Setting `system peak_refresh_rate` to 120Hz fails to lock high refresh rate; MIUI inserts a `PRIORITY_MIUI_REFRESH_RATE` vote in `DisplayModeDirector` that drops FPS when idling or typing. Link both `secure miui_refresh_rate 120` and `system is_smart_fps 0` | [`agent/skills/android-miui-settings/`](agent/skills/android-miui-settings/) |
| **`chsh` does not take effect in desktop terminal** | Shell changed via `chsh` but terminal restarts still spawn Bash; `gnome-terminal-server` caches PAM variables across windows | [`linux-desktop/`](linux-desktop/) section 2.1 |
| **`Connection refused` while the proxy is up (Windows `bx`)** | Same `socks5h` root cause as the Clash row below, but on Windows the variable lives in the user environment and `jq` is also missing, so two unrelated errors look like one network failure. `curl --noproxy` -> `000` vs via proxy -> `301` tells them apart; a `bx.cmd` / `bx` wrapper around `bx-bin.exe` fixes it | [`agent/brave-search/bx-cli.md`](agent/brave-search/bx-cli.md) section 3 |
| **Clash desktop proxy misses CLI traffic** | Browser proxies fine while CLI commands time out; `bx` hitting `socks5h` exits 5 | [`linux-desktop/`](linux-desktop/) section 2.2 |
| **Linux Mint 22 mirror mismatch & update timeout** | Blindly editing `ubuntu.sources` drops Mint repos; overseas mirrors throttle at ~300 kB/s triggering `mintupdate` TCP timeouts. Dual-track TUNA mirrors yield 16x speedup | [`linux-desktop/`](linux-desktop/) section 2.3 |
| **Installers pollute the 4-layer shell split** | `pnpm setup` and nvm appending rc files break the single source of truth | [`linux-desktop/`](linux-desktop/) section 2.4 |
| **CLI paste shortcut lacks clipboard backend** | Pressing Ctrl+V/Alt+V in CLI reports `no supported clipboard tool` (agy) or fails silently with the image never attached (Claude Code, which pops only `No image found in clipboard.` and never shows its `Image in clipboard` hint); the native desktop requires `xclip`/`wl-clipboard`, and so does WSLg -- there WSLg bridges the host Windows clipboard, so the same three packages fix it. Claude Code spawns the tool per keypress, so no restart is needed -- unlike Go-based CLIs that cache `LookPath` at process init | [`linux-desktop/`](linux-desktop/) section 2.5 |
| **`sudo chsh -s <shell>` without a username changes root's shell** | Your own default shell stayed `/bin/bash` while root's became `/bin/zsh`, with no error at all: `chsh` without a username acts on the invoking user, and `sudo` makes that user root | [`wsl/setup/`](wsl/setup/) step 3 |
| **GNOME Terminal silently drops OSC 52 clipboard** | `/copy` reports success but system clipboard stays empty; VTE lacks OSC 52 write support, recommend Ghostty | [`linux-desktop/`](linux-desktop/) section 2.6 |
| **History migration triggers Zsh corrupt history** | Concatenating multi-device histories crashes Zsh startup; embedded `\x00` null bytes break parsing, sanitize and normalize | [`linux-desktop/`](linux-desktop/) section 2.7 |
| **`sudo` strips proxy causing APT timeouts** | Normal terminal connects fine but `sudo apt` times out on Typora; `env_reset` strips vars, configure `sudoers` whitelist | [`linux-desktop/`](linux-desktop/) section 2.8 |
| **Fcitx 5 default profile missing Pinyin** | After fresh Fcitx 5 install hotkeys do nothing; default profile only contains `keyboard-us`, add `pinyin` | [`linux-desktop/`](linux-desktop/) section 2.9 |
| **Ghostty defaults Ctrl+Enter to fullscreen** | Multi-line input in CLI/editors accidentally triggers fullscreen; unbind via `ctrl+enter=unbind` and rebind F11 | [`linux-desktop/`](linux-desktop/) section 2.10 |
| **Nemo file manager lacks Ghostty context menu** | Cannot open Ghostty directly in selected folders; configure Nemo Action distinguishing item selection from directory background | [`linux-desktop/`](linux-desktop/) section 2.11 |
| **AI agent `sudo` blocks forever waiting for a password** | Non-interactive subprocesses have no TTY to receive the `sudo` password prompt; the command hangs indefinitely. Grant `NOPASSWD: ALL` once with a single manual password entry | [`linux-desktop/`](linux-desktop/) section 2.12 |
| **pnpm 12 global install spawns interactive build-approval UI; Node must be pre-installed** | `pnpm add -g` shows a checkbox prompt that AI agents cannot answer; even with `--allow-build`, postinstall fails with `node: not found` (exit 127) if nvm has not been sourced. Install Node via nvm first, then pass `--allow-build=<exact-pkg-name>` per package; the optional global pass-through is section 2.16 | [`linux-desktop/`](linux-desktop/) section 2.13 |
| **Fcitx 5 session env missing in GUI apps (`run_im none`)** | Terminal types Chinese fine while WPS/WeChat/GUI apps cannot activate IME; `~/.xinputrc` set to `none` suppresses Xsession IM exports. Set `im-config -n fcitx5` and persist in `/etc/environment` & `~/.xprofile` | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) pitfall 1 |
| **WPS Office Linux drops IME (Qt QPlatformInputContext fallback)** | WPS Office cannot type Chinese; missing `QT_IM_MODULE=fcitx` makes bundled Qt fall back to `compose` permanently. Inject IM vars in `/usr/bin/wps` wrappers and restart | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) pitfall 2 |
| **Fcitx 5 AltTriggerKeys hijacks Left Shift from Rime `commit_code`** | Left Shift forces Chinese candidate commitment instead of raw Pinyin letters; Fcitx 5 `AltTriggerKeys=Shift_L` intercepts Shift before Rime engine. Clear `AltTriggerKeys` in `~/.config/fcitx5/config` | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) pitfall 4 |
| **Fontconfig fallback drops into Traditional Chinese glyphs** | Priority 65 `Droid Sans Fallback` runs before Noto CJK (priority 70), producing Taiwanese/archaic glyphs. Normalize `zh-Hans` and prepend Noto Sans/Serif SC | [`linux-desktop/`](linux-desktop/) section 2.14 |
| **Fcitx 5 Rime candidate panel hijacks Left/Right arrow keys** | Pressing Left/Right in linear layout navigates candidates instead of moving cursor in pinyin buffer; unbind selector linear bindings to restore in-place editing | [`linux-desktop/`](linux-desktop/) section 2.15 · [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) pitfall 8 |
| **pnpm 12 blocks build scripts and 24h fresh package releases** | `pnpm add -g` blocks with interactive `approve-builds` prompt and delays packages published <24h (`minimumReleaseAge`). **Optional**, for a machine used only for personal Vibe Coding: enable `dangerouslyAllowAllBuilds: true` and `minimumReleaseAge: 0`; otherwise allow builds per package with `pnpm add -g --allow-build=<pkg>` | [`linux-desktop/`](linux-desktop/) section 2.16 |
| **A Node major upgrade invalidates every native addon** | `better_sqlite3.node was compiled against NODE_MODULE_VERSION 127 ... requires 137` the moment Node 22 becomes 24; the error blames npm build scripts and tells you to pass `--allow-scripts`, which is a dead end when pnpm owns the install and the script already ran successfully. Reinstall every global package with native deps after each major bump | [`linux-desktop/`](linux-desktop/) section 2.17 |
| **Ghostty silently ignores unknown config keys** | `shell = /usr/bin/zsh` is accepted with no warning and no effect -- the key is `command`, and Ghostty 1.3.1 drops unrecognised keys without a word. `+show-config` cannot tell you either; only `+validate-config` reports `unknown field` with a line number | [`linux-desktop/`](linux-desktop/) section 2.18 · [`linux-desktop/files/ghostty/config`](linux-desktop/files/ghostty/config) |
| **Clash Verge Rev reports its own failures as success** | The Connections panel stays empty and the tray menu dies with no error anywhere: the WebSocket connect failure is swallowed into a 1-second reconnect loop, and the tray returns `Ok(())` when it cannot find the tray. Silent failure is written policy upstream, not a one-off -- 48 of 85 substantial Rust files have no tests, and Linux is compiled and shipped but never functionally tested | [`linux-desktop/`](linux-desktop/) section 2.19 |
| **The update manager's "mirror is unreachable" banner is a false positive** | The GUI accuses your mirror of being down while apt is downloading from that same mirror at full speed: the check is a single HEAD with no retry, and it only fires when the *official* repo answers and the mirror does not -- so the message points the opposite way from the real fault | [`linux-desktop/`](linux-desktop/) section 2.20 |
| **MintUpdate's `aptk` holds the dpkg lock after a stalled fetch** | `apt-get install` fails with "Could not get lock /var/lib/dpkg/lock-frontend ... held by process (aptk)" long after the update window closed: the lock holder is the background daemon, not the window. Bypass with `apt-get download` + `dpkg-deb -x` into `/usr/local/bin`, then `dpkg -i` once the lock frees | [`linux-desktop/`](linux-desktop/) section 2.21 |
| **GNOME's `http enabled` flag does not gate Firefox** | On KDE the desktop proxy lives in two unrelated stores, and `org.gnome.system.proxy.http enabled=false` reads like "the HTTP proxy is off" -- but libxul consults only `mode` and the per-scheme host/port. Headless A/B/C proof: `mode=manual` renders with the flag either way, `mode=none` times out | [`linux-desktop/fedora/`](linux-desktop/fedora/README.md) section 4.1 |
| **pnpm 12 ignores `~/.npmrc` for its supply-chain keys** | Mirroring `dangerouslyAllowAllBuilds` / `minimumReleaseAge` into `~/.npmrc` is inert: pnpm reads them only from `~/.config/pnpm/config.yaml`, while npm 11 prints `Unknown user config` on every single command | [`linux-desktop/fedora/`](linux-desktop/fedora/README.md) section 4.2 |
| **KDE splits the desktop proxy settings in two** | The proxy client's system-proxy switch writes only `kioslaverc`; Firefox reads the GNOME schema, Chromium reads `kioslaverc`, and the CLI reads neither -- so with the switch off, Firefox proxies and Chromium does not. "Turn on TUN and it works" hides the gap instead of diagnosing it; the fix is to let the client own `kioslaverc` | [`linux-desktop/fedora/`](linux-desktop/fedora/README.md) section 4.3 |
| **Fedora's Noto CJK families already carry the SC suffix** | The Mint fontconfig rule matches the family `Noto Sans CJK` and rewrites it to the SC variant; Fedora ships one family per region, so the rule matches nothing and the `zh-Hans` BCP-47 form still falls through to the Latin family | [`linux-desktop/fedora/`](linux-desktop/fedora/README.md) section 4.4 |
| **Ghostty on Fedora comes from a COPR, and Flathub has never carried it** | `dnf list --available ghostty` finds nothing because the Fedora repos do not ship it -- but `dnf copr enable scottames/ghostty` installs 1.3.1. Meanwhile the *filtered* flathub remote is a red herring: its filter file is one line, `# Unfiltered`, and the API's "App not found" means Ghostty was never published there at all. Upstream ships macOS binaries only; every other platform is a packager's job | [`linux-desktop/fedora/`](linux-desktop/fedora/README.md) section 4.7 |
| **A KDE custom shortcut cannot be written blind** | Three candidate `kglobalshortcutrc` group layouts all fail to register a component in the kglobalaccel daemon, and KDE 6.7's `Component` interface has no `registerShortcut` -- the format has to come from the writer, and the writer is a GUI | [`linux-desktop/fedora/`](linux-desktop/fedora/README.md) section 4.8 |
| **Fedora's `uv` refuses to download a Python until told to** | `uv run --python 3.12` fails with "No interpreter found for Python 3.12 ... Python downloads are set to 'manual'": the RPM ships `/etc/uv/uv.toml` with `python-downloads = "manual"`. Install once with `uv python install 3.12` and pin it in `~/.config/uv/.python-version` | [`linux-desktop/fedora/`](linux-desktop/fedora/README.md) section 4.9 |
| **The session environment hands the proxy variables down** | The terminal has no network even though the rc file no longer hardcodes a port: `systemctl --user show-environment` still lists the variables the client injected, and a terminal started from the panel inherits that snapshot *before* the rc file runs -- so the invisible source wins. Clear the variables where they enter the process, and clean the snapshot | [`linux-desktop/fedora/`](linux-desktop/fedora/README.md) section 4.10 |
| **A desktop session script pins `SHELL`, so `/etc/passwd` never reaches the terminal** | `usermod -s <shell>` succeeds and `/etc/passwd` shows the new shell, yet every terminal still opens the old one -- LinuxLab's `start-desktop.sh` does a bare `export SHELL=/bin/bash` before LXQt starts, and the whole session tree inherits it. Restarting the desktop does not help | [`honor-linuxlab/`](honor-linuxlab/) 2.4 |
| **`chsh` cannot work in the Linux Lab container** | `Password: chsh: PAM: System error`, and `/etc/passwd` does not change: the container runs no PAM, so `chsh` fails at authentication every time. Use `sudo usermod -s` instead, and remember it fixes only `/etc/passwd` -- the session layer needs its own fix | [`honor-linuxlab/`](honor-linuxlab/) 2.5 |
| **No `add-apt-repository`, and every keyserver is unreachable** | The binary is a guard shim whose real target is missing, and `keyserver.ubuntu.com` / `launchpad.net` / `keys.openpgp.org` all return `000` while `ppa.launchpadcontent.net` returns `200`. The only way forward is `[trusted=yes]`, which is a deliberate security downgrade and must be recorded as one | [`honor-linuxlab/`](honor-linuxlab/) 2.6 |
| **`[pip] index-url` does not cover uv's own resolver** | `uv pip install` uses the mirror while `uv add` / `uv sync` / `uv run --with` still reach pypi.org: they read `[[index]]`, a separate table. Configure both, then confirm with `uv -v` which host was actually contacted | [`tools/python/`](tools/python/) section 5 |
| **The repo's own gates degrade silently without their gitignored inputs** | No `tools/.sync-map` makes `sync-skills.sh` exit 2 and disables skill check/deploy entirely; no `tools/.privacy-names` makes `privacy-gate.sh` print `the literal-name check was skipped` and still exit 0. Neither failure looks like a failure at a glance | [`tools/README.md`](tools/README.md) |
| **`bash -lc` and `bash -ic` resolve a different PATH** | Debian's `~/.bashrc` returns early for non-interactive shells, so a login-but-not-interactive shell never sources `~/.shell_common`: nvm is missing and `node` falls back to `/usr/bin/node` (v22 while an interactive shell reports v24). Verifying one way and using the other yields a false "the change did not take" | [`shell/`](shell/) |
| **`Add-AppxPackage` says the framework is missing, not that the package is broken** | winget v1.29.380 refuses to install with `0x80073CF3 ... depends on a framework that could not be found`, while the machine already lists a `WindowsAppRuntime` package -- the `.CBS` variant, a different package name the deployment validator does not accept | [`windows/terminal/winget-and-terminal-without-store.md`](windows/terminal/winget-and-terminal-without-store.md) section 2.2 |
| **`startingDirectory: null` in `profiles.defaults` never reaches WSL tabs** | cmd and PowerShell inherit the folder while the WSL tab still opens at `~`: the WSL fragment ships a profile-level `startingDirectory: "~"`, and profile settings outrank defaults. Override the same `guid` in `profiles.list` | [`windows/terminal/windows-terminal-system32-auto-home.md`](windows/terminal/windows-terminal-system32-auto-home.md) section 2 |
| **Agent shells start with `-NoProfile`, so the profile's UTF-8 never runs** | Interactive pwsh prints emoji fine while the same command through an agent shows `?`; the harness spawns `pwsh -NoProfile`, which skips all four profiles. Put `[Console]::OutputEncoding` in the first statement of that call -- a later assignment in the same process does nothing, and `chcp` still says 936 because stdout is a pipe | [`windows/powershell/cjk-command-io.md`](windows/powershell/cjk-command-io.md) section 3.1 |
| **A dual boot is 8 hours off at boot and correct minutes later** | The clock is wrong only until the network comes up, so it looks like a sync problem: the RTC holds local time while Windows is told it holds UTC (`RealTimeIsUniversal=1`), and the NTP sync silently repairs it every boot. The screen lies; the hardware does not | [`os-install/dual-boot-time-sync.md`](os-install/dual-boot-time-sync.md) section 2 |
| **A `LocalRTC` change passes every Linux check, and the next Windows boot is 8 hours out** | Each side's probe sees only its own reading and its own write, so a one-sided change looks clean until the other system boots. Windows keeps the RTC in the convention its `RealTimeIsUniversal` names (measured on two machines, flag 1 = UTC, flag 0 = local), so read that flag before touching `LocalRTC`. And reboot right after the change: the running kernel keeps writing the RTC in the convention it was given at boot | [`os-install/dual-boot-time-sync.md`](os-install/dual-boot-time-sync.md) section 1.1, section 8 incident 3 |
| **A minimax-code session dies on every prompt after one compaction** | The turn that used to work fails with `HistoryScannerError: Canonical history scan failed: unsafe-artifact`, and so does every prompt after it -- the next one dies in the `history_read` stage before the model is called. The history content is intact: the compaction's parent snapshot was published with `link()`, and under PRoot `readdir` reports the directory entry type of an inode with several names as `DT_LNK`, which the validator reads as "symlink". The compaction itself was not forced by the context window (35% of 512000 tokens used): the tool-output byte budget triggers it on its own | [`agent/minimax-code/jsonl-repair.md`](agent/minimax-code/jsonl-repair.md) sections 3, 5-6 |
| **An English display language routes Chinese into Japanese glyphs** | Explorer's `Segoe UI Variable*` has no `SystemLink` entry, and the en-US image's link table puts Meiryo / MS UI Gothic and JhengHei ahead of Microsoft YaHei -- the CJK fonts are installed, the wrong one is picked. Reorder `SystemLink` (Microsoft YaHei first, plus a base `Segoe UI Variable` entry) -- measured to fix Explorer; redirecting `FontMapperFamilyFallback` alone changed nothing. Do not "fix" this by switching the display language | [`windows/display-font-fallback-20261117.md`](windows/display-font-fallback-20261117.md) section 3 |
| **A resident IME reverts `Set-WinUserLanguageList -Force`** | Writing `zh-Hans-SG` through the cmdlet reads back correctly in-process but is back to `zh-Hans-CN` eight seconds later in a fresh shell; writing `HKCU\Control Panel\International\User Profile\Languages` directly stays. The cmdlet broadcasts a setting change the IME answers | [`windows/display-font-fallback-20261117.md`](windows/display-font-fallback-20261117.md) section 4 |
| **On Wayland, the input method reaches only half the apps** | Chinese input works in the terminal, the Plasma search bar and Dolphin, but not in Chrome or Firefox, with nothing erroring: `fcitx5-diagnose` shows the working apps on `frontend:dbus` and the broken ones on `frontend:wayland`, so the split is the Wayland path itself. The browsers' cause was that **Fcitx5 was not KWin's input method**: select Fcitx 5 under System Settings -> Keyboard -> Virtual Keyboard, and Chrome (no flags) and Firefox type on native Wayland, with or without `GTK_IM_MODULE`. Two more causes on the way: `XMODIFIERS=@im=none` (imsettings skips the CJK locale) and a `default.custom.yaml` patch that the schema never reads. Removing the global `GTK_IM_MODULE`/`QT_IM_MODULE` was not the fix in either direction | [`linux-desktop/wayland-fcitx5-rime.md`](linux-desktop/wayland-fcitx5-rime.md) |
| **The shared shell file kept a dead proxy** | When no proxy port answered the probe, `shell/files/shell_common` section 5 unset only its own helper variables, so `HTTPS_PROXY` / `ALL_PROXY` inherited from the parent shell or the desktop session survived and pointed every request at a closed port -- in bash and zsh alike, measured in a network namespace with nothing listening. Section 5 now clears the six proxy variables before it probes | [`shell/files/shell_common`](shell/files/shell_common) section 5 |
| **The shared file's comment promised a NO_PROXY export that was never there** | `shell/files/shell_common` says "NO_PROXY below stays either way" and then exports nothing, so with a live proxy the loopback traffic went through the proxy and came back as a 502 with an empty body. The Fedora copy of the same probe had the export all along: the canonical file was the one missing it, and a copy that is supposed to be verbatim was ahead of its source | [`linux-bootstrap/`](linux-bootstrap/README.md) |
| **Ghostty 1.3.x has two config file names, and the GUI creates the empty one** | The canonical path is `$XDG_CONFIG_HOME/ghostty/config.ghostty`, but `config` is read too, and the two are merged per key with `config.ghostty` winning; the GUI creates an EMPTY `config.ghostty` on first run when neither file exists. A config written to `config` alone is not the path the tool itself calls canonical, and a validator run without the glued `--config-file=<path>` form says nothing about either file | [`linux-bootstrap/`](linux-bootstrap/README.md) |
| **On Plasma Wayland, CopyQ keeps the history but cannot paste for you, and `xdotool` cannot type at all** | CopyQ records copies from native Wayland and XWayland apps and its own `Meta+V` shortcut works, but its synthesized Ctrl+V never reaches the focused window; `xdotool type` inserts nothing, even into XWayland windows. `ydotool` (uinput) types everywhere and is the workaround for both. Automated typing into an input method also needs a 130-140 ms key delay, or it reports failures a person typing does not see | [`linux-desktop/wayland-clipboard-automation.md`](linux-desktop/wayland-clipboard-automation.md) |
| **The fallback Linux on the HDD booted from the SSD** | Mint was installed on the HDD as a fallback for an SSD failure, but its installer put GRUB into the SSD's existing ESP (`EFI/ubuntu`) and left the HDD's ESP empty -- so the SSD dying would take the fallback's way in with it. A fallback's bootloader has to live on the fallback's own disk; and reinstalling the SSD's Linux must reuse that ESP without formatting it | [`os-install/triple-boot-layout.md`](os-install/triple-boot-layout.md) |

---

## License

Copyright © 2026 Leo `<28289630+Leonis03@users.noreply.github.com>`

**Code and config are [MIT](LICENSE); documentation is [CC BY 4.0](LICENSE-DOCS).** Both allow
commercial use and redistribution, and both require attribution.

| Scope | License | What it covers |
| :--- | :--- | :--- |
| Code and config | [MIT](LICENSE) | Everything that is **not** a `.md` file -- the `.sh` and `.py` files under `tools/` and `agent/skills/*/scripts/`, the `.ps1` and `.reg` files under `windows/files/`, the config originals under `shell/files/`, `wsl/setup/files/` and `linux-desktop/files/`, and `.gitignore` |
| Documentation | [CC BY 4.0](LICENSE-DOCS) | Every `.md` file -- both READMEs, the per-directory guides, skill bodies, pitfall write-ups and forensic analyses |

The split exists because **Creative Commons itself recommends against using CC licenses for
software**, and so does the FSF (CC BY 4.0 is a free license and is GPL-compatible, but "should
not be used on software"); the OSI has never approved any CC license. CC BY 4.0 §2(b)(2)
expressly grants **no patent rights**, §6(a) terminates the license **automatically** on breach
(§6(b) allows a 30-day cure), and §2(a)(5)(B) forbids applying technological protection
measures. Harmless for prose; real friction for scripts that get copied around.

### Third-party content

The following is **not** covered by either license above; copyright stays with its authors:

- `windows/files/reference/SamplePSReadLineProfile_GitHub.ps1` -- a verbatim 729-line copy of the
  sample profile from [PowerShell/PSReadLine](https://github.com/PowerShell/PSReadLine),
  Copyright (c) 2013 Jason Shirk, **BSD-2-Clause**. The full notice is reproduced in that
  file's header.
- `agent/skills/find-skills/` -- taken from `skills/find-skills/` in
  [vercel-labs/skills](https://github.com/vercel-labs/skills), **MIT**. The standalone skills
  repo leaves it out.
- `agent/skills/skill-creator/` -- taken unmodified from
  `plugins/skill-creator/skills/skill-creator/` in
  [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official),
  copyright Anthropic, **Apache-2.0** (full text in its `LICENSE.txt`). The standalone skills
  repo leaves it out.
- `shell/files/bashrc` retains fragments of Debian's stock `.bashrc`
  (`shopt -s checkwinsize`, `lesspipe`, `dircolors`, `alias ll=` and similar).
- Several files under `shell/files/` contain installer-generated blocks:
  oh-my-zsh lines and the Antigravity CLI PATH block.

These are widely-copied boilerplate fragments, noted here for accuracy; no copyright is
claimed over them.
