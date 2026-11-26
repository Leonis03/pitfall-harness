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
| **硬件 RTC** | 主板纽扣电池供电的 CMOS | Windows，按它的 `RealTimeIsUniversal` 指定的约定写；Linux 内核，NTP 同步期间每 11 分钟写一次，按开机时被告知的约定写；以及任何跑 `hwclock --systohc` 的人（第 1.1 节） | 每个系统，开机时 |
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
>
> **两个开关都是开机时读取的，不是改动那一刻生效。** 改 `RealTimeIsUniversal` 在下次重启
> 之前毫无效果——而中间那次关机写 RTC，用的还是**旧值**，因为内核保留的是开机时读到的那个
> 标志。Linux 的 `LocalRTC` 同理。所以改约定不是两分钟的编辑：它要等一次重启才变得可观测，
> 而 8 小时的错误恰恰是在那次重启后才出现。改 → 重启 → 再测。

### 1.1 谁在写 RTC

约定不只是两边怎么**读** RTC：两边也都会**写**它，RTC 里存的是最后写入的那一方留下的值。
只有两边写入的约定都是对方读取的约定，契约才成立。

**Windows 让 RTC 保持在它的开关所指定的约定上。** 在两台开关几周没动过的机器上实测：

| 机器 | `RealTimeIsUniversal` | RTC 里实际存的 | 怎么测的 |
| :--- | :--- | :--- | :--- |
| A（第 5.1 节） | `1` | **UTC** | 两周的 `Kernel-General` 事件 1（第 3.1 节）：生效的是 `RealTimeIsUniversal=true`，`CmosTime` 等于时钟正确时的真实 UTC。Windows 与 Linux（`LocalRTC=no`）交替开机数周，全部正确，而且 Windows 时间服务是关着的——8 小时的错误会一直显示在屏幕上 |
| B（第 5.2 节） | `0`（值不存在） | **本地时间** | 两周的 `Kernel-General` 事件 12（开机）和事件 1：每次开机和唤醒时 RTC 都是真实本地时间，从未记录过接近时区偏移量的改动 |

Windows 具体在什么时候写 RTC——校时、唤醒还是关机——没有测过，契约也不依赖它：约定跟着
开关走，而生效的开关是**开机时**读到的那个（读法见第 3.1 节）。

> 之前对第 8 节的一种解读认为 Windows **不管开关是几都写本地时间**，并据此把机器 A 改成了
> 两边都存本地时间。它依据的那几次开机之间开关被改过，所以那几次关机时生效的开关和注册表里
> 显示的不是同一个。机器 A 推翻了这个结论——开关为 `1`，RTC 存 UTC，持续数周——第 8 节
> 事故三记录了照它去做的代价。

**在 Linux 上，写 RTC 的是内核，不是关机。** chrony 开着 `rtcsync`（Fedora 默认开）时，
内核会在 NTP 同步期间每 11 分钟把系统时钟写进 RTC，按**开机时**被告知的约定写。
`LocalRTC=yes` 时，systemd 在开机早期告诉内核，并记一行日志：

```text
RTC configured in localtime, applying delta of 480 minutes to system time.
```

（480 分钟 = UTC+08:00）。`LocalRTC=no` 时没有这一行。所以 `timedatectl set-local-rtc`
改的是**下一次开机**怎么读 RTC，不是正在运行的内核怎么写它：重启之前内核仍按旧约定写，
它的下一次 11 分钟写入可能把改完后那次 `hwclock --systohc` 的结果覆盖掉。这个覆盖是按内核
和 systemd 的机制推断的，没有实际观察到——第 8 节测到的那次改动之后马上就重启了。
**改完 `LocalRTC` 立刻重启**，然后找上面那一行日志。

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

注册表显示的是**下一次**开机要用的值。正在运行的内核用的值是开机时读到的，Windows 会把它
记下来：每次时钟变动（校时、唤醒、手动设置）都会写一条 `Kernel-General` 事件 1，它的 XML
里带着这个值，旁边还有 RTC 的原始值。

```powershell
$e = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=1} -MaxEvents 1
$e.TimeCreated
([xml]$e.ToXml()).Event.EventData.Data |
  Where-Object Name -in 'NewTime','CmosTime','RealTimeIsUniversal' | Select-Object Name, '#text'
```

那里的 `RealTimeIsUniversal` 是 `true` 或 `false`：写这条事件的那次开机**实际生效**的开关。
`CmosTime` 是 RTC 的原始值，不管存的是什么都带一个 `Z`；把它和独立来源（第 3.3 节）的真实
时间比较，就知道 RTC 存的是哪种约定。唤醒事件上不要拿它和 `NewTime` 比：那时 `NewTime`
就是按同一个开关**从** RTC 算出来的，两者永远一致。消息正文说的是同一件事
（`RTC time is in UTC: true`），但用的是显示语言；XML 字段名不会变。

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

