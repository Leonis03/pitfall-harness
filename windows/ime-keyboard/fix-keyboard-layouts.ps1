# Remove stray keyboard layouts left in the language switcher after languages were
# uninstalled. Keeps en-US plus any tags passed to -Keep ("de-DE,ja-JP").
#
# What it does, in order: self-elevates; prints the language list and the four
# Preload / Substitutes keys; resets the user language list through
# Set-WinUserLanguageList (the supported API); exports the four keys to .reg files
# in the current directory; deletes Preload / Substitutes values not on the keep
# list; tries lpksetup /u for leftover de-DE / el-GR / ru-RU packs; warns if
# language settings sync is ON (it re-adds layouts from the cloud); asks to reboot.
# Writes a transcript FixKeyboardLayouts_<time>.log to the current directory.
#
# Background and the manual fallback: stray-keyboard-layouts.md
# Usage:  pwsh -NoProfile -ExecutionPolicy Bypass -File fix-keyboard-layouts.ps1 [-Keep "ja-JP"]
[CmdletBinding()]
param(
    [string]$Keep = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# PowerShell has no HKU: drive by default, so Test-Path 'HKU:\...' is silently
# $false and the .DEFAULT keys would be skipped as "missing".
if (-not (Test-Path 'HKU:\')) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
}

function Ensure-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
            if (-not $PSCommandPath) {
                throw "Cannot self-elevate because the script path is unknown."
            }
            $hostExe = (Get-Process -Id $PID).Path
            $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
            if (-not [string]::IsNullOrWhiteSpace($Keep)) {
                $arguments += @('-Keep', $Keep)
            }
            Write-Host "Elevation required. Relaunching as administrator..."
            Start-Process -FilePath $hostExe -ArgumentList $arguments -Verb RunAs | Out-Null
            exit
        }
    } catch {
        throw "Administrator check failed: $($_.Exception.Message)"
    }
}

function Write-Section {
    param(
        [Parameter(Mandatory)][string]$Message
    )
    Write-Host ''
    Write-Host "=== $Message ==="
}

function Normalize-LanguageTag {
    param(
        [Parameter(Mandatory)][string]$Tag
    )
    $trimmed = $Tag.Trim()
    if (-not $trimmed) { return $null }
    try {
        return ([System.Globalization.CultureInfo]::GetCultureInfo($trimmed)).Name
    } catch {
        Write-Warning ("Skipping invalid language tag '{0}'" -f $Tag)
        return $null
    }
}

function Convert-ToRegPath {
    param(
        [Parameter(Mandatory)][string]$PsPath
    )
    if ($PsPath -match '^(HK[A-Z0-9]+):\\(.+)$') {
        return "$($matches[1])\$($matches[2])"
    }
    return $PsPath
}

function Normalize-LayoutCode {
    param(
        [AllowNull()][string]$Code
    )
    if ([string]::IsNullOrWhiteSpace($Code)) { return '' }
    $sanitized = ($Code -replace '[^0-9A-Fa-f]', '')
    if (-not $sanitized) {
        $sanitized = $Code
    }
    $sanitized = $sanitized.PadLeft(8, '0')
    return $sanitized.ToUpperInvariant()
}

