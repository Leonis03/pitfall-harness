#!/usr/bin/env bash
# bootstrap-linux.sh -- provision a fresh Linux machine from this repo's originals.
#
# WHAT THIS IS
#   A machine-agnostic bootstrap. It takes a box that has just been
#   installed and brings it to the state this repo documents: mirrors,
#   base packages, the node/python toolchain, git identity, zsh with
#   oh-my-zsh and the two recommended plugins, and the four-layer shell
#   config from ../shell/files.
#
# WHAT THIS IS NOT
#   It is not the desktop setup (fonts, fcitx5, Ghostty, the Nemo action --
#   stage 8 does those, but only when the machine actually has a desktop),
#   and it is not a partitioner. Nothing here touches a disk layout.
#
# HOW IT WAS DERIVED
#   Every step below was mined from the real shell histories of six
#   machines; see ../history-inventory.md for the provenance and for what
#   was deliberately left out. The history told us WHAT to install. The
#   repo's own notes told us the ORDER and the traps.
#
# SAFETY
#   - Every step that modifies a file backs the file up first, into
#     $BOOTSTRAP_BACKUP_DIR (default ~/.bootstrap-backups/<timestamp>).
#   - Every step is idempotent: a satisfied step reports SKIP and exits 0.
#   - The mirror stage verifies the new source and RESTORES the original
#     if the verification fails. A mirror that does not work is worse
#     than no mirror.
#   - --dry-run prints every command and touches nothing.
#
# USAGE
#   bash bootstrap-linux.sh --dry-run          # show the plan, change nothing
#   bash bootstrap-linux.sh                    # run every stage, with prompts
#   bash bootstrap-linux.sh --stage 2,3 --yes  # run only these stages
#   bash bootstrap-linux.sh --shell-files /path/to/repo/shell/files
#
# STAGES
#   0 preflight   report the machine, change nothing
#   1 mirrors     apt/dnf source -> a China mirror, with rollback
#   2 packages    the base package set every history installed
#   3 node        nvm, node LTS, corepack, pnpm
#   4 python      uv, pinned to 3.12
#   5 git         identity, only if it is not set yet
#   6 zsh         zsh, oh-my-zsh, the two plugins, chsh
#   7 shell       the four-layer config from ../shell/files
#   8 desktop     fcitx5, Ghostty, the Nemo action -- desktop machines only
#
# EXIT CODES
#   0 everything ran (or was already satisfied)
#   1 a stage failed; the stage that failed is named
#   2 the machine is not supported by this script

set -euo pipefail

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

DRY_RUN=0
ASSUME_YES=0
STAGES=""
SHELL_FILES=""
SKIP_MIRROR=0
MIRROR_HOST="${BOOTSTRAP_MIRROR:-mirrors.tuna.tsinghua.edu.cn}"

SCRIPT_NAME="$(basename "$0")"
STARTED_AT="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BOOTSTRAP_BACKUP_DIR:-$HOME/.bootstrap-backups/$STARTED_AT}"

