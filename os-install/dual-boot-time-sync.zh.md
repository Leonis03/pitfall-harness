# 双系统时间协调（Windows + Linux）

*中文 · [English](dual-boot-time-sync.md) · 返回 [os-install/](README.zh.md)*

如何让同一台机器上装着的两个操作系统——Windows 与某个 Linux 发行版——的时钟保持一致，
以及如何把「不一致」的不同成因区分开。

这是双系统装完之后才会暴露的那部分：安装程序按一种约定设了钟，第二个系统按另一种约定
读硬件时钟，结果要么是永久性偏差，要么更糟——**偏差会自愈，于是没人发现**。

---

## 1. 三个钟，一份契约

| 时钟 | 存在哪 | 谁写 | 谁读 |
| :--- | :--- | :--- | :--- |
| **硬件 RTC** | 主板纽扣电池供电的 CMOS | 最后关机的一方，以及任何跑过 `hwclock --systohc` 的系统 | 每个系统，开机时 |
| **系统时钟** | 运行中的内核 | 操作系统：开机时从 RTC 取，之后由 NTP 校正 | 全部进程 |
| **NTP** | 网络 | 上游服务器 | `w32time` / `chrony` / `systemd-timesyncd` |

两个系统开机时读的是**同一个** RTC。唯一的自由变量是各自**用什么约定去解释它**：

| 约定 | RTC 里存的是 | Windows 设置 | Linux 设置 |
| :--- | :--- | :--- | :--- |
| **本地时间** | 本地墙钟时间 | `RealTimeIsUniversal = 0` | `timedatectl set-local-rtc 1` |
| **UTC** | UTC | `RealTimeIsUniversal = 1` | `timedatectl set-local-rtc 0` |

> RTC 自己并不知道它存的是哪一种约定。机器可以处于任一状态，固件里也不会记录这个选择。
> **这份契约必须同时写进两个系统**，而且要写下来——它从外面完全看不见，重装任意一边都会
> 把它悄悄重置。

Windows 注册表位置（两个值都在这里）：

```
HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation
  RealTimeIsUniversal   0 = RTC 存本地时间，1 = RTC 存 UTC
  TimeZoneKeyName       Windows 时区 id（"Singapore Standard Time"、"China Standard Time" 等）
```

Linux：

```bash
timedatectl show -p LocalRTC        # yes = RTC 存本地时间，no = 存 UTC
```

> `RealTimeIsUniversal = 1` **不是**每台 Windows 的默认值，也不是「这台机器用 UTC」的开关。
> 它是双系统契约里由 Windows 保管的那一半。

---

## 2. 8 小时偏差的特征

双系统最常见的故障长这样：

```text
进 Windows  ->  时钟显示 19:22，实际是 11:22
进 Linux    ->  时钟显示 03:22，实际是 11:22
两者相差    ->  正好是一个 UTC 偏移量，方向相反
```

这样读：**两个系统恰好差一个 UTC 偏移量，而且各自「按自己的约定」都是对的**。Windows 把
一个它认为是 UTC 的值再加上 `+08:00`；Linux 把一个它认为是本地时间的值再加上 `+08:00`。

决定性问题是：**到底是谁读错了 RTC**：

```text
RTC 存本地时间
  Windows（RealTimeIsUniversal=1）当 UTC 读 -> 晚 8 小时
  Linux  （LocalRTC=no）        当 UTC 读 -> 正确

RTC 存 UTC
  Windows（RealTimeIsUniversal=0）当本地读 -> 早 8 小时
  Linux  （LocalRTC=yes）       当本地读 -> 早 8 小时
```

改之前两边都查一遍。这里改错方向会让偏差**翻倍**，而不是消失——那时两个系统看起来
「错得更离谱」。

---

## 3. 先诊断，再动手

### 3.1 Windows 侧

