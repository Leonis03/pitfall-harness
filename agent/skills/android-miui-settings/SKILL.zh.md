---
name: android-miui-settings-zh
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

# Android 与 小米 MIUI / HyperOS 系统设置自动化运维指南

在已 Root 的 Android 设备（Termux Debian chroot 容器）上运行 AI Agent（Claude Code、Antigravity CLI / `agy`）或后端编译服务时，常常需要操作宿主系统的 `SettingsProvider` 数据库（如自动化配置 DoT 私人 DNS、彻底关闭幽灵进程查杀、锁定 120Hz 高刷新率、收紧 PowerKeeper 保活、全量备份还原系统设置）。

然而，由于 Android 原生 Bionic libc 动态链接器、Magisk tmpfs 库覆写以及 Linker Namespace 隔离的综合影响，在 chroot 容器内直接调用宿主 `/system/bin/settings` 会连续引发崩溃。本 Skill 提炼真实探索中的排错经验，提供基于**针对性 Mount Namespace 穿透（`nsenter -t 1 -m`）**的解决方案。

---

## 1. 运行 `miui-settings.sh`

> **路径规范**：技能已安装部署于 `~/.gemini/config/skills/android-miui-settings/` 以及 `/root/vibe-coding-pitfalls-private/agent/skills/android-miui-settings/`。

### 1.1 私人 DNS (DoT) 快速配置与验证
Android 的私人 DNS 功能通过 DNS-over-TLS (DoT) 对全系统 DNS 进行加密传输，内置主流服务商别名：

```bash
# 查询当前私人 DNS 模式、域名以及 ConnectivityService 实际 TLS 握手状态
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns status

# 一键切换为阿里公共 DoT (dns.alidns.com)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns ali

# 一键切换为腾讯 DNSPod DoT (dot.pub)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns dnspod

# 一键切换为 Cloudflare 或 Google DoT
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns cloudflare
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns google

# 设置自定义 DoT 服务商域名
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns hostname <custom-domain>

# 恢复为自动模式 (Auto / Opportunistic) 或彻底关闭
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns auto
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dns off
```

---

### 1.2 幽灵进程查杀管理 (Android 12/13/14 Phantom Process Killer)
Android 12+ 引入的 PhantomProcessKiller 限制每个应用派生子进程不超过 32 个，会导致 Termux 中的长时间编译、Python 进程、多线程 Subagent 被系统强制 `SIGKILL`：

```bash
# 查询当前监控状态、上限值及实时 ActivityManager 状态
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh phantom status

# 彻底关闭幽灵进程查杀，并将进程数上限扩展至最大整型 (2147483647)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh phantom disable

# 自定义幽灵进程数上限 (例如 512, 1024)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh phantom limit 1024

# 恢复系统原生幽灵进程监控
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh phantom enable
```

---

### 1.3 屏幕高刷新率精准控制 (MIUI / HyperOS 专有投票通道)
MIUI / HyperOS 在 `DisplayModeDirector` 中内置了专有的最高优先级投票 `PRIORITY_MIUI_REFRESH_RATE`。仅修改 AOSP 的 `peak_refresh_rate` 会被系统框架覆盖。本脚本实现跨表联动（同时设置 `secure miui_refresh_rate`、`secure user_refresh_rate` 与 `system is_smart_fps`）：

```bash
# 查看当前屏幕刷新率配置与 DisplayModeDirector 实时生效投票
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate status

# 锁定全域恒定 120Hz 高刷 (强行关闭打字或静止时的智能动态降频)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate 120

# 切换为 90Hz 或 60Hz 节能模式
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate 90
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate 60

# 恢复 MIUI 智能动态帧率调节
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh refresh-rate auto
```

---

### 1.4 系统过渡动画缩放 (动画延迟调优)
可缩短或关闭系统窗口、切换与控件动画，显著提升操作响应速度，适用于无头环境或远程控制：

```bash
# 查看当前动画缩放倍率
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh animation status

# 开启极速动画 (0.5x)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh animation fast

# 完全关闭动画 (0.0x)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh animation off

# 恢复默认 1.0x
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh animation normal
```