# Populated by detect_env()
DISTRO_ID=""
DISTRO_VERSION=""
PKG_MGR=""
IS_WSL=0
IS_WAYLAND=0
HAS_DESKTOP=0
RUN_AS=""
NODE_VERSION="24"
PYTHON_VERSION="3.12"

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
step()  { printf '  \033[0;36m--\033[0m %s\n' "$*"; }
ok()    { if [ "$DRY_RUN" -eq 1 ]; then printf '  \033[0;90mPLAN\033[0m %s\n' "$*"; else printf '  \033[0;32mOK\033[0m %s\n' "$*"; fi; }
skip()  { printf '  \033[0;33mSKIP\033[0m %s\n' "$*"; }
warn()  { printf '  \033[0;33mWARN\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

run() {
  # run a command, honouring --dry-run
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  \033[0;90m$ %s\033[0m\n' "$*"
    return 0
  fi
  "$@"
}

run_sh() {
  # run a shell command string, honouring --dry-run
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  \033[0;90m$ %s\033[0m\n' "$1"
    return 0
  fi
  bash -c "$1"
}

have() { command -v "$1" >/dev/null 2>&1; }

mkdir_p() {
  # mkdir_p <dir...> -- creates directories, honours --dry-run
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  \033[0;90m$ mkdir -p %s\033[0m\n' "$*"
    return 0
  fi
  mkdir -p "$@"
}

confirm() {
  # confirm <question> -- returns 0 for yes
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    die "$1 -- no terminal to ask on; pass --yes to proceed"
  fi
  printf '  %s [y/N] ' "$1"
  local a=""
  read -r a
  case "$a" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

backup_file() {
  # backup_file <path> -- copies into the backup dir, keeps the mode
  local f="$1"
  [ -e "$f" ] || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  \033[0;90m$ backup %s -> %s\033[0m\n' "$f" "$BACKUP_DIR"
    return 0
  fi
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp -a "$f" "$BACKUP_DIR/$f"
  step "backed up $f"
}

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------

usage() {
  sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --yes|-y)       ASSUME_YES=1 ;;
    --stage)        STAGES="$2"; shift ;;
    --stage=*)      STAGES="${1#*=}" ;;
    --shell-files)  SHELL_FILES="$2"; shift ;;
    --shell-files=*) SHELL_FILES="${1#*=}" ;;
    --no-mirror)    SKIP_MIRROR=1 ;;
    --mirror-host)  MIRROR_HOST="$2"; shift ;;
    --mirror-host=*) MIRROR_HOST="${1#*=}" ;;
    -h|--help)      usage ;;
    *)              die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

want_stage() {
  # want_stage <n> -- true if this stage is selected
  [ -z "$STAGES" ] && return 0
  case ",$STAGES," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------
# Stage 0: detect the machine
# --------------------------------------------------------------------------

detect_env() {
  step "reading /etc/os-release"
  if [ -r /etc/os-release ]; then
    DISTRO_ID="$(. /etc/os-release && echo "${ID:-unknown}")"
    DISTRO_VERSION="$(. /etc/os-release && echo "${VERSION_ID:-unknown}")"
  else
    DISTRO_ID="unknown"
    DISTRO_VERSION="unknown"
  fi

  if have apt-get; then
    PKG_MGR="apt"
  elif have dnf; then
    PKG_MGR="dnf"
  elif have pacman; then
    PKG_MGR="pacman"
  elif have apk; then
    PKG_MGR="apk"
  else
    PKG_MGR=""
  fi

  if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=1
  fi
  [ -n "${WAYLAND_DISPLAY:-}" ] && IS_WAYLAND=1
  [ -n "${XDG_CURRENT_DESKTOP:-}" ] && HAS_DESKTOP=1

  if [ "$(id -u)" -eq 0 ]; then
    RUN_AS=""
  elif have sudo; then
    RUN_AS="sudo"
  else
    die "need root or sudo for this script"
  fi
}

stage_preflight() {
  info "Stage 0: preflight"
  step "distro        : $DISTRO_ID $DISTRO_VERSION"
  step "package mgr   : ${PKG_MGR:-none found}"
  step "wsl           : $([ "$IS_WSL" -eq 1 ] && echo yes || echo no)"
  step "wayland       : $([ "$IS_WAYLAND" -eq 1 ] && echo yes || echo no)"
  step "desktop       : $([ "$HAS_DESKTOP" -eq 1 ] && echo "${XDG_CURRENT_DESKTOP:-yes}" || echo no)"
  step "backup dir    : $BACKUP_DIR"
  step "dry run       : $([ "$DRY_RUN" -eq 1 ] && echo yes || echo no)"

  case "$PKG_MGR" in
    apt|dnf|pacman|apk) : ;;
    *) die "no supported package manager on this machine" ;;
  esac
  ok "preflight done"
}

# --------------------------------------------------------------------------
# Stage 1: mirrors
# --------------------------------------------------------------------------

stage_mirrors() {
  info "Stage 1: package mirrors"
  if [ "$SKIP_MIRROR" -eq 1 ]; then
    skip "mirrors disabled by --no-mirror"
    return 0
  fi
  case "$PKG_MGR" in
    apt) apt_mirrors ;;
    dnf) dnf_mirrors ;;
    *)  skip "no mirror recipe for $PKG_MGR" ;;
  esac
}

