---
name: android-miui-settings
description: >-
  Inspect, configure, and automate Android and Xiaomi MIUI / HyperOS system settings
  (system, secure, global) directly from within a root Debian chroot container.
  Use when managing Private DNS (DoT), display refresh rate (60Hz/90Hz/120Hz),
  disabling Android 12/13/14 Phantom Process Killer limits, tuning Xiaomi PowerKeeper
  background policies, optimizing Doze battery whitelist, managing Do Not Disturb
  (DND) and stream volumes, simulating UI input, taking screenshots, or creating settings
  backup snapshots via targeted nsenter -m.
allowed-tools: Bash Read
argument-hint: "[command] [namespace] [key] [value]"
arguments: [action, namespace, key]
---

# Android and Xiaomi MIUI / HyperOS Settings Automation Guide

When running AI coding agents (Claude Code, Antigravity CLI / `agy`) inside a rooted Android chroot environment (Termux Debian), accessing the host Android settings database (`SettingsProvider`) is essential for network automation, DoT configuration, background process survival, and display tuning.

However, invoking Android's `/system/bin/settings` directly fails due to Bionic dynamic linker conflicts, Magisk tmpfs overrides, and Linker Namespace isolation. This skill provides a solution via targeted **Mount Namespace penetration (`nsenter -t 1 -m`)**.

---

## 1. Quick Execution via `miui-settings.sh`

> **Paths.** Installed copies exist at `~/.gemini/config/skills/android-miui-settings/` and `/root/vibe-coding-pitfalls-private/agent/skills/android-miui-settings/`. Running `bash <skill-dir>/scripts/miui-settings.sh` works out-of-the-box.

### 1.1 Private DNS (DoT) Automation
Android's Private DNS encrypts DNS traffic using DNS-over-TLS (DoT). Configure it instantly:

```bash
# Check current Private DNS mode, hostname, and ConnectivityService TLS validation
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns status

# Switch to AliDNS DoT (dns.alidns.com)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns ali

# Switch to Tencent DNSPod DoT (dot.pub)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns dnspod

# Switch to Cloudflare or Google DoT
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns cloudflare
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns google

# Set custom DoT hostname
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns hostname <your-domain>

# Revert to Automatic (opportunistic) mode or turn off
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns auto
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns off
```

---

### 1.2 Phantom Process Killer Management (Android 12/13/14)
Android's `PhantomProcessKiller` strictly caps spawned subprocesses (Termux bash, compilers, Python, uv, subagents) to 32 per app before sending `SIGKILL`.

```bash
# Check current monitor state, max limit, and live ActivityManager settings
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh phantom status

# Completely disable phantom process monitoring and maximize process limit (2147483647)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh phantom disable

# Set custom limit (e.g. 512, 1024)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh phantom limit 1024

# Re-enable stock monitoring
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh phantom enable
```

---

### 1.3 Display Refresh Rate Control (MIUI / HyperOS Priority Vote)
MIUI / HyperOS enforces a proprietary `PRIORITY_MIUI_REFRESH_RATE` vote in `DisplayModeDirector`. Setting AOSP `peak_refresh_rate` alone is insufficient. This script updates both `secure miui_refresh_rate`, `secure user_refresh_rate`, and `system is_smart_fps`:

```bash
# Check current refresh rate settings and active DisplayModeDirector votes
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate status

# Lock constant 120Hz (disables smart dynamic drop to 60/30/1Hz)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate 120

# Switch to 90Hz or 60Hz
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate 90
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate 60

# Restore dynamic smart FPS
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate auto
```

---

### 1.4 System Animation Scales
Speed up UI transitions or disable animations for headless / VNC / remote operation:

```bash
# Check current animation scales
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh animation status

# Set to 0.5x (Fast)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh animation fast

# Disable animations completely (0.0x)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh animation off

# Restore stock 1.0x
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh animation normal
```

---

### 1.5 Xiaomi PowerKeeper & Doze Battery Optimization
Prevent background service kills during long-running tasks:

```bash
# Restrict PowerKeeper AppOps (RUN_IN_BACKGROUND ignore)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh powerkeeper restrict
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh powerkeeper status

# Add Termux to Doze battery whitelist
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh doze whitelist com.termux
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh doze status
```

---

### 1.6 Do Not Disturb (DND) & Audio Stream Volumes
Manage notification interruption policies, Zen mode ringer, and audio streams:

```bash
# Check current Zen mode, ringer mode, and notification policy
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dnd status

# Enable Contacts-Only ringing policy (priority mode + normal ringer + unmuted media)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dnd contacts-only

# Turn DND completely on or off
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dnd on
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dnd off

# Inspect all audio stream volumes (Media, Ringtone, Alarm, Notification)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh volume status

# Adjust specific stream volume
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh volume media 75
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh volume ring 10
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh volume alarm 12
```

---

### 1.7 One-Click Presets
Apply curated optimization sets for specific operating modes:

```bash
# Full performance preset for AI Coding Agents:
# Disables phantom killer (limit=max), locks 120Hz, sets 0.5x animations, restricts PowerKeeper, whitelists Termux
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh preset performance

# Balanced preset: phantom limit 512, dynamic 120Hz, 0.5x animations
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh preset balanced

# Battery saver preset: 60Hz, 1.0x animations, phantom limit 128
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh preset battery

# Restore factory stock settings
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh preset stock
```

---

### 1.8 UI Interaction & Screen Capture
Safely interact with Android apps and capture screen state:

```bash
# Check currently focused window and activity (safety check before input simulation)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh input focus

# Tap at coordinates (x y) -- warns if Termux is in foreground
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh input tap 500 1000

# Swipe gesture
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh input swipe 500 1500 500 500 300

# Key events (26=POWER, 3=HOME, 4=BACK, 187=APP_SWITCH)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh input key 4

# Capture screen directly into container directory (auto-translates storage paths)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh screencap /root/md/screen.png
```

---

### 1.9 Full Settings Backup & Rollback
Export and restore all settings (`global`, `system`, `secure`) via structured JSON:

```bash
# Export complete snapshot (~880+ settings) with device metadata
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh backup /root/md/settings_backup.json

# Dry-run restore check
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh restore /root/md/settings_backup.json --dry-run

# Selective restore
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh restore /root/md/settings_backup.json --dns
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh restore /root/md/settings_backup.json --display
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh restore /root/md/settings_backup.json --animation
```

---

### 1.10 General Settings Query and Manipulation
Android separates settings into three tables: `global`, `secure`, and `system`.

```bash
# Read a setting
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh get global private_dns_mode
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh get system screen_off_timeout

# Write a setting
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh put system screen_off_timeout 600000

# Delete an override key
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh delete global http_proxy

# List all keys in a table with regex filtering
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh list global dns
```

---

## 2. Technical Pitfalls & Forensics Summary

Detailed technical forensics are documented in [`references/bionic-namespace-and-settings-pitfalls.md`](references/bionic-namespace-and-settings-pitfalls.md).

| Trap | Symptom | Root Cause | Solution |
| :--- | :--- | :--- | :--- |
| **Bionic Linker Mismatch** | `cannot execute: required file not found` | ELF binaries need `/system/bin/linker64` | `nsenter -t 1 -m` mounts real host `/system` |
| **Magisk Stub Collisions** | `CANNOT LINK EXECUTABLE: libutils.so >= 0` | Magisk tmpfs overrides `/system/lib64` with 0-byte stubs | Mount namespace penetration accesses real libraries |
| **Full Namespace Failure** | `reassociate to namespaces failed: Invalid argument` | Kernel forbids PID/user reassociation for multithreaded callers | Enter **only Mount Namespace (`-m`)** |
| **MIUI Refresh Rate Override** | 120Hz drops to 60/30Hz despite AOSP settings | `DisplayModeDirector` prioritizes `PRIORITY_MIUI_REFRESH_RATE` | Set `secure miui_refresh_rate 120` & `system is_smart_fps 0` |
| **Phantom Process Killer** | Termux subagents/compilers killed (`SIGKILL`) | Android 12+ caps background subprocesses to 32 | `settings put global settings_enable_monitor_phantom_procs false` + `max_phantom_processes 2147483647` |
| **Storage Path Disparity** | Screencap writes fail or files missing in Debian | Host `/sdcard` maps to `/android/storage/emulated/0` | Script translates container paths via temporary host transfer |
| **Input Focus Trap** | Touch taps misfire into terminal soft keyboard | Events dispatch to current `mCurrentFocus` (Termux) | Script audits focus window and warns before touch dispatch |

---

## 3. Verified Settings Reference Matrix

| Setting Key | Table | Typical Values | Description |
| :--- | :--- | :--- | :--- |
| `private_dns_mode` | `global` | `off`, `opportunistic`, `hostname` | Private DNS (DoT) mode: off, auto, or custom |
| `private_dns_specifier` | `global` | `dns.alidns.com`, `dot.pub` | Domain of the DoT provider |
| `settings_enable_monitor_phantom_procs` | `global` | `true`, `false` | Android 12+ Phantom Process Killer monitor toggle |
| `max_phantom_processes` | `device_config` (am) | `32` (default), `2147483647` | ActivityManager phantom process threshold |
| `miui_refresh_rate` | `secure` | `60`, `90`, `120` | Xiaomi framework display mode vote |
| `user_refresh_rate` | `secure` | `60`, `90`, `120` | Display refresh rate mode selected by user |
| `peak_refresh_rate` | `system` | `60.0`, `90.0`, `120.0` | AOSP peak refresh rate limit |
| `min_refresh_rate` | `system` | `60.0`, `120.0` | AOSP minimum refresh rate floor |
| `is_smart_fps` | `system` | `0` (disabled), `1` (enabled) | Xiaomi smart dynamic refresh rate switching |
| `window_animation_scale` | `global` | `0.0`, `0.5`, `1.0` | Window animation transition speed |
| `transition_animation_scale` | `global` | `0.0`, `0.5`, `1.0` | Activity transition animation speed |
| `animator_duration_scale` | `global` | `0.0`, `0.5`, `1.0` | Application animator duration scale |
| `screen_off_timeout` | `system` | `60000` (1m), `600000` (10m) | Display sleep timeout in milliseconds |
| `zen_mode` | `global` | `0` (off), `1` (priority), `2` (silence), `3` (alarms) | Android Zen Mode / DND state |
| `mode_ringer` | `global` | `0` (silent), `1` (vibrate), `2` (normal) | Global ringer mode |
| `quiet_mode_enable` | `secure` | `0`, `1` | MIUI Quiet Mode toggle |
| `airplane_mode_on` | `global` | `0`, `1` | Airplane mode toggle |
| `http_proxy` | `global` | `:0` (disabled) or `host:port` | Global Android HTTP proxy |
