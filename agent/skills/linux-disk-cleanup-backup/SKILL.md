---
name: linux-disk-cleanup-backup
description: Reclaim disk space on a Linux machine by deleting only what can be regenerated -- package-manager caches, build caches, AI-tool session garbage, installed software, IDE and toolchain installs, and model weights -- and back up what must survive to an external NTFS or ext4 drive. Use this skill whenever the user mentions disk space, disk usage, a full filesystem, df -h, freeing or reclaiming space, shrinking a filesystem or a WSL disk image, cleaning caches, backing up a home directory, archiving a machine, or making a backup image of a machine smaller. Offers routine housekeeping for a system in daily use, an archival cleanup pass for a system that will not be used again, and a backup pass that copies the irreplaceable data to an external drive.
---

# Linux Disk Cleanup and Backup

## Overview

Two halves of one job, and the second half is the one that matters.

| Half | Question | Result |
| :--- | :--- | :--- |
| **Cleanup** | What can be deleted because it comes back? | Space, on the machine |
| **Backup** | What must survive if the machine is gone? | Data, on another drive |

The cleanup half has two modes with different blast radius and different approval
rhythm.

| Mode | Trigger | Goal | Reclaim | Approval |
| :--- | :--- | :--- | :--- | :--- |
| **Routine** | The machine is in daily use and merely crowded | Return to a steady state; nothing the user notices is missing | Hundreds of MiB to a few GiB | Caches and logs: go ahead. Anything else: ask first |
| **Archival** | The machine is being retired | Leave only what cannot be produced again | Tens of GiB | Sign-off **per class**, never one blanket yes |

Archival mode licenses removing installed software, session history, and toolchains;
routine mode does not.

**Cleanup and backup are not substitutes.** Deleting a regenerable cache does not
back anything up, and copying a home directory does not shrink it. A machine being
retired usually needs both, in that order -- clean first, so the backup does not carry
what could be re-downloaded.

## Step 0 -- measure, do not delete

Run the bundled scanner. It is read-only.

> **Paths.** The command below uses `~/.agents/skills/linux-disk-cleanup-backup/`. Any installed
> copy works: `~/.claude/skills/linux-disk-cleanup-backup/`,
> `~/.gemini/config/skills/linux-disk-cleanup-backup/`, or a path relative to this SKILL.md
> instead -- only one of the three needs to exist.

```bash
bash ~/.agents/skills/linux-disk-cleanup-backup/scripts/scan-disk.sh /
```

It reports: filesystem usage and the **home / outside-home split**; the largest
directories; package-manager residue; installed-package volume against a fresh-install
baseline; the largest individual files; and every git repository with **no remote**.

**Measure `/home` and everything else separately.** On a WSL Ubuntu 24.04 that was
cleaned to a third of its size, `/home` fell to 2.7 GB while 4.8 GB of increment
remained *outside* it -- apt caches, snap download cache, journal, and extra packages.
A home-only cleanup leaves that untouched.

