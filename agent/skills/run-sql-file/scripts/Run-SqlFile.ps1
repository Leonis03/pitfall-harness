<#
.SYNOPSIS
    Run a .sql file with sqlcmd and return a UTF-8 output file whose Chinese text survives.
.DESCRIPTION
    Auto-detects the script's encoding (GBK / UTF-8 / UTF-16 / ASCII), passes the matching
    input code page to sqlcmd, writes UTF-16 output, then converts it to UTF-8.
    Read the resulting file with `cat` from Bash - printing CJK straight to the PowerShell
    console gets mangled by the transport.
.EXAMPLE
    .\Run-SqlFile.ps1 -Path "<your-sql-dir>\SQLQuery1.sql" -Database study
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Database = 'master',
    [string]$Server = '<your-host>\SQL2016',
    [ValidateSet('auto', '936', '65001', '1252', 'utf16', 'utf8bom', 'ascii')][string]$InputEncoding = 'auto',
    [string]$Separator = '|',
    [int]$Width = 400,
    [switch]$NoHeaders,
    [string]$OutDir = $env:TEMP
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "Script not found: $Path" }
[System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)

function Get-SqlFileCodePage {
    param([string]$FilePath)
    $b = [System.IO.File]::ReadAllBytes($FilePath)
    if ($b.Length -ge 2 -and (($b[0] -eq 0xFF -and $b[1] -eq 0xFE) -or ($b[0] -eq 0xFE -and $b[1] -eq 0xFF))) { return 'utf16' }
    # A UTF-8 BOM is auto-detected by sqlcmd - no -f flag needed at all.
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return 'utf8bom' }
    $hasHigh = $false
    foreach ($byte in $b) { if ($byte -gt 0x7F) { $hasHigh = $true; break } }
    if (-not $hasHigh) { return 'ascii' }
    # High bytes with no BOM: valid UTF-8 byte sequence means UTF-8, otherwise GBK.
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        [void]$strict.GetString($b)
        return '65001'
    } catch { return '936' }
}

$cp = if ($InputEncoding -eq 'auto') { Get-SqlFileCodePage -FilePath $Path } else { $InputEncoding }

$base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
$raw = Join-Path $OutDir "$base.utf16"
$out = Join-Path $OutDir "$base.out.txt"

$sqlArgs = @(
    '-S', $Server, '-d', $Database, '-E', '-b',
    '-i', $Path, '-o', $raw, '-u', '-W', "-s$Separator", '-w', $Width
)
if ($cp -notin @('utf16', 'ascii', 'utf8bom')) { $sqlArgs += @('-f', "i:$cp") }
if ($NoHeaders) { $sqlArgs += '-h-1' }

& sqlcmd @sqlArgs
$code = $LASTEXITCODE

# Convert even on failure - sqlcmd writes its error text into the same output file.
if (Test-Path -LiteralPath $raw) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($out, [System.IO.File]::ReadAllText($raw, [System.Text.Encoding]::Unicode), $utf8)
    Remove-Item -LiteralPath $raw -Force
} else {
    throw "sqlcmd produced no output file (exit $code)"
}

[PSCustomObject]@{
    Script       = $Path
    Database     = $Database
    Server       = $Server
    InputCodePage = $cp
    ExitCode     = $code
    OutputFile   = $out
    ReadWith     = 'cat "' + ($out.Replace([char]92, '/') -replace '^C:', '/c') + '"'
}
