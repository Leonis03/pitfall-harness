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
| **Hardware RTC** | The motherboard's coin-cell-backed CMOS | Windows, in the convention its `RealTimeIsUniversal` names; the Linux kernel every 11 minutes while NTP is synchronized, in the convention it was given at boot; anyone running `hwclock --systohc` (section 1.1) | Every OS, at boot |
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
>
> **Both flags are read at boot, not at the moment you change them.** A change
> to `RealTimeIsUniversal` has no effect until the next restart -- and the
> shutdown in between still writes the RTC under the *old* value, because the
> kernel keeps the flag it read at boot. The same is true of `LocalRTC` on
> Linux. So a convention change is not a two-minute edit: it is a change that
> only becomes observable after a reboot, which is exactly when an 8-hour error
> shows up. Change it, reboot, then measure.

### 1.1 Who writes the RTC

The convention is not only how each side *reads* the RTC: each side also
*writes* it, and the RTC holds whatever the last writer left. The contract
holds only when both sides write the convention the other one reads.

**Windows keeps the RTC in the convention its flag names.** Measured on two
machines whose flag was not touched for weeks:

| Machine | `RealTimeIsUniversal` | What the RTC held | How it was measured |
| :--- | :--- | :--- | :--- |
| A (section 5.1) | `1` | **UTC** | Two weeks of `Kernel-General` event 1 (section 3.1): `RealTimeIsUniversal=true` in force, and `CmosTime` equal to the true UTC of a clock that was right. Weeks of alternating Windows and Linux (`LocalRTC=no`) boots, all correct, with the Windows time service disabled -- so an 8-hour error would have stayed on screen |
| B (section 5.2) | `0` (absent) | **local time** | Two weeks of `Kernel-General` events 12 (boot) and 1: the RTC held the true local time at every boot and resume, and no change near the zone offset was ever logged |

When Windows writes the RTC -- at a time sync, at a resume, at shutdown -- was
not measured, and the contract does not depend on it: the convention follows
the flag, and the flag in force is the one read **at boot** (section 3.1 shows
how to read it).

> An earlier reading of section 8 concluded that Windows writes **local time
> whatever the flag says**, and moved machine A to local time on both sides.
> The boots it relied on had the flag changed between them, so the shutdowns
> in question ran under a different flag than the registry showed. Machine A
> refutes it -- flag `1`, RTC in UTC, for weeks -- and section 8, incident 3,
> records what acting on it cost.

**On Linux the kernel writes the RTC, not the shutdown.** With chrony's
`rtcsync` (on by default on Fedora) the kernel copies the system clock into
the RTC every 11 minutes while NTP is synchronized. It writes in the
convention it was given **at boot**: when `LocalRTC=yes`, systemd tells the
kernel during early boot and logs

```text
RTC configured in localtime, applying delta of 480 minutes to system time.
```

(480 minutes = UTC+08:00). When `LocalRTC=no` there is no such line. So
`timedatectl set-local-rtc` changes how the *next* boot reads the RTC, not
how the running kernel writes it: until the next reboot the kernel keeps the
old convention, and its next 11-minute write can undo the
`hwclock --systohc` that followed the change. That overwrite is inferred from
the kernel and systemd mechanism, not observed -- the change measured in
section 8 was followed by an immediate reboot. **Change `LocalRTC`, then
reboot at once**, and look for the line above.

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

The registry shows the value the **next** boot will use. The value the running
kernel uses was read at boot, and Windows logs it: every clock change (a sync,
a resume, a manual set) writes a `Kernel-General` event 1 whose XML carries
that value next to the raw RTC value.

```powershell
$e = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=1} -MaxEvents 1
$e.TimeCreated
([xml]$e.ToXml()).Event.EventData.Data |
  Where-Object Name -in 'NewTime','CmosTime','RealTimeIsUniversal' | Select-Object Name, '#text'
```

`RealTimeIsUniversal` there is `true` or `false`: the flag **in force** for
the boot that wrote the event. `CmosTime` is the RTC's raw value, printed
with a `Z` whatever it holds; compared with the true time from an independent
source (section 3.3) it shows which convention the RTC held. Do not compare
it with `NewTime` on a resume event: there `NewTime` was computed *from* the
RTC under the same flag, so the two always agree. The message text says the
same thing (`RTC time is in UTC: true`), but in the display language; the
XML field names do not change.

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

