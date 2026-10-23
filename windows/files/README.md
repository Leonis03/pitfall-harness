# Windows 侧可部署原件

这个目录只有**可部署原件** —— 复制到实机就用的文件。文档在上一级。

| 子目录 | 内容 | 部署到 |
| :--- | :--- | :--- |
| `powershell/` | `$PROFILE` 原件、关窗口脚本 | `%USERPROFILE%\Documents\PowerShell\`；脚本就地运行或做快捷方式 |
| `ime-keyboard/` | 幽灵键盘布局清理脚本 | 就地运行（自提升，备份写在当前工作目录） |
| `windows-update/` | 两个 Update 策略 `.reg` | 管理员 `reg import`，然后 `gpupdate /force` |
| `reference/` | 第三方参考文件 | **不部署** |

配置顺序和取舍见 [`../setup/README.md`](../setup/README.md)。

## 约定

- **全部纯 ASCII**，含注释。非 ASCII 在 WSL/Windows 边界、归档、shell 解析里会静默出问题。
- **`.ps1` 是 LF**（`.gitattributes` 的 `* text=auto eol=lf`），
  **`.reg` 是 CRLF**（显式 `*.reg text eol=crlf`，regedit 要的就是 CRLF）。
- **不含真实标识符**：`%USERPROFILE%` 之类由 shell 展开，其余用占位符，见 [`../../redaction.md`](../../redaction.md)。
- 原件不含版本号硬编码的路径。终端 profile 名、发行版名这类机器相关的值一律**现场探测**，
  见 [`../context-menu/README.md`](../context-menu/README.md) 第 9 节。

## reference/

`SamplePSReadLineProfile_GitHub.ps1` 是 [PowerShell/PSReadLine](https://github.com/PowerShell/PSReadLine)
官方示例 profile 的逐字副本（**BSD-2-Clause**，Jason Shirk）。

**不部署，也不要改。** 要自定义按键改 `powershell/Microsoft.PowerShell_profile.ps1`，
那份已经实现了同类功能并且是本仓库验证过的。要更新只能整目录重新逐字复制。
许可证归属见根 [`README.md`](../../README.md) 的 Third-party content 一节。
