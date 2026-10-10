# Set up the Brave Search CLI (bx) on Windows so that it works behind a local proxy.
#
# Steps (each one is skipped when already done, so re-running is safe, and re-running
# is also the fix after a bx upgrade):
#   1. jq         winget install jqlang.jq, if jq is missing.
#   2. bx         official install.ps1, if neither bx.exe nor bx-bin.exe exists.
#   3. wrapper    bx.exe -> bx-bin.exe, plus bx.cmd (PowerShell / cmd) and a POSIX
#                 `bx` script (Git Bash). A fresh bx.exe left by an upgrade replaces
#                 bx-bin.exe, because PowerShell would otherwise run it and bypass
#                 the wrapper.
#   4. API key    `bx config set-key` (interactive, key stays out of shell history),
#                 only when no key is configured and BRAVE_SEARCH_API_KEY is unset.
#   5. verify     one search piped through jq.
#
# Why a wrapper: bx's HTTP client (ureq) cannot parse ALL_PROXY=socks5h://..., falls
# back to a direct connection and fails with "error: io: Connection refused" (exit 5)
# even though the proxy is up. The wrapper clears ALL_PROXY for the bx process only,
# so HTTPS_PROXY / HTTP_PROXY are used and curl / git keep their socks5h setting.
# Background: agent/brave-search/bx-cli.md section 3.
#
# Usage:  pwsh -NoProfile -File setup-bx-windows.ps1 [-SkipInstall] [-SkipKey]
#         [-InstallDir <dir>]   (default: $HOME\.local\bin)
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $HOME '.local\bin'),
    [switch]$SkipInstall,
    [switch]$SkipKey
)

$ErrorActionPreference = 'Stop'

function Step($m) { Write-Host "[STEP] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Info($m) { Write-Host "[INFO] $m" -ForegroundColor Gray }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }

function Update-SessionPath {
    # A running shell does not see PATH changes made by winget; reload them here.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

Update-SessionPath    # pick up jq / bx installed since this shell started
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$exe = Join-Path $InstallDir 'bx.exe'
$bin = Join-Path $InstallDir 'bx-bin.exe'

# 1. jq
Step 'jq'
if (Get-Command jq -ErrorAction SilentlyContinue) {
    Ok "jq present: $((Get-Command jq).Source)"
} elseif ($SkipInstall) {
    Warn 'jq missing and -SkipInstall given; skipping.'
} else {
    winget install -e --id jqlang.jq --accept-source-agreements --accept-package-agreements | Out-Host
    Update-SessionPath
    if (Get-Command jq -ErrorAction SilentlyContinue) {
        Ok 'jq installed (open a new terminal for other shells to see it)'
    } else {
        Warn 'jq installed but not on PATH yet; open a new terminal.'
    }
}

# 2. bx
Step 'bx binary'
if ((Test-Path $exe) -or (Test-Path $bin)) {
    Ok 'bx already installed'
} elseif ($SkipInstall) {
    Warn 'bx missing and -SkipInstall given; skipping.'
} else {
    # Run the installer in a child process: Invoke-Expression would run it in this
    # scope, where its variables overwrite ours (bx-bin.exe was never created).
    $env:BX_INSTALL_DIR = $InstallDir
    $installer = 'irm https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.ps1 | iex'
    & (Get-Process -Id $PID).Path -NoProfile -Command $installer | Out-Host
    Remove-Item Env:BX_INSTALL_DIR -ErrorAction SilentlyContinue
    if (-not (Test-Path $exe)) { throw "bx.exe was not installed into $InstallDir" }
}

# 3. wrapper
Step 'proxy wrapper'
if (Test-Path $exe) {
    Move-Item -LiteralPath $exe -Destination $bin -Force
    Info 'bx.exe -> bx-bin.exe'
}
if (-not (Test-Path $bin)) { throw "bx-bin.exe not found in $InstallDir" }

$cmd = @'
@echo off
rem Wrapper for bx-bin.exe: clear ALL_PROXY (socks5h is not parsed by bx) for this process only.
setlocal
if defined HTTPS_PROXY (set "ALL_PROXY=" & set "all_proxy=")
if defined HTTP_PROXY (set "ALL_PROXY=" & set "all_proxy=")
"%~dp0bx-bin.exe" %*
exit /b %ERRORLEVEL%
'@
$sh = @'
#!/bin/sh
# Wrapper for bx-bin.exe (Git Bash does not consult PATHEXT, so it cannot use bx.cmd).
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}${https_proxy:-}${http_proxy:-}" ]; then
    export ALL_PROXY=
    export all_proxy=
fi
exec "$DIR/bx-bin.exe" "$@"
'@
[IO.File]::WriteAllText((Join-Path $InstallDir 'bx.cmd'), ($cmd -replace "`r?`n", "`r`n") + "`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $InstallDir 'bx'), ($sh -replace "`r`n", "`n") + "`n", [Text.Encoding]::ASCII)
Ok "wrote bx.cmd and bx in $InstallDir"

if (($env:Path -split ';') -notcontains $InstallDir) {
    Warn "$InstallDir is not on PATH; add it to the user PATH."
}

# 4. API key
Step 'API key'
$wrapper = Join-Path $InstallDir 'bx.cmd'
$keyFile = (& $wrapper config path | Select-Object -First 1)    # %APPDATA%\brave-search\config.json on Windows
$hasKey = $env:BRAVE_SEARCH_API_KEY -or ($keyFile -and (Test-Path $keyFile) -and ((Get-Content $keyFile -Raw) -match '"api_key"\s*:\s*"[^"]+"'))
if ($hasKey) {
    Ok 'API key already configured'
} elseif ($SkipKey) {
    Warn 'No API key and -SkipKey given. Run later: bx config set-key'
} else {
    Info 'No API key found. Paste it at the prompt (it is not echoed into shell history).'
    & $wrapper config set-key
}

# 5. verify
Step 'verify'
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    Warn 'jq not available; skipping the search check.'
    return
}
if (-not $hasKey -and -not ($keyFile -and (Test-Path $keyFile))) {
    Warn 'No API key yet; skipping the search check.'
    return
}
$titles = & $wrapper web 'brave search cli' --count 1 | jq -r '.web.results[0].title'
if ($LASTEXITCODE -eq 0 -and $titles) {
    Ok "search works: $titles"
} else {
    Warn 'Search failed. See agent/brave-search/bx-cli.md section 10 (exit codes and fixes).'
}
