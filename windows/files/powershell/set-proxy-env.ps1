# set-proxy-env.ps1 -- write the user-level proxy environment variables, but
# only after checking that the port is actually open.
#
# WHY A SCRIPT AND NOT A MANUAL REGISTRY EDIT
#
# The six values live in HKCU\Environment, so every newly started application
# inherits them. Two things go wrong when they are set by hand:
#
#   - a value pointing at a port nothing listens on breaks every proxied
#     request ("connection refused") while a direct connection still works.
#     That is the "the terminal has no network" failure, and it is invisible
#     from the tool that is failing;
#   - the two spellings of each name (HTTP_PROXY and http_proxy) have to
#     match, because different clients read different ones.
#
# WHAT IT DOES
#
#   1. probe the port (a TCP connect to the loopback address)
#   2. if it answers: write the six variables and broadcast WM_SETTINGCHANGE,
#      so that applications started from Explorer inherit them
#   3. if it does not answer: remove the variables instead (they would point
#      at a dead port) and exit non-zero
#
# WHAT IT CANNOT DO
#
# It cannot change the environment of a process that is already running.
# Windows snapshots the environment when a process starts, so an agent, an
# IDE or a desktop app that was launched before this script ran keeps the old
# values until it is restarted. This is the usual reason for "the terminal can
# reach the network but my agent cannot".
#
# USAGE
#
#   pwsh -File .\set-proxy-env.ps1 -Port <proxy-port>
#   pwsh -File .\set-proxy-env.ps1 -Port <http-port> -SocksPort <socks-port>
#   pwsh -File .\set-proxy-env.ps1 -Port <proxy-port> -Force     # set without probing
#   pwsh -File .\set-proxy-env.ps1 -Port <proxy-port> -KeepStale  # do not clear on failure
#
# Exit codes:
#   0  the variables were written
#   2  no port answered and the variables were cleared (or kept, with -KeepStale)
#
# The port is not stored in this file: it differs per client and per machine.
# A Clash-family mixed port answers both HTTP and SOCKS5 on the same socket,
# so -Port alone is enough. A client with two separate ports needs both:
# -Port for the HTTP one and -SocksPort for the SOCKS5 one. Each is probed
# on its own, and only the pair that answered is written.
#
# Verify afterwards with:
#   [Environment]::GetEnvironmentVariable('HTTP_PROXY', 'User')

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 65535)]
    [int]$Port,

    [string]$HostAddress = '127.0.0.1',

    # The SOCKS5 port, when the client listens on a different one for SOCKS5
    # than for HTTP. 0 means "the same port as -Port", which is what a mixed
    # port does -- one socket answering both HTTP CONNECT and the SOCKS5
    # greeting. A client with two separate ports MUST be given both: the
    # ALL_PROXY pointed at the HTTP port fails with "Connection reset by
    # peer", because that port only answers HTTP CONNECT.
    [ValidateRange(0, 65535)]
    [int]$SocksPort = 0,

    # socks5h resolves the hostname on the proxy side; socks5 resolves it here.
    [ValidateSet('socks5h', 'socks5')]
    [string]$SocksScheme = 'socks5h',

    # Set the variables even when the port does not answer.
    [switch]$Force,

    # Leave the existing variables alone when the port does not answer.
    [switch]$KeepStale
)

$ErrorActionPreference = 'Stop'

# PowerShell hashtable keys are case-insensitive, so the two spellings of
# each name cannot live in one hashtable: keep them in plain arrays.
$httpNames = @('HTTP_PROXY', 'http_proxy', 'HTTPS_PROXY', 'https_proxy')
$socksNames = @('ALL_PROXY', 'all_proxy')
$VariableNames = @($httpNames) + @($socksNames)

