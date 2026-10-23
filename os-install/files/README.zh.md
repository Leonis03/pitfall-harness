# os-install/files —— 只读探针

*中文 · [English](README.md) · 返回 [os-install/](../README.zh.md)*

可部署原件：复制到实机就能跑的脚本。**本目录里的每个脚本都是只读的。** 没有一个会改
设置、启停服务或写硬件时钟。它们只报告；由人来决定并执行修复，修复命令写在正文里，
紧挨着支撑它的实测数据。

| 脚本 | 跑在哪 | 报告什么 | 退出码 |
| :--- | :--- | :--- | :--- |
| [`check-time-sync.ps1`](check-time-sync.ps1) | Windows | 时间服务、同步模式、NTP 实测偏差、独立的 HTTP `Date` 交叉校验、RTC 约定（`RealTimeIsUniversal`）、快速启动，以及被「稍后的同步」掩盖的开机偏差 | 0 = 干净，1 = 有发现，2 = 探针没能跑起来 |
| [`check-time-sync.sh`](check-time-sync.sh) | Linux | 时钟模式（`LocalRTC`）、时区、NTP 状态、**两种约定下**的 RTC 读数与系统时钟对比、实测偏差（chrony 或 systemd-timesyncd）、HTTP `Date` 交叉校验，以及另一套系统必须匹配的值 | 0 = 干净，1 = 有发现，2 = 探针没能跑起来 |

## 用法

```powershell
# Windows
pwsh -File .\check-time-sync.ps1
pwsh -File .\check-time-sync.ps1 -NtpServer ntp.example.com,pool.ntp.org -HttpHost www.example.com
```

NTP 服务器参数接受一个**列表**：脚本按顺序逐个尝试，用第一个能应答的——因为一个解析不了
的名字，在输出里长得和时钟故障一模一样。

```bash
# Linux
bash check-time-sync.sh
sudo bash check-time-sync.sh          # 大多数发行版上读 RTC 需要 root
bash check-time-sync.sh --http-host www.example.com
```

## 怎么读输出

- `OK` / `INFO` —— 不用管。
- `WARN` —— 值得你做一次决策的真实状况：服务关着、某个源失败、快速启动开着、时钟在漂。
- `FAIL` —— 是缺陷不是偏好。具体是：RTC 在**两种**解释下都和系统时钟对不上；RTC 实际装的
  约定与本侧的 `LocalRTC` 设置互相矛盾；时钟与独立来源差了一个时区量级；注册表键根本读不到；
  Windows Time 服务不存在；或者时间服务事件带着晚于「现在」的时间戳——那正是「开机时钟跑快、
  之后被悄悄修好」的签名。
- `SKIP` —— 这台机器上探针跑不了（没有 `chronyc`、没有 root 读 RTC、没有网络）。这不是
  发现项，另一侧手工查。

最值得读两遍的发现是**开机偏差**：脚本会找出时间戳**晚于当前时间**的时间服务事件，并
用开机时刻做锚点。这正是「开机时时钟是错的、几分钟后被一次同步悄悄修好」的signature ——
屏幕看着对、硬件其实不对，而那次修复正是没人发现的原因。

## 约定

- **纯 ASCII**，含注释。
- **LF 行尾。**
- **不含真实标识符**：NTP 服务器与 HTTP 主机都是参数，默认值是公开服务。
- 脚本是自包含的：复制一个文件，跑起来，读输出。
