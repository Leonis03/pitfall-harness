#!/usr/bin/env bash
# scan-disk.sh -- measure where a Linux filesystem's bytes actually are, before deleting any of them.
#
# Usage:
#   bash scan-disk.sh [target]          # default: /
#
# Read-only. Deletes nothing, changes nothing, installs nothing.
#
# Prints six sections:
#   1  filesystem usage and the home / outside-home split
#   2  the largest directories on the target filesystem
#   3  package-manager residue (apt cache, snap cache, retired snap revisions, journal)
#   4  installed-package volume against a fresh-install baseline
#   5  the largest individual files
#   6  git repositories with no remote -- the only local copy of that work
#
# Sections 3 and 4 are distro-aware (apt, dnf, zypper, pacman, apk; dpkg or rpm).
# An unrecognised manager prints `unsupported:` -- never an empty section, because
# an empty section is indistinguishable from "nothing to clean".
#
# sudo is used where the paths are root-owned. Without it those sections are
# marked incomplete rather than silently reporting a small number: `du` skips
# mode-700 directories (/var/lib/private, /var/log/private, /var/db/sudo) and
# still prints a total, so the number is a LOWER BOUND. See rule 10 in SKILL.md.
#
# Notes on the shell-level traps this script is written to avoid:
#   - `du -s` and `--max-depth` conflict; use one or the other, never both.
#   - `du` reports KiB blocks; divide by 1024 for MiB, not by 1048576.
#   - Bind mounts (WSL's /mnt/c, /usr/lib/wsl) are not part of the filesystem
#     under test. `du -x` is what excludes them; without it a WSL host's
#     Windows-side driver directory dwarfs the real answer.
#   - A glob is expanded by the CALLER's shell. `sudo rm -rf /root-only-dir/*`
#     silently does nothing when the caller cannot read the directory.
#     Reading with `find` instead of a glob avoids the class entirely.

set -Eeuo pipefail

TARGET="${1:-/}"

if [[ ! -d "$TARGET" ]]; then
    echo "scan-disk.sh: '$TARGET' is not a directory" >&2
    exit 1
fi

have_sudo=0
if [[ "$(id -u)" != "0" ]] && sudo -n true 2>/dev/null; then
    have_sudo=1
elif [[ "$(id -u)" == "0" ]]; then
    have_sudo=1
fi

# Run du as root when possible so root-owned directories are counted. Already
# being root means plain `du` sees everything -- and a root box without sudo
# installed would otherwise fail every measurement with "command not found".
du_args() {
    if [[ "$(id -u)" == "0" ]]; then
        du "$@"
    elif [[ $have_sudo == 1 ]]; then
        sudo du "$@"
    else
        du "$@" 2>/dev/null
    fi
}

section() {
    printf '\n=== %s ===\n' "$1"
}

# MiB from du's KiB output, two decimals.
to_mib() {
    awk -v k="${1:-0}" 'BEGIN { printf "%.1f", k / 1024 }'
}

# Without root, du skips every mode-700 root directory and still prints a
# total -- a LOWER BOUND that reads like an answer. Say so once, at the top,
# so every figure in every section carries the caveat (rule 10 in SKILL.md).
if [[ $have_sudo == 0 ]]; then
    printf 'NOTE: no passwordless sudo -- every du figure below is a LOWER BOUND.\n'
    printf '      du skips mode-700 root directories and still prints a total.\n'
    printf '      Re-run with sudo for the root-owned parts.\n'
fi

# ---------------------------------------------------------------- section 1
section "1. filesystem usage"

df -h "$TARGET" | sed 's/^/  /'

HOME_DIR="${HOME:-/root}"
if [[ -d "$HOME_DIR" ]]; then
    home_kib=$(du_args -sx "$HOME_DIR" 2>/dev/null | cut -f1 || true)
    home_kib="${home_kib:-0}"
    outside_kib=$(du_args -sx --exclude="$HOME_DIR" --exclude=/mnt --exclude=/proc \
                          --exclude=/sys --exclude=/dev --exclude=/run "$TARGET" 2>/dev/null | cut -f1 || true)
    outside_kib="${outside_kib:-0}"
    printf '\n  home (%s)          %s MiB\n' "$HOME_DIR" "$(to_mib "$home_kib")"
    printf '  everything else    %s MiB\n' "$(to_mib "$outside_kib")"
