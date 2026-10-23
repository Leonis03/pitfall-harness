[CmdletBinding()]
param(
    [string]$Distro,
    [string]$VhdxPath,
    [switch]$Compact,
    [switch]$ForceStopService,
    [switch]$LegacyOptimizeVhd
)

$ErrorActionPreference = "Stop"

function Format-GiB {
    param([Int64]$Bytes)
    return [Math]::Round($Bytes / 1GB, 2)
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LxssEntry {
    $lxss = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (-not (Test-Path $lxss)) {
        return $null
    }

    $entries = @(
        Get-ChildItem $lxss | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath
            [PSCustomObject]@{
                DistributionName = $p.DistributionName
                BasePath         = $p.BasePath
                VhdFileName      = $p.VhdFileName
            }
        }
    )

    return $entries
}

# wsl --import-in-place writes BasePath with a verbatim (\\?\) prefix, which
# Test-Path and Get-Item reject. Strip it before touching the filesystem.
function ConvertTo-NormalPath {
    param([string]$Path)
    if ($Path -like '\\?\*') {
        return $Path.Substring(4)
    }
    return $Path
}

function Get-WslMajorVersion {
    # `wsl --version` comes back as UTF-16LE when captured: every character is
    # followed by a NUL byte (87,0,83,0,76,0,...). The console renders the NULs
    # invisibly, so the text looks clean but no regex can match across them.
    # Strip them before parsing. Same class of gotcha as `wsl --list --quiet`.
    $raw = & wsl --version 2>$null | ForEach-Object { $_ -replace "`0", '' }
    if (-not $raw) { return $null }

    $first = ($raw | Where-Object { $_ -match '\S' } | Select-Object -First 1)
    if (-not $first) { return $null }

    # The banner itself follows the console code page, but the version digits
    # are ASCII, so match on digits only.
    $m = [regex]::Match($first, '(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) { return $null }

    return [int]$m.Groups[1].Value
}

function Get-DistroVhdPath {
    param($Entries, [string]$Name)

    # Wrap with @() : returning a single-element array from a function unrolls
    # it to a scalar, and indexing a scalar with [0] is not reliable.
    $list = @($Entries)
    if ($list.Count -eq 0) { return $null }

    if ($Name) {
        $hit = $list | Where-Object { $_.DistributionName -eq $Name } | Select-Object -First 1
        if (-not $hit) { return $null }
        return (ConvertTo-NormalPath (Join-Path (ConvertTo-NormalPath $hit.BasePath) $hit.VhdFileName))
    }

    # Exactly one distro registered: use it instead of guessing a drive letter.
    if ($list.Count -eq 1) {
        $e = $list[0]
        if (-not $Distro) { $script:Distro = $e.DistributionName }
        return (ConvertTo-NormalPath (Join-Path (ConvertTo-NormalPath $e.BasePath) $e.VhdFileName))
    }

    return $null
}

function Get-LinuxUsedBytes {
    param([string]$Name)

    $raw = & wsl -d $Name -- bash -lc "df -B1 --output=used / | tail -n 1 | tr -d ' '" 2>$null | ForEach-Object { $_ -replace "`0", '' }
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $raw = ($raw | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return [Int64]$raw.Trim()
}

function Wait-VhdDetached {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 30
    )

    if (-not (Get-Command Get-VHD -ErrorAction SilentlyContinue)) {
        # Cannot query attachment state without the Hyper-V module.
        return $true
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $vhd = Get-VHD -Path $Path
            if (-not $vhd.Attached) { return $true }
        } catch {
            return $true
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    return $false
}

$entries = Get-LxssEntry

if (-not $VhdxPath) {
    $VhdxPath = Get-DistroVhdPath -Entries $entries -Name $Distro
}

if (-not $VhdxPath) {
    $names = ($entries | ForEach-Object { $_.DistributionName }) -join ", "
    throw "Could not resolve a VHDX path for distro '$Distro'. Registered distros: [$names]. Pass -Distro or -VhdxPath explicitly."
}

if (-not (Test-Path -LiteralPath $VhdxPath)) {
    throw "VHDX path does not exist: $VhdxPath"
}

if (-not $Distro) {
    $hit = $entries | Where-Object { $VhdxPath -like "*$($_.BasePath.Replace('\?','?'))*" } | Select-Object -First 1
    if ($hit) { $Distro = $hit.DistributionName }
}

if (-not $Distro) {
    throw "Distro name is unknown. Pass -Distro explicitly."
}

$wslMajor = Get-WslMajorVersion
$useNativeCompact = ($wslMajor -ne $null -and $wslMajor -ge 3 -and -not $LegacyOptimizeVhd)

$initial = Get-Item -LiteralPath $VhdxPath
$linuxUsed = Get-LinuxUsedBytes -Name $Distro

Write-Host "Distro: $Distro"
Write-Host "VHDX: $VhdxPath"
Write-Host "WSL major version: $(if ($wslMajor) { $wslMajor } else { 'unknown' })"
Write-Host "Compaction path: $(if ($useNativeCompact) { 'wsl --manage --compact' } else { 'Optimize-VHD -Mode Full' })"
Write-Host "Host VHDX size: $($initial.Length) bytes ($(Format-GiB $initial.Length) GiB)"

if ($linuxUsed) {
    $estimate = [Math]::Max([Int64]0, [Int64]($initial.Length - $linuxUsed))
    Write-Host "Linux used: $linuxUsed bytes ($(Format-GiB $linuxUsed) GiB)"
    Write-Host "Upper bound reclaimable: $estimate bytes ($(Format-GiB $estimate) GiB)"
    Write-Host "NOTE: this is a ceiling, not a prediction. Expect a fraction of it;"
    Write-Host "      the remainder is ext4/VHDX metadata and untrimmable blocks."
} else {
    Write-Host "Linux used: unavailable from current WSL context"
}

if (-not $Compact) {
    Write-Host "Estimate only. Re-run with -Compact to trim and compact."
    exit 0
}

if (-not $useNativeCompact) {
    if (-not (Test-IsAdministrator)) {
        throw "The Optimize-VHD path requires an elevated Administrator PowerShell."
    }
    if (-not (Get-Command Optimize-VHD -ErrorAction SilentlyContinue)) {
        throw "Optimize-VHD is unavailable. Enable the Hyper-V PowerShell module, drop -LegacyOptimizeVhd on WSL 3.x, or use diskpart compact vdisk."
    }
}

# -u root, not `sudo` inside bash -lc: a non-interactive login shell either
# prompts for a password and hangs, or fails outright with no tty.
Write-Host "Running fstrim..."
& wsl -d $Distro -u root -- fstrim -av
if ($LASTEXITCODE -ne 0) {
    throw "fstrim failed for distro '$Distro'."
}

Write-Host "Stopping WSL..."
& wsl --shutdown
Start-Sleep -Seconds 3

if (-not (Wait-VhdDetached -Path $VhdxPath -TimeoutSeconds 30)) {
    if ($ForceStopService) {
        Write-Host "VHDX is still attached. Stopping WSLService..."
        Stop-Service -Name WSLService -Force
        Start-Sleep -Seconds 5
    }
}

if ($useNativeCompact) {
    Write-Host "Running wsl --manage $Distro --compact ..."
    & wsl --manage $Distro --compact
    if ($LASTEXITCODE -ne 0) {
        throw "wsl --manage $Distro --compact failed with exit code $LASTEXITCODE."
    }
} else {
    $vhd = Get-VHD -Path $VhdxPath
    if ($vhd.Attached) {
        throw "VHDX is still attached. Close active WSL sessions or retry with -ForceStopService."
    }

    Write-Host "Compacting VHDX with Optimize-VHD..."
    Optimize-VHD -Path $VhdxPath -Mode Full
}

$final = Get-Item -LiteralPath $VhdxPath
$reclaimed = $initial.Length - $final.Length
$pct = if ($initial.Length -gt 0) { [Math]::Round(100 * $reclaimed / $initial.Length, 2) } else { 0 }

Write-Host "Final VHDX size: $($final.Length) bytes ($(Format-GiB $final.Length) GiB)"
Write-Host "Reclaimed: $reclaimed bytes ($(Format-GiB $reclaimed) GiB, $pct% of the original host file)"

Write-Host "Verifying distro startup..."
& wsl -l -v
& wsl -d $Distro -- whoami
& wsl -d $Distro -- sh -lc "df -h / | tail -n 1"
