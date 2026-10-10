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
| Windows 11 + WSL2 (Ubuntu 24.04, migrating to Fedora 44) | [`wsl/`](wsl/) · [`windows/`](windows/) |
| Native Linux desktop (Linux Mint 22) | [`linux-desktop/`](linux-desktop/) |
| The four-layer bash / zsh config both of the above share | [`shell/`](shell/) |
| Android (Termux root chroot, Honor tablet Linux Lab) | the `android-chroot-debian` and three sibling skills under [`agent/skills/`](agent/skills/) |
| Rented cloud GPUs (DeepLN) | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) · [`gpu-cuda-checks/`](agent/skills/gpu-cuda-checks/) |

> **AI agents: read [`AGENTS.md`](AGENTS.md) first** -- the directory map, a "to do X, edit
> these files" table, the files that must change together, and the pre-commit checks.

Two kinds of content live here: **config files you can deploy as-is**, and **conclusions left
behind by debugging** -- the latter is usually worth more than the config itself, because it
records *why* things are the way they are.

> **WSL migration in progress.** **Ubuntu 24.04** was the primary distro; day-to-day work has
> moved to **Fedora 44** and the configuration is being aligned to it. Both are installed
> side by side: Ubuntu is still the WSL default (the `*` in `wsl -l -v`), but commands are
> actually typed in Fedora. The three core shell-config layers (`.zshenv`, `.shell_wslfn`,
> `.shell_common`) hash identically on both; what still differs is either dictated by the
> distro (Fedora's fcitx5 block, its `/etc/bashrc` chain) or still converging. The full
> comparison, split into what is avoidable and what is not, is in
> [`wsl/distro-differences.md`](wsl/distro-differences.md).
>
> Most references to Ubuntu elsewhere in these docs still hold; where they do not, the
> difference is recorded in that file.

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
| Rebuild on a native Linux desktop | [`linux-desktop/`](linux-desktop/), with the shell config from [`shell/`](shell/) |
| Set up Git and GitHub (including the privacy email) | [`git-github/`](git-github/) |
| Set up Claude Code | [`agent/claude-code/`](agent/claude-code/) |
| Find a ready-made skill, or sync skills to this machine | [`agent/skills/`](agent/skills/) -- deploy with `tools/sync-skills.sh`, not `cp` |
| Look up one specific trap | See the pitfall index below |
| Have an AI agent change something in this repo | [`AGENTS.md`](AGENTS.md) -- the agent-facing entry point |
| Understand the writing and publishing rules here | [`conventions.md`](conventions.md) -- ASCII boundaries, naming, `tmp/`, the pre-publish gate, the two-repo sync |
| Understand the placeholder scheme: no real usernames in the repo, yet everything resolves on deploy | [`redaction.md`](redaction.md) -- the three classes of value and the two pipelines |

---

## Layout

Every top-level directory except `tmp/` has a `README.md` index. Where a directory has a `files/`
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

[`terminal/`](windows/terminal/) (Windows Terminal config) ·
[`powershell/`](windows/powershell/) (PowerShell 7 profile, PSReadLine, closing every File
Explorer window without killing the shell, closing or killing Typora) ·
[`ime-keyboard/`](windows/ime-keyboard/) (stray keyboard layouts after uninstalling languages,
first-Pinyin-letter-leaks-as-Latin checklist) ·
[`context-menu/`](windows/context-menu/) (diagnosing and trimming context-menu entries) ·
[`windows-update/`](windows/windows-update/) (pin feature updates to 24H2 while keeping
updates visible)

### [`linux-desktop/`](linux-desktop/) -- native Linux desktop

Rebuild notes for Linux Mint 22 (Ubuntu 24.04 noble base): mirrors, the proxy and `sudo`,
`chsh`, fcitx5, the clipboard, Ghostty and a Nemo context-menu action, merging shell history
from several machines. `files/` holds the Ghostty config and the Nemo action originals.

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
off for Chinese documents); and three scripts that maintain this repo --
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
| **`execve` is decoupled from `/proc/self/exe`** | Command runner fails with `readlink /proc/self/exe: no such file`, mistaken for kernel fork failure. Linux `execve(2)` does not need `/proc`; modern Go/CLI runtimes query it for self-inspection. Mounting `/proc` satisfies runtime dependencies, not privilege escalation | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **`unshare -m` isolates mounts from running peer sessions** | Mounts fixed on host and `--check` passes, yet running agent still fails with `open /dev/ptmx: no such device`. `unshare -m` creates a private Mount Namespace; restarting the agent inside the existing un-exited `bash` keeps it trapped in the stale namespace | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Android Termux reports `required file not found`** | Executing a freshly installed CLI binary fails with file not found even though `ls` confirms it exists. `readelf -l` reveals `PT_INTERP` requests `/lib/ld-linux-aarch64.so.1`, but Android runs Bionic libc (`/system/bin/linker64`); the kernel cannot find the glibc linker and returns ENOENT. A glibc chroot container is required | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Hotplugged USB drives are invisible in chroot** | Connecting an external drive after starting the Debian container leaves `/android/mnt/media_rw` empty even though Android recognizes it. `unshare -m` and `rprivate` block mount propagation; bridge mounts dynamically via `nsenter -t 1 -m` | [`agent/skills/termux-debian-external-drive/`](agent/skills/termux-debian-external-drive/) |
| **NTFS permission masking breaks SSH key authentication** | Running `chmod 600` on private keys stored directly on NTFS exits 0 but the underlying FUSE driver fixes modes to `770`, triggering OpenSSH protection blocks; store keys in `.tar` archives and unpack to native Linux storage | [`agent/skills/termux-debian-external-drive/`](agent/skills/termux-debian-external-drive/) |
| **Android Bionic Linker namespace fracture and Magisk tmpfs stub collision** | Calling host `/system/bin/settings` inside Debian chroot fails with `cannot execute` or dynamic linker crash (`file offset for libutils.so >= file size: 0 >= 0`). Magisk tmpfs overrides libraries with 0-byte stubs and the linker lacks container runtime topology; execute via targeted Mount Namespace penetration (`nsenter -t 1 -m`) | [`agent/skills/android-miui-settings/`](agent/skills/android-miui-settings/) |
| **MIUI proprietary refresh rate vote overrides AOSP settings** | Setting `system peak_refresh_rate` to 120Hz fails to lock high refresh rate; MIUI inserts a `PRIORITY_MIUI_REFRESH_RATE` vote in `DisplayModeDirector` that drops FPS when idling or typing. Link both `secure miui_refresh_rate 120` and `system is_smart_fps 0` | [`agent/skills/android-miui-settings/`](agent/skills/android-miui-settings/) |
| **`chsh` does not take effect in desktop terminal** | Shell changed via `chsh` but terminal restarts still spawn Bash; `gnome-terminal-server` caches PAM variables across windows | [`linux-desktop/`](linux-desktop/) section 2.1 |
| **`Connection refused` while the proxy is up (Windows `bx`)** | Same `socks5h` root cause as the Clash row below, but on Windows the variable lives in the user environment and `jq` is also missing, so two unrelated errors look like one network failure. `curl --noproxy` -> `000` vs via proxy -> `301` tells them apart; a `bx.cmd` / `bx` wrapper around `bx-bin.exe` fixes it | [`agent/brave-search/bx-cli.md`](agent/brave-search/bx-cli.md) section 3 |
| **Clash desktop proxy misses CLI traffic** | Browser proxies fine while CLI commands time out; `bx` hitting `socks5h` exits 5 | [`linux-desktop/`](linux-desktop/) section 2.2 |
| **Linux Mint 22 mirror mismatch & update timeout** | Blindly editing `ubuntu.sources` drops Mint repos; overseas mirrors throttle at ~300 kB/s triggering `mintupdate` TCP timeouts. Dual-track TUNA mirrors yield 16x speedup | [`linux-desktop/`](linux-desktop/) section 2.3 |
| **Installers pollute the 4-layer shell split** | `pnpm setup` and nvm appending rc files break the single source of truth | [`linux-desktop/`](linux-desktop/) section 2.4 |
| **CLI paste shortcut lacks clipboard backend** | Pressing Ctrl+V/Alt+V in CLI reports `no supported clipboard tool`; native desktop requires `xclip`/`wl-clipboard` | [`linux-desktop/`](linux-desktop/) section 2.5 |
| **GNOME Terminal silently drops OSC 52 clipboard** | `/copy` reports success but system clipboard stays empty; VTE lacks OSC 52 write support, recommend Ghostty | [`linux-desktop/`](linux-desktop/) section 2.6 |
| **History migration triggers Zsh corrupt history** | Concatenating multi-device histories crashes Zsh startup; embedded `\x00` null bytes break parsing, sanitize and normalize | [`linux-desktop/`](linux-desktop/) section 2.7 |
| **`sudo` strips proxy causing APT timeouts** | Normal terminal connects fine but `sudo apt` times out on Typora; `env_reset` strips vars, configure `sudoers` whitelist | [`linux-desktop/`](linux-desktop/) section 2.8 |
| **Fcitx 5 default profile missing Pinyin** | After fresh Fcitx 5 install hotkeys do nothing; default profile only contains `keyboard-us`, add `pinyin` | [`linux-desktop/`](linux-desktop/) section 2.9 |
| **Ghostty defaults Ctrl+Enter to fullscreen** | Multi-line input in CLI/editors accidentally triggers fullscreen; unbind via `ctrl+enter=unbind` and rebind F11 | [`linux-desktop/`](linux-desktop/) section 2.10 |
| **Nemo file manager lacks Ghostty context menu** | Cannot open Ghostty directly in selected folders; configure Nemo Action distinguishing item selection from directory background | [`linux-desktop/`](linux-desktop/) section 2.11 |
| **AI agent `sudo` blocks forever waiting for a password** | Non-interactive subprocesses have no TTY to receive the `sudo` password prompt; the command hangs indefinitely. Grant `NOPASSWD: ALL` once with a single manual password entry | [`linux-desktop/`](linux-desktop/) section 2.12 |
| **pnpm 12 global install spawns interactive build-approval UI; Node must be pre-installed** | `pnpm add -g` shows a checkbox prompt that AI agents cannot answer; even with `--allow-build`, postinstall fails with `node: not found` (exit 127) if nvm has not been sourced. Install Node via nvm first, then pass `--allow-build=<exact-pkg-name>` per package; the optional global pass-through is section 2.16 | [`linux-desktop/`](linux-desktop/) section 2.13 |
| **Fcitx 5 session env missing in GUI apps (`run_im none`)** | Terminal types Chinese fine while WPS/WeChat/GUI apps cannot activate IME; `~/.xinputrc` set to `none` suppresses Xsession IM exports. Set `im-config -n fcitx5` and persist in `/etc/environment` & `~/.xprofile` | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) section 1.1 |
| **WPS Office Linux drops IME (Qt QPlatformInputContext fallback)** | WPS Office cannot type Chinese; missing `QT_IM_MODULE=fcitx` makes bundled Qt fall back to `compose` permanently. Inject IM vars in `/usr/bin/wps` wrappers and restart | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) section 1.2 |
| **Fcitx 5 AltTriggerKeys hijacks Left Shift from Rime `commit_code`** | Left Shift forces Chinese candidate commitment instead of raw Pinyin letters; Fcitx 5 `AltTriggerKeys=Shift_L` intercepts Shift before Rime engine. Clear `AltTriggerKeys` in `~/.config/fcitx5/config` | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) section 1.4 |
| **Fontconfig fallback drops into Traditional Chinese glyphs** | Priority 65 `Droid Sans Fallback` runs before Noto CJK (priority 70), producing Taiwanese/archaic glyphs. Normalize `zh-Hans` and prepend Noto Sans/Serif SC | [`linux-desktop/`](linux-desktop/) section 2.14 |
| **Fcitx 5 Rime candidate panel hijacks Left/Right arrow keys** | Pressing Left/Right in linear layout navigates candidates instead of moving cursor in pinyin buffer; unbind selector linear bindings to restore in-place editing | [`linux-desktop/`](linux-desktop/) section 2.15 · [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) |
| **pnpm 12 blocks build scripts and 24h fresh package releases** | `pnpm add -g` blocks with interactive `approve-builds` prompt and delays packages published <24h (`minimumReleaseAge`). **Optional**, for a machine used only for personal Vibe Coding: enable `dangerouslyAllowAllBuilds: true` and `minimumReleaseAge: 0`; otherwise allow builds per package with `pnpm add -g --allow-build=<pkg>` | [`linux-desktop/`](linux-desktop/) section 2.16 |

