# 不经 Microsoft Store 装 winget 和 Windows Terminal

适用场景：Windows 11 **LTSC / IoT Enterprise LTSC**、精简版、或任何没有 Microsoft Store
的镜像。这类镜像默认既没有 `winget`，也没有 Windows Terminal，两个都得手动侧载（sideload）。

> 相关：[`windows-terminal-and-wsl-configuration.md`](windows-terminal-and-wsl-configuration.md)（路径继承与
> `OSC 9;9`）、[`windows-terminal-system32-auto-home.md`](windows-terminal-system32-auto-home.md)（System32 自动回家）

---

## 一、为什么要绕开 Store

Store 版安装走的是 Appx 部署通道，没有 Store 就没有这条通道。但 `.msixbundle` 包本身
可以直接从 GitHub Release 下载，再用 `Add-AppxPackage` 注册——**完全不需要 Store，也不需要
 winget 自己**（这不是先有鸡还是先有蛋的问题：包是手下的，工具是装完才有的）。

前置条件只有一个：**PowerShell**（LTSC 自带 Windows PowerShell 5.1 就够）。

---

## 二、winget（App Installer）

### 1. 下载地址

`aka.ms/getwinget` 会 301 跳到 GitHub 上的真实文件，跟着跳就行：

```
https://aka.ms/getwinget
  -> https://github.com/microsoft/winget-cli/releases/download/<tag>/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
```

Release 页（拿最新 tag）：<https://github.com/microsoft/winget-cli/releases/latest>

想确认资源名同样用 `expanded_assets` 查，不要凭记忆拼：

```bash
curl -sSL https://github.com/microsoft/winget-cli/releases/expanded_assets/<tag>
```

v1.29.290 的实际资源里，除了 msixbundle 还有 `DesktopAppInstaller_Dependencies.zip`
（依赖包，见下节）和 `DesktopAppInstallerPolicies.zip`。

> **没有**「免注册便携版 zip」。`winget-cli_<version>_WindowsDesktop.zip` 那类文件在
> v1.29.290 的资源列表里并不存在，老笔记里的话不要信——要么装 Appx 包，要么不装。

### 2. 依赖

App Installer 的包自己声明了框架依赖。**v1.29.380 实际需要三个**：

| 依赖包 | 最低版本 | 说明 |
| :--- | :--- | :--- |
| `Microsoft.VCLibs.140.00` | `14.0.33519.0` | 通用 C++ 运行库 |
| `Microsoft.VCLibs.140.00.UWPDesktop` | `14.0.33728.0` | 桌面版 UWP 运行时 |
| `Microsoft.WindowsAppRuntime.1.8` | `8000.616.304.0` | **Windows App Runtime 1.8** |

权威来源是同一个 Release 里的清单文件，别凭记忆列依赖：

```powershell
curl.exe -sSL "https://github.com/microsoft/winget-cli/releases/download/v1.29.380/DesktopAppInstaller_Dependencies.json"
```

缺了就从同一个 Release 的 `DesktopAppInstaller_Dependencies.zip` 里取，
**不要在装不上去的时候才怀疑它**。压缩包按架构分目录（`x64/`、`x86/`、`arm64/`），
每个目录正好三个 `.appx`。

> ⚠️ **`Microsoft.WindowsAppRuntime.CBS` 不顶用。** 系统里可能已经装着 CBS 变体
> （版本号形如 `5001.x.x.x`），但它的包名是 `Microsoft.WindowsAppRuntime.CBS`，
> 部署校验要的是 `Microsoft.WindowsAppRuntime.1.8`——**包名不同，不通用**。
> 只查「有没有 WindowsAppRuntime」会得出错的结论。

解压并按顺序装（顺序有依赖，VCLibs 在前）。这些框架包按机器级注册，
用管理员权限的 PowerShell 执行：

```powershell
Expand-Archive -Path DesktopAppInstaller_Dependencies.zip -DestinationPath deps

Add-AppxPackage -Path deps\x64\Microsoft.VCLibs.140.00_14.0.33519.0_x64.appx
Add-AppxPackage -Path deps\x64\Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_x64.appx
Add-AppxPackage -Path deps\x64\Microsoft.WindowsAppRuntime.1.8_8000.616.304.0_x64.appx
```

架构按本机选：`$env:PROCESSOR_ARCHITECTURE` 是 `AMD64` 就用 `x64/`。

压缩包本身有官方校验值：同一个 Release 下的 `DesktopAppInstaller_Dependencies.txt`
就是它的 SHA-256。