```bash
journalctl -b | grep -i 'configured in localtime'                # present only if this boot started with LocalRTC=yes
journalctl -b -u chronyd -u chrony | grep -E 'wrong by|stepped'   # how far off this boot started
```

The `hwclock` comparison shows what the *other* OS left in the RTC only until
this system's own first 11-minute write replaces it (section 1.1). After that
the RTC holds this system's write, and the two readings say nothing about the
other side. chrony's first correction is the lasting record: `System clock
wrong by 28799.x seconds` (or `-28800.x`) at this boot means the OS that ran
before it left the RTC in the other convention; a second or two is drift.

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
> right one is the one that matches what the RTC *currently* holds. On Linux,
> `hwclock --show` and `hwclock --show --utc` read the same hardware clock
> under the two conventions -- whichever agrees with `date` is the convention
> the RTC is effectively in. On the machine this document was written on, the
> answer is **UTC**, so Option B applies -- and it applies to *both* sides,
> because the RTC's content is decided by whoever wrote it last, not by the
> reader. Measure again after any change of writer: a manual clock set or a
> shutdown from the other OS can flip it.

> **Read the other side before changing this one.** Before touching
> `LocalRTC`, read `RealTimeIsUniversal` on Windows -- the registry value and
> the value in force (section 3.1) -- and the reverse. Each side can pass all
> of its own checks while the contract is broken: section 8, incident 3, is a
> Linux-side change that passed every Linux-side probe and put the next
> Windows boot 8 hours out.

### Option A -- the RTC holds local time

```powershell
# Windows: read and keep the RTC as local time (takes effect at the next restart)
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -Value 0
```

```bash
# Linux: read and write the RTC as local time
sudo timedatectl set-local-rtc 1
sudo hwclock --systohc --localtime     # write the current (correct) time back
sudo systemctl reboot                  # at once: until then the kernel writes the old convention
# after the reboot
journalctl -b | grep -i 'configured in localtime'   # must be present
hwclock --show --localtime             # must match `date`, also 12 minutes after NTP sync
```

### Option B -- the RTC holds UTC

```powershell
# Windows: read and keep the RTC as UTC (takes effect at the next restart)
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -Value 1
```

```bash
# Linux: read and write the RTC as UTC
sudo timedatectl set-local-rtc 0
sudo hwclock --systohc --utc           # write the current (correct) time back
sudo systemctl reboot                  # at once, as above
# after the reboot
journalctl -b | grep -i 'configured in localtime'   # must print nothing
hwclock --show --utc                   # must match `date -u`, also 12 minutes after NTP sync
```

Option B matches the Linux default (`LocalRTC=no`) and the common BIOS default
(UTC). Option A matches the Windows default. **Either is fine; mixing them is
the bug.** Whatever is chosen, record it in the install notes -- it is the one
piece of the dual-boot contract that no tool can read for you.

### A fresh Linux install next to Windows

When the choice is still open, prefer **Option B (UTC)**:

- It is every distribution's default, so a reinstall of the Linux side keeps
  the contract with nothing to redo. Option A has to be re-applied after every
  Linux reinstall, with the reboot of section 1.1.
- `timedatectl` itself warns that an RTC in local time "cannot be fully
  supported".
- The cost is one registry value on Windows (`RealTimeIsUniversal = 1`), set
  once and re-set only after a Windows reinstall.

An installer can choose local time on its own when it finds Windows on the
disk, and does not always ask. Whatever it showed, check after the first boot:

```bash
timedatectl show -p LocalRTC        # expect no, for Option B
```

Then run the cross-system round of section 7 once before trusting it.

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

### 5.1 The policy on machine A (Windows + Fedora)

The deliberate choice here, written down so the next reader does not have to
rediscover it:

| Setting | Value | Why |
| :--- | :--- | :--- |
| W32Time service | `Disabled`, stopped | Automatic repair is **off on purpose**. A clock that is quietly patched hides the fault; the operator wants to find the cause instead of inheriting a corrected symptom |
| `Type` under `...\W32Time\Parameters` | `NoSync` | The second half of what the Settings toggle writes -- both are needed to keep the service off |
| NTP peers | still in `NtpServer` | Left in place, so the service can be re-enabled with one command and so `w32tm /stripchart` still has a target to measure against |
| RTC convention | **UTC on both sides** -- `RealTimeIsUniversal = 1` on Windows, `LocalRTC = no` on Linux | Measured, not assumed: the raw RTC value equals **UTC** (section 8, incident 2), and weeks of Windows events show the RTC kept in UTC under flag `1` (section 1.1). Windows is in the right mode as found -- **do not change `RealTimeIsUniversal`**. The Linux side is the distro default and needs no change either; a reinstall keeps it, but check (section 4). Verify it with `timedatectl show -p LocalRTC` (expect `no`) and `hwclock --show --utc` (must equal `date -u`). Re-verified the hard way on 2026-11-21 (section 8, incident 3) |
| Fast startup | disabled | Section 6 |
| Time zone | a fixed UTC+08:00 zone, no DST | |

The cost of the first two rows is accepted and measured: the clock free-runs
(about 1.7 s per day on this class of hardware). The RTC convention is the one
setting that must **not** be changed on a hunch: it is read at boot, and
getting it wrong costs a full 8 hours at every startup (section 8, incident 2).

The probe script exists for the same reason. It reports the state of the
machine at any moment, so the operator can tell "the fault is still there"
from "the fault was fixed an hour ago and I did not notice" -- which is
exactly what a self-healing clock looks like from the outside.

### 5.2 Machine B (Windows + Linux Mint)

A second machine, measured read-only on 2026-11-21. It runs the other
convention, and its Windows side is consistent with it:

| Setting | Value |
| :--- | :--- |
| RTC convention, Windows side | **local time** -- `RealTimeIsUniversal` absent (= `0`); `Kernel-General` event 1 shows `RealTimeIsUniversal=false` in force, and the RTC held the true local time at every boot and resume the log covers (two weeks) |
| RTC convention, Linux side | **not measured yet** -- it must be `LocalRTC = yes` to match. With `no`, every Windows boot that follows a Mint session starts 8 hours behind (section 2) |
| W32Time service | `Automatic`, running, `Type = NTP` -- an 8-hour error would be corrected after boot, but it would still leave a `Kernel-General` event 1 with a change near the zone offset; none was logged |
| Fast startup | **on** at the first measurement, turned off the same day |
| Time zone | a fixed UTC+08:00 zone, no DST |

If the Mint side turns out to be `LocalRTC = no`, move this machine to UTC on
both sides (Option B) rather than changing Mint: it is the convention machine
A has proven, and it survives a reinstall of the Linux side.

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
# and the value in force for this boot (section 3.1)              # expect: the same as the registry
```