apt_mirrors() {
  # The host is swapped, the path is kept: deb.debian.org/debian becomes
  # <mirror>/debian, archive.ubuntu.com/ubuntu becomes <mirror>/ubuntu.
  # Both source layouts are handled: the classic one-line sources.list and
  # the deb822 files (ubuntu.sources, debian.sources) that Ubuntu 24.04 and
  # Debian 12 ship.
  local targets=()
  [ -f /etc/apt/sources.list ] && targets+=("/etc/apt/sources.list")
  [ -f /etc/apt/sources.list.d/ubuntu.sources ] && targets+=("/etc/apt/sources.list.d/ubuntu.sources")
  [ -f /etc/apt/sources.list.d/debian.sources ] && targets+=("/etc/apt/sources.list.d/debian.sources")

  if [ "${#targets[@]}" -eq 0 ]; then
    skip "no apt source file found to rewrite"
    return 0
  fi
  if grep -qs "$MIRROR_HOST" "${targets[@]}"; then
    skip "already pointing at $MIRROR_HOST"
    return 0
  fi

  for f in "${targets[@]}"; do
    backup_file "$f"
    run $RUN_AS sed -i \
      -e "s|deb.debian.org|$MIRROR_HOST|g" \
      -e "s|archive.ubuntu.com|$MIRROR_HOST|g" \
      -e "s|security.ubuntu.com|$MIRROR_HOST|g" "$f"
  done

  # Verify, and roll back when the new source does not work.
  step "verifying the new source"
  if run_sh "$RUN_AS apt-get update -qq"; then
    ok "mirror in use: $MIRROR_HOST"
  else
    warn "the mirror did not work -- restoring the original source"
    for f in "${targets[@]}"; do
      [ -f "$BACKUP_DIR/$f" ] && run $RUN_AS cp -a "$BACKUP_DIR/$f" "$f"
    done
    run_sh "$RUN_AS apt-get update -qq" || true
    warn "restored the original source"
  fi
}