fi

# ---------------------------------------------------------------- section 2
section "2. largest directories on $TARGET"

# `head` in a pipeline closes the pipe early; under `pipefail` that SIGPIPE
# aborts the whole script. `awk` consumes all input instead, so limit with awk.
du_args -x --max-depth=1 "$TARGET" 2>/dev/null | sort -rn \
    | awk 'NR<=16 {printf "  %10.1f MiB  %s\n", $1/1024, $2}'

# ---------------------------------------------------------------- section 3
section "3. package-manager residue (regenerable)"

# Which manager owns the cache. Guessing wrong leaves this section EMPTY, which
# reads exactly like "nothing to clean" -- so an unrecognised manager prints
# `unsupported:` rather than nothing.
detect_manager() {
    for c in apt-get dnf zypper pacman apk; do
        if command -v "$c" >/dev/null 2>&1; then
            echo "$c"; return
        fi
    done
    echo none
}

pkg_manager=$(detect_manager)
printf '  detected package manager: %s\n' "$pkg_manager"

case "$pkg_manager" in
    apt-get)
        for p in /var/cache/apt/archives /var/lib/apt/lists /var/lib/snapd/cache /var/log/journal; do
            if [[ -e "$p" ]]; then
                k=$(du_args -sx "$p" 2>/dev/null | cut -f1 || true)
                printf '  %-26s %8s MiB\n' "$p" "$(to_mib "${k:-0}")"
            fi
        done
        printf '  clean with: sudo apt clean / sudo journalctl --vacuum-size=50M\n'
        ;;
    dnf)
        # dnf4 and dnf5 use different cache paths; on Fedora 41+ only libdnf5 exists.
        for p in /var/cache/libdnf5 /var/cache/dnf /var/log/journal; do
            if [[ -e "$p" ]]; then
                k=$(du_args -sx "$p" 2>/dev/null | cut -f1 || true)
                printf '  %-26s %8s MiB\n' "$p" "$(to_mib "${k:-0}")"
            fi
        done
        # The user-level cache is a SECOND copy, not the same one -- see routine.md.
        if [[ -d "$HOME_DIR/.cache/libdnf5" ]]; then
            k=$(du_args -sx "$HOME_DIR/.cache/libdnf5" 2>/dev/null | cut -f1 || true)
            printf '  %-26s %8s MiB  (user-level copy, separate from the above)\n' \
                "$HOME_DIR/.cache/libdnf5" "$(to_mib "${k:-0}")"
        fi
        printf '  clean with: sudo dnf clean all / sudo journalctl --vacuum-size=50M\n'
        ;;
    zypper|pacman|apk)
        case "$pkg_manager" in
            zypper) paths=(/var/cache/zypp /var/log/journal); clean="sudo zypper clean --all" ;;
            pacman) paths=(/var/cache/pacman/pkg);              clean="sudo paccache -rk2" ;;
            apk)    paths=(/var/cache/apk);                     clean="sudo apk cache clean" ;;
        esac
        for p in "${paths[@]}"; do
            [[ -e "$p" ]] || continue
            k=$(du_args -sx "$p" 2>/dev/null | cut -f1 || true)
            printf '  %-26s %8s MiB\n' "$p" "$(to_mib "${k:-0}")"
        done
        printf '  clean with: %s\n' "$clean"
        ;;
    none)
        printf '  unsupported: no known package manager found -- measure the cache by hand\n'
        ;;
esac

if command -v snap >/dev/null 2>&1; then
    # `snap list --all` columns: Name Version Rev Tracking Publisher Notes.
    # The revision is $3, NOT $2 -- $2 is the version string, and
    # `snap remove --revision=` rejects a version.
    retired=$(snap list --all 2>/dev/null | awk 'NR>1 && $6 ~ /^disabled/ {print $1" "$3}' || true)
    if [[ -n "$retired" ]]; then
        printf '\n  retired snap revisions (removable):\n'
        while read -r name rev; do
            [[ -n "$name" ]] && printf '    %-12s rev %s\n' "$name" "$rev"
        done <<<"$retired"
    fi