**Linux**

```bash
timedatectl show -p LocalRTC -p NTPSynchronized
# the chosen convention: --utc here, --localtime for the local one
hwclock --show --utc       # must equal `date -u`; with --localtime it must equal `date`
journalctl -b | grep -i 'configured in localtime'                # present exactly when LocalRTC=yes
journalctl -b -u chronyd -u chrony | grep -E 'wrong by|stepped'   # no correction near the zone offset
```

**Cross-system**

```text
1. `date` in Linux and the clock in Windows agree, to the minute
2. Reboot into the other system, repeat -- the agreement survives the reboot;
   on Linux, read chrony's correction for that boot as well
3. The measured offset stays under a second after both sides are up
4. After a LocalRTC change: reboot at once, and check the RTC again 12 minutes
   after NTP synchronization -- the kernel's own RTC write has happened by then
```

Step 2 is the one that catches the RTC convention bug: **a clock that is only
correct until the next reboot is not fixed.** Run it in both directions --
Linux to Windows and Windows to Linux -- because each direction tests the other
side's write.

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

## 8. Three incidents, measured

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
6. So the RTC held local time: a pre-sync system clock of `19:22:59` with
   Windows adding `+08:00` to a UTC-valued RTC means the hardware clock held
   `11:22:59`. At that moment the true local time was `11:22:49` and the true
   UTC was `03:22:49`, so the RTC was **8 hours ahead of UTC** -- it held local
   time. Whoever wrote it last had written local time.