dnf_mirrors() {
  # TUNA mirrors the Fedora tree as releases/ and updates/ directories and
  # does NOT publish a metalink for it: the obvious metalink swap 404s.
  # So the main repos are written with explicit baseurls, and the original
  # files are disabled rather than deleted.
  local repo="/etc/yum.repos.d/tuna-fedora.repo"
  local repo_files=(
    /etc/yum.repos.d/fedora.repo
    /etc/yum.repos.d/fedora-updates.repo
    /etc/yum.repos.d/fedora-updates-testing.repo
    /etc/yum.repos.d/fedora-modular.repo
  )
  local desired f

  desired="$(cat <<EOF
[fedora-tuna]
name=Fedora \$releasever - \$basearch (TUNA)
baseurl=https://$MIRROR_HOST/fedora/releases/\$releasever/Everything/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch

[fedora-tuna-updates]
name=Fedora \$releasever - \$basearch - updates (TUNA)
baseurl=https://$MIRROR_HOST/fedora/updates/\$releasever/Everything/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch

[fedora-tuna-updates-testing]
name=Fedora \$releasever - \$basearch - updates-testing (TUNA)
baseurl=https://$MIRROR_HOST/fedora/updates/testing/\$releasever/Everything/\$basearch/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch
EOF
)"

  # Compare the whole file, not just the host: a machine that ran the old
  # version already mentions the mirror, so a host-only guard would keep its
  # broken repo file forever.
  if [ -f "$repo" ] && [ "$(cat "$repo")" = "$desired" ]; then
    skip "already using $MIRROR_HOST for dnf"
    return 0
  fi

  [ -f "$repo" ] && backup_file "$repo"

  for f in "${repo_files[@]}"; do
    [ -f "$f" ] && backup_file "$f"
  done

  info "  writing $repo"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  \033[0;90m$ write %s\033[0m\n' "$repo"
  else
    # /etc/yum.repos.d is root-owned: a plain redirect runs as the invoking
    # user and dies with "Permission denied" under set -e. Pipe through the
    # privilege wrapper instead (empty RUN_AS leaves a plain tee).
    printf '%s\n' "$desired" | $RUN_AS tee "$repo" >/dev/null
  fi

  # The originals keep their metalink; disabling them makes the TUNA repos
  # the only source, which is the point of switching.
  for f in "${repo_files[@]}"; do
    [ -f "$f" ] || continue
    run $RUN_AS sed -i 's|^enabled=1$|enabled=0|' "$f"
  done

  step "verifying the new repos"
  if run_sh "$RUN_AS dnf -q makecache --refresh"; then
    ok "dnf source in use: $MIRROR_HOST"
  else
    warn "the mirror did not work -- restoring the original repos"
    for f in "${repo_files[@]}"; do
      [ -f "$BACKUP_DIR/$f" ] && run $RUN_AS cp -a "$BACKUP_DIR/$f" "$f"
    done
    run_sh "$RUN_AS rm -f '$repo'" || true
    warn "restored the original repos"
  fi
}

# --------------------------------------------------------------------------
# Stage 2: base packages
# --------------------------------------------------------------------------

# The package set every machine in the history ended up with. The names are
# the apt names; the dnf names are mapped below, because "default-jdk" and
# "build-essential" do not exist on Fedora.
APT_BASE_PACKAGES=(
  "curl" "ca-certificates" "git" "build-essential" "unzip" "zstd"
  "python3-pip" "default-jdk" "bubblewrap" "ffmpeg"
  "libicu-dev" "libcurl4-openssl-dev" "zlib1g-dev" "libkrb5-dev"
  "xclip" "xsel" "wl-clipboard" "imagemagick"
  "gnome-keyring" "libsecret-1-0" "dbus-x11"
  "xfonts-base"
)

DNF_BASE_PACKAGES=(
  "curl" "ca-certificates" "git" "gcc" "gcc-c++" "make" "unzip" "zstd"
  "python3-pip" "java-latest-openjdk-headless" "bubblewrap" "ffmpeg"
  "libicu-devel" "libcurl-devel" "zlib-devel" "krb5-devel"
  "xclip" "xsel" "wl-clipboard" "ImageMagick"
  "gnome-keyring" "libsecret" "dbus-x11"
  "dejavu-sans-mono-fonts" "google-noto-sans-cjk-fonts"
)

stage_packages() {
  info "Stage 2: base packages"
  case "$PKG_MGR" in
    apt) pkg_apt "${APT_BASE_PACKAGES[@]}" ;;
    dnf) pkg_dnf "${DNF_BASE_PACKAGES[@]}" ;;
    *)  skip "no package recipe for $PKG_MGR" ;;
  esac
}

pkg_apt() {
  run_sh "$RUN_AS apt-get update -qq"
  local missing=()
  local p
  for p in "$@"; do
    # dpkg-query answers "install ok installed" for a package that is there
    if ! dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed"; then
      missing+=("$p")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    skip "all base packages present"
    return 0
  fi
  step "installing: ${missing[*]}"
  run_sh "$RUN_AS apt-get install -y ${missing[*]}"
  ok "base packages installed"
}

pkg_dnf() {
  local missing=()
  local p
  for p in "$@"; do
    if ! rpm -q "$p" >/dev/null 2>&1; then
      missing+=("$p")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    skip "all base packages present"
    return 0
  fi
  step "installing: ${missing[*]}"
  run_sh "$RUN_AS dnf install -y ${missing[*]}"
  ok "base packages installed"
}

# --------------------------------------------------------------------------
# Stage 3: node, corepack, pnpm
# --------------------------------------------------------------------------

