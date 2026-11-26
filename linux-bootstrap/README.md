# linux-bootstrap -- provisioning a fresh Linux machine

*English | [Chinese](README.zh.md) | back to [README](../README.md)*

## What this directory is

A bootstrap for a machine that has just been installed: mirrors, the base package set, the
node and python toolchains, the git identity, zsh with oh-my-zsh and the two recommended
plugins, and the four-layer shell config from [`../shell/`](../shell/).

It was derived from the real shell histories of six machines. The provenance, the per-machine
inventory, and -- more importantly -- **what was deliberately left out** are in
[history-inventory.md](history-inventory.md).

The history answered *what* to install. The repo's own notes answered *in what order* and
*what breaks along the way*. Neither alone is a template; together they are.

## Files

| File | Deploys to | What it does |
| :--- | :--- | :--- |
| [`files/bootstrap-linux.sh`](files/bootstrap-linux.sh) | run it | the provisioning itself; modifies the machine |
| [`files/check-bootstrap.sh`](files/check-bootstrap.sh) | run it | a read-only probe of the result |

The convention in [`../os-install/files/`](../os-install/files/) is that the scripts there
only read and report. **This directory breaks that convention on purpose**: the bootstrap
has to write to the machine to be a bootstrap. The read-only half is kept separate, as
`check-bootstrap.sh`, so that "the bootstrap ran" and "the machine is in the expected
state" stay two separate questions.

## The three layers

A shell history is a record of what happened, not a plan. Mining one produces three
kinds of material, and only the first two belong in a template:

| Layer | What it looks like | What happens to it |
| :--- | :--- | :--- |
| **Universal core** | the same package or tool installed on five different machines | becomes a stage |
| **Machine-specific** | one box's mirror, one box's input method, one box's proxy port | becomes a placeholder or a detection |
| **One-off** | a rented GPU host, a model download, a login to a downloader | dropped |

The inventory lists the counts, so the split is auditable rather than a matter of taste.

## Stages

| Stage | Does | Notes |
| :--- | :--- | :--- |
| 0 preflight | reads `/etc/os-release`, finds the package manager, WSL, Wayland, desktop | changes nothing |
| 1 mirrors | apt/dnf source -> a China mirror | **verifies, and restores the original if the mirror does not work** |
| 2 packages | the base package set | the apt names and the dnf names are different, and both are listed |
| 3 node | nvm, node LTS, corepack, pnpm | corepack, not a second pnpm installer |
| 4 python | uv, pinned to 3.12 | Fedora's uv refuses to download a Python until told to |
| 5 git | the identity, only if it is not set yet | never overwrites an existing identity; skipped with a warning under `--yes` or without a terminal |
| 6 zsh | zsh, oh-my-zsh, the two plugins, `chsh` | `--keep-zshrc`, so a hand-written `.zshrc` survives |
| 7 shell | the four-layer config from `../shell/files` | replaces `~/.bashrc` too (backed up); also updates the desktop session's `SHELL` snapshot |
| 8 desktop | fcitx5, Ghostty, the Nemo action | only on a machine that has a desktop; on Plasma Wayland it reminds you to select Fcitx 5 as the virtual keyboard |

Every stage is idempotent. A stage whose work is already done reports `SKIP` and exits 0.

Verified on 2026-11-22 in Debian 13 (trixie) containers, as root and as a normal user with
passwordless `sudo`, two passes each: stages 0-4, 6 and 7 ok, stage 5 skipped (identity set in
advance), stage 8 skipped (no desktop), and the second pass skipped what the first had done.
`check-bootstrap.sh` then reported three false failures and one false skip, fixed since (see the
last two traps below).

## Order matters, and the history is not the order

The histories show the order the work *happened* in, which is not the order it *should*
happen in. Two examples the template encodes:

- **The mirrors come first.** Every machine switched its source before installing
  anything, and the installs were the slow part of every session.
- **The shell config comes after the shell exists.** The histories install zsh, then
  oh-my-zsh, then the plugins, and only then write a `.zshrc` that lists them -- a
  `.zshrc` written before the plugins are cloned starts a shell that fails to start.