```powershell
# 服务状态——Disabled 或 Stopped 表示没有任何东西在校正时钟
Get-Service W32Time | Select-Object Status, StartType

# 到底配没配同步（"NTP" 与 "NoSync"）
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' |
  Select-Object Type, NtpServer

# 服务认为自己用的源、上次同步时间
w32tm /query /source
w32tm /query /status

# 对上游服务器的实测偏差（秒，带正负号）
w32tm /stripchart /computer:<your-ntp-server> /dataonly /samples:3

# RTC 约定，以及本 OS 到底按 UTC 还是本地时间
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' |
  Select-Object RealTimeIsUniversal, TimeZoneKeyName
```

`w32tm /query /status` 报 **`The service has not been started. (0x80070426)`**
不是网络问题。它的意思是 Windows Time 服务被禁用了，时钟在自由走，没有任何东西会校正它。

`w32tm /stripchart` **在服务不运行的情况下也能用**，所以服务关掉时用它探测。

> 一个解析不了的 NTP 名字会**一个样本都不给**，而这和「时钟坏了」在输出里长得一模一样。
> 备好一份候选列表，把「没有样本」当成网络结论而不是时钟结论。写这份文档的机器上，
> 列表里的一个名字被 DNS 挡了，其余都正常应答。

### 3.2 Linux 侧

```bash
timedatectl                                  # LocalRTC、NTPSynchronized、时区
timedatectl show -p LocalRTC -p NTPSynchronized
hwclock --show                              # 按本地时间读 RTC
hwclock --show --utc                        # 同一个 RTC 按 UTC 读
timedatectl timesync-status                 # systemd-timesyncd
chronyc tracking                            # 客户端是 chrony 时
```

`hwclock --show` 和 `hwclock --show --utc` 读的是**同一个** RTC，只是解释方式不同；
util-linux 永远按**本地时间**打印，所以这两行相差正好一个 UTC 偏移量。与系统时钟一致的
那个解释，就是 RTC **实际装着**哪种约定——如果两个都不一致，说明 RTC 本身是陈旧的。

> 比较这两行要比较的是**解析出的时刻**，不是字符串。`hwclock` 打印的是带本地偏移量的
> 本地时间串，`date -d` 能正确读它；但拿 UTC 那条读数做比较时，基准也必须是 UTC 时刻。
> `date -d "$(date -u ...)"` 会按**本地**时区去解析 UTC 墙钟串，基准因此偏了一个偏移量：
> UTC 那条的距离被算成两倍，于是一台配置正确的机器在**两种**读法下都像是差了 8 小时。

### 3.3 独立交叉验证

不要让本地时钟自报误差。拿远端服务器自己的时钟做对比：

```powershell
(Invoke-WebRequest -Method Head https://<any-https-host>).Headers.Date
```

或者不用 PowerShell：

```bash
curl -sI https://<any-https-host> | grep -i '^date:'
```

`Date` 头是远端主机的 GMT 时间。换算后比较。**两个独立来源互相印证**才是本地时钟正确的
证据；单看 `w32tm /query /status` 证明不了。

---

## 4. 选一种约定，写进两个系统

在系统时钟已知正确的前提下做（先过 3.3）。

> **先测再选。** 两个方案不是随便挑一个：正确的是那个**与 RTC 现状一致**的。在 Linux 上，
> `hwclock --show` 与 `hwclock --show --utc` 是同一个硬件时钟的两种读法——与 `date` 对得上的
> 那个，就是 RTC 实际所处的约定。写这份文档的那台机器上答案是**本地时间**，所以适用方案 A，
> 要改的是 Windows 那一侧。

### 方案 A —— RTC 存本地时间

```powershell
# Windows：把 RTC 当本地时间读
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -Value 0
```

```bash
# Linux：把 RTC 当本地时间读
sudo timedatectl set-local-rtc 1
sudo hwclock --systohc --localtime     # 把当前（正确的）时间写回去
hwclock --show --localtime              # 必须与 `date` 一致
```

### 方案 B —— RTC 存 UTC