```bash
journalctl -b | grep -i 'configured in localtime'                # 只有本次开机时 LocalRTC=yes 才有
journalctl -b -u chronyd -u chrony | grep -E 'wrong by|stepped'   # 本次开机时差了多少
```

`hwclock` 的比较只能在本系统第一次 11 分钟写入之前，显示**另一个**系统留在 RTC 里的值
（第 1.1 节）。之后 RTC 里就是本系统自己写的值，两种读法说明不了另一侧的任何事。chrony 的
第一次校正才是能留下来的记录：本次开机出现 `System clock wrong by 28799.x seconds`（或
`-28800.x`），说明在它之前运行的系统按另一种约定写了 RTC；一两秒只是漂移。

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
> 那个，就是 RTC 实际所处的约定。写这份文档的那台机器上答案是 **UTC**，所以适用方案 B，
> 而且是**两边都适用**——因为 RTC 里存什么由**最后写它的那一方**决定，不由读它的一方决定。
> 换过写方就要重测：一次手工拨表，或者从另一个系统关机，都可能把它翻过来。

> **改这一侧之前，先读另一侧。** 动 `LocalRTC` 之前，先读 Windows 的 `RealTimeIsUniversal`
> ——注册表里的值和实际生效的值（第 3.1 节）——反过来也一样。每一侧都可能通过自己的全部检查，
> 而契约已经坏了：第 8 节事故三就是一次 Linux 侧的改动，Linux 侧的探针全部通过，下一次
> 进 Windows 却差了 8 小时。

### 方案 A —— RTC 存本地时间

```powershell
# Windows：按本地时间读并保持 RTC（下次重启生效）
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -Value 0
```

```bash
# Linux：按本地时间读写 RTC
sudo timedatectl set-local-rtc 1
sudo hwclock --systohc --localtime     # 把当前（正确的）时间写回去
sudo systemctl reboot                  # 立刻重启：在此之前内核仍按旧约定写
# 重启之后
journalctl -b | grep -i 'configured in localtime'   # 必须有这一行
hwclock --show --localtime             # 必须与 `date` 一致，NTP 同步 12 分钟后仍一致
```

### 方案 B —— RTC 存 UTC

```powershell
# Windows：按 UTC 读并保持 RTC（下次重启生效）
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -Value 1
```

```bash
# Linux：按 UTC 读写 RTC
sudo timedatectl set-local-rtc 0
sudo hwclock --systohc --utc           # 把当前（正确的）时间写回去
sudo systemctl reboot                  # 立刻重启，理由同上
# 重启之后
journalctl -b | grep -i 'configured in localtime'   # 必须没有输出
hwclock --show --utc                   # 必须与 `date -u` 一致，NTP 同步 12 分钟后仍一致
```

方案 B 与 Linux 默认值（`LocalRTC=no`）和常见 BIOS 默认（UTC）一致；方案 A 与 Windows
默认值一致。**两种都行，混用就是 bug。** 选定之后写进安装记录——这是双系统契约里唯一
没有工具能替你读出来的那一项。

### 在 Windows 旁边新装 Linux

还能选的时候，优先**方案 B（UTC）**：

- 它是所有发行版的默认值，重装 Linux 侧之后契约不用重做。方案 A 每次重装 Linux 都要重新
  设置一遍，还要按第 1.1 节立刻重启。
- `timedatectl` 自己就警告，RTC 存本地时间"不能被完全支持"（cannot be fully supported）。
- 代价是 Windows 上一个注册表值（`RealTimeIsUniversal = 1`），设一次即可，只有重装
  Windows 后才要再设。

安装程序在磁盘上发现 Windows 时，可能会自行选择本地时间，而且不一定会问。不管它显示了
什么，第一次开机后都检查：

```bash
timedatectl show -p LocalRTC        # 方案 B 应为 no
```

然后在信任它之前，按第 7 节完整跑一圈跨系统验证。

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

### 5.1 机器 A（Windows + Fedora）上的策略

这里是有意做的选择，写下来是为了下一个读者不必重新发现：

