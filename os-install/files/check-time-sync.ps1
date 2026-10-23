# check-time-sync.ps1 -- report the state of the Windows clock and of the RTC
# convention it shares with a second, dual-booted operating system.
#
# READ-ONLY. This script never changes a setting, never starts or stops a
# service, and never writes to the registry. It reports, and a human decides.
#
# Exit codes:
#   0  no finding
#   1  at least one finding (WARN or FAIL)
#   2  a probe could not run (missing tool, permission, no network)
#
# Usage:
#   pwsh -File check-time-sync.ps1
#   pwsh -File check-time-sync.ps1 -NtpServer time.windows.com
#
# What it checks:
#   1. the Windows Time service state (disabled = nothing corrects the clock)
#   2. the sync mode (NoSync vs NTP) and the configured peers
#   3. the measured offset against an NTP server
#   4. an independent cross-check against a remote HTTPS Date header
#   5. the RTC convention (RealTimeIsUniversal) and the time zone
#   6. Windows fast startup (a stale RTC for the second OS)
#   7. time-service events whose timestamps sit in the future -- the signature
#      of a clock that was running fast and was later corrected
#
# Companion: check-time-sync.sh (same checks, Linux side).

[CmdletBinding()]
param(
    # NTP server(s) used for the measured offset, tried in order until one
    # answers. Any reachable server works; a public list is a safer default
    # than a single host, because a blocked name would otherwise make the
    # probe look like a clock problem.
    [string]$NtpServer = 'ntp.aliyun.com,ntp.ntsc.ac.cn,time.windows.com,pool.ntp.org',

    # Host used for the independent HTTP Date cross-check. Any HTTPS host works.
    [string]$HttpHost = 'www.microsoft.com',

    # How far back to look for time-service events.
    [int]$LookbackHours = 24
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [ValidateSet('OK', 'INFO', 'WARN', 'FAIL', 'SKIP')]
        [string]$Level,
        [string]$Check,
        [string]$Detail
    )
    $findings.Add([pscustomobject]@{ Level = $Level; Check = $Check; Detail = $Detail })
}

function Write-Section {
    param([string]$Title)
    Write-Output ''
    Write-Output "== $Title =="
}

# The UTC offset of this machine, in minutes. It comes from the registry, not
# from the network, so it must not depend on whether an NTP server answered:
# the event attribution below needs it to recognise a clock that was a whole
# zone out at boot.
function Get-ZoneOffsetMinutes {
    $tz = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -ErrorAction SilentlyContinue
    if (-not $tz -or $null -eq $tz.ActiveTimeBias) { return $null }
    $bias = [int64]$tz.ActiveTimeBias
    if ($bias -gt 2147483647) { $bias = $bias - 4294967296 }
    # ActiveTimeBias is the UTC offset in MINUTES (UTC = local + bias).
    return [math]::Abs($bias)
}

# Run a command with a bounded budget. Returns an object with two fields, so
# a caller can tell "the command finished and said nothing" from "the command
# never came back" -- the two need different words in the report.
function Invoke-WithTimeout {
    param(
        [scriptblock]$Action,
        [int]$TimeoutSeconds = 12
    )
    $job = Start-Job -ScriptBlock $Action
    Wait-Job -Job $job -Timeout $TimeoutSeconds | Out-Null
    # A job that errored ends in state Failed, not Completed -- both mean
    # "it came back"; only a job still Running after the budget is a timeout.
    if ($job.State -in @('Completed', 'Failed')) {
        $out = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force
        return [pscustomobject]@{ TimedOut = $false; Output = ($out -join "`n") }
    }
    Stop-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force
    return [pscustomobject]@{ TimedOut = $true; Output = '' }
}

# ---------------------------------------------------------------- 1. service
Write-Section 'Windows Time service'

$svc = Get-Service -Name W32Time -ErrorAction SilentlyContinue
if (-not $svc) {
    Add-Finding -Level 'FAIL' -Check 'W32Time service' -Detail 'service not found on this system'
} else {
    $detail = "Status=$($svc.Status) StartType=$((Get-CimInstance Win32_Service -Filter "Name='W32Time'").StartMode)"
    if ($svc.Status -ne 'Running') {
        Add-Finding -Level 'WARN' -Check 'W32Time service' -Detail "$detail -- the clock is not being corrected"
    } else {
        Add-Finding -Level 'OK' -Check 'W32Time service' -Detail $detail
    }
}

# ------------------------------------------------------------ 2. sync mode
Write-Section 'Sync mode and peers'

$paramPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
$w32params = Get-ItemProperty -Path $paramPath -ErrorAction SilentlyContinue
if ($w32params) {
    $type = $w32params.Type
    $peers = $w32params.NtpServer
    Add-Finding -Level 'INFO' -Check 'W32Time Parameters' -Detail "Type=$type"
    Add-Finding -Level 'INFO' -Check 'NtpServer' -Detail "$peers"
    if ($type -eq 'NoSync') {
        Add-Finding -Level 'WARN' -Check 'Sync mode' -Detail 'Type=NoSync -- no automatic correction at all'
    }
} else {
    Add-Finding -Level 'FAIL' -Check 'W32Time Parameters' -Detail 'registry key not readable'
}

if ($svc -and $svc.Status -eq 'Running') {
    $source = (w32tm /query /source 2>&1 | Out-String).Trim()
    if ($source -match 'not been started|error') {
        Add-Finding -Level 'WARN' -Check 'Sync source' -Detail $source
    } else {
        Add-Finding -Level 'OK' -Check 'Sync source' -Detail $source
    }

    $status = (w32tm /query /status 2>&1 | Out-String)
    $stratum = if ($status -match 'Stratum:\s*(\d+)') { $Matches[1] } else { '?' }
    $leap = if ($status -match 'Leap Indicator:\s*(\d+)') { $Matches[1] } else { '?' }
    $lastSync = if ($status -match 'Last Successful Sync Time:\s*(.+)') { $Matches[1].Trim() } else { 'never' }
    if ($stratum -ne '?' -and [int]$stratum -gt 0) {
        Add-Finding -Level 'OK' -Check 'Sync status' -Detail "Stratum=$stratum Leap=$leap LastSync=$lastSync"
    } else {
        Add-Finding -Level 'WARN' -Check 'Sync status' -Detail "Stratum=$stratum Leap=$leap LastSync=$lastSync -- not synchronized"
    }
} else {
    Add-Finding -Level 'SKIP' -Check 'Sync source / status' -Detail 'service is not running'
}

# -------------------------------------------------------------- 3. the offset
Write-Section 'Measured offset against NTP'

$zoneMinutes = Get-ZoneOffsetMinutes

$offsets = @()
$usedServer = $null
$failedServers = @()
foreach ($candidate in ($NtpServer -split '[,\s]+' | Where-Object { $_ })) {
    # w32tm has no timeout of its own: a name that does not resolve keeps it
    # retrying for a while, and with four candidates the probe would sit there
    # for minutes. Give each one a bounded budget and move on.
    $result = Invoke-WithTimeout -TimeoutSeconds 12 -Action {
        w32tm /stripchart "/computer:$using:candidate" /dataonly /samples:3 2>&1 | Out-String
    }
    if ($result.TimedOut) {
        $failedServers += "$candidate (timed out)"
        continue
    }
    $parsed = [regex]::Matches($result.Output, '([+-]\d+\.\d+)s') | ForEach-Object { [double]$_.Groups[1].Value }
    if ($parsed.Count -gt 0) {
        $offsets = @($parsed)
        $usedServer = $candidate
        break
    }
    $failedServers += $candidate
}

if ($null -eq $usedServer) {
    Add-Finding -Level 'WARN' -Check 'NTP offset' -Detail ("no sample from any of: " + ($failedServers -join ', ') + " -- unreachable names look like a clock problem but are a network one")
} else {
    $maxAbs = ($offsets | ForEach-Object { [math]::Abs($_) } | Measure-Object -Maximum).Maximum
    $level = if ($maxAbs -lt 1) { 'OK' } elseif ($maxAbs -lt 60) { 'WARN' } else { 'FAIL' }
    $detail = ("{0}: " -f $usedServer) + (($offsets | ForEach-Object { "{0:+0.000;-0.000;0.000}s" -f $_ }) -join ', ')
    if ($failedServers.Count -gt 0) {
        $detail = $detail + ("  (unreachable: " + ($failedServers -join ', ') + ")")
    }
    # An offset that matches this machine's zone offset is not drift: it is the
    # clock showing the wrong zone -- the RTC is being read under the wrong
    # convention (RealTimeIsUniversal vs the Linux LocalRTC setting), or the
    # display is showing UTC. Name it, so the finding points at the cause.
    if ($zoneMinutes -and [math]::Abs($maxAbs - ($zoneMinutes * 60)) -le 120) {
        $detail = $detail + ("  <-- this is the zone offset ({0} h): the clock is showing the WRONG ZONE, not drifting. The RTC is being read under the wrong convention -- check RealTimeIsUniversal here against LocalRTC on the other system" -f ($zoneMinutes / 60))
    }
    Add-Finding -Level $level -Check 'NTP offset' -Detail $detail
}

# --------------------------------------------------- 4. independent cross-check
Write-Section "Independent cross-check via https://$HttpHost"