```powershell
(Get-FileHash DesktopAppInstaller_Dependencies.zip -Algorithm SHA256).Hash
```

### 3. 验签再安装

**这一步不能省。** 下载走公网，先验微软签名再执行注册：

```powershell
$pkg = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
$sig = Get-AuthenticodeSignature $pkg
$sig.Status                                    # 必须是 Valid
$sig.SignerCertificate.Subject                 # 应为 CN=Microsoft Corporation
$sig.TimeStamperCertificate.Subject            # 应有官方时间戳
Add-AppxPackage -Path $pkg
```

---

## 三、Windows Terminal

### 1. ⚠️ 资源名在 v1.25 变了

老教程里的 `Microsoft.WindowsTerminal_<version>_x64__8wekyb3d8bbwe.msixbundle` **从 v1.25 起
不再带架构后缀**。拼错不会报「文件不存在」，而是下载下来一个 9 字节的 `Not Found`，
直到 `Add-AppxPackage` 才报 `0x80073CF0 ... 0x8007000D 打开文件失败`。

**别猜资源名**，直接查：

```bash
curl -sSL https://github.com/microsoft/terminal/releases/expanded_assets/<tag>
```

（`expanded_assets` 返回的是小段 HTML，比调 API 稳。tag 从
<https://github.com/microsoft/terminal/releases/latest> 的 302 `Location` 里取。）

v1.25.2733.0 的实际资源名形如：

```
Microsoft.WindowsTerminal_1.25.2733.0_8wekyb3d8bbwe.msixbundle
```

### 2. 验签再安装

Terminal 包自己声明的框架依赖是 `Microsoft.VCLibs.140.00.UWPDesktop` 和
`Microsoft.UI.Xaml.2.8`——第二个多数装机自带，缺了会报和 winget 一样的 `0x80073CF3`。
UWPDesktop 那个已经在第二节装好了。

```powershell
$pkg = "$env:TEMP\Microsoft.WindowsTerminal_1.25.2733.0_8wekyb3d8bbwe.msixbundle"
(Get-AuthenticodeSignature $pkg).Status        # Valid
Add-AppxPackage -Path $pkg
```

### 3. 验证

```powershell
winget --version
(Get-Command wt).Source    # 应指向 %LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe
```

`wt.exe` 本身只有 2 字节，内容就是 `MZ`——那是 **App Execution Alias**
（`IO_REPARSE_TAG_APPEXECLINK`）。这才是该用的那个；`Program Files\WindowsApps\`
下的真身直接执行会 `rc=126` 权限拒绝（详见 `wsl-windows-command` skill）。

---

## 四、代理环境下 TLS 会先挂掉

装了本地代理（Clash 之类）并且它做 HTTPS 中间人时，系统证书链校验过不去：

```
Invoke-WebRequest : The SSL connection could not be established
curl : schannel: failed to receive handshake
```

下载可以临时绕过证书校验：

```powershell
curl.exe -kSL -o $pkg <url>
```

**但绕过 TLS 不等于可以跳过验签。** 两条链路要分开：证书校验失败是代理的问题，
`Get-AuthenticodeSignature` 验的是包自带的微软签名，跟系统证书链是两回事。
所以做法是——传输层放宽，包体层照验。

---

## 五、装完之后：`msstore` 源用不了

LTSC 没有 Store，`winget source list` 里那个 `msstore` 源是死的。装包时显式指定源：

```powershell
winget install <PackageId> --source winget
```

想彻底清掉（会影响少数只在该源的包，自行取舍）：

```powershell
winget source remove msstore
```

---

## 六、验证清单

| 检查项 | 命令 | 期望 |
| :--- | :--- | :--- |
| 依赖框架齐了 | `Get-AppxPackage \| Where-Object { $_.Name -match 'WindowsAppRuntime\.1\.8\|VCLibs' }` | 三个依赖都在，版本不低于第二节的表 |
| winget 版本 | `winget --version` | `v1.x.y.z` |
| 联网可用 | `winget search --id Microsoft.PowerShell --source winget` | 返回结果列表 |
| wt 别名 | `where.exe wt` | `%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe` |
| 包已注册 | `Get-AppxPackage Microsoft.WindowsTerminal` | Version 字段非空 |

> 装不上时先看 `0x80073CF3` 还是 `0x80073CF0`：前者是**依赖框架缺失**（回到第二节），
> 后者是**包文件本身有问题**（9 字节的 `Not Found`，见第三节）。两者报错长得像，成因完全不同。
