# Dual-boot time coordination (Windows + Linux)

*English · [中文](dual-boot-time-sync.zh.md) · back to [os-install/](README.md)*

How to keep the clock of two installed operating systems -- Windows and a Linux
distribution sharing the same machine -- in agreement, and how to tell the three
different causes of a disagreement apart.

This is the part of a dual-boot install that only shows up after the install
"works": the installer sets the clock in one convention, the second OS reads the
hardware clock in another, and the result is an offset that is either permanent
or -- worse -- self-healing and therefore invisible.

---

## 1. Three clocks, one contract

| Clock | Where it lives | Who writes it | Who reads it |
| :--- | :--- | :--- | :--- |
| **Hardware RTC** | The motherboard's coin-cell-backed CMOS | Whoever boots last, and any OS that runs `hwclock --systohc` | Every OS, at boot |
| **System clock** | The running kernel | The OS, from the RTC at boot, then from NTP | Every process |
| **NTP** | The network | An upstream server | `w32time` / `chrony` / `systemd-timesyncd` |

Both operating systems read the **same** RTC at boot. The only free parameter
is the *convention* each one uses to interpret it:

| Convention | RTC contains | Windows setting | Linux setting |
| :--- | :--- | :--- | :--- |
| **Local time** | Local wall-clock time | `RealTimeIsUniversal = 0` | `timedatectl set-local-rtc 1` |
| **UTC** | UTC | `RealTimeIsUniversal = 1` | `timedatectl set-local-rtc 0` |

> The RTC itself does not know which convention it holds. A machine can be in
> either state, and nothing in the firmware records the choice. **The contract
> has to live in both operating systems**, and it has to be written down, because
> it is invisible from the outside and a reinstall of either side silently
> resets it.

Windows registry key (both values live here):

```
HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation
  RealTimeIsUniversal   0 = RTC holds local time, 1 = RTC holds UTC
  TimeZoneKeyName       the Windows time-zone id ("Singapore Standard Time", "China Standard Time", ...)
```

Linux:

```bash
timedatectl show -p LocalRTC        # yes = RTC holds local time, no = UTC
```

> `RealTimeIsUniversal = 1` is **not** the Windows default on every machine and
> it is not a "UTC machine" setting. It is the half of the dual-boot contract
> that Windows keeps.

---

## 2. The 8-hour signature

The most common dual-boot failure looks like this:

```text
boot into Windows  ->  the clock reads 19:22 when it is 11:22
boot into Linux    ->  the clock reads 03:22 when it is 11:22
the difference     ->  exactly the UTC offset, both times, opposite directions
```

Read it like this: **the two systems disagree by exactly the UTC offset, and
each is "right" in its own convention.** Windows adds `+08:00` to a value it
believes is UTC; Linux adds `+08:00` to a value it believes is local time.

The decisive question is *which side is misreading the RTC*:

```text
RTC holds local time
  Windows (RealTimeIsUniversal=1) reads it as UTC  ->  +8h too late
  Linux   (LocalRTC=no)            reads it as UTC  ->  correct

RTC holds UTC
  Windows (RealTimeIsUniversal=0) reads it as local ->  -8h too early
  Linux   (LocalRTC=yes)           reads it as local ->  -8h too early
```

Check both sides before changing anything. A wrong fix here makes the offset
double instead of removing it, and both systems then look "more broken".

---

## 3. Diagnose before you touch anything

### 3.1 Windows side

```powershell
# service state -- "Disabled" or "Stopped" means nothing is correcting the clock
Get-Service W32Time | Select-Object Status, StartType

# is a sync configured at all ("NTP" vs "NoSync")
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' |
  Select-Object Type, NtpServer

# what the service thinks its source and last sync are
w32tm /query /source
w32tm /query /status

# measured offset against an upstream server, in seconds (+/-)
w32tm /stripchart /computer:<your-ntp-server> /dataonly /samples:3

# the RTC convention, and whether the OS is on UTC or local time
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' |
  Select-Object RealTimeIsUniversal, TimeZoneKeyName
```

`w32tm /query /status` failing with **`The service has not been started.
(0x80070426)`** is not a network problem. It means the Windows Time service is
disabled, so the clock is free-running and nothing will ever correct it.

`w32tm /stripchart` works **without** the service running, so it is the probe to
use when the service is off.

> An NTP name that does not resolve produces **no sample at all**, which reads
> exactly like "the clock is broken". Keep a list of candidates and treat
> "no sample" as a network result, not a clock result. On the machine this
> document was written on, one name in the list was blocked by DNS while the
> others answered.

