#!/usr/bin/env bash
# check-bootstrap.sh -- report whether this machine matches the state
# bootstrap-linux.sh produces. Read-only: it changes nothing.
#
# WHY A SEPARATE PROBE
#   A bootstrap that reports its own success is only as good as the
#   author's assumptions. This script asks the same questions from the
#   outside, so a stage that silently did nothing still shows up here.
#
# EXIT CODES
#   0 every required check passed
#   1 at least one required check failed (the failing checks are listed)
#
# USAGE
#   bash check-bootstrap.sh

set -uo pipefail

PASS=0
FAIL=0
WARN=0

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
pass() { printf '  \033[0;32mPASS\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
warn() { printf '  \033[0;33mWARN\033[0m %s\n' "$*"; WARN=$((WARN + 1)); }
skip() { printf '  \033[0;90mSKIP\033[0m %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

check() {
  # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

# --------------------------------------------------------------------------

info "machine"
if [ -r /etc/os-release ]; then
  printf '  distro: %s %s  (%s)\n' \
    "$(. /etc/os-release && echo "${ID:-?}")" \
    "$(. /etc/os-release && echo "${VERSION_ID:-?}")" \
    "$(. /etc/os-release && echo "${PRETTY_NAME:-?}")"
fi
if grep -qi microsoft /proc/version 2>/dev/null; then
  printf '  wsl: yes\n'
else
  printf '  wsl: no\n'
fi

info "packages"
if have apt-get; then
  printf '  package manager: apt-get\n'
  # -r: Debian 13 keeps its source in sources.list.d/debian.sources (deb822),
  # and grep without -r skips a directory -- the mirror always read as the
  # vendor default, while apt was fetching from it.
  if grep -rqs "mirrors.tuna\|mirrors.aliyun\|mirrors.ustc" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    pass "apt source points at a mirror"
  else
    skip "apt source is the vendor default (not a mirror)"
  fi
elif have dnf; then
  printf '  package manager: dnf\n'
  if [ -f /etc/yum.repos.d/tuna-fedora.repo ]; then
    pass "the TUNA dnf repo file is present"
  else
    skip "no TUNA dnf repo file"
  fi
  if rpm -q ghostty >/dev/null 2>&1; then
    pass "ghostty is installed ($(rpm -q ghostty))"
  else
    skip "ghostty is not installed (the COPR is the Fedora route)"
  fi
fi

# The toolchains are put on PATH by ~/.zshrc (nvm, ~/.local/bin), which this
# non-interactive script never reads. Measured on Debian 13 right after a
# working bootstrap: `zsh -ic` found node, pnpm and uv while this script's
# own PATH did not, so all three read as missing. Ask the shell a user opens.
if have zsh && [ -f "$HOME/.zshrc" ]; then
  user_path="$(zsh -ic 'printf "%s\n" "$PATH"' 2>/dev/null | tail -1)"
  if [ -n "$user_path" ]; then
    export PATH="$user_path"
    printf '  PATH taken from an interactive zsh\n'
  fi
fi

info "node toolchain"
check "node is on PATH" command -v node
if have node; then
  printf '  node: %s\n' "$(node -v 2>/dev/null)"
fi
check "nvm is installed" test -s "$HOME/.nvm/nvm.sh"
if have pnpm; then
  printf '  pnpm: %s\n' "$(pnpm -v 2>/dev/null || echo unknown)"
  pass "pnpm is on PATH"
else
  fail "pnpm is not on PATH"
fi

info "python toolchain"
check "uv is on PATH" command -v uv
if have uv; then
  printf '  uv: %s\n' "$(uv --version 2>/dev/null)"
  if uv python find 3.12 >/dev/null 2>&1; then
    pass "python 3.12 is available through uv"
  else
    fail "python 3.12 is not installed (uv python install 3.12)"
  fi
fi

info "git"
if have git; then
  # The effective identity is what matters: it can come from the system,
  # the global or the repository config, and a repo-local identity is a
  # legitimate answer (see git-github/).
  if git config user.name >/dev/null 2>&1 && git config user.email >/dev/null 2>&1; then
    pass "git identity resolves"
    printf '  name : %s\n' "$(git config user.name 2>/dev/null)"
    printf '  where: %s\n' "$(git config --show-origin --get user.name 2>/dev/null | head -1 | awk '{print $1}')"
  else
    fail "git identity is not set (git config --global user.name / user.email)"
  fi
else
  fail "git is not installed"
fi
if have gh; then
  if gh auth status >/dev/null 2>&1; then
    pass "gh is authenticated"
  else
    warn "gh is installed but not authenticated (gh auth login)"
  fi
fi

info "zsh"
check "zsh is installed" command -v zsh
if [ -d "$HOME/.oh-my-zsh" ]; then
  pass "oh-my-zsh is installed"
else
  fail "oh-my-zsh is not installed"
fi
for p in zsh-autosuggestions zsh-syntax-highlighting; do
  if [ -d "$HOME/.oh-my-zsh/custom/plugins/$p" ]; then
    pass "$p is present"
  else
    fail "$p is missing from ~/.oh-my-zsh/custom/plugins"
  fi
done
if [ -f "$HOME/.zshrc" ]; then
  if grep -q "zsh-autosuggestions" "$HOME/.zshrc" && grep -q "zsh-syntax-highlighting" "$HOME/.zshrc"; then
    pass "~/.zshrc lists both plugins"
  else
    fail "~/.zshrc does not list both plugins"
  fi
  # The syntax highlighting plugin has to be the LAST one: it hooks the
  # widgets the others also hook, and the order decides who wins.
  last_plugin="$(awk '/^plugins=/' "$HOME/.zshrc" | sed 's/.*(//; s/).*//' | tr ' ' '\n' | grep -v '^$' | tail -1)"
  if [ "$last_plugin" = "zsh-syntax-highlighting" ]; then
    pass "zsh-syntax-highlighting is the last plugin"
  else
    fail "zsh-syntax-highlighting is not last in the plugin list (last: ${last_plugin:-none})"
  fi
else
  fail "~/.zshrc does not exist"
fi
login_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"
if [ "$login_shell" = "/usr/bin/zsh" ]; then
  pass "the login shell is zsh"
else
  fail "the login shell is $login_shell, not /usr/bin/zsh"
fi

info "shell config"
for f in zshenv shell_wslfn shell_common zshrc; do
  if [ -f "$HOME/.$f" ]; then
    pass "~/.$f exists"
  else
    fail "~/.$f is missing"
  fi
done
if [ -f "$HOME/.shell_common" ] && grep -q "shell_wslfn\|zshenv" "$HOME/.shell_common" 2>/dev/null; then
  skip "~/.shell_common mentions the other layers"
else
  skip "~/.shell_common does not reference the other layers (fine)"
fi

info "desktop"
if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
  if have fcitx5; then
    pass "fcitx5 is installed"
  else
    skip "fcitx5 is not installed"
  fi
  # A new shell should carry the toolkit IM variables on every session type:
  # X11 needs them, and on Plasma Wayland they did not matter to the browsers
  # once Fcitx 5 was KWin's virtual keyboard (linux-desktop/wayland-fcitx5-rime.md,
  # root cause 4). Ask a real shell instead of grepping the file.
  if [ -f "$HOME/.shell_common" ] && have zsh; then
    im_state="$(zsh -ic 'echo "[${GTK_IM_MODULE:-unset}][${QT_IM_MODULE:-unset}][${XMODIFIERS:-unset}]"' 2>/dev/null | tail -1)"
    if [ "$im_state" = "[fcitx][fcitx][@im=fcitx]" ]; then
      pass "a new shell exports GTK_IM_MODULE, QT_IM_MODULE and XMODIFIERS for fcitx"
    else
      warn "a new shell has unexpected IM variables: $im_state"
    fi
  fi
  if have ghostty; then
    printf '  ghostty: %s\n' "$(ghostty --version 2>/dev/null | head -1)"
    gdir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
    found=""
    for gname in config.ghostty config; do
      if [ -f "$gdir/$gname" ]; then
        found="$gname"
        break
      fi
    done
    if [ -n "$found" ]; then
      pass "a ghostty config exists ($gdir/$found)"
      # The flag has to be glued to the path with "=", or the validator
      # exits 1 and says nothing on every file.
      out="$(ghostty +validate-config --config-file="$gdir/$found" 2>&1)" && rc=0 || rc=$?
      if [ "$rc" -eq 0 ]; then
        pass "the ghostty config validates"
      elif [ -n "$out" ]; then
        fail "the ghostty config does not validate: $out"
      else
        fail "the ghostty config did not validate and said nothing (empty file?)"
      fi
    else
      fail "no ghostty config in $gdir"
    fi
  fi
  if fc-match "Sarasa Term SC" >/dev/null 2>&1 && fc-match "Sarasa Term SC" | grep -qi sarasa; then
    pass "the Sarasa Term SC font resolves"
  else
    warn "Sarasa Term SC does not resolve (the 1:2 terminal font ratio will not hold)"
  fi
else
  skip "no desktop session"
fi

printf '\n\033[1msummary:\033[0m %d pass, %d fail, %d warn\n' "$PASS" "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
