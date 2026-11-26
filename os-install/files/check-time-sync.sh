#!/usr/bin/env bash
# check-time-sync.sh -- report the state of the Linux clock and of the RTC
# convention it shares with a dual-booted second operating system.
#
# READ-ONLY. This script never changes a setting, never writes the RTC
# (no `hwclock --systohc`), and never starts or stops a service. It reports,
# and a human decides.
#
# Exit codes:
#   0  no finding
#   1  at least one finding (WARN or FAIL)
#   2  a probe could not run (no timedatectl, no RTC access, no network)
#
# Usage:
#   bash check-time-sync.sh
#   bash check-time-sync.sh --http-host www.example.com
#
# What it checks:
#   1. the clock mode (LocalRTC), the time zone and the NTP state
#   2. the RTC read under both conventions, compared with the system clock
#   3. who writes the RTC from this side: chrony's rtcsync, and whether the
#      convention the kernel was given at boot still matches LocalRTC
#   4. the measured offset against an NTP server (chrony or systemd-timesyncd),
#      with a remote HTTPS Date header as the fallback when neither reports one
#   5. how far off this boot started (chrony's first correction) -- the lasting
#      record of what the OS that ran before this boot left in the RTC
#   6. the dual-boot contract, printed as the value the other OS must match
#
# Companion: check-time-sync.ps1 (same checks, Windows side).

set -uo pipefail

HTTP_HOST="www.microsoft.com"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --http-host)
            HTTP_HOST="${2:-}"
            shift 2
            ;;
        -h|--help)
            # the header comment, from line 2 to the first line that is not one
            sed -n '2,/^[^#]/{/^#/p}' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

WARN=0
FAIL=0
SKIP=0
# What the RTC physically holds: "local", "utc", or "" when it cannot be
# determined (no hwclock, no permission, or the RTC is stale).
rtc_holds=""
# 1 once the RTC was actually read under both conventions.
rtc_read=0

# This machine's UTC offset in seconds (east positive), from `date +%z`. It
# names a boot-time error of exactly one zone: the RTC written in the other
# convention.
zone_hhmm="$(date +%z)"
zone_sign=1
[ "${zone_hhmm:0:1}" = "-" ] && zone_sign=-1
zone_s=$(( zone_sign * ( 10#${zone_hhmm:1:2} * 3600 + 10#${zone_hhmm:3:2} * 60 ) ))
zone_abs=$(( zone_s < 0 ? -zone_s : zone_s ))

section() {
    echo
    echo "== $1 =="
}

# level, check, detail
report() {
    local level="$1" check="$2" detail="$3"
    case "$level" in
        OK)   printf 'OK    %-22s %s\n' "$check" "$detail" ;;
        INFO) printf 'INFO  %-22s %s\n' "$check" "$detail" ;;
        WARN) printf 'WARN  %-22s %s\n' "$check" "$detail"; WARN=$((WARN + 1)) ;;
        FAIL) printf 'FAIL  %-22s %s\n' "$check" "$detail"; FAIL=$((FAIL + 1)) ;;
        SKIP) printf 'SKIP  %-22s %s\n' "$check" "$detail"; SKIP=$((SKIP + 1)) ;;
    esac
}

# ---------------------------------------------------------------- 1. mode
section "Clock mode"

if command -v timedatectl >/dev/null 2>&1; then
    td_out="$(timedatectl show 2>/dev/null)"
    local_rtc="$(printf '%s\n' "$td_out" | sed -n 's/^LocalRTC=//p')"
    ntp_sync="$(printf '%s\n' "$td_out" | sed -n 's/^NTPSynchronized=//p')"
    timezone="$(printf '%s\n' "$td_out" | sed -n 's/^Timezone=//p')"

    report INFO "Timezone" "$timezone"
    if [ "$local_rtc" = "yes" ]; then
        report INFO "LocalRTC" "yes -- this side reads the RTC as local time"
    elif [ "$local_rtc" = "no" ]; then
        report INFO "LocalRTC" "no -- this side reads the RTC as UTC"
    else
        report WARN "LocalRTC" "unknown (value: '${local_rtc}')"
    fi

    if [ "$ntp_sync" = "yes" ]; then
        report OK "NTPSynchronized" "yes"
    else
        report WARN "NTPSynchronized" "no -- the clock is not being corrected by NTP"
    fi
else
    report SKIP "timedatectl" "not found -- is this a systemd machine?"
    local_rtc="unknown"
    ntp_sync="unknown"
fi

# ---------------------------------------------------------------- 2. the RTC
section "RTC versus system clock"

