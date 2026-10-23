---
name: compress-wsl-space
description: Safely estimate and compact local WSL2 ext4.vhdx disk usage on Windows. Use when the user asks to check how much WSL disk space can be reclaimed, shrink or compress WSL storage, run fstrim plus wsl manage compact or Optimize-VHD, troubleshoot WSL VHDX size growth, or document the local WSL compaction workflow.
---

# Compress WSL Space

## Overview

Use this skill to reduce Windows-side WSL2 `ext4.vhdx` size after files were deleted inside Linux.

**Which compaction command to use depends on the WSL version, not on preference:**

| WSL | Command | Needs |
| :--- | :--- | :--- |
| **3.0 or newer** | `wsl --manage <Distro> --compact` | nothing special -- no admin, no Hyper-V module |
| 2.x | `Optimize-VHD -Path <vhdx> -Mode Full` | elevated Administrator + Hyper-V PowerShell module |

`wsl --manage <Distro> --compact` was verified on WSL 3.0.1.0 (2026-10-17). Detect it
before choosing a path -- see [Detect the WSL version](#detect-the-wsl-version).

The rest of the workflow is identical for both:

1. Measure the host VHDX file size and Linux `df` usage.
2. Run `fstrim` inside the distro to mark free ext4 blocks.
3. Stop WSL so the VHDX is detached.
4. Compact (`--compact` or `Optimize-VHD -Mode Full`).
5. Restart the distro and verify `whoami` plus `df -h /`.

Do not enable WSL sparse VHD as a default fix. Treat sparse mode as experimental
unless the user explicitly asks for it and accepts the risk. `--manage --set-sparse`
exists on WSL 3.0 and is subject to the same warning.

## Detect the WSL version

```powershell
wsl --version
```

The first line reads `WSL version: 3.x.x` or `2.x.x`. A machine where `wsl --version`
prints nothing, or prints an install hint, has only the inbox forwarder stub and no
compaction verb at all -- see
[`../../../wsl/storage/wsl-distro-move-to-d-drive.md`](../../../wsl/storage/wsl-distro-move-to-d-drive.md).

Never probe `wsl --help` for the verb by string-matching its raw output. The help text
follows the console code page, so on a zh-CN host the bytes arrive mis-decoded and
**every** ASCII match returns false -- including verbs that do exist. Use `wsl --version`.

## Quick Start

```powershell
# Estimate only
powershell -NoProfile -ExecutionPolicy Bypass -File .\compress-wsl-space\scripts\compact-wsl-vhdx.ps1 -Distro <Name>

# Execute compaction (picks --compact or Optimize-VHD automatically)
powershell -NoProfile -ExecutionPolicy Bypass -File .\compress-wsl-space\scripts\compact-wsl-vhdx.ps1 -Distro <Name> -Compact

# Force the legacy Optimize-VHD path even on WSL 3.x
powershell -NoProfile -ExecutionPolicy Bypass -File .\compress-wsl-space\scripts\compact-wsl-vhdx.ps1 -Distro <Name> -Compact -LegacyOptimizeVhd

# If active WSL sessions keep the VHDX attached, allow stopping WSLService
powershell -NoProfile -ExecutionPolicy Bypass -File .\compress-wsl-space\scripts\compact-wsl-vhdx.ps1 -Distro <Name> -Compact -ForceStopService
```

Or do it by hand on WSL 3.x -- no script needed:

```powershell
wsl -d <Name> -u root -- fstrim -av
wsl --shutdown
wsl --manage <Name> --compact
wsl -d <Name> -- sh -lc 'whoami; df -h / | tail -n 1'
```

**Do not hard-code the VHDX path.** Read `BasePath` from the registry instead; the
distro may live on any drive, and `--import-in-place` even writes it with a `\\?\`
prefix:

```powershell
Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | ForEach-Object {
    Get-ItemProperty $_.PSPath | Select-Object DistributionName, BasePath, VhdFileName
}
```

## Workflow

### Estimate

Read the distro path from:

```powershell
HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss
```

Then compare:

- Windows host file size: `Get-Item <BasePath>\<VhdFileName>`
- Linux used bytes: `wsl -d <Distro> -- bash -lc "df -B1 --output=used / | tail -n 1 | tr -d ' '"`

The naive upper bound is:

```text
VHDX file size - Linux used bytes
```

**Treat that number as an upper bound, never as a prediction.** Measured on WSL 3.0.1.0
(2026-10-17, Debian 13): host VHDX 4.073 GB, Linux used 3.54 GB -- a gap of roughly
0.53 GB -- and `wsl --manage <Name> --compact` returned **198 MB (4.75%)**. The rest is
ext4 and VHDX metadata plus blocks that cannot be trimmed.

Two consequences:

- A gap of 0.5 GB does **not** mean 0.5 GB comes back. Report the bound, then report what
  was actually reclaimed as a percentage of the host file.
- A small gap can still yield a useful result. Do not skip compaction just because the
  estimated reclaim looks unimpressive.

**Diminishing returns on repeat runs.** A second compaction shortly after the first one
reclaimed 26 MB (0.55%) on the same host whose first run had returned 198 MB (4.75%),
because ordinary activity in between had already re-grown the file. Compact once, at
rest, when the space is actually wanted -- and never promise a number in advance.

### Compact

Only compact when:

- The user explicitly asks to compress or compact.
- The VHDX can be detached.

Run `fstrim` as root via `-u root`, **not** through `sudo` inside `bash -lc`:

```powershell
wsl -d <Name> -u root -- fstrim -av
```

`sudo` inside a non-interactive login shell either prompts (and hangs) or fails with no
tty. `-u root` needs neither.

Then stop WSL and compact:

```powershell
wsl --shutdown
wsl --manage <Name> --compact            # WSL 3.x
# or, on 2.x / with -LegacyOptimizeVhd:
Optimize-VHD -Path "<vhdx>" -Mode Full
```

`wsl --terminate <Distro>` is **not** a substitute for `wsl --shutdown` here. Verified on
WSL 2.7.14.0: if another distro holds a bind mount of this one under `/mnt/wsl` (see
[cross-distro.md](../wsl-windows-command/references/cross-distro.md) section 2),
`--terminate` leaves the filesystem mounted and writable from that distro while
`wsl -l -v` reports `Stopped`. The VHDX stays attached. Only dropping the last mount, or
`--shutdown`, releases it.

If `wsl --shutdown` leaves the VHDX attached, inspect running processes. If the user has
requested compression and accepts disconnecting active WSL sessions, stop `WSLService`:

```powershell
Stop-Service -Name WSLService -Force
```

Then re-check (2.x / `Optimize-VHD` path only -- `Get-VHD` needs the Hyper-V module):

```powershell
Get-VHD -Path "<vhdx>" | Select-Object Path, FileSize, Attached
```

Proceed only when `Attached` is `False`.

### Verify

After compaction, always verify:

```powershell
Get-Item "<vhdx>" | Select-Object FullName, Length, LastWriteTime
wsl -l -v                               # the distro must still be VERSION 2
wsl -d <Name> -- whoami
wsl -d <Name> -- sh -lc 'df -h / | tail -n 1'
```

Report:

- Original VHDX size.
- Final VHDX size.
- Reclaimed bytes **and** percentage of the original host file.
- Whether the distro restarted and is still VERSION 2.
- Which compaction path ran (`--compact` or `Optimize-VHD`).
- Any forced WSLService stop.

## Failure Handling

- If WSL cannot see the distro from the current user context, do not unregister or import
  anything. Report that exact estimation needs the registered distro context; host-side
  VHDX size can still be read if the file path is known.
- If `wsl --manage <Name> --compact` is rejected as an unknown verb, the WSL build
  predates 3.0 -- fall back to `Optimize-VHD`, and say which path you took.
- If `Optimize-VHD` is unavailable on the 2.x path, tell the user the Hyper-V PowerShell
  module is missing or use the official `diskpart compact vdisk` fallback.
- If the VHDX remains attached, do not compact. Stop active WSL sessions first.
- If `fstrim` succeeds but compaction is blocked, it is safe to retry later after WSL is
  fully stopped.
- On WSL 3.x the compaction path needs neither elevation nor the Hyper-V module. If the
  script asked for Administrator anyway, that is a bug in the path selection, not a
  permission problem on the user's machine.