function Test-TcpPort {
    param(
        [string]$Address,
        [int]$PortNumber,
        [int]$TimeoutMs = 1500
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($Address, $PortNumber, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

Write-Host '== current state =='
foreach ($name in $VariableNames) {
    $userValue = [Environment]::GetEnvironmentVariable($name, 'User')
    $procValue = [Environment]::GetEnvironmentVariable($name, 'Process')
    Write-Host ('{0,-12} user="{1}"  process="{2}"' -f $name, $userValue, $procValue)
}

$socksPortEffective = if ($SocksPort -eq 0) { $Port } else { $SocksPort }

$httpOpen = Test-TcpPort -Address $HostAddress -PortNumber $Port
$socksOpen = if ($socksPortEffective -eq $Port) { $httpOpen } else { Test-TcpPort -Address $HostAddress -PortNumber $socksPortEffective }
Write-Host ''
Write-Host ('probe {0}:{1} (HTTP)  -> {2}' -f $HostAddress, $Port, $(if ($httpOpen) { 'OPEN' } else { 'refused' }))
if ($socksPortEffective -ne $Port) {
    Write-Host ('probe {0}:{1} (SOCKS) -> {2}' -f $HostAddress, $socksPortEffective, $(if ($socksOpen) { 'OPEN' } else { 'refused' }))
}

if ((-not $httpOpen -and -not $socksOpen) -and -not $Force) {
    if ($KeepStale) {
        Write-Host 'The port is not listening; keeping the existing variables (KeepStale).'
    } else {
        Write-Host 'The port is not listening; removing the proxy variables so that no request'
        Write-Host 'is sent to a dead port. A direct connection is the path that works.'
        foreach ($name in $VariableNames) {
            [Environment]::SetEnvironmentVariable($name, $null, 'User')
        }
    }
    Write-Host ''
    Write-Host 'Note: a client in TUN mode opens no local port at all, because it takes the'
    Write-Host 'traffic at the network layer. Unset variables are the correct state there.'
    Write-Host 'Note: a process that is already running keeps the environment it started'
    Write-Host 'with. Restart it (or this script will not help it) after changing values.'
    exit 2
}

$httpValue = 'http://{0}:{1}' -f $HostAddress, $Port
$socksValue = '{0}://{1}:{2}' -f $SocksScheme, $HostAddress, $socksPortEffective

# One port per variable: write each pair only if that port answered. A
# variable pointing at a port nothing listens on turns every proxied request
# into "connection refused" while a direct connection works fine.
if ($httpOpen -or $Force) {
    foreach ($name in $httpNames) {
        [Environment]::SetEnvironmentVariable($name, $httpValue, 'User')
    }
}
if ($socksOpen -or $Force) {
    foreach ($name in $socksNames) {
        [Environment]::SetEnvironmentVariable($name, $socksValue, 'User')
    }
}

Write-Host ''
Write-Host 'written to HKCU\Environment:'
if ($httpOpen -or $Force) {
    foreach ($name in $httpNames) {
        Write-Host ('  {0,-12} = {1}' -f $name, $httpValue)
    }
}
if ($socksOpen -or $Force) {
    foreach ($name in $socksNames) {
        Write-Host ('  {0,-12} = {1}' -f $name, $socksValue)
    }
}

# Broadcast WM_SETTINGCHANGE so that Explorer refreshes its own copy of the
# environment; applications started from it then inherit the new values.
# Processes that are already running keep their snapshot -- that is the whole
# point of the note above.
try {
    if (-not ('EnvBroadcast' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class EnvBroadcast
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@
    }
    $broadcastResult = [UIntPtr]::Zero
    [void][EnvBroadcast]::SendMessageTimeout(
        [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$broadcastResult)
    Write-Host ''
    Write-Host 'broadcast WM_SETTINGCHANGE (Environment): newly started applications inherit the values.'
} catch {
    Write-Host ''
    Write-Host ('could not broadcast WM_SETTINGCHANGE: {0}' -f $_.Exception.Message)
}

Write-Host ''
Write-Host 'Restart anything that was already running (agents, IDEs, desktop apps) to pick these up.'
exit 0
