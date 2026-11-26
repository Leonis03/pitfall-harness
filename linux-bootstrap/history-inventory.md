# History inventory -- the shell histories behind the bootstrap

*English | [Chinese](history-inventory.zh.md) | back to [linux-bootstrap/](README.md)*

## Why this file exists

[`files/bootstrap-linux.sh`](files/bootstrap-linux.sh) was not written from imagination. It
was mined from the shell histories of the machines kept on an external drive, and this file
records what was in them -- so that a later agent can check the mining, disagree with it, or
extend it, without re-reading 200 KB of history.

Where each file sat on the drive is not recorded here: the folder names on the drive name the
devices. All that matters below is that certain paths held a `.bash_history`, a
`.zsh_history`, or a `.zsh_history.bak.<timestamp>`.

## What was on the drive

**16 history files, 7,186 commands, 202 KB**, from 8 machine profiles. The zsh histories
carry timestamps; the bash ones do not, which is the first thing that limits what the bash
files can tell you.

| file name | files | commands | bytes |
| :--- | ---: | ---: | ---: |
| `.bash_history` | 9 | 5,604 | 139,518 |
| `.zsh_history` | 6 | 1,536 | 65,398 |
| `.zsh_history.bak.<timestamp>` | 1 | 46 | 1,885 |

The zsh timestamps span 2026-05-29 .. 2026-10-19.

Not every profile is an independent machine, and counting the copies would inflate every
number in this file:

- One pair is a **copy of another profile's home directory** that sits inside a git
  repository (1,700 bash commands and 255 zsh commands, the same as the original minus a
  few). It is a backup of that box, not another box.
- Two more are dated snapshots of that same home directory.

So the real count is **6 distinct machine profiles**, not 8.

## Layer 1: the universal core

The commands that appear on more than one machine. These became the stages of the bootstrap.

| What | Where it shows up | Became |
| :--- | :--- | :--- |
| `apt update` / `apt install` | Ubuntu (3 machines), WSL (2), Fedora (0 -- it uses dnf) | stage 2, two package vocabularies |
| base build set: `build-essential`, `gcc`, `curl`, `git`, `unzip`, `zstd` | every apt machine | stage 2 |
| media/dev libraries: `ffmpeg`, `libicu-dev`, `libcurl4-openssl-dev`, `zlib1g-dev`, `libkrb5-dev` | Ubuntu, and the same list on the WSL box | stage 2 |
| JDK (`default-jdk`), `python3-pip` | Ubuntu, WSL | stage 2 |
| clipboard trio: `xclip`, `xsel`, `wl-clipboard` | Ubuntu | stage 2 |
| keyring trio: `gnome-keyring`, `libsecret-1-0`, `dbus-x11` | Ubuntu (with `wslu`, WSL-only) | stage 2 |
| `nvm` + `nvm install` + `corepack enable` + `pnpm` | every machine that has node | stage 3 |
| `uv` installer, `uv python install` | Fedora, Ubuntu, WSL | stage 4 |
| `git config --global user.name` / `user.email` | Ubuntu, WSL | stage 5 |
| `zsh` + the oh-my-zsh installer + the two plugins | every machine | stage 6 |
| `chsh` to zsh | WSL, Fedora | stage 6 |
| `fcitx5` + `im-config -n fcitx5` | Ubuntu | stage 8 |
| `dnf copr enable scottames/ghostty` + `dnf install ghostty` | Fedora | stage 8 |

The install vocabulary, deduplicated: **25 distinct apt commands, 3 apt-get, 4 pnpm, 2 uv,
2 pip, 1 npm**. That is the whole reusable surface. Everything else in 7,186 commands is
either machine-specific or one-off.

## Layer 2: machine-specific

Real, but tied to one box. In the bootstrap these became a placeholder or a runtime
detection, never a literal value:

- **The proxy.** One machine wrote a proxy script into `/etc/profile.d/`, another probed
  candidate ports with a protocol handshake and exported only the ones that answered. The
  second approach is what the repo's `shell/files/shell_common` does, and what the
  bootstrap relies on -- there is no port in this template.
- **The apt mirror.** One box rewrote `deb.debian.org` to a China mirror, another rewrote
  `archive.ubuntu.com`. Both are the same operation on different source layouts.
- **The input method.** `im-config -n fcitx5` on Ubuntu; nothing on Fedora, where the
  package provides `/etc/profile.d/fcitx5.sh`.
- **The third-party app repositories.** A Typora apt key was installed by hand on one box.
  Dropped: it is a single application, not an environment.

## Layer 3: one-off, and dropped

Things the histories contain that must **not** become a template:

- Remote GPU boxes: `ssh` with per-session ports, `ssh-copy-id`, `rsync` of model
  directories, `proxychains4`.
- Application logins and downloads: a downloader login, an editor launch, a `--conversation`
  resume with a session id.
- A Java project build, a Python environment activation, a `conda` environment.
- Single-command debugging: `file`, `dpkg -S`, `apt-cache depends`.

None of them are environment setup; they are work.

## What the history could not tell us

Three limits worth recording, because they shaped the template:

1. **The order in the history is the order things happened, not the order they should
   happen.** Two boxes installed packages before switching mirrors; both were slow. The
   template puts the mirror first on purpose.
2. **The bash histories have no timestamps.** Four of the eight profiles are bash-only, and
   for those the sequence is simply unknown -- only the set of commands survives. The zsh
   histories with `: <epoch>:<elapsed>;` prefixes are the ones that made the ordering
   question answerable.
3. **A history shows the successful commands, not the failed ones.** A command that failed
   and was retried appears once or twice with no marker. That is why the traps in
   [`README.md`](README.md) come from the repo's own notes rather than from the history.

## Redaction

The raw files contain account names, an email address, host names, ports and paths. None of
those are reproduced here, and neither are the file locations on the drive, whose folder names
identify the devices -- see [`../redaction.md`](../redaction.md).
