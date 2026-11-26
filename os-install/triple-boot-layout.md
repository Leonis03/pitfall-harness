# Two disks, three systems: the fallback's bootloader belongs on its own disk

*English · [中文](triple-boot-layout.zh.md) · back to [os-install/](README.md)*

> **Environment**: one desktop, UEFI, Secure Boot off. An NVMe SSD holds Windows 11 and a Linux
> distribution; a 1 TB HDD holds Linux Mint 22 as a **fallback** plus data volumes.
> **Measured** 2026-11-22, before the SSD's Linux (Fedora 44, tried and abandoned) was replaced.
> **Scope**: where each system's bootloader lives, why the fallback did not survive the disk it
> was meant to survive, and how to reinstall the SSD's Linux without breaking the other two. The
> clock contract between the systems is in [`dual-boot-time-sync.md`](dual-boot-time-sync.md).

---

## 1. The layout as measured

| Disk | Partition | Size | Content |
| :--- | :--- | ---: | :--- |
| SSD | ESP (vfat) | 500M | `EFI/BOOT`, `EFI/Microsoft`, `EFI/fedora`, `EFI/ubuntu` -- **the bootloaders of all three systems** |
| SSD | Microsoft reserved, Windows `C:`, an NTFS data volume | 16M, 128G, 32G | Windows |
| SSD | ext4 | 1.9G | an old Fedora `/boot`, orphaned (not in `fstab`) |
| SSD | ext4 + btrfs | 2G + 313G | Fedora `/boot`, `/` and `/home` |
| HDD | ESP (vfat, ESP partition type) | 487M | **empty** -- no `EFI/` directory at all |
| HDD | ext4 x3 | 61G, 61G, 100G | Mint `/`, `/var`, `/home` |
| HDD | NTFS x3 | 709G in total | data |

The firmware boot order was Fedora, Windows Boot Manager, Ubuntu (Mint) -- all three entries
pointing at the SSD's ESP. No partition reported `FSTYPE` `BitLocker`.

How it was read, all read-only:

```bash
lsblk -o NAME,SIZE,ROTA,FSTYPE,PARTTYPENAME,MOUNTPOINTS   # ROTA 0 = SSD, 1 = HDD
sudo efibootmgr -v                                       # which partition each entry points at
findmnt /boot/efi
```

An ESP that is not mounted can be inspected with a read-only mount
(`sudo mount -o ro /dev/<esp> <dir>`, then `ls <dir>/EFI`).

---

## 2. The pitfall: the fallback booted from the disk it was meant to survive

Mint's root file system is on the HDD, but its GRUB and its firmware entry live in `EFI/ubuntu`
on the **SSD's** ESP, and the HDD's own ESP is empty. If the SSD dies, the HDD still holds a
complete Mint that nothing can start, short of a rescue medium. The fallback depended on the very
disk it was supposed to replace.

The installer put its bootloader on the ESP it found -- the one Windows had created on the SSD --
instead of creating one on the HDD. Whether Mint's installer offers a way to choose was not
re-measured; a common way around it is to disable or disconnect the SSD for the install, so that
the only ESP the installer can see is the HDD's.

**The rule:** a fallback system's bootloader lives on the fallback's own disk, and the firmware has
an entry for it there.

---

## 3. Moving Mint's bootloader to the HDD (not measured yet)

To be run from Mint. This is the intended procedure, not yet carried out on this machine:

```bash
findmnt /boot/efi                      # today: the SSD's ESP
sudo umount /boot/efi
sudo mount /dev/<hdd-esp> /boot/efi    # the HDD's ESP, sda1 on this machine
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=mint-hdd
sudo update-grub
sudo efibootmgr -v                     # a new "mint-hdd" entry pointing at the HDD
```

Then change Mint's `/etc/fstab` so that `/boot/efi` is the HDD's ESP (by UUID), or the next GRUB
update goes back to the SSD. The old `EFI/ubuntu` on the SSD can stay as a second way in; it
simply stops receiving updates.

Verify it the only way that counts: pick the HDD entry in the firmware boot menu -- ideally once
with the SSD disabled in the firmware -- and see Mint start.

---

## 4. Reinstalling the SSD's Linux without breaking the other two

- **Reuse the SSD's ESP; do not format it.** Windows Boot Manager lives there, and so does Mint's
  bootloader until section 3 is done. In the installer, select the existing ESP as the EFI system
  partition without formatting it.
- Delete only the old Linux partitions -- on this machine the orphaned `/boot`, the current
  `/boot` and the btrfs volume -- and keep Microsoft reserved, `C:` and the NTFS data volume.
- After the new system boots, remove what the old one left: its directory in the ESP
  (`EFI/fedora` here) and its firmware entry (`sudo efibootmgr -b <num> -B`). Do it only after the
  new system starts on its own.
- If the new GRUB does not list Windows and Mint, enable os-prober
  (`GRUB_DISABLE_OS_PROBER=false` in `/etc/default/grub`, then `sudo update-grub`).
- **The RTC convention must be the same on all three systems.** Two Linux systems are two writers,
  and each one has its own `LocalRTC`. See [`dual-boot-time-sync.md`](dual-boot-time-sync.md).

---

## 5. Before wiping: what lives only on that system

Measured on the Fedora system before it was replaced -- the parts that no package and no repo
original can bring back:

| What | Where |
| :--- | :--- |
| the Rime learning database | `~/.local/share/fcitx5/rime/*.userdb/` |
| the Rime customisations | `~/.local/share/fcitx5/rime/*.custom.yaml`, `custom_phrase.txt` |
| Fcitx5's own settings | `~/.config/fcitx5/` |
| the CopyQ history and commands | `~/.local/share/copyq/`, `~/.config/copyq/` |
| fonts installed by hand | `~/.local/share/fonts/` |
| SSH keys | `~/.ssh/` |
| browser profiles | `~/.config/google-chrome/`, `~/.mozilla/` |
| third-party package sources | `dnf5 repo list --enabled` / `/etc/apt/sources.list.d/` |
| hand-edited system configuration | `sudo rpm -Va` (Fedora) or `debsums -ce` (Debian) |

Sizes and names are enough to plan the copy (`du -sh <dir>`); nothing in this list needs to be
read to decide that it must be kept.