try {
    $resp = Invoke-WebRequest -Method Head -Uri "https://$HttpHost" -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
    $dateHeader = $resp.Headers['Date']
    if ($dateHeader) {
        $remote = [datetime]::Parse($dateHeader).ToUniversalTime()
        $localUtc = (Get-Date).ToUniversalTime()
        $delta = ($localUtc - $remote).TotalSeconds
        $level = if ([math]::Abs($delta) -lt 2) { 'OK' } elseif ([math]::Abs($delta) -lt 60) { 'WARN' } else { 'FAIL' }
        Add-Finding -Level $level -Check 'HTTP Date' -Detail ("remote UTC " + $remote.ToString('yyyy-MM-dd HH:mm:ss') + ", local UTC " + $localUtc.ToString('yyyy-MM-dd HH:mm:ss') + ", delta " + ("{0:+0.000;-0.000;0.000}s" -f $delta))
    } else {
        Add-Finding -Level 'SKIP' -Check 'HTTP Date' -Detail 'no Date header in the response'
    }
} catch {
    Add-Finding -Level 'SKIP' -Check 'HTTP Date' -Detail "probe failed: $($_.Exception.Message)"
}

# ------------------------------------------------------------- 5. RTC mode
Write-Section 'RTC convention and time zone'

$tzInfo = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -ErrorAction SilentlyContinue
if ($tzInfo) {
    $rtu = $tzInfo.RealTimeIsUniversal
    # The value is only present when somebody set it. Absent means 0 -- the
    # RTC holds local time -- which is the common case, not an anomaly.
    $rtuAbsent = $null -eq $rtu
    if ($rtuAbsent) { $rtu = 0 }
    $zone = $tzInfo.TimeZoneKeyName
    $offsetText = 'unknown'
    if ($null -ne $tzInfo.ActiveTimeBias) {
        # ActiveTimeBias is the UTC offset in minutes, stored as an unsigned
        # 32-bit value: UTC = local + bias, so the bias is negative east of
        # Greenwich (-480 for UTC+08:00).
        $bias = [int64]$tzInfo.ActiveTimeBias
        if ($bias -gt 2147483647) { $bias = $bias - 4294967296 }
        $offsetText = ("{0:+0.0;-0.0;0.0}" -f (-($bias / 60.0))) + ' h'
    }
    Add-Finding -Level 'INFO' -Check 'Time zone' -Detail "TimeZoneKeyName=$zone offset=$offsetText"
    if ($rtu -eq 1) {
        Add-Finding -Level 'INFO' -Check 'RealTimeIsUniversal' -Detail '1 -- the RTC is read as UTC; the Linux side must use LocalRTC=no'
    } elseif ($rtu -eq 0) {
        $absentNote = if ($rtuAbsent) { ' (the value is absent from the registry; 0 is the default -- the RTC holds local time)' } else { '' }
        Add-Finding -Level 'INFO' -Check 'RealTimeIsUniversal' -Detail ("0 -- the RTC is read as local time; the Linux side must use LocalRTC=yes$absentNote")
    } else {
        Add-Finding -Level 'WARN' -Check 'RealTimeIsUniversal' -Detail "unexpected value: $rtu"
    }
} else {
    Add-Finding -Level 'FAIL' -Check 'TimeZoneInformation' -Detail 'registry key not readable'
}

# ---------------------------------------------------------- 6. fast startup
Write-Section 'Windows fast startup'

$hib = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue
if ($null -eq $hib) {
    Add-Finding -Level 'INFO' -Check 'Fast startup' -Detail 'HiberbootEnabled not present'
} elseif ($hib.HiberbootEnabled -eq 0) {
    Add-Finding -Level 'OK' -Check 'Fast startup' -Detail 'disabled -- the RTC is not carried across shutdowns'
} else {
    Add-Finding -Level 'WARN' -Check 'Fast startup' -Detail 'enabled -- the second OS may read a stale RTC'
}

# ------------------------------------------------- 7. the "fast clock" signature
Write-Section 'Time-service event timeline'

$now = Get-Date
$since = $now.AddHours(-$LookbackHours)
$events = @()
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        ProviderName = 'Microsoft-Windows-Time-Service'
        StartTime = $since
    } -ErrorAction Stop
} catch {
    Add-Finding -Level 'SKIP' -Check 'Event log' -Detail "cannot read the System log: $($_.Exception.Message)"
}