if command -v hwclock >/dev/null 2>&1; then
    rtc_local="$(hwclock --show --localtime 2>&1)"
    rtc_utc="$(hwclock --show --utc 2>&1)"
    now_local="$(date '+%Y-%m-%d %H:%M:%S')"
    now_utc="$(date -u '+%Y-%m-%d %H:%M:%S')"

    if printf '%s' "$rtc_local" | grep -qi 'cannot\|permission\|denied\|access'; then
        report SKIP "hwclock" "cannot read the RTC -- run as root for this probe"
    else
        rtc_local_line="$(printf '%s\n' "$rtc_local" | head -1)"
        rtc_utc_line="$(printf '%s\n' "$rtc_utc" | head -1)"
        report INFO "RTC as local" "$rtc_local_line"
        report INFO "RTC as UTC"   "$rtc_utc_line"

        # The RTC holds one value; each reading interprets it differently.
        # Whichever reading agrees with the system clock is the convention the
        # RTC actually HOLDS. If neither agrees, the RTC is stale and the
        # convention cannot be determined from here.
        rtc_epoch_local="$(date -d "$rtc_local_line" +%s 2>/dev/null)"
        rtc_epoch_utc="$(date -d "$rtc_utc_line" +%s 2>/dev/null)"
        now_epoch_local="$(date -d "$now_local" +%s 2>/dev/null)"
        # `date -u -d`, not `date -d`: the string is a UTC wall clock, and
        # `date -d` parses it in the LOCAL zone. Parsing it as local shifts
        # the reference by the UTC offset, which doubles the reported distance
        # of the UTC reading and makes a correctly configured machine (RTC
        # holding UTC) look 8 hours out under BOTH readings.
        now_epoch_utc="$(date -u -d "$now_utc" +%s 2>/dev/null)"

        if [ -n "$rtc_epoch_local" ] && [ -n "$rtc_epoch_utc" ]; then
            rtc_read=1
            d_local=$((rtc_epoch_local - now_epoch_local))
            d_utc=$((rtc_epoch_utc - now_epoch_utc))
            report INFO "RTC minus system" "as local: ${d_local}s   as UTC: ${d_utc}s"

            best=""
            bestdiff=999999
            for pair in "local:$d_local" "utc:$d_utc"; do
                name="${pair%%:*}"
                value="${pair##*:}"
                abs=$((value < 0 ? -value : value))
                if [ "$abs" -lt "$bestdiff" ]; then
                    bestdiff="$abs"
                    best="$name"
                fi
            done

            if [ "$bestdiff" -le 2 ]; then
                report OK "RTC consistency" "the RTC agrees with the system clock under the '$best' reading (${bestdiff}s)"
                rtc_holds="$best"
            elif [ "$bestdiff" -le 300 ]; then
                report WARN "RTC consistency" "the RTC is ${bestdiff}s away from the system clock -- probably a slow drift, or a machine that was off for a while"
                rtc_holds=""
            else
                report FAIL "RTC consistency" "the RTC is ${bestdiff}s away from the system clock under BOTH readings -- the hardware clock is stale or holds a different date. Boot the other system and check its convention."
                rtc_holds=""
            fi
        fi
    fi
else
    report SKIP "hwclock" "not found (util-linux)"
fi

# ------------------------------------------------- 3. who writes the RTC here
section "Kernel RTC writes"

# Linux does not write the RTC at shutdown. With chrony's `rtcsync` the kernel
# copies the system clock into the RTC every 11 minutes while NTP is
# synchronized, in the convention systemd announced to it AT BOOT. A LocalRTC
# change made after boot does not reach those writes until the next reboot,
# so the next 11-minute write can undo a `hwclock --systohc`.
rtcsync_file=""
for f in /etc/chrony.conf /etc/chrony/chrony.conf; do
    if [ -r "$f" ] && grep -Eq '^[[:space:]]*rtcsync' "$f"; then
        rtcsync_file="$f"
        break
    fi
done
if [ -n "$rtcsync_file" ]; then
    report INFO "rtcsync" "on ($rtcsync_file) -- the kernel writes the RTC every 11 minutes while NTP is synchronized"
elif command -v chronyc >/dev/null 2>&1; then
    report INFO "rtcsync" "not set in the chrony config -- chrony does not ask the kernel to write the RTC"
else
    report INFO "rtcsync" "chrony not found -- whether the kernel writes the RTC depends on the NTP client (not checked)"
fi