function Get-AllowedLayoutCodes {
    param(
        [Parameter(Mandatory)][string[]]$LanguageTags
    )

    $map = @{
        'en-US' = @('00000409','00010409','00020409')
        'en-GB' = @('00000809')
        'en-CA' = @('00001009')
        'en-AU' = @('00000C09')
        'en-IN' = @('00004009')
        'en-NZ' = @('00001409')
        'de-DE' = @('00000407','00010407')
        'el-GR' = @('00000408')
        'ru-RU' = @('00000419')
        'fr-FR' = @('0000040C','0001040C')
        'es-ES' = @('0000040A','0002040A')
        'it-IT' = @('00000410')
        'pt-BR' = @('00000416')
        'pt-PT' = @('00000816')
        'nl-NL' = @('00000413')
        'sv-SE' = @('0000041D')
        'da-DK' = @('00000406')
        'fi-FI' = @('0000040B')
        'nb-NO' = @('00000414')
        'pl-PL' = @('00000415')
        'cs-CZ' = @('00000405')
        'sk-SK' = @('0000041B')
        'sl-SI' = @('00000424')
    }

    $codes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($tag in $LanguageTags) {
        if (-not $tag) { continue }
        if ($map.ContainsKey($tag)) {
            foreach ($code in $map[$tag]) {
                $null = $codes.Add((Normalize-LayoutCode -Code $code))
            }
            continue
        }
        try {
            $list = New-WinUserLanguageList -Language $tag
            foreach ($entry in $list) {
                foreach ($tip in ($entry.InputMethodTips | Where-Object { $_ })) {
                    $parts = $tip -split ':'
                    $candidate = $parts[-1]
                    $null = $codes.Add((Normalize-LayoutCode -Code $candidate))
                }
            }
        } catch {
            Write-Warning ("Unable to derive keyboard layouts for '{0}'. Update the built-in map if needed." -f $tag)
        }
    }

    if ($codes.Count -eq 0) {
        foreach ($fallback in @('00000409','00010409','00020409')) {
            $null = $codes.Add($fallback)
        }
    }

    return $codes
}

function Show-WinLanguageList {
    try {
        $list = Get-WinUserLanguageList
        if (-not $list) {
            Write-Host "<no entries>"
            return
        }
        ($list | Select-Object LanguageTag, InputMethodTips | Format-Table -AutoSize | Out-String).TrimEnd().Split([Environment]::NewLine) | ForEach-Object {
            Write-Host $_
        }
    } catch {
        Write-Warning ("Unable to query Get-WinUserLanguageList: {0}" -f $_)
    }
}

function Show-RegistryKey {
    param(
        [Parameter(Mandatory)][string]$Path
    )
    Write-Host "[$Path]"
    if (-not (Test-Path -Path $Path)) {
        Write-Host "  <missing>"
        return
    }
    try {
        $key = Get-Item -Path $Path
        $names = $key.GetValueNames()
        if (-not $names -or $names.Count -eq 0) {
            Write-Host "  <empty>"
            return
        }
        foreach ($name in $names) {
            $value = $key.GetValue($name)
            Write-Host ("  {0} = {1}" -f $name, $value)
        }
    } catch {
        Write-Warning ("Unable to read {0}: {1}" -f $Path, $_)
    }
}

function Export-RegistryKey {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -Path $Path)) {
        Write-Host "Skipping export for $Path (missing)."
        return
    }
    $regPath = Convert-ToRegPath -PsPath $Path
    try {
        & reg.exe export $regPath $Destination /y | Out-Null
        Write-Host "Exported $regPath to $Destination"
    } catch {
        Write-Warning ("Failed to export {0}: {1}" -f $regPath, $_)
    }
}

function Clean-PreloadKey {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$AllowedCodes
    )
    if (-not (Test-Path -Path $Path)) {
        Write-Host "Preload key $Path missing; nothing to clean."
        return
    }
    try {
        $key = Get-Item -Path $Path
        foreach ($name in $key.GetValueNames()) {
            $value = [string]$key.GetValue($name)
            $normalized = Normalize-LayoutCode -Code $value
            if (-not $AllowedCodes.Contains($normalized)) {
                Write-Host ("Removing preload entry '{0}' = {1}" -f $name, $value)
                try {
                    Remove-ItemProperty -Path $key.PSPath -Name $name -ErrorAction Stop
                } catch {
                    Write-Warning ("Unable to remove {0} from {1}: {2}" -f $name, $Path, $_)
                }
            }
        }
    } catch {
        Write-Warning ("Failed to inspect {0}: {1}" -f $Path, $_)
    }
}