stage_node() {
  info "Stage 3: node toolchain"

  export NVM_DIR="$HOME/.nvm"

  # nvm installs into $HOME, so it never needs root.
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    skip "nvm already installed"
  else
    step "installing nvm"
    run_sh "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash"
  fi

  # nvm is a shell function; load it for this run.
  # shellcheck disable=SC1091
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
  fi

  if [ ! -s "$NVM_DIR/nvm.sh" ] && ! have node; then
    die "nvm is not installed and its installer did not create $NVM_DIR/nvm.sh"
  fi

  if have node; then
    step "node is $(node -v)"
  else
    step "installing node $NODE_VERSION"
    # run_sh is a fresh `bash -c`: the nvm function has to be sourced there.
    run_sh ". \"\$NVM_DIR/nvm.sh\" && nvm install $NODE_VERSION"
    run_sh ". \"\$NVM_DIR/nvm.sh\" && nvm alias default $NODE_VERSION"
    # The install ran in a child shell, so this shell's PATH still has no
    # node. Reload nvm now that the default alias exists, or the corepack
    # checks below cannot find the binary it just installed.
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
  fi

  if have corepack; then
    step "enabling corepack"
    run_sh "corepack enable"
  fi

  if have pnpm; then
    step "pnpm is $(pnpm -v 2>/dev/null || echo unknown)"
  else
    step "installing pnpm through corepack"
    run_sh "corepack prepare pnpm@latest --activate"
  fi

  # pnpm 10+ skips dependency lifecycle scripts by default, and pnpm 12 also
  # pops an INTERACTIVE approve-builds prompt that an agent cannot answer.
  # The repo's own pnpm config turns the guard off and removes the
  # cooling-off window; it is optional, so it is only applied on request.
  if [ -f "$SHELL_FILES/pnpm/config.yaml" ] || [ -f "$(dirname "${SHELL_FILES:-/nonexistent}")/pnpm/config.yaml" ]; then
    step "note: pnpm config.yaml exists in the repo; apply it with stage 8 if wanted"
  fi
  ok "node toolchain ready"
}

# --------------------------------------------------------------------------
# Stage 4: python via uv
# --------------------------------------------------------------------------

stage_python() {
  info "Stage 4: python toolchain"

  if have uv; then
    step "uv is $(uv --version 2>/dev/null || echo unknown)"
  else
    step "installing uv"
    run_sh "curl -LsSf https://astral.sh/uv/install.sh | sh"
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi

  # Fedora's uv RPM ships /etc/uv/uv.toml with python-downloads = "manual",
  # so `uv run --python 3.12` fails until an interpreter is installed once.
  if ! uv python find $PYTHON_VERSION >/dev/null 2>&1; then
    step "installing python $PYTHON_VERSION through uv"
    run_sh "uv python install $PYTHON_VERSION"
  else
    skip "python $PYTHON_VERSION already available"
  fi
  ok "python toolchain ready"
}

# --------------------------------------------------------------------------
# Stage 5: git identity
# --------------------------------------------------------------------------

stage_git() {
  info "Stage 5: git identity"
  if ! have git; then
    skip "git is not installed"
    return 0
  fi
  if git config --global user.name >/dev/null 2>&1; then
    skip "git identity already set ($(git config --global user.name))"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    step "would ask for user.name and user.email"
    return 0
  fi
  # The identity cannot be guessed, and a `read` at EOF fails the whole run
  # under `set -e`. Under --yes or without a terminal, leave it to the user.
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
    warn "git identity is not set; skipped under --yes / without a terminal"
    warn "set it with: git config --global user.name ...; git config --global user.email ..."
    return 0
  fi
  local name email
  printf '  git user.name  : '
  read -r name
  printf '  git user.email : '
  read -r email
  [ -n "$name" ] && run git config --global user.name "$name"
  [ -n "$email" ] && run git config --global user.email "$email"
  ok "git identity set"
}

# --------------------------------------------------------------------------
# Stage 6: zsh, oh-my-zsh, the two plugins
# --------------------------------------------------------------------------