# systemd logs this line at boot, and only when LocalRTC=yes: it is the moment
# the kernel is told that the RTC holds local time.
if command -v journalctl >/dev/null 2>&1; then
    pid1_log="$(journalctl -b _PID=1 -q --no-pager -o cat 2>/dev/null)"
    if [ -z "$pid1_log" ]; then
        report SKIP "Boot convention" "cannot read this boot's systemd log -- run as root for this probe"
    elif [ "$local_rtc" = "yes" ] || [ "$local_rtc" = "no" ]; then
        boot_local="no"
        printf '%s\n' "$pid1_log" | grep -q 'RTC configured in localtime' && boot_local="yes"
        if [ "$boot_local" = "$local_rtc" ]; then
            if [ "$boot_local" = "yes" ]; then
                report OK "Boot convention" "systemd told the kernel at boot that the RTC holds local time -- matches LocalRTC"
            else
                report OK "Boot convention" "the kernel was set up at boot for an RTC in UTC -- matches LocalRTC"
            fi
        else
            report WARN "Boot convention" "LocalRTC=$local_rtc now, but this boot started with LocalRTC=$boot_local -- the setting was changed after boot (or the journal no longer holds the boot messages). Until the next reboot the kernel keeps writing the RTC in the OLD convention: reboot now"
        fi
    fi
else
    report SKIP "Boot convention" "journalctl not found"
fi

# ------------------------------------------------------------- 4. the offset
section "Measured offset against NTP"

offset_found=0
if command -v chronyc >/dev/null 2>&1; then
    chrony_out="$(chronyc tracking 2>&1)"
    sys_line="$(printf '%s\n' "$chrony_out" | sed -n 's/^System time *: *//p')"
    last_line="$(printf '%s\n' "$chrony_out" | sed -n 's/^Last offset *: *//p')"
    if [ -n "$sys_line" ]; then
        offset_found=1
        report INFO "chrony" "system time: $sys_line   last offset: ${last_line:-unknown}"
        case "$sys_line" in
            *"second slow"*) report OK "NTP offset" "the clock is slow by $sys_line" ;;
            *"second fast"*) report OK "NTP offset" "the clock is fast by $sys_line" ;;
            *) report INFO "NTP offset" "$sys_line" ;;
        esac
    else
        report SKIP "chrony" "no tracking data (is chronyd running?)"
    fi
elif command -v timedatectl >/dev/null 2>&1; then
    ts_out="$(timedatectl timesync-status 2>&1)"
    if printf '%s' "$ts_out" | grep -q 'Synchronized'; then
        offset_found=1
        report INFO "systemd-timesyncd" "$(printf '%s' "$ts_out" | tr '\n' ' ' | head -c 200)"
        report OK "NTP offset" "synchronized; systemd-timesyncd does not report a signed offset"
    else
        report SKIP "timesync-status" "$(printf '%s' "$ts_out" | tr '\n' ' ' | head -c 200)"
    fi
else
    report SKIP "NTP client" "neither chronyc nor timedatectl timesync-status is available"
fi

if [ "$offset_found" -eq 0 ]; then
    # Last resort: ask a remote server for its own clock.
    if command -v curl >/dev/null 2>&1; then
        date_hdr="$(curl -sI --max-time 15 "https://$HTTP_HOST" 2>/dev/null | sed -n 's/^[Dd]ate: *//p' | tr -d '\r' | head -1)"
        if [ -n "$date_hdr" ]; then
            remote_epoch="$(date -u -d "$date_hdr" +%s 2>/dev/null)"
            local_epoch="$(date -u +%s)"
            if [ -n "$remote_epoch" ]; then
                delta=$((local_epoch - remote_epoch))
                abs=$((delta < 0 ? -delta : delta))
                if [ "$abs" -le 2 ]; then
                    report OK "HTTP Date" "the clock agrees with $HTTP_HOST (${delta}s)"
                elif [ "$abs" -le 60 ]; then
                    report WARN "HTTP Date" "the clock is ${delta}s away from $HTTP_HOST"
                else
                    report FAIL "HTTP Date" "the clock is ${delta}s away from $HTTP_HOST -- a timezone-scale error, check the RTC convention"
                fi
            fi
        else
            report SKIP "HTTP Date" "no Date header from $HTTP_HOST (no network?)"
        fi
    fi
fi

# --------------------------------------------- 5. how far off this boot started
section "This boot's start"