## Traps the sources taught us

Each of these is in the template because a real machine ran into it:

| Trap | What the template does |
| :--- | :--- |
| `dnf list --available ghostty` finds nothing, which reads as "there is no package" | installs Ghostty from the COPR, where the official install page points for Fedora |
| The upstream project ships macOS binaries only | the distro route is the only route; the script picks the route per distro |
| The apt source layout changed: `sources.list` vs the deb822 `.sources` files | rewrites whichever files exist, host only, so the path survives |
| TUNA mirrors the Fedora tree as `releases/` and `updates/` and publishes **no metalink** | the obvious metalink swap 404s; the dnf stage writes explicit baseurls instead |
| Fedora's uv RPM sets `python-downloads = "manual"` | installs the interpreter once with `uv python install` |
| pnpm 10+ skips dependency build scripts, and pnpm 12 pops an **interactive** approve-builds prompt an agent cannot answer | the repo's `linux-desktop/files/pnpm/config.yaml` is the answer; see 2.16 there |
| On Plasma Wayland the browsers type nothing until Fcitx 5 is KWin's input method; neither setting nor removing `GTK_IM_MODULE` / `QT_IM_MODULE` changes that | the shared file keeps exporting them (X11 needs them, Wayland does not mind); stage 8 prints the virtual-keyboard reminder -- see `../linux-desktop/wayland-fcitx5-rime.md`, root cause 4 |
| A shell inherits proxy variables from its parent and from the desktop session; when nothing answers the probe, the stale values used to survive | the shared file clears the six proxy variables before it probes |
| The README runs the script as a normal user with `sudo`, but the first test containers ran as root | the TUNA repo file is written through `$RUN_AS tee`; the non-root path was tested in a container with a passwordless-sudo user |
| `run_sh` is a fresh `bash -c`, so the `nvm` function sourced in the script's own shell does not exist there | nvm is sourced inside each `run_sh` call and reloaded in the parent afterwards; a failed installer stops the stage with a clear error |
| The desktop session keeps its own `SHELL` snapshot, and a terminal started from the panel inherits it **before** any rc file runs | the systemd user environment and the D-Bus activation environment are updated too |
| `ghostty +validate-config --config-file <path>` (with a space) exits 1 and says nothing on every file | the script uses the glued `--config-file=<path>` form |
| Ghostty 1.3.x reads both `config` and `config.ghostty`, and the GUI creates an empty `config.ghostty` on first run | the config is written to both names, identical |
| The checker grepped `/etc/apt/sources.list.d/` without `-r`, so Debian 13's deb822 `debian.sources` never matched and a working mirror read as "vendor default" | `check-bootstrap.sh` searches the directory recursively |
| The checker ran `command -v node` in its own non-interactive shell, which never reads `~/.zshrc`, so node, pnpm and uv read as missing right after a working bootstrap | `check-bootstrap.sh` takes `PATH` from an interactive zsh first |

## How to use

```bash
# 1. look at the plan; nothing is changed
bash files/bootstrap-linux.sh --dry-run

# 2. run it (prompts before the steps that need an answer)
bash files/bootstrap-linux.sh

# 3. run part of it
bash files/bootstrap-linux.sh --stage 2,3 --yes

# 4. deploy the shell config from the repo
bash files/bootstrap-linux.sh --stage 7 --shell-files ../shell/files

# 5. check the result from the outside
bash files/check-bootstrap.sh
```

`--dry-run` prints every command and touches nothing. Files that the script modifies are
backed up into `~/.bootstrap-backups/<timestamp>/` first.

## See also

- [history-inventory.md](history-inventory.md) -- where every step came from
- [`../shell/`](../shell/) -- the four-layer config this deploys
- [`../linux-desktop/`](../linux-desktop/) -- the desktop side: fonts, fcitx5, Ghostty, the Nemo action
- [`../wsl/setup/`](../wsl/setup/) -- the WSL-specific rebuild, which this complements