function Clean-SubstitutesKey {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$AllowedCodes
    )
    if (-not (Test-Path -Path $Path)) {
        Write-Host "Substitutes key $Path missing; nothing to clean."
        return
    }
    try {
        $key = Get-Item -Path $Path
        foreach ($name in $key.GetValueNames()) {
            $value = [string]$key.GetValue($name)
            $normalized = Normalize-LayoutCode -Code $value
            if (-not $AllowedCodes.Contains($normalized)) {
                Write-Host ("Removing substitute '{0}' = {1}" -f $name, $value)
                try {
                    Remove-ItemProperty -Path $key.PSPath -Name $name -ErrorAction Stop
                } catch {
                    Write-Warning ("Unable to remove {0} from {1}: {2}" -f $name, $Path, $_)
                }
            }
        }
    } catch {
        Write-Warning ("Failed to inspect {0}: {1}" -f $Path, $_)
    }
}

function Test-LanguageSyncEnabled {
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SettingSync\Groups\Language'
    if (-not (Test-Path -Path $path)) {
        return $false
    }
    try {
        $value = (Get-ItemProperty -Path $path -Name Enabled -ErrorAction SilentlyContinue).Enabled
        return ($null -ne $value -and [int]$value -ne 0)
    } catch {
        Write-Warning ("Unable to evaluate cloud language sync setting: {0}" -f $_)
        return $false
    }
}

function Remove-LanguagePacks {
    param(
        [string[]]$TagsToRemove
    )
    if (-not $TagsToRemove) { return }
    $getPackagesCmd = Get-Command -Name Get-WindowsPackage -ErrorAction SilentlyContinue
    if (-not $getPackagesCmd) {
        Write-Warning "Get-WindowsPackage cmdlet not available; skipping language pack removal."
        return
    }
    foreach ($tag in $TagsToRemove) {
        if (-not $tag) { continue }
        try {
            $packages = @()
            try {
                $searchPattern = ($tag -replace '-', '_')
                $packages = Get-WindowsPackage -Online -ErrorAction Stop | Where-Object { $_.PackageName -like "*LanguagePack*" -and $_.PackageName -match $searchPattern }
            } catch {
                Write-Warning ("Unable to query installed packages while checking {0}: {1}" -f $tag, $_)
                continue
            }
            if (-not $packages) {
                Write-Host "Language pack $tag not detected; skipping uninstall."
                continue
            }
            Write-Host "Attempting to uninstall language pack $tag..."
            try {
                $proc = Start-Process -FilePath "$env:SystemRoot\System32\lpksetup.exe" -ArgumentList '/u', $tag, '/s' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
                Write-Host ("lpksetup.exe exited with code {0} for {1}" -f $proc.ExitCode, $tag)
            } catch {
                Write-Warning ("Failed to run lpksetup.exe for {0}: {1}" -f $tag, $_)
            }
        } catch {
            Write-Warning ("Unexpected error while handling {0}: {1}" -f $tag, $_)
        }
    }
}

Ensure-Administrator

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path -Path (Get-Location) -ChildPath ("FixKeyboardLayouts_{0}.log" -f $timestamp)
Start-Transcript -Path $logPath | Out-Null