# The RTC comparison in section 2 shows what the other OS wrote only until
# this system's first 11-minute write replaces it. chrony's first correction
# is the lasting record: a correction of about one zone offset means the OS
# that ran before this boot left the RTC in the other convention.
if command -v chronyc >/dev/null 2>&1 && command -v journalctl >/dev/null 2>&1; then
    chrony_log="$(journalctl -b -u chronyd -u chrony -q --no-pager -o cat 2>/dev/null)"
    step_line="$(printf '%s\n' "$chrony_log" | grep -m1 'System clock wrong by')"
    if [ -n "$step_line" ]; then
        step_s="$(printf '%s\n' "$step_line" | sed -n 's/.*wrong by \(-\{0,1\}[0-9][0-9]*\).*/\1/p')"
        step_s="${step_s:-0}"
        step_abs=$(( step_s < 0 ? -step_s : step_s ))
        zone_gap=$(( step_abs - zone_abs ))
        zone_gap=$(( zone_gap < 0 ? -zone_gap : zone_gap ))
        if [ "$zone_abs" -gt 0 ] && [ "$zone_gap" -le 120 ]; then
            report FAIL "Boot offset" "this boot started one zone offset out (${step_s}s, chrony: '$step_line') -- the OS that ran before it left the RTC in the other convention. NTP corrected it, which is why the clock looks right now"
        elif [ "$step_abs" -le 2 ]; then
            report OK "Boot offset" "this boot started ${step_s}s from NTP time"
        elif [ "$step_abs" -le 300 ]; then
            report INFO "Boot offset" "this boot started ${step_s}s from NTP time -- drift, or a machine that was off for a while"
        else
            report WARN "Boot offset" "this boot started ${step_s}s from NTP time -- not a zone offset, but more than drift"
        fi
    elif [ -z "$chrony_log" ]; then
        report SKIP "Boot offset" "cannot read chrony's log for this boot -- run as root for this probe"
    else
        report OK "Boot offset" "chrony logged no correction this boot -- the clock started within its step threshold"
    fi
else
    report SKIP "Boot offset" "needs chrony and journalctl -- with systemd-timesyncd, compare date with an HTTP Date header right after boot instead"
fi

# ------------------------------------------------ 6. the dual-boot contract
section "Dual-boot contract"

# The contract is ONE convention that both systems read AND write. This side
# writes in the convention LocalRTC names (through the kernel, section 3), and
# Windows keeps the RTC in the convention its RealTimeIsUniversal names
# (measured on two machines: dual-boot-time-sync.md section 1.1). So the value
# the other OS must match follows from LocalRTC, not from the RTC's content:
# once this system has been synchronized for 11 minutes with rtcsync, the RTC
# holds this system's own write, whatever the other OS left there.
case "$local_rtc" in
    no)  report INFO "Contract" "LocalRTC=no: the RTC holds UTC -- the Windows side must have RealTimeIsUniversal=1" ;;
    yes) report INFO "Contract" "LocalRTC=yes: the RTC holds local time -- the Windows side must have RealTimeIsUniversal=0 (its default)" ;;
    *)   report INFO "Contract" "unknown -- check both sides by hand" ;;
esac

# Does the RTC's content match this side's setting? When it does not, the last
# writer used the other convention, and this side read it wrong at boot.
if [ -n "$rtc_holds" ] && { [ "$local_rtc" = "yes" ] || [ "$local_rtc" = "no" ]; }; then
    expected="local"
    [ "$local_rtc" = "no" ] && expected="utc"
    holds_text="local time"
    [ "$rtc_holds" = "utc" ] && holds_text="UTC"
    expected_text="local time"
    [ "$expected" = "utc" ] && expected_text="UTC"
    if [ "$rtc_holds" = "$expected" ]; then
        report OK "RTC convention" "the RTC holds $holds_text and this side reads it as $expected_text -- the two agree (after 11 synchronized minutes this is this side's own write, not evidence about the other OS)"
    else
        report FAIL "RTC convention" "the RTC holds $holds_text but this side reads it as $expected_text -- the last writer used the other convention: the other OS (its RealTimeIsUniversal does not match LocalRTC here), or a LocalRTC change not yet followed by a reboot. Pick one convention for both sides"
    fi
elif [ "$rtc_read" -eq 1 ] && [ -z "$rtc_holds" ]; then
    report INFO "RTC holds" "unknown (the RTC agrees with the system clock under neither reading) -- check the other side by hand"
fi

uptime_s="$(uptime -s 2>/dev/null)"
[ -n "$uptime_s" ] && report INFO "Boot time" "$uptime_s"

# ------------------------------------------------------------------ verdict
echo
echo "== Verdict =="
if [ "$FAIL" -gt 0 ]; then
    echo "RESULT: $FAIL failing, $WARN warning(s), $SKIP skipped. See the list above."
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "RESULT: $WARN warning(s), no failing check, $SKIP skipped."
    exit 1
else
    echo "RESULT: no finding ($SKIP skipped)."
    exit 0
fi
