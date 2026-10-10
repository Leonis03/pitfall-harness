# Windows 侧

| 路径 | 内容 |
| :--- | :--- |
| [`terminal/`](terminal/) | Windows Terminal：启动目录继承（`startingDirectory: null`）、PowerShell 侧的 System32 自动回家与 `OSC 9;9` 路径上报 |
| [`powershell/`](powershell/) | PowerShell 7 profile 原件（`Microsoft.PowerShell_profile.ps1`）、PSReadLine 官方示例、一键关闭所有资源管理器窗口、优雅 / 强制关闭 Typora 并丢弃会话（`close-typora.ps1` / `kill-typora.ps1`，原理见 [`typora-close-and-kill.md`](powershell/typora-close-and-kill.md)） |
| [`ime-keyboard/`](ime-keyboard/) | 输入法与键盘布局：卸载语言后残留的幽灵键盘布局（含清理脚本）、搜狗首字母漏成英文的排查清单 |
| [`context-menu/`](context-menu/) | 右键菜单项的排查与精简（含屏蔽 AMD Catalyst 扩展） |
| [`windows-update/`](windows-update/) | 把功能更新钉在 24H2、保留更新可见性的 `.reg` |

- `terminal/windows-terminal-and-wsl-configuration.md` 第二节记的是早期「把环境变量全写进
  `~/.zshrc`」的做法，已被四层分层取代；WSL 侧现行配置见 [`../shell/`](../shell/)。
- `powershell/SamplePSReadLineProfile_GitHub.ps1` 是第三方文件（BSD-2-Clause），不要改，见根目录 README 的许可证一节。
