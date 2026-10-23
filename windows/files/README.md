# Windows 侧可部署原件

这个目录只有**可部署原件** —— 复制到实机就用的文件。文档在上一级。

| 子目录 | 内容 | 部署到 |
| :--- | :--- | :--- |
| `powershell/` | `$PROFILE` 原件、关窗口脚本、代理环境变量写入脚本 | `%USERPROFILE%\Documents\PowerShell\`；脚本就地运行或做快捷方式 |
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
- **代理端口不写死在原件里**：`set-proxy-env.ps1` 的 `-Port` 是必填参数，端口是机器状态
  不是仓库内容；命令示例里写 `<proxy-port>`，部署时填本机客户端的混合口。

## powershell/set-proxy-env.ps1

写 Windows 用户级代理环境变量（`HKCU\Environment`）的脚本，**先探测端口再写**：

```powershell
pwsh -File .\set-proxy-env.ps1 -Port <proxy-port>
pwsh -File .\set-proxy-env.ps1 -Port <http-port> -SocksPort <socks-port>
```

端口没人监听时它**不写**（而是清掉旧值），因为指向死端口的变量会把每个走代理的请求
变成立刻被拒，而直连其实通着——这就是「终端突然没网」的成因。TUN 模式下客户端根本不
开本地端口，此时**变量应当不设**，脚本会提示这一点。写完广播 `WM_SETTINGCHANGE`，
让**之后新启动**的应用继承；已经在跑的进程仍持有旧环境，必须重启它。

**一个端口一个变量。** 混合口一个端口就够（同一 socket 既答 HTTP CONNECT 也答 SOCKS5
问候）；客户端分成两个口时必须两个都给：`ALL_PROXY` 指向 HTTP 口会得到
"Connection reset by peer"，因为那个口只答 CONNECT。两个口各探各的，**只写应答的那一对**。
背景见 [`../../git-github/README.md`](../../git-github/README.md) 第四节。

## reference/

`SamplePSReadLineProfile_GitHub.ps1` 是 [PowerShell/PSReadLine](https://github.com/PowerShell/PSReadLine)
官方示例 profile 的逐字副本（**BSD-2-Clause**，Jason Shirk）。

**不部署，也不要改。** 要自定义按键改 `powershell/Microsoft.PowerShell_profile.ps1`，
那份已经实现了同类功能并且是本仓库验证过的。要更新只能整目录重新逐字复制。
许可证归属见根 [`README.md`](../../README.md) 的 Third-party content 一节。