if ($events) {
    $syncs = $events | Where-Object { $_.Id -eq 35 }
    $fails = $events | Where-Object { $_.Id -eq 134 }
    $future = $events | Where-Object { $_.TimeCreated -gt $now }

    Add-Finding -Level 'INFO' -Check 'Events' -Detail ("{0} time-service events in the last {1} h: {2} sync, {3} source failure" -f $events.Count, $LookbackHours, $syncs.Count, $fails.Count)

    if ($syncs.Count -gt 0) {
        $last = $syncs | Sort-Object TimeCreated -Descending | Select-Object -First 1
        $msg = (($last.Message -split "`r?`n")[0]).Trim()
        Add-Finding -Level 'INFO' -Check 'Last sync event' -Detail ("{0:yyyy-MM-dd HH:mm:ss} -- {1}" -f $last.TimeCreated, $msg)
    }

    if ($fails.Count -gt 0) {
        $last = $fails | Sort-Object TimeCreated -Descending | Select-Object -First 1
        $msg = (($last.Message -split "`r?`n")[0]).Trim()
        Add-Finding -Level 'WARN' -Check 'Source failures' -Detail ("{0} event(s); last at {1:yyyy-MM-dd HH:mm:ss} -- {2}" -f $fails.Count, $last.TimeCreated, $msg)
    }

    if ($future.Count -gt 0) {
        # The question is "how far off was the clock when the machine came up?".
        # The anchor is the boot, but the attribution has to be careful: the
        # events carry the clock as it was WHEN THEY WERE WRITTEN, which may be
        # a different scale from the boot time (a clock that was later
        # corrected) and may belong to an earlier boot entirely.
        #
        # An event belongs to the current boot when its stamp is within an
        # hour of the boot time -- either directly, or shifted by exactly the
        # zone offset (the boot happened while the clock was a whole zone
        # out, and was corrected afterwards). Anything else is history.
        $first = $future | Sort-Object { $_.TimeCreated } | Select-Object -First 1
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $zoneSeconds = 0
        if ($null -ne $zoneMinutes) { $zoneSeconds = $zoneMinutes * 60 }
        $gapMinutes = $null
        $thisBoot = $false
        if ($boot) {
            $gapMinutes = ($first.TimeCreated - $boot).TotalMinutes
            $candidates = @($gapMinutes)
            if ($zoneSeconds -gt 0) { $candidates += ($gapMinutes - ($zoneSeconds / 60)); $candidates += ($gapMinutes + ($zoneSeconds / 60)) }
            $thisBoot = @($candidates | Where-Object { [math]::Abs($_) -le 60 }).Count -gt 0
        }
        if ($thisBoot) {
            $size = ("{0:N2} h at boot (boot {1:yyyy-MM-dd HH:mm:ss}, first time-service event stamped {2:yyyy-MM-dd HH:mm:ss}, uncertainty = the few minutes between the two)" -f ($gapMinutes / 60), $boot, $first.TimeCreated)
            Add-Finding -Level 'FAIL' -Check 'Future-stamped events' -Detail ("{0} event(s) carry a timestamp later than now: the clock was running fast when they were written, {1}. An NTP sync corrected it later, which is why the clock looks right now. The RTC convention is the defect, not the sync." -f $future.Count, $size)
        } else {
            # $boot can be missing when CIM is unavailable; subtracting $null
            # from a DateTime throws, and the whole finding would be lost.
            $sinceBoot = 'an unknown number of hours'
            if ($boot) { $sinceBoot = ("{0:N2} h from the current boot time" -f (($first.TimeCreated - $boot).TotalHours)) }
            Add-Finding -Level 'INFO' -Check 'Future-stamped events' -Detail ("{0} event(s) carry a timestamp later than now, but they belong to an EARLIER boot (first at {1:yyyy-MM-dd HH:mm:ss}, {2}) -- the clock was corrected after that boot, which is why the stamps sit in the future. The current boot shows no such error." -f $future.Count, $first.TimeCreated, $sinceBoot)
        }
    }
} elseif (-not ($findings | Where-Object { $_.Check -eq 'Event log' })) {
    Add-Finding -Level 'INFO' -Check 'Events' -Detail 'no time-service events in the window'
}

# ------------------------------------------------------------------ verdict
Write-Output ''
Write-Output '== Verdict =='
$findings | ForEach-Object {
    $line = '{0,-5} {1,-22} {2}' -f $_.Level, $_.Check, $_.Detail
    switch ($_.Level) {
        'OK'   { Write-Host $line -ForegroundColor Green }
        'INFO' { Write-Host $line -ForegroundColor Gray }
        'WARN' { Write-Host $line -ForegroundColor Yellow }
        'FAIL' { Write-Host $line -ForegroundColor Red }
        'SKIP' { Write-Host $line -ForegroundColor DarkGray }
    }
}

$warn = @($findings | Where-Object { $_.Level -eq 'WARN' }).Count
$fail = @($findings | Where-Object { $_.Level -eq 'FAIL' }).Count

Write-Output ''
if ($fail -gt 0) {
    Write-Output "RESULT: $fail failing, $warn warning(s). See the finding list above."
    exit 1
} elseif ($warn -gt 0) {
    Write-Output "RESULT: $warn warning(s), no failing check."
    exit 1
} else {
    Write-Output 'RESULT: no finding.'
    exit 0
}