---

## License

Copyright © 2026 Leo `<28289630+Leonis03@users.noreply.github.com>`

**Code and config are [MIT](LICENSE); documentation is [CC BY 4.0](LICENSE-DOCS).** Both allow
commercial use and redistribution, and both require attribution.

| Scope | License | What it covers |
| :--- | :--- | :--- |
| Code and config | [MIT](LICENSE) | Everything that is **not** a `.md` file -- the `.sh` and `.py` files under `tools/` and `agent/skills/*/scripts/`, the `.ps1` files under `windows/`, the config originals under `shell/files/`, `wsl/setup/files/` and `linux-desktop/files/`, and `.gitignore` |
| Documentation | [CC BY 4.0](LICENSE-DOCS) | Every `.md` file -- both READMEs, the per-directory guides, skill bodies, pitfall write-ups and forensic analyses |

The split exists because **Creative Commons itself recommends against using CC licenses for
software**, and so does the FSF (CC BY 4.0 is a free license and is GPL-compatible, but "should
not be used on software"); the OSI has never approved any CC license. CC BY 4.0 §2(b)(2)
expressly grants **no patent rights**, §6(a) terminates the license **automatically** on breach
(§6(b) allows a 30-day cure), and §2(a)(5)(B) forbids applying technological protection
measures. Harmless for prose; real friction for scripts that get copied around.

### Third-party content

The following is **not** covered by either license above; copyright stays with its authors:

- `windows/powershell/SamplePSReadLineProfile_GitHub.ps1` -- a verbatim 694-line copy of the
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
