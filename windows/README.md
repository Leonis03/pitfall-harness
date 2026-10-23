# Windows 侧

| 路径 | 内容 |
| :--- | :--- |
| [`setup/`](setup/) | **新机器的 Windows 环境配置 runbook**：从刚装好的 LTSC 开始，配到终端、PowerShell、输入法、右键菜单、更新策略都就位。带强制流程（先探测 → 列清单 → 问可选项 → 再动手）。整份可以交给 Agent 执行 |
| [`files/`](files/) | 可部署原件（`$PROFILE`、清理脚本、Update 策略 `.reg`） |
| [`powershell/`](powershell/) | profile 功能文档（canonical：[`profile-features.md`](powershell/profile-features.md)）、中文命令 I/O 与报错语言（[`cjk-command-io.md`](powershell/cjk-command-io.md)）、用 shell 驱动 PowerShell 时自己骗了自己的地方（[`powershell-scripting-pitfalls.md`](powershell/powershell-scripting-pitfalls.md)）、优雅 / 强制关闭 Typora 并丢弃会话 |
| [`terminal/`](terminal/) | Windows Terminal：启动目录继承、System32 自动回家与 `OSC 9;9` 路径上报；无 Store 的 LTSC / 精简镜像如何侧载 winget 与 Terminal |
| [`ime-keyboard/`](ime-keyboard/) | 输入法与键盘布局：卸载语言后残留的幽灵键盘布局（含排查）、搜狗首字母漏成英文的排查清单 |
| [`context-menu/`](context-menu/) | 右键菜单项的排查与精简（含屏蔽 AMD Catalyst 扩展、Open in Terminal / Open in WSL） |
| [`windows-update/`](windows-update/) | 把功能更新钉在 24H2、保留更新可见性的 `.reg` 做了什么、什么时候用 |

## 从哪读起

**配一台新机器** → [`setup/README.md`](setup/README.md)。别直接照抄本文档里的单个片段：
`agent/minimax-code/agents-windows.md` 那类全局规则文件里记的路径、profile 名、发行版名都是
**某一台机器在某一时刻的快照**，换机器会静默出错。

**查一个具体现象** → 直接进对应的目录。

## 关于 profile 的四份文档

`$PROFILE` 的相关文档历史上散过好几份，现在权威关系是：

| 文件 | 地位 |
| :--- | :--- |
| [`files/powershell/Microsoft.PowerShell_profile.ps1`](files/powershell/Microsoft.PowerShell_profile.ps1) | **唯一权威原件**，部署的就是它 |
| [`powershell/profile-features.md`](powershell/profile-features.md) | **canonical 文档**，原件的忠实超集 |
| [`powershell/powershell-7-config-prompt.md`](powershell/powershell-7-config-prompt.md) | **已降级为历史参考**，早期任务书形态，与部署行为有三处不一致，抄了会写出不一样的 profile |

## 换机器时必须现场取值的

下面这些**不能照抄**，本仓库另有实测记录（[`context-menu/README.md`](context-menu/README.md) 第 8、9 节）：

- WSL 发行版名 / Windows Terminal 的 profile 名（本机当时是 `Debian`，别的机器不是）
- `wt.exe` 的实际路径与包目录（带版本号，随更新变）
- 侧载用的资源名（winget / Terminal 的 msixbundle 名字变过格式）
- 显卡扩展的 CLSID（没装对应驱动就根本没注册，屏蔽它是空操作）
- `windows-terminal-and-wsl-configuration.md` 第二节记的是早期「把环境变量全写进 `~/.zshrc`」的做法，
  已被四层分层取代；WSL 侧现行配置见 [`../shell/`](../shell/)。

[`powershell/SamplePSReadLineProfile_GitHub.ps1`](files/reference/SamplePSReadLineProfile_GitHub.ps1)
已移到 `files/reference/`，是第三方逐字副本，不部署也不修改。