fi

# ---------------------------------------------------------------- section 4
section "4. installed packages versus a fresh-install baseline"

if command -v dpkg-query >/dev/null 2>&1; then
    pkg_count=$(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l | tr -d ' ')
    pkg_mib=$(dpkg-query -W -f='${Installed-Size}\n' 2>/dev/null | awk '{s+=$1} END {printf "%.0f", s/1024}')
    manual_count=$(apt-mark showmanual 2>/dev/null | wc -l | tr -d ' ')
    printf '  installed packages   %s (manual %s)\n' "$pkg_count" "$manual_count"
    printf '  installed size       %s MiB\n' "$pkg_mib"
    printf '  a fresh Ubuntu 24.04 is about 380 packages / 1300 MiB, ~35 of them manual\n'
    printf '\n  largest installed packages:\n'
    dpkg-query -W -f='${Installed-Size}\t${binary:Package}\n' 2>/dev/null | sort -rn \
        | awk -F'\t' 'NR<=12 {printf "    %8.1f MiB  %s\n", $1/1024, $2}'
elif command -v rpm >/dev/null 2>&1; then
    pkg_count=$(rpm -qa 2>/dev/null | wc -l | tr -d ' ')
    printf '  installed packages   %s\n' "$pkg_count"
    printf '  a fresh Fedora 44 server is roughly 550-700 packages; a desktop more\n'
    printf '\n  largest installed packages:\n'
    rpm -qa --qf '%{SIZE}\t%{NAME}\n' 2>/dev/null | sort -rn \
        | awk -F'\t' 'NR<=12 {printf "    %8.1f MiB  %s\n", $1/1048576, $2}'
    printf '\n  kernels installed: %s (running %s)\n' \
        "$(rpm -q kernel 2>/dev/null | wc -l | tr -d ' ')" "$(uname -r)"
    printf '  NOTE: no per-package baseline exists for rpm -- judge by category, not by count\n'
else
    printf '  unsupported: no dpkg-query and no rpm -- count packages by hand\n'
fi

# ---------------------------------------------------------------- section 5
section "5. largest individual files under $HOME_DIR"

if [[ -d "$HOME_DIR" ]]; then
    find "$HOME_DIR" -xdev -type f -size +50M -printf '%s\t%p\n' 2>/dev/null | sort -rn \
        | awk -F'\t' 'NR<=20 {printf "  %9.1f MiB  %s\n", $1/1048576, $2}'
    big_models=$(find "$HOME_DIR" -xdev -type f \
        \( -name '*.pth' -o -name '*.pt' -o -name '*.ckpt' -o -name '*.safetensors' \
           -o -name '*.bin' -o -name '*.onnx' \) -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "%.0f", s/1048576}')
    if [[ -n "$big_models" && "${big_models:-0}" != "0" ]]; then
        printf '\n  model-weight files total: %s MiB\n' "$big_models"
    fi
fi

# ---------------------------------------------------------------- section 6
section "6. git repositories with no remote (only local copy)"

found=0
while IFS= read -r dotgit; do
    repo="${dotgit%/.git}"
    remote=$(git -C "$repo" remote -v 2>/dev/null | head -1 || true)
    if [[ -z "$remote" ]]; then
        dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        size=$(du_args -sx "$repo" 2>/dev/null | cut -f1 || true)
        printf '  %-46s %8s MiB  (%s uncommitted files)\n' "$repo" "$(to_mib "${size:-0}")" "$dirty"
        found=1
    fi
done < <(find "$HOME_DIR" -xdev -maxdepth 5 -type d -name .git 2>/dev/null)
[[ $found == 0 ]] && printf '  (none, or none reachable without sudo)\n'

printf '\nscan-disk.sh: read-only. Nothing was deleted. Decide the mode before deleting anything.\n'