```powershell
# Windows：把 RTC 当 UTC 读
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -Value 1
```

```bash
# Linux：把 RTC 当 UTC 读
sudo timedatectl set-local-rtc 0
sudo hwclock --systohc --utc           # 把当前（正确的）时间写回去
hwclock --show --utc                   # 必须与 `date -u` 一致
```

方案 B 与 Linux 默认值（`LocalRTC=no`）和常见 BIOS 默认（UTC）一致；方案 A 与 Windows
默认值一致。**两种都行，混用就是 bug。** 选定之后写进安装记录——这是双系统契约里唯一
没有工具能替你读出来的那一项。

> `hwclock --systohc` 会按当前生效的 RTC 约定去解释**系统**时钟。显式带上 `--utc` 或
> `--localtime`，避免写入时被误解。

---

## 5. 同步策略：自动校正 vs. 有意漂移

RTC 约定解决的是**偏移**；同步策略决定**漂移**是否被校正，以及你能不能看见这件事发生。

### 自动

```powershell
Set-Service W32Time -StartupType Automatic
Start-Service W32Time
w32tm /config /syncfromflags:manual /manualpeerlist:"<your-ntp-server>,0x8 <second-server>,0x8" /update
Restart-Service W32Time
w32tm /resync /force
```

在设置界面，**「日期和时间 → 自动设置时间」**这个开关实际只写两处：W32Time 服务的启动
类型，和 `...\W32Time\Parameters` 下的 `Type` 值（开=`NTP`，关=`NoSync`）。在某台机器上
把它关掉之后的实测结果：服务 `Disabled` 且已停止，`Type = NoSync`。**这个开关不是独立的
开关——它就是服务配置本身。**

### 有意为之

```powershell
Set-Service W32Time -StartupType Disabled
Stop-Service W32Time
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' `
  -Name Type -Value NoSync
```

关掉的代价（实测，不是推测）：

- 时钟自由走。消费级主板 RTC 的漂移是几十 ppm：按 20 ppm 算，约 **每天 1.7 秒、每月 50 秒**，无人校正。
- RTC 约定上的 8 小时错误在开机时也不再被校正。它变成一个**每次开机都看得见**的常驻错误
  ——这恰恰是部分运维想要的：宁要一个会被发现的错钟，也不要一个被悄悄补好的对钟。
- 在它错着的时候，TLS、Git 提交签名、`systemd` 定时任务、文件时间戳都会出问题。

### 中间路线：既保留修复，也保留证据

自动校正不等于「静默」。Windows Time 服务会把每一次尝试、成功与失败写进 `System` 日志，
provider 名 `Microsoft-Windows-Time-Service`：

| 事件 ID | 含义 |
| :--- | :--- |
| `35` | 时钟**已同步**，并记明用了哪个源 |
| `37` | provider 收到了有效时间数据 |
| `134` | 某个源**失败**（DNS 或网络）；服务会按递增的间隔重试 |
| `158` | 某个 provider 已停止（例如物理机上的 `VMICTimeProvider`——属正常噪音） |

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Time-Service'} -MaxEvents 30 |
  Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List
```

事件 `35` 是「确实修过」的证据，`134` 是「让修复变得不可能的那张网络」的第一个信号。这
就是「系统自己修好了」和「我知道它被修好了、也知道为什么」之间的差别。

### 5.1 这台机器上的策略

这里是有意做的选择，写下来是为了下一个读者不必重新发现：

