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
#   3. the measured offset against an NTP server (chrony or systemd-timesyncd)
#   4. an independent cross-check against a remote HTTPS Date header
#   5. the dual-boot contract, printed as the value the other OS must match
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
            sed -n '2,30p' "$0"
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

# -------------------------------------------------------------- 3. the offset
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

# ------------------------------------------------ 4. the dual-boot contract
section "Dual-boot contract"

# The contract is a property of the HARDWARE CLOCK, not of this side's
# setting: the other OS has to read the RTC the way the RTC actually holds
# it. Derive it from the measurement when that is possible, and only fall
# back to the setting when it is not.
if [ -n "$rtc_holds" ]; then
    if [ "$rtc_holds" = "local" ]; then
        report INFO "RTC holds" "local time -- the other OS must use RealTimeIsUniversal=0"
    else
        report INFO "RTC holds" "UTC -- the other OS must use RealTimeIsUniversal=1"
    fi
else
    report INFO "RTC holds" "unknown (the RTC agrees with the system clock under neither reading) -- check the other side by hand"
fi

# Does this side's own setting match the content of the RTC? When it does
# not, this side's clock is out by the UTC offset -- the dual-boot fault.
if [ -n "$rtc_holds" ] && [ "$local_rtc" != "unknown" ]; then
    expected="local"
    [ "$local_rtc" = "no" ] && expected="utc"
    holds_text="$rtc_holds time"
    [ "$rtc_holds" = "utc" ] && holds_text="UTC"
    expected_text="$expected time"
    [ "$expected" = "utc" ] && expected_text="UTC"
    if [ "$rtc_holds" = "$expected" ]; then
        report OK "RTC convention" "the RTC holds $holds_text and this side reads it as $expected_text -- the two agree"
    else
        report FAIL "RTC convention" "the RTC holds $holds_text but this side is configured to read it as $expected_text -- this side's clock is out by the UTC offset, and the other OS must use RealTimeIsUniversal=$( [ "$rtc_holds" = "utc" ] && echo 1 || echo 0 )"
    fi
elif [ "$local_rtc" = "yes" ]; then
    report INFO "Contract" "this side reads the RTC as LOCAL time; if the RTC really holds local time, the other OS must use RealTimeIsUniversal=0"
elif [ "$local_rtc" = "no" ]; then
    report INFO "Contract" "this side reads the RTC as UTC; if the RTC really holds UTC, the other OS must use RealTimeIsUniversal=1"
else
    report INFO "Contract" "unknown -- check the other side by hand"
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