stage_zsh() {
  info "Stage 6: zsh + oh-my-zsh"

  if have zsh; then
    skip "zsh already installed"
  else
    case "$PKG_MGR" in
      apt) run_sh "$RUN_AS apt-get install -y zsh" ;;
      dnf) run_sh "$RUN_AS dnf install -y zsh" ;;
    esac
  fi

  if [ -d "$HOME/.oh-my-zsh" ]; then
    skip "oh-my-zsh already installed"
  else
    step "installing oh-my-zsh (unattended, keeps an existing .zshrc)"
    # --keep-zshrc matters: without it the installer overwrites a .zshrc
    # that was placed there on purpose.
    run_sh "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" --unattended --keep-zshrc"
  fi

  local plugins="$HOME/.oh-my-zsh/custom/plugins"
  mkdir_p "$plugins"
  local p
  for p in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ -d "$plugins/$p/.git" ]; then
      skip "$p already cloned"
      continue
    fi
    step "cloning $p"
    run git clone --depth=1 "https://github.com/zsh-users/$p.git" "$plugins/$p"
  done

  # The plugin list itself lives in ~/.zshrc, which stage 7 deploys from
  # the repo. Here we only make sure the list mentions both plugins.
  if [ -f "$HOME/.zshrc" ] && grep -q "zsh-autosuggestions" "$HOME/.zshrc"; then
    skip "~/.zshrc already lists the plugins"
  else
    warn "~/.zshrc does not list the plugins yet -- stage 7 deploys the repo's .zshrc"
  fi

  # The login shell, so a terminal that reads /etc/passwd starts zsh too.
  local current
  current="$(getent passwd "$(id -un)" | cut -d: -f7)"
  if [ "$current" = "/usr/bin/zsh" ]; then
    skip "login shell is already zsh"
  else
    step "setting the login shell to zsh (was $current)"
    run_sh "$RUN_AS chsh -s /usr/bin/zsh \"$(id -un)\""
  fi
  ok "zsh ready"
}

# --------------------------------------------------------------------------
# Stage 7: the four-layer shell config
# --------------------------------------------------------------------------

stage_shell() {
  info "Stage 7: four-layer shell config"

  if [ -z "$SHELL_FILES" ]; then
    skip "no --shell-files given; skipping the config deploy"
    warn "pass --shell-files <repo>/shell/files to deploy it"
    return 0
  fi
  if [ ! -d "$SHELL_FILES" ]; then
    die "--shell-files points at a directory that does not exist: $SHELL_FILES"
  fi

  local f
  for f in zshenv shell_wslfn shell_common zshrc bashrc profile; do
    local src="$SHELL_FILES/$f"
    local dst="$HOME/.$f"
    if [ ! -f "$src" ]; then
      skip "$f not in $SHELL_FILES"
      continue
    fi
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      skip "~/.$f already identical"
      continue
    fi
    backup_file "$dst"
    step "installing ~/.$f"
    run cp "$src" "$dst"
  done

  # The shell config is only half the job: the desktop session keeps its
  # own SHELL snapshot, and a terminal started from the panel inherits that
  # snapshot before any rc file runs.
  if [ "$HAS_DESKTOP" -eq 1 ] && have systemctl; then
    step "updating the systemd user session environment"
    run systemctl --user set-environment SHELL=/usr/bin/zsh || warn "systemctl --user failed (no session bus?)"
    if have dbus-update-activation-environment; then
      run dbus-update-activation-environment --systemd SHELL=/usr/bin/zsh || true
    fi
  fi

  ok "shell config deployed"
}

# --------------------------------------------------------------------------
# Stage 8: desktop extras
# --------------------------------------------------------------------------