| 设置 | 取值 | 为什么 |
| :--- | :--- | :--- |
| W32Time 服务 | `Disabled`，已停止 | **故意关掉自动修复**。被悄悄补好的时钟会把故障藏起来；运维要的是找到原因，而不是接手一个已经被修正的现象 |
| `...\W32Time\Parameters` 下的 `Type` | `NoSync` | 设置界面那个开关写的另一半——两处都改，服务才真的保持关闭 |
| NTP 源 | 仍保留在 `NtpServer` 里 | 留着服务就能一条命令重新启用，`w32tm /stripchart` 也还有可测量的目标 |
| RTC 约定 | **两边都用 UTC** —— Windows 侧 `RealTimeIsUniversal = 1`，Linux 侧 `LocalRTC = no` | 是实测出来的，不是假设：RTC 的原始值等于 **UTC**（第 8 节事故二），而且几周的 Windows 事件显示开关为 `1` 时 RTC 一直保持 UTC（第 1.1 节）。Windows 现在的模式就是对的——**不要动 `RealTimeIsUniversal`**；Linux 侧也是发行版默认值，同样不用改，重装也会保持，但要检查（第 4 节）。核验用 `timedatectl show -p LocalRTC`（应为 `no`），且 `hwclock --show --utc` 必须等于 `date -u`。2026-11-21 付出代价重新验证过一次（第 8 节事故三） |
| 快速启动 | 关闭 | 见第 6 节 |
| 时区 | 固定 UTC+08:00，无夏令时 | |

前两行的代价是接受过并量化过的：时钟自由走（这类硬件约每天 1.7 秒）。而 RTC 约定是**唯一
一个不能凭直觉改**的设置：它在**开机时被读取**，猜错一次就是每次开机差 8 小时
（第 8 节事故二）。

探针脚本存在的理由也在这里：它随时报告机器的状态，让运维能分辨「故障还在」和「一小时
前修好了而我没注意到」——从外面看，一台会自愈的时钟就是这个样子。

### 5.2 机器 B（Windows + Linux Mint）

第二台机器，2026-11-21 只读测量。它用的是另一种约定，Windows 侧与之自洽：

| 设置 | 取值 |
| :--- | :--- |
| RTC 约定，Windows 侧 | **本地时间** —— `RealTimeIsUniversal` 不存在（= `0`）；`Kernel-General` 事件 1 显示生效的是 `RealTimeIsUniversal=false`，日志覆盖的两周里每次开机和唤醒时 RTC 都是真实本地时间 |
| RTC 约定，Linux 侧 | **尚未测量** —— 必须是 `LocalRTC = yes` 才匹配。如果是 `no`，每次 Mint 会话之后再开 Windows 都会慢 8 小时（第 2 节） |
| W32Time 服务 | `Automatic`，运行中，`Type = NTP` —— 8 小时的错误开机后会被校正，但仍会留下一条改动接近时区偏移量的 `Kernel-General` 事件 1；一条都没有 |
| 快速启动 | 第一次测量时**开着**，当天已关闭 |
| 时区 | 固定 UTC+08:00，无夏令时 |

如果 Mint 侧是 `LocalRTC = no`，就把这台机器改成两边都用 UTC（方案 B），而不是改 Mint：
这是机器 A 已经验证过的约定，而且重装 Linux 侧也不会丢。

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
# 以及本次开机实际生效的值（第 3.1 节）                           # 期望：与注册表一致
```

**Linux**

```bash
timedatectl show -p LocalRTC -p NTPSynchronized
# 按所选约定：这里是 --utc，本地约定则用 --localtime
hwclock --show --utc       # 必须等于 `date -u`；用 --localtime 时必须等于 `date`
journalctl -b | grep -i 'configured in localtime'                # 当且仅当 LocalRTC=yes 时有
journalctl -b -u chronyd -u chrony | grep -E 'wrong by|stepped'   # 没有接近时区偏移量的校正
```

**跨系统**

```text
1. Linux 的 `date` 与 Windows 的时钟一致（分钟级）
2. 重启进另一个系统再比一次——一致性能扛过重启；
   在 Linux 上同时看那次开机 chrony 的校正
3. 两边都起来之后，实测偏差仍小于一秒
4. 改过 LocalRTC 之后：立刻重启，NTP 同步 12 分钟后再查一次 RTC
   ——那时内核自己的 RTC 写入已经发生过了