try {
    $rawKeepTags = @('en-US')
    if (-not [string]::IsNullOrWhiteSpace($Keep)) {
        $rawKeepTags += ($Keep -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $normalizedKeepTags = @()
    foreach ($tag in $rawKeepTags) {
        $normalized = Normalize-LanguageTag -Tag $tag
        if ($null -ne $normalized -and $normalizedKeepTags -notcontains $normalized) {
            $normalizedKeepTags += $normalized
        }
    }
    if ($normalizedKeepTags -notcontains 'en-US') {
        $normalizedKeepTags = @('en-US') + $normalizedKeepTags
    } else {
        $normalizedKeepTags = @('en-US') + ($normalizedKeepTags | Where-Object { $_ -ne 'en-US' })
    }
    $normalizedKeepTags = @($normalizedKeepTags)

    Write-Section "Effective language tags to keep"
    Write-Host ($normalizedKeepTags -join ', ')

    $allowedLayoutCodes = Get-AllowedLayoutCodes -LanguageTags $normalizedKeepTags
    Write-Host ("Allowed keyboard layout codes: {0}" -f ([string]::Join(', ', ($allowedLayoutCodes | Sort-Object))))

    Write-Section "Current language list"
    Show-WinLanguageList

    Write-Section "Registry snapshot before cleanup"
    $registryPaths = @(
        'HKCU:\Keyboard Layout\Preload',
        'HKCU:\Keyboard Layout\Substitutes',
        'HKU:\.DEFAULT\Keyboard Layout\Preload',
        'HKU:\.DEFAULT\Keyboard Layout\Substitutes'
    )
    foreach ($path in $registryPaths) {
        Show-RegistryKey -Path $path
    }

    Write-Section "Updating user language list"
    try {
        $currentList = Get-WinUserLanguageList
        $currentTags = @()
        if ($currentList) {
            $currentTags = $currentList | ForEach-Object { $_.LanguageTag }
        }
        $tagsToRemove = @()
        foreach ($tag in $currentTags) {
            if ($normalizedKeepTags -notcontains $tag) {
                $tagsToRemove += $tag
            }
        }
        if ($tagsToRemove) {
            Write-Host ("Removing language tags: {0}" -f ($tagsToRemove -join ', '))
        } else {
            Write-Host "No extra language tags detected."
        }

        $finalList = New-WinUserLanguageList -Language $normalizedKeepTags[0]
        for ($i = 1; $i -lt $normalizedKeepTags.Count; $i++) {
            $finalList.Add($normalizedKeepTags[$i])
        }
        Set-WinUserLanguageList -LanguageList $finalList -Force
        Write-Host ("Applied language list: {0}" -f ($normalizedKeepTags -join ', '))
    } catch {
        Write-Warning ("Failed to update the user language list: {0}" -f $_)
    }

    Write-Section "Exporting registry backups"
    foreach ($path in $registryPaths) {
        $safeName = $path -replace '[:\\\\\\. ]','_'
        $dest = Join-Path -Path (Get-Location) -ChildPath ("FixKeyboardLayouts_{0}_{1}.reg" -f $timestamp, $safeName)
        Export-RegistryKey -Path $path -Destination $dest
    }

    Write-Section "Cleaning registry keys"
    foreach ($preloadPath in @('HKCU:\Keyboard Layout\Preload', 'HKU:\.DEFAULT\Keyboard Layout\Preload')) {
        Clean-PreloadKey -Path $preloadPath -AllowedCodes $allowedLayoutCodes
    }
    foreach ($subPath in @('HKCU:\Keyboard Layout\Substitutes', 'HKU:\.DEFAULT\Keyboard Layout\Substitutes')) {
        Clean-SubstitutesKey -Path $subPath -AllowedCodes $allowedLayoutCodes
    }

    Write-Section "Optional language pack removal"
    Remove-LanguagePacks -TagsToRemove @('de-DE','el-GR','ru-RU')

    if (Test-LanguageSyncEnabled) {
        Write-Warning "Language preference sync appears to be ON. Turn it off under Settings > Accounts > Windows backup > Remember my preferences > Language preferences before rebooting to prevent layouts from returning."
    } else {
        Write-Host "Language preference sync not detected or already disabled."
    }

    Write-Section "Final language list"
    Show-WinLanguageList

    Write-Section "Final Preload keys"
    foreach ($path in @('HKCU:\Keyboard Layout\Preload','HKU:\.DEFAULT\Keyboard Layout\Preload')) {
        Show-RegistryKey -Path $path
    }

    $rebootChoice = Read-Host "Reboot now? (Y/N)"
    if ($rebootChoice -match '^[Yy]') {
        Write-Host "Scheduling reboot in 5 seconds..."
        try {
            Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList '/r','/t','5' -WindowStyle Hidden -ErrorAction Stop | Out-Null
        } catch {
            Write-Warning ("Failed to schedule reboot: {0}" -f $_)
        }
    } else {
        Write-Host "Reboot skipped. Remember to restart later to ensure changes stick."
    }
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