---

### 1.5 小米神隐后台与 Doze 电池白名单
```bash
# 收紧小米 PowerKeeper 权限 (禁止其在后台随意杀死服务)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh powerkeeper restrict
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh powerkeeper status

# 将 Termux 加入 Doze 白名单，防止锁屏休眠断网
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh doze whitelist com.termux
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh doze status
```

---

### 1.6 免打扰 (DND / Zen Mode) 与音频流音量管理
精准控制系统免打扰打扰策略、重要联系人来电放行及各通道音量：

```bash
# 查看当前免打扰 (Zen Mode)、铃声模式与活动通知策略
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dnd status

# 开启「仅联系人响铃」免打扰策略 (Priority 优先级模式 + 铃声开 + 媒体音量保底)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dnd contacts-only

# 开启全免打扰或恢复正常响铃
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dnd on
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh dnd off

# 检查全部音频流音量 (媒体 STREAM_MUSIC、铃声 STREAM_RING、闹钟 STREAM_ALARM、通知 STREAM_NOTIFICATION)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh volume status

# 调节指定音频流音量
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh volume media 75
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh volume ring 10
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh volume alarm 12
```

---

### 1.7 场景预设一键配置 (Presets)
针对不同工作场景提供一键调优：

```bash
# AI Coding Agent 性能预设：
# 解除幽灵进程 (上限设为最大)、强锁 120Hz、开启 0.5x 极速动画、限制 PowerKeeper、加入 Doze 白名单
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh preset performance

# 均衡预设 (Balanced)：512 进程上限、动态 120Hz、0.5x 动画
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh preset balanced

# 省电预设 (Battery)：60Hz、1.0x 动画、128 进程上限
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh preset battery

# 恢复出厂默认设置 (Stock)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh preset stock
```

---

### 1.8 UI 交互模拟与跨容器截图
通过命令行自动化操作宿主界面并回传图片：

```bash
# 审计当前宿主前台焦点窗口 (防止在 Termux 窗口误触发软键盘事件)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh input focus

# 点击屏幕坐标 (若 Termux 为前台焦点会自动输出安全告警)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh input tap 500 1000

# 滑动手势
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh input swipe 500 1500 500 500 300

# 模拟按键 (26=电源, 3=Home, 4=返回, 187=多任务)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh input key 4

# 一键截图到 Debian 容器本地路径 (自动处理宿主与容器存储重定向)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh screencap /root/md/screen.png
```

---

### 1.9 系统设置全量快照备份与定向还原
将全系统 880+ 项配置导出为标准化 JSON 文件并支持精准回滚：

```bash
# 全量导出 JSON 快照 (包含设备型号、系统版本及 global/system/secure 三表)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh backup /root/md/settings_backup.json

# 预检演练模式 (Dry-Run)，仅打印将执行的变更而不实际写入
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh restore /root/md/settings_backup.json --dry-run

# 定向回滚子系统
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh restore /root/md/settings_backup.json --dns
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh restore /root/md/settings_backup.json --display
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh restore /root/md/settings_backup.json --animation
```

---

### 1.10 常规键值查询与操作
Android 系统设置分为三大独立表：`global`（全局）、`secure`（安全敏感）、`system`（用户偏好）：

```bash
# 读取键值
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh get global private_dns_mode
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh get system screen_off_timeout

# 写入键值
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh put system screen_off_timeout 600000

# 删除覆写键值 (恢复系统初始默认)
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh delete global http_proxy

# 列出指定表键值并支持正则过滤
bash ~/.gemini/config/skills/android-miui-settings/scripts/miui-settings.sh list global dns
```

---

## 2. 底层架构与排错踩坑矩阵

完整取证分析详见 [`references/bionic-namespace-and-settings-pitfalls.md`](references/bionic-namespace-and-settings-pitfalls.md)。