### 3.2 Linux side

```bash
timedatectl                                  # LocalRTC, NTPSynchronized, time zone
timedatectl show -p LocalRTC -p NTPSynchronized
hwclock --show                              # RTC read as local time
hwclock --show --utc                        # the same RTC read as UTC
timedatectl timesync-status                 # systemd-timesyncd
chronyc tracking                            # when chrony is the client
```

`hwclock --show` and `hwclock --show --utc` print the **same** RTC under two
interpretations, and util-linux always prints in *local* time -- so the two
lines differ by exactly the UTC offset. The one that matches the system clock
is the convention the RTC actually **holds**; if neither matches, the RTC is
stale.

> Comparing the two lines means comparing parsed *instants*, not strings.
> `hwclock` prints a local-time string carrying the local offset, so `date -d`
> reads it correctly -- but the reference the UTC reading is measured against
> has to be a UTC instant as well. `date -d "$(date -u ...)"` parses the UTC
> wall clock in the **local** zone and shifts the reference by the offset,
> which doubles the reported distance of the UTC reading and makes a
> correctly configured machine look 8 hours out under *both* readings.

### 3.3 The independent cross-check

Do not trust the local clock to report its own error. Compare it against a
remote server's own clock:

```powershell
(Invoke-WebRequest -Method Head https://<any-https-host>).Headers.Date
```

or, without PowerShell:

```bash
curl -sI https://<any-https-host> | grep -i '^date:'
```

The `Date` header is the remote host's clock, in GMT. Convert and compare. Two
independent sources agreeing is the only evidence that the local clock is
right; `w32tm /query /status` alone does not prove it.

---

## 4. Pick one convention and write it into both systems

Do this from a state where the system clock is already known to be correct
(after step 3.3).

> **Measure before you choose.** The two options are not interchangeable: the
> right one is the one that matches what the RTC *already* holds. On Linux,
> `hwclock --show` and `hwclock --show --utc` read the same hardware clock
> under the two conventions -- whichever agrees with `date` is the convention
> the RTC is effectively in. On the machine this document was written on, the
> answer was **local time**, so Option A applies and the change belongs on the
> Windows side.

### Option A -- the RTC holds local time

```powershell
# Windows: read the RTC as local time
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -Value 0
```

```bash
# Linux: read the RTC as local time
sudo timedatectl set-local-rtc 1
sudo hwclock --systohc --localtime     # write the current (correct) time back
hwclock --show --localtime              # must match `date`
```

### Option B -- the RTC holds UTC

```powershell
# Windows: read the RTC as UTC
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -Value 1
```

```bash
# Linux: read the RTC as UTC
sudo timedatectl set-local-rtc 0
sudo hwclock --systohc --utc           # write the current (correct) time back
hwclock --show --utc                   # must match `date -u`
```

Option B matches the Linux default (`LocalRTC=no`) and the common BIOS default
(UTC). Option A matches the Windows default. **Either is fine; mixing them is
the bug.** Whatever is chosen, record it in the install notes -- it is the one
piece of the dual-boot contract that no tool can read for you.

> `hwclock --systohc` interprets the *system* clock according to the RTC
> convention in force. Pass `--utc` or `--localtime` explicitly so the write
> cannot be misinterpreted.

---

## 5. Sync policy: automatic correction vs. deliberate drift

The RTC convention fixes the *offset*. The sync policy decides whether a
*drift* is corrected, and whether you get to see it happen.

### Automatic

```powershell
Set-Service W32Time -StartupType Automatic
Start-Service W32Time
w32tm /config /syncfromflags:manual /manualpeerlist:"<your-ntp-server>,0x8 <second-server>,0x8" /update
Restart-Service W32Time
w32tm /resync /force
```

On the Settings side, **Date & time -> Set time automatically** writes exactly
two things: the W32Time service start type and the `Type` value under
`...\W32Time\Parameters` (`NTP` when on, `NoSync` when off). Toggling it off on
one machine produced: service `Disabled` and stopped, `Type = NoSync`. The
toggle is not an independent switch -- it *is* the service configuration.

### Deliberate

```powershell
Set-Service W32Time -StartupType Disabled
Stop-Service W32Time
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' `
  -Name Type -Value NoSync