| 设置 | 取值 | 为什么 |
| :--- | :--- | :--- |
| W32Time 服务 | `Disabled`，已停止 | **故意关掉自动修复**。被悄悄补好的时钟会把故障藏起来；运维要的是找到原因，而不是接手一个已经被修正的现象 |
| `...\W32Time\Parameters` 下的 `Type` | `NoSync` | 设置界面那个开关写的另一半——两处都改，服务才真的保持关闭 |
| NTP 源 | 仍保留在 `NtpServer` 里 | 留着服务就能一条命令重新启用，`w32tm /stripchart` 也还有可测量的目标 |
| RTC 约定 | **两边都用本地时间** —— Windows 侧 `RealTimeIsUniversal = 0`，Linux 侧 `LocalRTC = yes` | 是实测出来的，不是假设：RTC 的原始值等于**本地时间**（第 8 节第 6 条）。发行版按本地时间读、时间正确；Windows 按 UTC 读、差 8 小时。**要改的是 Windows 那一侧**：`Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name RealTimeIsUniversal -Value 0`。Linux 侧不用动——用 `timedatectl show -p LocalRTC` 确认一下（应为 `yes`） |
| 快速启动 | 关闭 | 见第 6 节 |
| 时区 | 固定 UTC+08:00，无夏令时 | |

前两行的代价是接受过并量化过的：时钟自由走（这类硬件约每天 1.7 秒）。**不接受**的是那种
「被同步悄悄盖住」的 8 小时偏差，所以修复要落在**读错硬件时钟的那一侧**——而第 8 节的
实测说，那一侧是 Windows。

探针脚本存在的理由也在这里：它随时报告机器的状态，让运维能分辨「故障还在」和「一小时
前修好了而我没注意到」——从外面看，一台会自愈的时钟就是这个样子。

---

## 6. 第三个钟：Windows 快速启动

快速启动（`HiberbootEnabled=1`）把关机变成**混合关机**：用户会话被关掉，但内核会话会写进
休眠文件、下次开机再恢复——微软自己的说法是「内核会话没有被关闭，而是被 hibernate 了」。
于是那次开机是**唤醒**而不是冷启动：时钟来自快照而不是硬件时钟，RTC 则保持原值。已经有
报告的双系统后果是：紧接着冷启动的第二个系统读到的 RTC 比实际关机时间更旧，于是显示错的
时间，直到有东西校正它。

RTC 到底会陈旧到什么程度取决于机器，所以这条要当成**待验证的假设**，而不是可以依赖的机制：
快速启动开着时，「只有 Linux 那边时间不对」有第三种可能成因，解法是先把快速启动关掉再复测，
然后才轮到动 RTC 约定。

```powershell
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
  -Name HiberbootEnabled | Select-Object HiberbootEnabled
```

`0` = 快速启动关闭（双系统机器上的安全设置），`1` = 开启。

快速启动开启时，「只有 Linux 时间不对」这个症状有第三种可能成因，**正确做法是关掉快速
启动再复测**，而不是先去动 RTC 约定。

---

## 7. 验证清单

任何改动之后跑一遍。每一行都是探针，不是假设。

**Windows**

```powershell
Get-Service W32Time | Select-Object Status, StartType            # 期望：Running / Automatic
w32tm /query /source                                             # 期望：真实源，不报错
w32tm /query /status                                             # 期望：Stratum > 0，Leap 0
w32tm /stripchart /computer:<your-ntp-server> /dataonly /samples:3   # 期望：|偏差| < 1 秒
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' |
  Select-Object RealTimeIsUniversal                               # 期望：0 或 1，与所选约定一致
```

**Linux**

```bash
timedatectl show -p LocalRTC -p NTPSynchronized
# 按所选约定：这里是 --utc，本地约定则用 --localtime
hwclock --show --utc       # 必须等于 `date -u`；用 --localtime 时必须等于 `date`
```

**跨系统**

```text
1. Linux 的 `date` 与 Windows 的时钟一致（分钟级）
2. 重启进另一个系统再比一次——一致性能扛过重启
3. 两边都起来之后，实测偏差仍小于一秒
```

第 2 步才是抓 RTC 约定 bug 的那一步：**只在下次重启前正确的时间，等于没修好。**

**机器状态存档**（Windows，每项一行）：

```powershell
Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'
Get-TimeZone | Select-Object Id
Get-Service W32Time | Select-Object Status, StartType
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' | Select-Object Type, NtpServer
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' | Select-Object RealTimeIsUniversal, TimeZoneKeyName
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled
```