**Incident 2 -- the same machine, one day later, and the opposite error.**

`RealTimeIsUniversal` was changed to `0` on the strength of finding 6, with
the reasoning "the RTC holds local time, so Windows should read it as local
time". The next boot showed the clock **8 hours behind**: `09:03` when the true
local time was `17:03`. Three independent `Date:` headers and an NTP
`stripchart` agreed on the true time; the machine clock was showing **UTC**.

**The measurement that settled it:** the RTC was read as UTC, so the clock
displayed exactly the RTC's value, and that value tracked true UTC to within a
few seconds (the boot stamp `08:14:38` was the true UTC at that moment). The
RTC was therefore holding **UTC**, not local time. Finding 6 was right about
the 10-23 boot and wrong about the RTC in general: the RTC's content depends on
**who wrote it last**, and a manual clock set (or a shutdown from an OS whose
convention differs) is enough to flip it.

**Incident 3 -- a one-sided change, 2026-11-21.**

On the strength of the "Windows writes local time whatever the flag" reading
(section 1.1), the Linux side of this machine (machine A) was moved to local
time:
`timedatectl set-local-rtc 1`, `hwclock --systohc --localtime`, then an
immediate reboot. Every Linux-side check passed:

- the boot logged `RTC configured in localtime, applying delta of 480 minutes`;
- chrony logged no correction at that boot, and `date` matched an HTTP `Date`
  header;
- 17 minutes after NTP synchronization, `hwclock --show --localtime` still
  matched `date` to a second, and the probe reported `RTC convention OK`.

The next Windows boot came up **28,801 s ahead**. Its flag was `1`, and nobody
had read it before the change: Windows read the local-time RTC as UTC and
added the zone. With the time service disabled, nothing corrected it -- the
error was on screen at once, as section 5.1 intends.

The same Windows log showed why the old setup had worked: two weeks of
`Kernel-General` events with `RealTimeIsUniversal=true` and the RTC holding the
true UTC. The Linux side was put back to `LocalRTC = no`, rebooted at once,
and its probe passes again.

**Lesson.** Four lessons, all about the same contract:

1. **The flag is read at boot.** Changing `RealTimeIsUniversal` while the
   machine is running changes nothing until the next reboot -- and the *old*
   value is still in force for the shutdown write that happens in between. A
   change made at 12:52 sat unnoticed until the next reboot, and then cost 8
   hours at every startup.
2. **Measure the RTC, do not infer it.** The decisive test is on the Linux
   side, where the same hardware clock can be read under both conventions:
   `hwclock --show` and `hwclock --show --utc`. On Windows the equivalent is
   the boot stamp: the first time-service event of a boot carries the clock as
   it was, so `display = RTC + zone` (flag 1) or `display = RTC` (flag 0)
   gives the RTC's value directly. `Kernel-General` event 1 states the flag in
   force and the raw RTC value outright (section 3.1).
3. **Read the other side before changing this one.** A probe sees one side,
   and each side can pass all of its own checks while the contract is broken.
   Only the other side's flag, read *before* the change, and a boot into the
   other system *after* it, show the contract.
4. **A `LocalRTC` change needs an immediate reboot.** The running kernel keeps
   writing the RTC in the convention it was given at boot (section 1.1).

**Which side to fix.** The measurement decides it, and the answer here is
**neither**: the contract is **UTC on both sides**, which is what both systems
already do. `RealTimeIsUniversal = 1` on Windows, `LocalRTC = no` on Linux. The
distros were never wrong, and the Windows flag was right until it was changed
on a wrong inference. The only thing that was actually broken was the
**automatic correction** (the disabled time service), and that is a deliberate
choice with a measured cost -- a free-running clock, roughly 1.7 s per day.

---

## 9. Related

- [`../windows/README.md`](../windows/README.md) -- the Windows side of this repo
- [`../linux-desktop/README.md`](../linux-desktop/README.md) -- the native Linux side
- [`../wsl/setup/README.md`](../wsl/setup/README.md) -- WSL: a third clock source, but it shares the Windows kernel's clock, so none of the RTC rules apply to it
- [`files/README.md`](files/README.md) -- the read-only probe scripts