stage_desktop() {
  info "Stage 8: desktop extras"
  if [ "$HAS_DESKTOP" -eq 0 ]; then
    skip "no desktop session on this machine"
    return 0
  fi

  # --- fcitx5 -----------------------------------------------------------
  # GTK_IM_MODULE, QT_IM_MODULE and XMODIFIERS come from the shared shell
  # file (stage 7), on every session type. On Plasma Wayland they are not what
  # makes the browsers type: KWin has to start Fcitx5 as the virtual keyboard.
  # That is a System Settings choice written by its own KCM, so this script
  # only reminds -- see linux-desktop/wayland-fcitx5-rime.md, root cause 4.
  if have fcitx5; then
    skip "fcitx5 already installed"
  else
    case "$PKG_MGR" in
      apt) run_sh "$RUN_AS apt-get install -y fcitx5 fcitx5-chinese-addons fcitx5-config-qt" ;;
      dnf) run_sh "$RUN_AS dnf install -y fcitx5 fcitx5-chinese-addons" ;;
    esac
  fi
  if [ "$PKG_MGR" = "apt" ] && have im-config; then
    step "selecting fcitx5 as the input method"
    run im-config -n fcitx5 || warn "im-config failed"
  fi
  if [ "$IS_WAYLAND" -eq 1 ] && [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then
    warn "Plasma Wayland: select Fcitx 5 under System Settings -> Keyboard -> Virtual Keyboard, then log out and in"
  fi

  # --- Ghostty -----------------------------------------------------------
  if have ghostty; then
    skip "ghostty already installed"
  else
    step "installing ghostty"
    case "$PKG_MGR" in
      dnf)
        # Fedora's own repositories do not carry it; the COPR does.
        run_sh "$RUN_AS dnf copr enable -y scottames/ghostty"
        run_sh "$RUN_AS dnf install -y ghostty"
        ;;
      apt)
        # The .deb route is Ubuntu/Mint only.
        step "installing ghostty from the community .deb (Ubuntu/Mint only)"
        run_sh "wget -q https://github.com/mkasberg/ghostty-ubuntu/releases/download/v1.3.1/ghostty_1.3.1_amd64.deb -O /tmp/ghostty.deb && $RUN_AS apt-get install -y /tmp/ghostty.deb"
        ;;
      *) skip "no ghostty recipe for $PKG_MGR" ;;
    esac
  fi

  # --- the config --------------------------------------------------------
  # Ghostty 1.3.x reads BOTH $XDG_CONFIG_HOME/ghostty/config and
  # .../config.ghostty, merging them per key with config.ghostty winning.
  # The GUI creates an EMPTY config.ghostty on first run when neither
  # exists, and an empty one shadows nothing -- but it also means the
  # canonical name has to be written explicitly, not assumed.
  local ghostty_src=""
  [ -n "$SHELL_FILES" ] && ghostty_src="$(dirname "$SHELL_FILES")/linux-desktop/files/ghostty/config"
  if [ -f "$ghostty_src" ]; then
    local gdir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
    mkdir_p "$gdir"
    local gname
    for gname in config.ghostty config; do
      if [ -f "$gdir/$gname" ] && cmp -s "$ghostty_src" "$gdir/$gname"; then
        skip "~/$(basename "$gdir")/$gname already identical"
        continue
      fi
      backup_file "$gdir/$gname"
      step "installing $gdir/$gname"
      run cp "$ghostty_src" "$gdir/$gname"
    done
    # Validate the way that actually works: the flag has to be glued to
    # the path with "=", otherwise the validator exits 1 and says nothing.
    if [ "$DRY_RUN" -eq 0 ] && have ghostty; then
      local gfile="$gdir/config.ghostty"
      local out rc
      out="$(ghostty +validate-config --config-file="$gfile" 2>&1)" && rc=0 || rc=$?
      if [ "$rc" -eq 0 ]; then
        ok "ghostty config validated"
      else
        warn "ghostty config validation failed: $out"
      fi
    fi
  else
    skip "no ghostty config original found (expected next to shell/files)"
  fi

  # --- the Nemo action (Mint/Cinnamon only) ------------------------------
  local nemo_src=""
  [ -n "$SHELL_FILES" ] && nemo_src="$(dirname "$SHELL_FILES")/linux-desktop/files/nemo/actions"
  if [ -n "$nemo_src" ] && [ -d "$nemo_src" ]; then
    if have nemo; then
      local ndir="$HOME/.local/share/nemo/actions"
      mkdir_p "$ndir"
      local nf
      for nf in "$nemo_src"/*.nemo_action; do
        [ -f "$nf" ] || continue
        backup_file "$ndir/$(basename "$nf")"
        run cp "$nf" "$ndir/$(basename "$nf")"
      done
    else
      skip "no nemo on this machine (the Nemo action is Mint/Cinnamon only)"
    fi
  fi
  ok "desktop extras done"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

main() {
  printf '\033[1m%s\033[0m -- fresh Linux bootstrap\n' "$SCRIPT_NAME"
  detect_env
  want_stage 0 && stage_preflight
  want_stage 1 && stage_mirrors
  want_stage 2 && stage_packages
  want_stage 3 && stage_node
  want_stage 4 && stage_python
  want_stage 5 && stage_git
  want_stage 6 && stage_zsh
  want_stage 7 && stage_shell
  want_stage 8 && stage_desktop
  printf '\n\033[1;32mDone.\033[0m backups (if any): %s\n' "$BACKUP_DIR"
}

main "$@"
