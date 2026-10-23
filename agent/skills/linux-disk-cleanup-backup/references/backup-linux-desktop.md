# Backing up a native Linux desktop

> **Status: not yet measured.** The procedure below is a skeleton. Every section
> marked *TODO* is unverified -- do not treat it as a runbook until it has been
> measured on the machine it describes, and do not delete the marker.
>
> The WSL procedure in [`backup-wsl-ntfs.md`](backup-wsl-ntfs.md) is measured and
> complete. This file exists so the two halves of the skill are discoverable from
> the same place, and so the next agent knows what still needs doing.

Target: Linux Mint 22 on the mechanical-disk machine.

---

## What differs from WSL

*TODO -- the reasons are expected to be:*

- **No drvfs.** The external drive is an ext4 partition, or a whole-disk image, or
  something the desktop's own udisks2 automounts. Which one is the open question --
  and it decides whether the NTFS permission caveat applies at all.
- **Mounting is not manual.** WSL's `[automount] enabled = false` is a WSL-only
  policy. On the desktop, udisks2 handles this, and the mount point is under
  `/media/$USER/<label>` or `/run/media/$USER/<label>`, not `/mnt`.
- **Ejecting is the desktop's job.** `gio mount` / `udisksctl unmount` or the
  file manager. Whether the same "unmount before pulling" rule applies needs
  checking.
- **The home directory is bigger and messier.** No WSL to bound it, and the desktop
  carries its own caches that are *not* in the WSL list. Which ones is unknown.

## Measure first

*TODO -- the desktop equivalent of `scan-disk.sh`, or simply running it here. The
script is distro-aware, so a Mint host should work with the `apt-get` branch. That
has not been run.*

```bash
bash ~/.agents/skills/linux-disk-cleanup-backup/scripts/scan-disk.sh /
```

## The exclusion list

*TODO -- measured on the Mint host. Expect the desktop-specific entries to be the
GUI application's own caches, the package manager's, and any flatpak or snap store,
none of which exist on the WSL side.*

## The copy

*TODO -- likely the same `tar` pipe as the WSL version, but the destination and
whether ext4 preserves the modes directly are open.*

## Verification

*TODO -- same shape as the WSL procedure. The private key and one `HEAD` per
repository remain the right spot checks.*

## Traps

*TODO -- expected to differ from the WSL list in ways that are not yet known. Do not
assume the WSL traps carry over: the `ls /mnt` and drvfs traps are WSL-specific.*