```

Cost of turning it off, measured rather than assumed:

- The clock free-runs. A consumer motherboard's RTC drifts by tens of ppm:
  at 20 ppm, roughly **1.7 s per day, 50 s per month**. Nothing corrects it.
- An 8-hour error in the RTC convention is no longer corrected at boot either.
  It becomes a permanent, visible-on-every-boot error -- which is what some
  operators actually want: a wrong clock that is noticed, rather than a right
  clock that was quietly patched.
- TLS, Git commit signing, `systemd` timers and file timestamps break while it
  is wrong.

### The middle ground: keep the repair, keep the evidence

Automatic correction does not have to mean "silent". The Windows Time service
logs every attempt, success and failure to the `System` log under provider
`Microsoft-Windows-Time-Service`:

| Event ID | Meaning |
| :--- | :--- |
| `35` | the clock was **synchronized** with a named source |
| `37` | the provider is receiving valid time data |
| `134` | a source **failed** (DNS or network); the service retries with a growing interval |
| `158` | a provider stopped (e.g. `VMICTimeProvider` on a physical machine -- expected noise) |

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Time-Service'} -MaxEvents 30 |
  Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List
```

Event `35` is the proof that a repair happened; `134` is the first sign of the
network that makes the repair impossible. This is the difference between "the
system fixed it" and "I know it was fixed, and I know why".

### 5.1 The policy on this machine

The deliberate choice here, written down so the next reader does not have to
rediscover it:

| Setting | Value | Why |
| :--- | :--- | :--- |
| W32Time service | `Disabled`, stopped | Automatic repair is **off on purpose**. A clock that is quietly patched hides the fault; the operator wants to find the cause instead of inheriting a corrected symptom |
| `Type` under `...\W32Time\Parameters` | `NoSync` | The second half of what the Settings toggle writes -- both are needed to keep the service off |
| NTP peers | still in `NtpServer` | Left in place, so the service can be re-enabled with one command and so `w32tm /stripchart` still has a target to measure against |
| RTC convention | **local time on both sides** -- `RealTimeIsUniversal = 0` on Windows, `LocalRTC = yes` on Linux | Measured, not assumed: the raw RTC value equals the **local** time (section 8, finding 6). The distros read it as local and were correct; Windows read it as UTC and was 8 hours out. **The Windows half is the one to change**: `Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name RealTimeIsUniversal -Value 0`. The Linux half needs no change -- confirm it with `timedatectl show -p LocalRTC` (expect `yes`) |
| Fast startup | disabled | Section 6 |
| Time zone | a fixed UTC+08:00 zone, no DST | |

The cost of the first two rows is accepted and measured: the clock free-runs
(about 1.7 s per day on this class of hardware). What is **not** accepted is an
8-hour error that a sync hides, so the fix belongs on the side that
misinterprets the hardware clock -- and the measurement in section 8 says that
side is Windows.

The probe script exists for the same reason. It reports the state of the
machine at any moment, so the operator can tell "the fault is still there"
from "the fault was fixed an hour ago and I did not notice" -- which is
exactly what a self-healing clock looks like from the outside.

---

## 6. The third clock: Windows fast startup

Fast startup (`HiberbootEnabled=1`) turns shutdown into a **hybrid shutdown**:
the user sessions are closed, but the kernel session is written to the
hibernation file and restored on the next power-on -- Microsoft's own wording
is that "the kernel session is not closed, but it is hibernated". That next
boot is therefore a *resume*, not a cold boot: the clock comes back from the
snapshot instead of from the hardware clock, and the RTC keeps whatever value
it had. The consequence reported for a dual boot is that the second OS,
cold-booting right after, reads an RTC that is older than the actual shutdown
and shows the wrong time until something corrects it.

How stale the RTC actually is depends on the machine, so treat this as a
hypothesis to test rather than a mechanism to rely on: with fast startup on,
"the clock is wrong in Linux only" has a third possible cause, and the fix is
to turn fast startup off and re-test before touching any RTC convention.

```powershell
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
  -Name HiberbootEnabled | Select-Object HiberbootEnabled
```

`0` = fast startup off (the safe setting for a dual-boot machine), `1` = on.

With fast startup on, the "the clock is wrong in Linux only" symptom has a
third possible cause, and the fix is to turn fast startup off and re-test
before touching any RTC convention.

---

## 7. Verification checklist

Run this after any change. Each line is a probe, not an assumption.

**Windows**

```powershell
Get-Service W32Time | Select-Object Status, StartType            # expect: Running / Automatic
w32tm /query /source                                             # expect: a real source, no error
w32tm /query /status                                             # expect: Stratum > 0, Leap 0
w32tm /stripchart /computer:<your-ntp-server> /dataonly /samples:3   # expect: |offset| < 1 s
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' |
  Select-Object RealTimeIsUniversal                               # expect: 0 or 1, matching the choice
```