```

第 2 步才是抓 RTC 约定 bug 的那一步：**只在下次重启前正确的时间，等于没修好。** 两个方向
都要跑——Linux 到 Windows、Windows 到 Linux——因为每个方向检验的是另一侧的写入。

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

## 8. 三次实测记录

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
6. 所以 RTC 存的是本地时间：Windows 把 RTC 当 UTC 读、再加上 `+08:00`，同步前的系统时钟
   `19:22:59` 反推硬件时钟存的是 `11:22:59`。那一刻真实本地时间是 `11:22:49`、真实 UTC 是
   `03:22:49`，所以 RTC 比 UTC 快 8 小时——**它存的是本地时间**。最后写它的那一方写的是本地时间。

**事故二 —— 同一台机器，一天之后，方向相反的错误。**

基于第 6 条把 `RealTimeIsUniversal` 改成了 `0`，理由是「RTC 存的是本地时间，Windows 就该
按本地时间读」。结果下一次开机，时钟**慢了 8 小时**：`09:03`，而真实本地时间是 `17:03`。
三个独立的 `Date:` 头加一次 NTP `stripchart` 都证明真实时间如此——机器时钟显示的是 **UTC**。

**定案的那次测量**：RTC 被当成 UTC 读了，所以时钟显示的就是 RTC 的值，而那个值在几秒内
紧跟真实 UTC（开机时间戳 `08:14:38` 正是那一刻的真实 UTC）。所以 RTC 存的是 **UTC**，
不是本地时间。第 6 条对 10-23 那次开机是对的，对「RTC 到底是什么」却是错的：RTC 里存什么
取决于**最后写它的那一方**，一次手工拨表、或一次来自另一套系统的关机，都足以把它翻过来。

**事故三 —— 只改了一侧，2026-11-21。**

基于「Windows 不管开关是几都写本地时间」这个解读（第 1.1 节），把这台机器（机器 A）的
Linux 侧改成了本地时间：`timedatectl set-local-rtc 1`、`hwclock --systohc --localtime`，
然后立刻重启。Linux 侧的检查全部通过：

- 开机日志里有 `RTC configured in localtime, applying delta of 480 minutes`；
- 那次开机 chrony 没有任何校正，`date` 与 HTTP `Date` 头一致；
- NTP 同步 17 分钟后，`hwclock --show --localtime` 与 `date` 仍相差不到一秒，探针报
  `RTC convention OK`。

下一次进 Windows，时钟**快了 28,801 秒**。它的开关是 `1`，改之前没人读过：Windows 把存着
本地时间的 RTC 当成 UTC 读，又加上了时区。时间服务是关着的，没有东西去校正——错误立刻
显示在屏幕上，这正是第 5.1 节想要的效果。

同一台 Windows 的日志也说明了原来的配置为什么一直正常：两周的 `Kernel-General` 事件都是
`RealTimeIsUniversal=true`，RTC 里存的是真实 UTC。Linux 侧已改回 `LocalRTC = no`，立刻
重启，探针重新通过。

**教训。** 四条，都是关于同一份契约：

1. **这个开关在开机时被读取。** 机器运行中改 `RealTimeIsUniversal`，在下次重启前不生效——
   而两次重启之间那次关机写 RTC，用的**还是旧值**。12:52 改的那一次，在下次重启之前
   都没人察觉，而之后每次开机都赔上 8 小时。
2. **要测 RTC，不要推。** 决定性的测试在 Linux 侧：同一个硬件时钟可以按两种约定各读一次，
   `hwclock --show` 和 `hwclock --show --utc`。Windows 侧等价物是开机时间戳：那次开机的
   第一条时间服务事件带的就是当时的时钟值，所以 `显示值 = RTC + 时区`（开关为 1）或
   `显示值 = RTC`（开关为 0），直接反推即可。`Kernel-General` 事件 1 则直接写明生效的开关
   和 RTC 原始值（第 3.1 节）。
3. **改这一侧之前，先读另一侧。** 探针只看得到一侧，每一侧都可能通过自己的全部检查，
   而契约已经坏了。只有改动**之前**读到的另一侧开关，加上改动**之后**开进另一个系统，
   才能说明契约是否成立。
4. **改 `LocalRTC` 之后要立刻重启。** 正在运行的内核仍按开机时被告知的约定写 RTC（第 1.1 节）。

**该改哪一侧。** 测量说了算，而这里的答案是**哪一侧都不用改**：契约就是**两边都用 UTC**，
这正是两套系统本来的状态。`RealTimeIsUniversal = 1`（Windows）、`LocalRTC = no`（Linux）。
发行版从来没错，Windows 那个开关在被错误推理改掉之前也是对的。真正坏掉的只有**自动校正**
（被关掉的时间服务），而那是一个有量化代价的有意选择——时钟自由走，每天约 1.7 秒。

---

## 9. 相关文档

- [`../windows/README.md`](../windows/README.md) —— 本仓库的 Windows 侧
- [`../linux-desktop/README.md`](../linux-desktop/README.md) —— 原生 Linux 侧
- [`../wsl/setup/README.md`](../wsl/setup/README.md) —— WSL：第三个时钟来源，但它与 Windows
  共用内核时钟，RTC 那套规则对它不适用
- [`files/README.md`](files/README.zh.md) —— 只读探针脚本