| 踩坑场景 | 错误现象 | 底层根因 | 解决方案 |
| :--- | :--- | :--- | :--- |
| **动态链接器缺失** | `cannot execute: required file not found` | Android ELF 依赖 `/system/bin/linker64` | `nsenter -t 1 -m` 映射宿主原生 `/system` |
| **Magisk 桩文件冲突** | `CANNOT LINK EXECUTABLE: libutils.so >= 0` | Magisk tmpfs 覆写 `/system/lib64` 为 0 字节桩 | 挂载穿透直接访问真实系统库 |
| **全命名空间关联失败** | `reassociate to namespaces failed: Invalid argument` | 内核对多线程进程限制关联 PID/User 命名空间 | 仅穿透挂载命名空间（`-m`） |
| **MIUI 专有高刷覆盖** | AOSP 设为 120Hz 依然频繁掉帧至 60Hz/30Hz | MIUI 框架在 DisplayModeDirector 强制专有投票 | 联动设置 `secure miui_refresh_rate 120` 与 `system is_smart_fps 0` |
| **幽灵进程杀手** | 长期后台编译与 Subagent 进程被无故 `SIGKILL` | Android 12+ 限制应用子进程不超过 32 个 | `settings_enable_monitor_phantom_procs false` + 扩展上限至最大值 |
| **外置存储路径割裂** | Screencap 无法写入容器路径或文件丢失 | 宿主 `/sdcard` 对应 Debian 容器的 `/android/storage/emulated/0` | 脚本层自动中转并完成容器路径搬运 |
| **前台焦点输入陷阱** | `input tap` 误触手机本地 Termux 软键盘 | 事件分发至当前 `mCurrentFocus` | 执行前自动审计前台焦点并发出安全警示 |

---

## 3. 核心键值速查表

| 键名 | 所属表 | 常用推荐值 | 说明 |
| :--- | :--- | :--- | :--- |
| `private_dns_mode` | `global` | `off`, `opportunistic`, `hostname` | 私人 DNS 模式：关闭、自动、自定义服务商 |
| `private_dns_specifier` | `global` | `dns.alidns.com`, `dot.pub` | DoT 加密 DNS 服务商域名 |
| `settings_enable_monitor_phantom_procs` | `global` | `false`, `true` | Android 12+ 幽灵进程查杀监控总开关 |
| `max_phantom_processes` | `device_config` (am) | `2147483647`, `512` | 允许派生的子进程最大硬限制 |
| `miui_refresh_rate` | `secure` | `60`, `90`, `120` | 小米框架层显示刷新率模式指定 |
| `user_refresh_rate` | `secure` | `60`, `90`, `120` | 用户界面选定的刷新率 |
| `peak_refresh_rate` | `system` | `60.0`, `120.0` | AOSP 系统允许的最高刷新率上限 |
| `min_refresh_rate` | `system` | `60.0`, `120.0` | AOSP 系统允许的最低刷新率下限 |
| `is_smart_fps` | `system` | `0` (关闭), `1` (开启) | 小米智能动态帧率切换（0 为强锁不降频） |
| `window_animation_scale` | `global` | `0.0`, `0.5`, `1.0` | 窗口过渡动画倍率 |
| `transition_animation_scale` | `global` | `0.0`, `0.5`, `1.0` | 活动切换过渡动画倍率 |
| `animator_duration_scale` | `global` | `0.0`, `0.5`, `1.0` | 应用控件动画时长缩放 |
| `screen_off_timeout` | `system` | `60000` (1分), `600000` (10分) | 屏幕休眠超时时间（毫秒） |
| `zen_mode` | `global` | `0` (关), `1` (优先), `2` (静音), `3` (闹钟) | Android 免打扰 / Zen Mode 状态 |
| `mode_ringer` | `global` | `0` (静音), `1` (振动), `2` (正常响铃) | 全局铃声状态 |
| `quiet_mode_enable` | `secure` | `0`, `1` | MIUI 免打扰开关 |
| `airplane_mode_on` | `global` | `0`, `1` | 飞行模式开关 |
| `http_proxy` | `global` | `:0` (禁用) 或 `host:port` | 全局 HTTP 代理配置 |