**Linux**

```bash
timedatectl show -p LocalRTC -p NTPSynchronized
# the chosen convention: --utc here, --localtime for the local one
hwclock --show --utc       # must equal `date -u`; with --localtime it must equal `date`
```

**Cross-system**

```text
1. `date` in Linux and the clock in Windows agree, to the minute
2. Reboot into the other system, repeat -- the agreement survives the reboot
3. The measured offset stays under a second after both sides are up
```

Step 2 is the one that catches the RTC convention bug: **a clock that is only
correct until the next reboot is not fixed.**

**A record of the machine's state** (Windows, one line each):

```powershell
Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'
Get-TimeZone | Select-Object Id
Get-Service W32Time | Select-Object Status, StartType
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' | Select-Object Type, NtpServer
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' | Select-Object RealTimeIsUniversal, TimeZoneKeyName
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled
```

The read-only probes in [`files/`](files/) do all of this in one run:
`check-time-sync.ps1` on Windows, `check-time-sync.sh` on Linux. They report,
they never change a setting.

---

## 8. One incident, measured

Recorded so the reasoning is reproducible rather than folklore.

**Symptom.** The Windows clock read `16:39` when the true local time was
`08:39` -- exactly 8 hours fast. The clock was *not* consistent with its own
time zone: the value had been set by hand, as if it were UTC, and the
`+08:00` zone was then applied on top of it.

**Findings.**

1. `Get-Service W32Time` -> `Stopped`, `StartType: Disabled`.
   `w32tm /query /status` -> `The service has not been started. (0x80070426)`.
   The registry held `Type = NoSync` with `NtpServer = time.windows.com,0x9`.
   So the clock was free-running and nothing was correcting it.
2. After enabling the service, configuring three peers and forcing a resync,
   the offset against the upstream server measured **+0.031 s**, and the
   remote `Date:` header matched the local clock exactly. The clock was right
   -- but only because it was being corrected every boot.
3. The next day, the machine booted at `11:22:49` local. The Time-service log
   for that boot shows events stamped **`19:22:59`** -- 8 hours ahead -- with
   three `134` events: *all three NTP peers failed DNS resolution* because the
   network was not up yet. Seven minutes later, at `19:29:35` (i.e. `11:29:35`
   real time), event `35` recorded a successful synchronization against
   `ntp.aliyun.com` and the clock was pulled back to the correct value.
   **The 8-hour error existed at every boot and was masked by the sync.**
4. The reason for the 8 hours: `RealTimeIsUniversal = 1` -- Windows was told
   the RTC holds UTC -- while the RTC physically held **local** time.
5. Fast startup was already off (`HiberbootEnabled = 0`), so the stale-RTC
   explanation was ruled out by measurement rather than assumption.
6. The raw RTC value equals the local time, and the arithmetic proves it:
   Windows read the RTC as UTC and then added the `+08:00` zone, so a
   pre-sync system clock of `19:22:59` means the hardware clock held
   `11:22:59` -- the true local time, not UTC. **The hardware clock was right
   all along; the interpretation flag was the defect.** The distros read the
   same RTC as local time and showed the correct clock after their install,
   which is why they were never the suspect.

**Lesson.** The clock was correct on screen and wrong in the hardware, and the
gap between the two was covered by an automatic repair that ran after the
network came up. Fixing the NTP service restored the *symptom*; the RTC
convention was the actual defect. A repair that runs minutes after every boot
is the reason a fault survives for months.

**Which side to fix.** The measurement decides it, and it decides it in the
opposite direction from the first guess. The RTC holds local time, so the
contract that fits this machine is **local on both sides**:
`RealTimeIsUniversal = 0` on Windows, `LocalRTC = yes` on Linux. The
alternative -- UTC on both sides -- holds only as long as the Linux side
rewrites the RTC after every Windows shutdown, because the side that writes
the RTC last decides what is in it. Choosing the convention that already
matches the hardware clock is the choice that survives.

---

## 9. Related

- [`../windows/README.md`](../windows/README.md) -- the Windows side of this repo
- [`../linux-desktop/README.md`](../linux-desktop/README.md) -- the native Linux side
- [`../wsl/setup/README.md`](../wsl/setup/README.md) -- WSL: a third clock source, but it shares the Windows kernel's clock, so none of the RTC rules apply to it
- [`files/README.md`](files/README.md) -- the read-only probe scripts
