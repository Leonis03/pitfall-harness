# Uninstalling WSL Completely

Two scopes. Pick one; the second is irreversible for the distro data.

**Status:** commands below come from a script drafted 2025-10-06 and are standard
`wsl` / `dism` / `winget` usage. This repo's machine still runs WSL, so the full sequence
was not re-run here.

## 0. Back up first

```powershell
wsl --list --verbose
wsl --export <distro> <backup-dir>\<distro>.tar     # per distro; --unregister cannot be undone
```

**Distros registered with `wsl --import-in-place` need a different backup.** There the
`ext4.vhdx` you registered *is* the live filesystem, with no intermediate layer, so
`--unregister` deletes the data itself rather than a copy of it:

```powershell
Copy-Item <BasePath>\ext4.vhdx <backup-dir>\<distro>-ext4.vhdx
```

Read `BasePath` from `HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss` rather than
assuming the default `AppData\Local\Packages` location. Recovering a distro afterwards
means `wsl --import-in-place <distro> <that file>` -- see
[`storage/wsl-distro-move-to-d-drive.md`](storage/wsl-distro-move-to-d-drive.md).

## 1. Remove one distro only

```powershell
wsl --shutdown
wsl --unregister <distro>      # deletes its ext4.vhdx
```

## 2. Remove WSL itself (elevated PowerShell)

```powershell
wsl --shutdown
wsl --list --quiet | ForEach-Object { if ($_) { wsl --unregister $_ } }
winget uninstall -e --id Microsoft.WSL --silent        # Store / MSIX build, if present
dism /online /disable-feature /featurename:VirtualMachinePlatform /norestart
dism /online /disable-feature /featurename:Microsoft-Windows-Subsystem-Linux /norestart
Restart-Computer
```

Gotchas:

- `wsl --list --quiet` prints UTF-16; piped through a pipeline it can carry NULs or blanks.
  Trim each name and skip empties before `--unregister`.
- `VirtualMachinePlatform` is also used by Docker Desktop's WSL backend, Android subsystems
  and some emulators. Disabling it breaks them. Hyper-V is **not** touched by the commands
  above; to drop it too: `dism /online /disable-feature /featurename:Microsoft-Hyper-V-All
  /norestart` and `bcdedit /set hypervisorlaunchtype off`.
- Features show as disabled only after the reboot.

## 3. Residue (after the reboot, only if the distros are already gone)

```powershell
Remove-Item -Recurse -Force "$env:ProgramData\wsl" -ErrorAction SilentlyContinue
Get-ChildItem "$env:LOCALAPPDATA\Packages" |
  Where-Object { $_.Name -match 'Ubuntu|Debian|SUSE|Kali|Alpine|Oracle|Fedora' } |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
```

A draft cleanup script also deleted the `Lxss` registry keys and
`WindowsApps\wsl.exe`. Do not: `HKCU:\...\Lxss` is where every registered distro lives
(including its `BasePath`, i.e. where the disk is), and deleting it orphans the vhdx files
instead of removing them. Use `wsl --unregister`.

If `wsl` still shows in Start search, rebuild the index:
`Get-Process SearchIndexer | Stop-Process -Force; Start-Service wsearch`.

## 4. Verify

```powershell
wsl --list --verbose                                  # no distros / "not installed"
dism /online /get-features /format:table | Select-String 'VirtualMachinePlatform|Subsystem-Linux'
```

Both features should read `Disabled`.

## 5. Reinstall

```powershell
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
# reboot, then:
wsl --install -d Ubuntu
```

Then follow [`setup/`](setup/) to rebuild the configuration.

### If the distro disk outlived the reinstall

A Windows reinstall clears the `Lxss` registration but not the vhdx sitting on another
drive. There is nothing to `--unregister` and nothing to `--manage --move`; register the
existing file directly:

```powershell
wsl --import-in-place <distro> <drive>\WSL\<distro>\ext4.vhdx
```

Normalize the ownership of the parent directory first -- a file left over from the old
install usually has no explicit per-user ACE, which shows up later as
`MountDisk/HCS/E_ACCESSDENIED`. Full sequence, with the `icacls` lines and the reason
`DefaultUid=0` is not a problem:
[`storage/wsl-distro-move-to-d-drive.md`](storage/wsl-distro-move-to-d-drive.md).

### If `wsl --install` does nothing

On Windows 11 build 26100 the inbox `wsl.exe` is a forwarder: `--install` only prints a
hint pointing at itself, and no new verbs appear in `--help`. Install the Store build
through winget instead:

```powershell
winget install --id 9P9TQF7MRM4R --source msstore --accept-source-agreements
```

Same trick for step 2 above's `winget uninstall -e --id Microsoft.WSL --silent`.