Then read the half of the job that matches the request: cleanup modes A and B below,
or [Mode C -- backup](#mode-c----backup-to-an-external-drive).

## The ten rules

These are the ways a cleanup silently fails. They are not advice; each one has a
failure signature you will not notice without checking.

1. **Use absolute paths in every `rm`.** The shell's working directory is not what you
   think. `rm -rf .cache` in the wrong directory reports success and deletes nothing.
   Verify existence after each class, not just the total.
2. **Re-measure the total after every class.** A small drop means a round did not
   take effect. Go back and look for the relative path.
3. **Check `git remote -v` before deleting a repository.** With a remote it can be
   re-cloned; without one it is the only copy. Both cases need the user, for opposite
   reasons.
4. **Deleting files does not shrink a container image.** A WSL VHDX only gives the space
   back after the guest is stopped and the image is compacted. See
   [Compacting a WSL disk image](#compacting-a-wsl-disk-image).
5. **Read-only files make `rm` fail silently.** Go's module cache and pip-installed
   packages are mode `0444`; `rm -rf` prints `Permission denied` for each one and
   carries on, so the directory survives and the totals barely move. `chmod -R u+w`
   first.
6. **zsh aborts the whole command on an unmatched glob.** `rm -f /path/*.db
   /path/*.db-wal` does not run at all if one of the two globs matches nothing -- bash
   passes the unmatched pattern through as a literal instead. Use `find ... -delete`.
7. **A glob is expanded by the caller's shell, and that can fail silently.** In
   `sudo rm -rf /root-owned-dir/*` the `*` is expanded by the *caller*. If the caller
   cannot read the directory, zsh reports `no matches found` and `rm` never runs.
   Use `sudo sh -c 'rm -f /path/*'`.
8. **Deleting a file is not the same as releasing the space.** Snap's download cache
   and the installed `.snap` are hard links (`ls` shows link count 2). Removing the
   cache copy frees nothing until the other link is gone. Re-measure with `du`.
9. **Shell history archives are not safe to commit as-is.** They contain live
   credentials. See [Archiving shell history](#archiving-shell-history).
10. **`Permission denied` from `du` is a wrong number, not noise.** Unprivileged `du`
    skips `/var/lib/private`, `/var/log/private`, `/var/db/sudo` and every other
    mode-700 root directory, and still prints a total -- a **lower bound** that reads
    as an answer. On a Fedora 44 WSL host, `/var/lib/firebird/data`,
    `/var/lib/NetworkManager` and `/var/lib/portables` were all skipped, so the
    reported `/var` figure excluded them entirely. Either re-measure with `sudo du`,
    or label the number as a partial. Never conclude "this directory is small" from a
    total that was produced with errors on stderr.

## Mode A -- routine housekeeping

Read [`references/routine.md`](references/routine.md) for the full catalog.

The short version: caches, logs, retired package-manager revisions, stale build
artifacts, abandoned virtual environments. Everything in the routine catalog is
regenerable, so the rhythm is **measure, clean, report** -- no per-item sign-off.
Anything beyond the catalog (installed software, session history, model weights) is
archival work and needs the user.

Two rules that are specific to routine mode:

- **Do not remove the software the user is currently running.** A cleanup that deletes
  the agent's own toolchain, the interpreter pinned in the project config, or the shell
  framework the rc file sources breaks the session mid-task. Check what is live before
  touching `PATH` and the home directory.
- **Do not remove a version the user pinned.** A project config naming a specific
  Python version, or a `PATH` entry pointing into a version manager, means that
  version is a dependency, not redundancy.

## Mode B -- archival pass

Read [`references/archival.md`](references/archival.md) for the full catalog.

This is the "this machine is being shut down and stored" case. The image may be
exported, snapshotted, or handed to someone else, and the goal is that it takes as
little space as possible **while still containing everything that cannot be produced
again**.

The rhythm changes here. Group the candidates into classes, report the size of each
class, and get one decision per class. A single "delete it all" is exactly how an
irreplaceable dataset gets deleted.

| Class | Example | Decision |
| :--- | :--- | :--- |
| Regenerable cache | package manager caches, build caches | Delete, no question |
| Re-installable software | IDEs, toolchains, language runtimes, browsers | Delete, but say what will need reinstalling |
| Re-downloadable weights | `torch.hub` checkpoints, LoRA adapters the user archived elsewhere | Delete if the user confirms a copy exists |
| Session history | AI-tool conversation databases, codex logs | Delete, and say which transcripts were in them |
| **Irreplaceable** | SSH keys, datasets, notes, source without a remote | **Never delete. Ask.** |

### The "is it really regenerable" ladder

Work down it, stop at the first rung that applies:

1. Re-downloaded by a package manager on demand -- delete.
2. Re-created by re-running a documented build step -- delete.
3. Re-created by re-training or re-deriving, but only with real time and compute --
   delete **only** with the user's confirmation that a copy exists elsewhere.
4. Existed exactly once, on this machine, with no other copy -- **keep, and tell the
   user it is there.**

### Pure-extraction check

A directory that was unpacked from an archive is not original data -- but the archive
has to still exist. Verify with `md5` before deleting the extracted copy, because an
unpacked file can have been written back afterwards:

```bash
T=$(mktemp -d) && unzip -qo <archive>.zip '*<file>' -d "$T"
md5sum "$T"/<path>/<file> <extracted>/<path>/<file>
rm -rf "$T"
```

Identical `md5` means the extracted copy is a faithful copy -- delete **the extracted
copy and keep the archive**. A mismatch means the extracted copy is now the original:
keep it. An archive's internal timestamps are preserved on extraction, so "the files
look old" is not evidence; only the `md5` is.

**The reverse trap**: sometimes the archive and the extracted copy live in the same
directory. Deleting the directory removes the archive too. Delete only the extracted
subdirectory.

## Archiving shell history

If the user wants `~/.bash_history` or `~/.zsh_history` kept in a repository, it needs
redaction first, and the redaction has a trap of its own.

**Scan with `grep -a`.** Shell history files routinely contain non-UTF-8 bytes. `file`
then reports `data` or `Non-ISO extended-ASCII text`, and **plain `grep` treats the file
as binary and skips it entirely** -- exit status 1, no output, which reads exactly like
"clean". That is a silent miss on the one check that matters.

```bash
grep -aEic 'password|passwd|secret|api[_-]?key|token|private key|ghp_|gho_|github_pat_|AKIA' ~/.bash_history
```

Cover at least: `AIza[0-9A-Za-z_-]{35}` (Google), `gh[pousr]_*` and `github_pat_*`
(GitHub), `xox[baprs]-*` (Slack), `sk-[A-Za-z0-9]{20,}` (generic API keys),
`KEY|TOKEN|SECRET|PASSWORD=<value>`, and inline credentials in `curl -H` / `--data`.

Redact **the copy that goes into the repository**, never the live file. Then re-check
the pushed content, not just the working copy:

```bash
git show origin/main:<path> | grep -a '<the key prefix>'    # must not match
```

If a live credential was found, **tell the user to rotate it**. It was on disk in
plaintext and may already be in a shell history, a terminal scrollback, or a log.

Record in the archive's own README: the time range covered (zsh records a timestamp per
entry; bash usually does not), the encoding, and the `md5sum`. A history file with no
provenance is not an archive.

## Mode C -- backup to an external drive

Read [`references/backup-wsl-ntfs.md`](references/backup-wsl-ntfs.md) for the
measured WSL procedure and [`references/backup-linux-desktop.md`](references/backup-linux-desktop.md)
for the native-desktop one.

This is the half that cannot be undone by "just reinstall". The catalog is short and
consists entirely of class E -- the irreplaceable list -- because everything
regenerable is excluded on purpose. **Backing up the regenerable half is how a backup
ends up 900 MB instead of 300 MB and gets abandoned.**

The measured shape, on a Fedora 44 WSL host with an NTFS 3.0 external drive:

```
$HOME            953 MiB
  minus .nvm     516 MiB   regenerable -- nvm install re-creates it
  minus .npm     128 MiB   regenerable
  minus .local    28 KiB   regenerable
  ------------------------------------------
  copied          284 MiB   8,845 files, 49 s over drvfs
```

### Order of operations

1. **Clean first.** Run the routine or archival pass. The exclusion list is
   derivable from the scan you already did.
2. **Mount the drive.** Under `[automount] enabled = false`, nothing is mounted for
   you; `mount -t drvfs` explicitly, and read the drive letter from Windows rather
   than guessing.
3. **Copy with `tar` piped**, not `cp -r`. It preserves permissions, follows the
   exclusions in one pass, and cannot half-copy a directory tree by running out of
   the wrong kind of space.
4. **Verify against the source** -- file count, then `md5sum` on the handful of files
   that would be catastrophic to lose.
5. **Eject before pulling.** `umount` first, or Windows cannot release the volume.

### What to verify, and why those files

A byte count is not a backup. Spot-check the specific files whose loss is
unrecoverable, because they are the ones a partial copy silently omits:

```bash
md5sum "$SRC/.ssh/id_ed25519" "$DEST/.ssh/id_ed25519"
for r in <repos>; do
  a=$(git -C "$SRC/$r" rev-parse HEAD); b=$(git -C "$DEST/$r" rev-parse HEAD)
  [[ "$a" == "$b" ]] && echo "ok $r ${a:0:8}"
done
```

Private keys, `.gitconfig`, the shell layers, and one `HEAD` per repository cover the
irreplaceable classes without hashing gigabytes.

### The regenerated-cache trap

**A directory deleted at 22:00 can be back at 08:00 the next morning.** A login
script that installs a version manager will re-create it on the next shell. Check
what came back between the cleanup and the backup:

```bash
du -sh ~/.nvm ~/.npm ~/.local 2>/dev/null    # non-zero after a cleanup means it regrew
```

Measured here: an archival cleanup removed `.nvm` and `.npm` entirely, and switching
the login shell from zsh to bash brought back **516 MiB** of `.nvm` and **128 MiB**
of `.npm`, because the bash profile sourced the version manager. The backup excluded
them again by hand, but on a machine you cannot inspect the same way, **prefer
excluding by pattern over trusting the exclusion list to still hold at copy time**.

### An external drive is readable by whoever holds it

An NTFS volume has no Unix permissions, and the drive is likely to leave the house.
Before writing a backup to it, scan the payload for credentials -- the history-file
procedure above applies unchanged -- and tell the user what the drive exposes:

```bash
grep -rlaE 'gh[pousr]_|AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,}|AKIA' "$DEST" 2>/dev/null
```

Anything found there now exists in two places with different blast radii. A token file
copied to a removable drive is a token that should be rotated, and the user has to be
the one to decide that.

## Compacting a WSL disk image

Deleting inside the guest frees the ext4 blocks, but the host-side `.vhdx` file keeps
its size until the image is compacted.

**WSL 3.0 and newer have a direct command.** It arrived in the 2.9.8 preview, went
stable in 3.0.1, and is implemented on the Windows Virtual Disk API
(`OpenVirtualDisk` + `CompactVirtualDisk`) -- so it needs no elevation, no manual
read-only attach, and no `diskpart`:

```powershell
wsl --version                  # 3.x is required
wsl -d <Distro> -u root -- fstrim -av
wsl --shutdown
wsl --manage <Distro> --compact
```

The distro must be **stopped**, otherwise the command fails with
`Wsl/Service/WSL_E_DISTRO_NOT_STOPPED`. Compaction is **manual only** -- there is no
auto-compaction, no shutdown hook, and no `.wslconfig` policy for it. It reclaims free
blocks inside the disk; it never deletes files.

**On WSL 2.x the command does not exist.** `wsl --manage` there offers only `--move`,
`--set-sparse`, `--set-default-user` and `--resize`, and the fallback is the manual
path: `Optimize-VHD -Path <vhdx> -Mode Full` (elevated, needs the Hyper-V module) or
`diskpart` + `compact vdisk`. `wsl --shutdown` does not always release the file handle
-- `WSLService` stays running -- which is why the old tutorials hit
`ERROR_SHARING_VIOLATION`. Note that sparse VHDs cannot be compacted by `diskpart` or
`Optimize-VHD` at all, and since WSL 2.6 `--set-sparse` requires `--allow-unsafe`
because sparse mode has caused data corruption.

**Do not hard-code the image path.** Read it from the registry; the distro may live on
any drive:

```powershell
Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' |
  ForEach-Object { $p = Get-ItemProperty $_.PSPath; "$($p.DistributionName) -> $($p.BasePath)" }
```

For the full estimation and verification procedure, use the
[`compress-wsl-space`](../compress-wsl-space/SKILL.md) skill, which selects between
`--compact` and `Optimize-VHD` by WSL version.

## Reporting

Finish with all four of these:

1. **Before and after**, by class, with the total at both ends. A total with no
   breakdown is not a report.
2. **What was deleted** as a list a user could audit -- paths and sizes, not just
   totals.
3. **What was deliberately kept and why** -- the irreplaceable list. This is the
   part the user needs when the image is restored somewhere else. For a backup,
   this list is what was *copied*, and the excluded set goes next to it.
4. **What to run next**, if the platform needs a compaction step to give the space
   back -- or, for a backup, how to restore and verify.

Then state plainly what was **not** done, and why: a tool the user still needs, a
credential that needs rotating, a directory that could not be verified.