[`files/`](files/) 里的只读探针把这些一次跑完：Windows 上 `check-time-sync.ps1`，
Linux 上 `check-time-sync.sh`。**它们只报告，不改任何设置。**

---

## 8. 一次实测记录

记下来，是为了让推理可复现，而不是变成口口相传的玄学。

**现象。** Windows 时钟显示 `16:39`，真实本地时间是 `08:39`——正好快 8 小时。这个值和
它自己的时区并不自洽：它是**按 UTC 手动设的**，之后又叠加了 `+08:00`。

**排查结果。**

1. `Get-Service W32Time` -> `Stopped`，`StartType: Disabled`。
   `w32tm /query /status` -> `The service has not been started. (0x80070426)`。
   注册表里是 `Type = NoSync`、`NtpServer = time.windows.com,0x9`。
   即：时钟自由运行，无人校正。
2. 启用服务、配三个上游、强制 resync 后，对上游服务器实测偏差 **+0.031 秒**，远端
   `Date:` 头与本地时钟完全一致。时钟是对的——但只是因为它每次开机都被校正。
3. 第二天，机器在本地 `11:22:49` 开机。那次开机的 Time-service 日志事件时间戳是
   **`19:22:59`**——快了 8 小时——并伴随三条 `134`：**三个 NTP 源全部 DNS 解析失败**，
   因为此时网络还没起来。七分钟后（`19:29:35`，即真实 `11:29:35`），事件 `35` 记录了
   对 `ntp.aliyun.com` 的成功同步，时钟被拉回正确值。
   **这个 8 小时错误每次开机都存在，是同步把它盖住了。**
4. 8 小时的来源：`RealTimeIsUniversal = 1`——Windows 被告知 RTC 存 UTC——而 RTC 实际
   存的是**本地时间**。
5. 快速启动当时已是关闭状态（`HiberbootEnabled = 0`），所以「陈旧 RTC」这个解释是被
   **实测排除**的，不是假设排除。
6. RTC 的原始值等于本地时间，算术过程可以证明：Windows 把 RTC 当 UTC 读、再加上
   `+08:00`，所以同步前的系统时钟 `19:22:59` 反推硬件时钟存的是 `11:22:59`——真实本地
   时间，而不是 UTC。**硬件时钟一直是对的，错的是那个解释开关。** 发行版读同一个 RTC 时
   按本地时间解释，装完系统显示的时间是对的——所以它们从来不是嫌疑人。

**教训。** 屏幕上的钟是对的、硬件里的钟是错的，而两者之间的落差被一个「网络起来之后
自动执行」的修复盖住了。修 NTP 服务恢复的是**症状**；RTC 约定才是真正的缺陷。一个
每次开机后几分钟才跑一次的修复，正是故障能潜伏数月的原因。

**该改哪一侧。** 是实测决定的，而且结论与第一反应**相反**。RTC 里存的是本地时间，所以适合
这台机器的契约是**两边都用本地时间**：Windows 侧 `RealTimeIsUniversal = 0`，Linux 侧
`LocalRTC = yes`。另一个选项（两边都用 UTC）只有在 Linux 侧每次 Windows 关机后都重写
一次 RTC 的前提下才成立——因为**最后写 RTC 的那一方，决定 RTC 里是什么**。而挑选那个
本来就与硬件时钟一致的约定，才是能活下来的选择。

---

## 9. 相关文档

- [`../windows/README.md`](../windows/README.md) —— 本仓库的 Windows 侧
- [`../linux-desktop/README.md`](../linux-desktop/README.md) —— 原生 Linux 侧
- [`../wsl/setup/README.md`](../wsl/setup/README.md) —— WSL：第三个时钟来源，但它与 Windows
  共用内核时钟，RTC 那套规则对它不适用
- [`files/README.md`](files/README.zh.md) —— 只读探针脚本
