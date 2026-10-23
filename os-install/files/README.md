# os-install/files -- read-only probes

*English · [中文](README.zh.md) · back to [os-install/](../README.md)*

Deployable originals: scripts you copy to the machine and run. **Every script in
this directory is read-only.** None of them changes a setting, starts or stops a
service, or writes to the hardware clock. They report; a human decides and runs
the fix, which is written down in the prose next to the measurement that
justified it.

| Script | Runs on | What it reports | Exit code |
| :--- | :--- | :--- | :--- |
| [`check-time-sync.ps1`](check-time-sync.ps1) | Windows | the time service, the sync mode, the measured NTP offset, an independent HTTP `Date` cross-check, the RTC convention (`RealTimeIsUniversal`), fast startup, and the boot-time error hidden by a later sync | 0 = clean, 1 = findings, 2 = a probe could not run |
| [`check-time-sync.sh`](check-time-sync.sh) | Linux | the clock mode (`LocalRTC`), the time zone, the NTP state, the RTC read under **both** conventions against the system clock, the measured offset (chrony or systemd-timesyncd), an HTTP `Date` cross-check, and the value the other OS has to match | 0 = clean, 1 = findings, 2 = a probe could not run |

## Usage

```powershell
# Windows
pwsh -File .\check-time-sync.ps1
pwsh -File .\check-time-sync.ps1 -NtpServer ntp.example.com,pool.ntp.org -HttpHost www.example.com
```

The NTP server parameter takes a **list**: the script tries each name in order and
uses the first one that answers, because a name that does not resolve looks
exactly like a clock problem in the output.

```bash
# Linux
bash check-time-sync.sh
sudo bash check-time-sync.sh          # the RTC read needs root on most distributions
bash check-time-sync.sh --http-host www.example.com
```

## Reading the output

- `OK` / `INFO` -- nothing to do.
- `WARN` -- a real condition worth a decision: the service is off, a source
  failed, fast startup is on, the clock drifts.
- `FAIL` -- a defect, not a preference. Concretely: the RTC disagrees with the
  system clock under **both** readings; the RTC's content and this side's
  `LocalRTC` setting disagree; the clock is a timezone-scale distance away from
  an independent source; a registry key could not be read at all; the Windows
  Time service is missing; or time-service events carry timestamps later than
  now -- the signature of a clock that was running fast and was later
  corrected.
- `SKIP` -- the probe could not run here (no `chronyc`, no root for the RTC, no
  network). Not a finding; check the other side by hand.

The one finding worth reading twice is the boot-time error: the script finds
time-service events stamped **later than now** and anchors them on the boot
time. That is the signature of a clock that was wrong at boot and was corrected
by a sync minutes later -- the screen looks right, the hardware is not, and the
repair is the reason nobody noticed.

## Conventions

- **Pure ASCII**, comments included.
- **LF line endings.**
- **No real identifiers**: the NTP server and the HTTP host are parameters with
  public defaults.
- The scripts are standalone: copy one file, run it, read the output.
