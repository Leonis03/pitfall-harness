# Windows 11 LTSC 环境配置 runbook

> **用途**：在一台**刚装好 Windows 11 LTSC / IoT Enterprise LTSC 的全新机器**上，把终端、
> PowerShell、输入法、右键菜单、Windows Update 策略配成本仓库验证过的样子。
>
> **使用方式**：把本文件整份交给 Claude Code / Antigravity / Codex 这类能操作系统的 Agent，
> 让它照着做。**不要只丢给一个只会回答问题的对话框。**
>
> **本文基准**：2026-10-18 在 Windows 11 IoT Enterprise LTSC + PowerShell 7 上实测。参考环境
> 与差异见 [`../README.md`](../README.md)。
>
> **不覆盖**：Windows 系统安装本身、驱动、Linux Mint 双系统的分区与 UEFI。装完系统、拿到
> 管理员权限之后才开始用本文。双系统是另一件事，仓库里目前没有对应文档。

---

## 零、Agent 必须遵守的流程

这一节优先级最高。**跳过任何一条都是在给用户制造一台坏机器。**

### 0.1 先探测，后计划

**不许跳过步骤 1 直接开配置。** 本仓库里所有「本机实测」表格都是某一台机器在某一时刻的快照。
换一台机器，硬编码的路径、profile 名、发行版名、注册表 GUID 有一半是错的，而且是**静默错**
——命令不报错，只是打开了错误的东西。

本仓库里的 Agent 全局规则文件开头就写着这句话（英文原文）：

> This machine's toolchain drifts, so re-verify instead of trusting a remembered baseline.

### 0.2 输出配置清单，等用户确认

探测完成后，**先输出一张表**，不要边探测边改。每行一项：

| 项目 | 本机现状 | 是否默认 | 依赖 | 风险 | 可逆性 |
| :--- | :--- | :--- | :--- | :--- | :--- |

- **本机现状**填步骤 1 的探测结果，不要填你的预期。
- **风险**栏写清楚会发生什么，不是写「低/中/高」。
- **可逆性**栏写清楚怎么撤回。无备份的注册表写入一律标「需先备份」。

### 0.3 可选项必须逐项问用户

**即使某一项有推荐默认值，也必须问。** 禁止「按默认来」「按常规配置」这类说法。

用户答完之后，把选择回填进清单表再开始。**无默认值、有风险、不可逆的项**要在正文里单独列出来，
不要淹没在表格里。

### 0.4 一次一步，每步验证

改完一项立刻跑它的验证命令，把实际输出回报给用户。**命令失败了就停下查原因，不要接着跑下一条**
——本仓库的
[`../../windows/powershell/powershell-scripting-pitfalls.md`](../../windows/powershell/powershell-scripting-pitfalls.md)
第 11 条记的就是这个：命令失败后不看就继续，并行出错，最后不知道是哪一条坏的。

### 0.5 动注册表前先备份

本步骤不是可选的。步骤 4、5、6 写的是 `HKCU`，**步骤 7 写的是 `HKLM`** —— 两个 hive 各导一次，
HKCU 的备份救不了 HKLM：

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out   = Join-Path $env:USERPROFILE "Desktop\reg-backup-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
reg export 'HKCU\Software\Classes' "$out\hkcu-classes.reg" /y
reg export 'HKCU\Software\Classes\Directory\ContextMenus' "$out\hkcu-ctxmenus.reg" /y 2>$null

# 步骤 7 的目标。键不存在时 reg export 会报错退出、不产出文件，
# 那是「本机还没有这套策略、没有东西可回滚」，不是失败 —— 照样把结论报给用户。
$wu = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
if (Test-Path $wu) {
    reg export 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' "$out\hklm-windowsupdate.reg" /y
} else {
    "no existing WindowsUpdate policy key -- nothing to roll back to; first import is a clean add"
}
```

没有备份文件就不许写。备份目录要告诉用户在哪。

### 0.6 关于 `wsl-windows-command` skill

**本文的每一步都在原生 Windows 上执行，不需要那个 skill。** 它是 WSL 侧专用的：全程用
`/mnt/c/...` 路径，靠 interop 桥接调 `powershell.exe`。原生 Windows 上 `/mnt/c` 不存在，
`%USERPROFILE%` 本来就是对的。

只有一种情况用得上：Agent 实际跑在 WSL 或 Linux Mint 里，要从那边驱动 Windows。那时才用它，
并且注意它记的编码坑（`wsl.exe` 被捕获时输出 UTF-16LE，每个字符后面跟一个 NUL，正则匹配不上，
解析前先 `tr -d '\0'`）。

---

## 一、参考环境与已知差异

2026-10-18 在下面这台机器上实测通过：

| 项 | 值 |
| :--- | :--- |
| 系统 | Windows 11 IoT Enterprise LTSC |
| 终端 | Windows Terminal（免 Store 侧载） |
| Shell | PowerShell 7（`pwsh`），profile 在 `%USERPROFILE%\Documents\PowerShell\` |
| WSL | Debian 13 (trixie) on WSL2 |
| 中文输入 | 搜狗拼音 |

**换机器时最容易踩的四处**（本仓库另有实测记录，[`../context-menu/README.md`](../context-menu/README.md)
第 8 节）：

| 项 | 换机器后的差异 |
| :--- | :--- |
| WSL 发行版名 | 不是 `Ubuntu`（本机是 `Debian`），**必须现查** |
| 终端图标 | 包里只有 `terminal_contrast-black.ico` / `terminal_contrast-white.ico`，没有普通版 `terminal.ico` |
| 显卡扩展 CLSID | 没有 AMD 驱动就根本没注册，屏蔽它是空操作 |
| 右键菜单位置 | `shell\` 下的传统词条只出现在「显示更多选项」（Shift + 右键）里 |

---

## 二、步骤 1：探测（只读，禁止跳过）

整段跑完，把输出原样报给用户。**这一段不改任何东西。**

```powershell
# ---- 系统与构建 ----
$os = Get-CimInstance Win32_OperatingSystem
"OS       : $($os.Caption) $($os.Version) build $($os.BuildNumber)"
"Arch     : $env:PROCESSOR_ARCHITECTURE"
"Locale   : system=$((Get-Culture).Name) ui=$((Get-UICulture).Name)"
"Admin    : " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"PowerShell: $($PSVersionTable.PSVersion)"

# ---- Store 在不在（LTSC 通常没有，这决定步骤 2 要不要做）----
"Store pkg: " + [bool](Get-AppxPackage Microsoft.WindowsStore -ErrorAction SilentlyContinue)

# ---- 侧载的 winget / 终端在不在 ----
"winget pkg : " + ((Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue).Version -join ',')
"Terminal   : " + ((Get-AppxPackage Microsoft.WindowsTerminal     -ErrorAction SilentlyContinue).Version -join ',')

# ---- 命令解析：这是最容易骗人的一段，见 0.1 ----
foreach ($n in 'winget','wt','pwsh','python','python3','python3.12','uv','node','npm','git','jq','bash','wsl') {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($c) {
        $sz = try { (Get-Item $c.Source -ErrorAction Stop).Length } catch { '?' }
        "{0,-12} -> {1}  ({2} bytes)" -f $n, $c.Source, $sz
    } else { "{0,-12} -> (not found)" -f $n }
}

# ---- 现有 $PROFILE：改之前必须先备份它 ----
foreach ($p in $PROFILE.CurrentUserCurrentHost, $PROFILE.CurrentUserAllHosts) {
    "{0,-46} exists={1}" -f $p, (Test-Path $p)
}

# ---- 语言与键盘布局：步骤 5 的输入 ----
"--- WinUserLanguageList ---"
Get-WinUserLanguageList | Format-List LanguageTag, Autonym, InputMethodTips

"--- HKCU Preload (幽灵键盘布局藏在这里) ---"
(Get-ItemProperty 'HKCU:\Keyboard Layout\Preload' -ErrorAction SilentlyContinue).PSObject.Properties |
    Where-Object { $_.Name -notmatch '^PS' } |
    ForEach-Object { "  {0} = {1}" -f $_.Name, $_.Value }

"--- HKCU Substitutes ---"
(Get-ItemProperty 'HKCU:\Keyboard Layout\Substitutes' -ErrorAction SilentlyContinue).PSObject.Properties |
    Where-Object { $_.Name -notmatch '^PS' } |
    ForEach-Object { "  {0} = {1}" -f $_.Name, $_.Value }

# ---- 终端 profile 名：步骤 6 的输入，不能照抄别的机器的 ----
"--- Windows Terminal profile names ---"
$st = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $st) {
    (Get-Content $st -Raw | ConvertFrom-Json).profiles.list |
        Select-Object name, guid, source |
        Format-Table -AutoSize
} else { "  settings.json not found: $st" }
```

**关于最后那段命令名解析**：文件大小是线索，不是结论。0 字节的 `winget` / `wt` 是 App Execution
Alias，正常工作；0 字节的 `bash` 曾经是打不开的 Store 存根。两者在文件系统里长得一模一样。
唯一的判据是**实际调用一次**：

```powershell
$c = Get-Command <name> -ErrorAction SilentlyContinue
$c.Source; (Get-Item $c.Source).Length   # 0-2 字节 => reparse point，得再查
& $c.Source --version                    # 这才是真正的测试
```

**有些命令永远不要探测**，探测本身会出事（弹窗、下载页、卡住）：
`wt --version`（GUI 应用，什么都不打印）、`wslconfig`（开 GUI 窗口不返回）、
以及任何 Store 别名被关掉后的 `bash`。方法见
[`../../agent/windows-agent/ghost-commands.md`](../../agent/windows-agent/ghost-commands.md)。

---

## 三、步骤 2：侧载 winget 与 Windows Terminal

> **可选项。** 先问用户：LTSC 通常没有 Store，但有人镜像里已经带了这两个包，
> 或者用户本来就想用 Store 装。**探测到已安装就跳过这步。**

**为什么**：Store 版安装走 Appx 部署通道，没有 Store 就没有这条通道。但 `.msixbundle` 可以
直接从 GitHub Release 下载，再用 `Add-AppxPackage` 注册——不需要 Store，也不需要 winget 自己
（包是手下的，工具是装完才有的）。前置条件只有 PowerShell，LTSC 自带的 5.1 就够。

### 2.1 取资源名，不要猜

**资源名带版本号，且变过格式。** 拼错不会报「文件不存在」，而是下载下来一个 9 字节的
`Not Found`，直到 `Add-AppxPackage` 才报 `0x80073CF0 ... 0x800700D 打开文件失败`。

老教程里的 `Microsoft.WindowsTerminal_<version>_x64__8wekyb3d8bbwe.msixbundle`
**从 v1.25 起不再带架构后缀**。所以现查：

```powershell
# 取最新 tag（跟随 302，Location 里就是 tag）
$wtTag = (curl.exe -sI 'https://github.com/microsoft/terminal/releases/latest' |
          Select-String -Pattern '^location:' ).ToString() -replace '.*/tag/|\r',''
"Terminal tag: $wtTag"

# 展开资源列表，返回的是小段 HTML，比调 API 稳
curl.exe -sSL "https://github.com/microsoft/terminal/releases/expanded_assets/$wtTag" |
    Select-String -Pattern 'msixbundle' -AllMatches
```

winget 同理（`aka.ms/getwinget` 会 301 到真实文件，跟着跳就行）：

```powershell
$wgTag = (curl.exe -sI 'https://github.com/microsoft/winget-cli/releases/latest' |
          Select-String -Pattern '^location:' ).ToString() -replace '.*/tag/|\r',''
curl.exe -sSL "https://github.com/microsoft/winget-cli/releases/expanded_assets/$wgTag" |
    Select-String -Pattern 'msixbundle|Dependencies' -AllMatches
```

> **没有「免注册便携版 zip」。** `winget-cli_<version>_WindowsDesktop.zip` 那类文件在
> v1.29.290 的资源列表里并不存在，老笔记里的话不要信。要么装 Appx 包，要么不装。

### 2.2 先查依赖

**要在装之前查**，不要等装不上去才怀疑。App Installer v1.29.380 声明了**三个**框架依赖：

| 依赖包 | 最低版本 |
| :--- | :--- |
| `Microsoft.VCLibs.140.00` | `14.0.33519.0` |
| `Microsoft.VCLibs.140.00.UWPDesktop` | `14.0.33728.0` |
| `Microsoft.WindowsAppRuntime.1.8` | `8000.616.304.0` |

权威清单是同一个 Release 里的 `DesktopAppInstaller_Dependencies.json`，别凭记忆列：

```powershell
curl.exe -sSL "https://github.com/microsoft/winget-cli/releases/download/v1.29.380/DesktopAppInstaller_Dependencies.json"

# 再和本机已注册的对比
Get-AppxPackage | Where-Object { $_.Name -match 'VCLibs|WindowsAppRuntime' } |
    Select-Object Name, Version
```

Windows Terminal 自己的框架依赖另有两个：`Microsoft.VCLibs.140.00.UWPDesktop`（同上）
和 `Microsoft.UI.Xaml.2.8`——后者多数装机自带，缺了会报同样的 `0x80073CF3`。

> ⚠️ **`Microsoft.WindowsAppRuntime.CBS` 不顶用。** 机器上可能已经装着 CBS 变体
> （版本号形如 `5001.x.x.x`），但部署校验要的是 `Microsoft.WindowsAppRuntime.1.8`，
> **包名不同，不通用**。只查「有没有 WindowsAppRuntime」会得出错的结论。

缺了就从同一个 Release 的 `DesktopAppInstaller_Dependencies.zip` 里取（按架构分
`x64/`、`x86/`、`arm64/` 三个目录），按顺序装，顺序有依赖：

```powershell
Expand-Archive -Path DesktopAppInstaller_Dependencies.zip -DestinationPath deps

Add-AppxPackage -Path deps\x64\Microsoft.VCLibs.140.00_14.0.33519.0_x64.appx
Add-AppxPackage -Path deps\x64\Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_x64.appx
Add-AppxPackage -Path deps\x64\Microsoft.WindowsAppRuntime.1.8_8000.616.304.0_x64.appx
```

框架包按机器级注册，用管理员权限的 PowerShell 装。压缩包的官方 SHA-256 在同一个
Release 下的 `DesktopAppInstaller_Dependencies.txt` 里，验完再解。

### 2.3 验签再安装

**这一步不能省。** 下载走公网，先验微软签名再执行注册：

```powershell
$pkg = Join-Path $env:TEMP 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
curl.exe -kSL -o $pkg 'https://aka.ms/getwinget'

$sig = Get-AuthenticodeSignature $pkg
$sig.Status                          # 必须是 Valid
$sig.SignerCertificate.Subject       # 应为 CN=Microsoft Corporation
$sig.TimeStamperCertificate.Subject  # 应有官方时间戳
Add-AppxPackage -Path $pkg
```

终端同样三步：下载 → `(Get-AuthenticodeSignature $pkg).Status` 为 `Valid` → `Add-AppxPackage`。

> **代理环境下 TLS 会先挂掉。** 装了做 HTTPS 中间人的本地代理（Clash 之类）时，
> `Invoke-WebRequest : The SSL connection could not be established` 或
> `curl : schannel: failed to receive handshake` 都是这个原因，上面已经用了 `curl.exe -kSL`。
>
> **但绕过 TLS 不等于可以跳过验签。** 两条链路要分开：证书校验失败是代理的问题，
> `Get-AuthenticodeSignature` 验的是包自带的微软签名，跟系统证书链是两回事。
> 传输层放宽，包体层照验。

---

## 四、步骤 3：PowerShell profile

> **可选项。** 默认配置。用户不一定要 Emacs 键位和智能引号。**问。**

**为什么**：这些功能（Emacs 编辑模式、历史前缀搜索、Token 级移动、智能括号引号、预测建议）
都是 PSReadLine 提供的，装 PowerShell 7 时就有，只是没绑按键。绑完日常操作会快很多。
第 0 节（编码 + 报错语言）则是为了中文环境下脚本不再输出乱码和中文报错。

### 3.1 先备份现有 profile

```powershell
$pf = $PROFILE.CurrentUserCurrentHost
if (Test-Path $pf) { Copy-Item $pf "$pf.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
$dir = Split-Path $pf
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
```

### 3.2 部署原件

从本仓库复制 `windows/files/powershell/Microsoft.PowerShell_profile.ps1` 到上一步的 `$pf` 路径。

> **不要把 profile 写在命令行里传。** 332 行、含引号和反引号，命令行长度和引号转义会先出问题。
> 写成文件再复制，见
> [`../../windows/powershell/powershell-scripting-pitfalls.md`](../../windows/powershell/powershell-scripting-pitfalls.md)
> 第 8 条「变量名撞车：路径被当成文件名」。
>
> **复制后检查行尾**：profile 必须是 **LF**。`edit` 类工具会按文件现有行尾归一化，改行尾只能
> 整文件重写，见 [`../../windows/powershell/cjk-command-io.md`](../../windows/powershell/cjk-command-io.md) 第 4.1 节。

### 3.3 功能清单与按键

原件共 9 节：

| 节 | 功能 | 默认开关 |
| :--- | :--- | :--- |
| 0 | 控制台编码 UTF8 + 报错语言 `en-US` + `PYTHONUTF8` | 开 |
| 1 | Emacs 编辑模式（`Ctrl+A`/`Ctrl+E`/`Ctrl+K`） | 开 |
| 2 | 历史前缀搜索（`↑`/`↓`） | 开 |
| 3 | `Alt+w` 暂存当前行到历史（不执行） | 开 |
| 4 | Token 级单词移动（`Alt+b`/`Alt+f`/`Alt+d`/`Alt+Backspace`） | 开 |
| 5 | 智能括号与引号，含 AST 判断 + 成对退格 | 开 |
| 6 | 预测建议（`→` 接受整行，`Ctrl+→` 接受一个词） | 开 |
| 7 | System32 / SysWOW64 自动转 `~` | 可关 |
| 8 | 终端路径实时上报 `OSC 9;9` | 可关 |

**第 7、8 节要问用户**：新手可能不习惯一开终端就被踢回用户目录；
`OSC 9;9` 只有在 Windows Terminal 里才有意义，其它终端是无害的空操作。

> **第 0 节的报错语言不是 `$PSUILanguage`。** PowerShell 7.4 引入了 `$PSUILanguage`，实测 7.6.7 上
> 设成 `en-US` 变量确实变了，报错**仍然是中文**；只有 `[Threading.Thread]::CurrentThread.CurrentUICulture`
> 真起作用。三个开关（代码页 / 报错语言 / `$PSUILanguage`）互相独立，别当一回事。

### 3.4 立即生效

```powershell
. $PROFILE          # 重载
```

---

## 五、步骤 4：终端路径与 System32 自动规避

> **可选项。** 默认配置，依赖步骤 3。**问。**

**为什么**：以管理员身份启动 `pwsh` 时，工作目录会变成 `C:\Windows\System32`，之后每条相对路径
命令都得写全路径。配置后只在**启动瞬间**跳回 `~`，之后日常手动 `cd` 不受影响。

### 5.1 探测，不要照抄

路径候选在多台机器上不一致，**现找**：

```powershell
$cands = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
) | Where-Object { Test-Path $_ }
$cands
if (-not $cands) { "NONE FOUND -- do not guess the path, ask the user" }
```

> **本仓库不下发 `settings.json` 原件，这是有意的。** 它含每台机器自己的默认 profile GUID、
> 配色方案、自定义键位，整份下发会覆盖用户已有配置。要改哪一项就用 `ConvertFrom-Json`
> 读出来、改、写回去，例如把 `startingDirectory` 设为 `null`（让新标签页继承当前路径）。
> 现成配方见
> [`../../windows/terminal/windows-terminal-system32-auto-home.md`](../../windows/terminal/windows-terminal-system32-auto-home.md)
> 第二节。

### 5.2 右键菜单改成原生 Terminal 调用

管理员和非管理员两处都要注册，先备份（流程 0.5 已备好）。

```powershell
$ctx = 'HKCU:\Software\Classes\Directory\ContextMenus\PowerShell7x64'
# 现查本机的命令，不要照抄 'PowerShell' 这个 profile 名
$profName = (Get-Content $st -Raw | ConvertFrom-Json).profiles.list |
    Where-Object { $_.source -eq 'Microsoft.PowerShell' } |
    Select-Object -First 1 -ExpandProperty name
"profile name: $profName"
```

> 本仓库记录的是 `PowerShell7x64` 这个键名，来自 x64 MSI 布局。**别的安装方式键名不同**
> （MSIX 安装是 `Directory\ContextMenus\WindowsTerminal` 之类）。先列出
> `HKCU:\Software\Classes\Directory\ContextMenus` 看实际有哪些，再决定写哪个。

**验证**：`ShellNew` → 右键应出现「使用 PowerShell 打开」；以管理员身份在桌面右键同理。

---

## 六、步骤 5：输入法与键盘布局

> **可选项，但很痛。** 只有当切换输入法时弹出「德语 / 希腊语 / 俄语」这些没装过的键盘布局时
> 才需要做。**先问用户有没有这个症状**，没有就跳过。

**为什么**：卸载一个语言后，它的键盘布局常常留在语言切换器里。布局数超过 4 个时 `Ctrl+Shift`
一次轮不完，得连按多次才能回到中文，体感像「输入法失灵」。

### 6.1 先看现状

步骤 1 的 `HKCU:\Keyboard Layout\Preload` / `Substitutes` 输出就是输入。常见幽灵键位是
`de-DE`、`el-GR`、`ru-RU` 这类——装了对应语言才该出现。

**只删没装过的。** 装过的语言（中文简体、英文 US）必须留着。

### 6.2 跑清理脚本

```powershell
pwsh -NoProfile -File <repo>\windows\files\ime-keyboard\fix-keyboard-layouts.ps1
```

脚本会**自提升**（自己请求管理员），并在改之前把 4 个注册表键导出成 `.reg` 备份，
再 `Set-WinUserLanguageList -Force`。

> 备份和日志写在**脚本的当前工作目录**下，文件名 `FixKeyboardLayouts_<时间戳>.log`
> 和几个 `.reg`。**跑之前先告诉用户会写在哪里**，跑完把路径报出来。
>
> 脚本末尾有一份硬编码的清理包列表 `@('de-DE','el-GR','ru-RU')`。
> **不要照抄到别的语言组合上**——先按 6.1 的实际输出改，再跑。

### 6.3 云同步会加回来

OneDrive / 账号同步可能把删掉的布局重新注册回来。同步设置里「语言」一项可以单独排除。

---

## 七、步骤 6：右键菜单（Terminal / WSL）

> **可选项。** 依赖步骤 2、3 装好终端，且装了 WSL。**问。**

**为什么**：`shell\` 下的传统词条只出现在「显示更多选项」（Shift + 右键）里，不值得为它多按一次
Shift。注册到 `Drive` / `Directory` / `DesktopBackground` 三个位置才能在普通右键里直接看到。

### 7.1 三个值必须现场取

**这是本仓库明确记过的一条：`.reg` 无法参数化，写死反而误导，所以没有 `.reg` 原件。**
（见 [`../context-menu/README.md`](../context-menu/README.md) 第 10 节的说明。）

| 值 | 怎么取 |
| :--- | :--- |
| 终端 profile 名 | `(Get-Content $st -Raw \| ConvertFrom-Json).profiles.list \| Where-Object { $_.source -eq 'Microsoft.PowerShell' }` |
| WSL 发行版/profile 名 | 同上，`source -eq 'Microsoft.WSL'`。**不是发行版名本身** |
| `wt.exe` 路径 | `(Get-Command wt).Source` |

> `wt.exe -p "Ubuntu"` 里的 `-p` 传的是 **Windows Terminal 的 profile 名称**，不是 WSL 发行版名。
> 名字对不上时 wt 报错或回落到默认 profile，于是「Open in WSL」打开的是 PowerShell。
> 本机当时是 `Debian`，但**必须现查**。

### 7.2 图标从安装包里取

```powershell
$wtApp = Get-AppxPackage -Name Microsoft.WindowsTerminal | Select-Object -First 1
Copy-Item "$($wtApp.InstallLocation)\Images\terminal_contrast-black.ico" `
          "$env:LOCALAPPDATA\Microsoft\WindowsTerminal\terminal.ico"
```

包目录带版本号会随更新变化，**所以现取**。

> **别用 `Icon.ExtractAssociatedIcon` 从 exe 抽图标。** 实测抽出来只有 766 字节（单尺寸），
> 放进右键菜单放大发虚；包里那份是 43 KB 多分辨率。

### 7.3 AMD 右键扩展：先确认它注册过

```powershell
Test-Path 'Registry::HKEY_CLASSES_ROOT\CLSID\{fdadfee3-02d1-4e7c-a511-380f4c98d73b}'
```

返回 `$false`（没装 AMD 驱动）就**不要写屏蔽项**，写了是空操作，还会在清单里制造一个
「已配置」的假象。

### 7.4 需要注册的词条

`WindowsTerminal` × 5（`DesktopBackground`、`Drive\Background`、`Drive`、`Directory\Background`、
`Directory`），`OpenInWSL` × 5（同样 5 个位置）——各带 `(default)` 与 `Icon` 两个属性，
`command` 子键放实际命令行。完整路径、数据类型、内容见
[`../context-menu/README.md`](../context-menu/README.md) 第 7 节的表，**照表重建，不要复制别机的值**。

---

## 八、步骤 7：Windows Update 策略

> **可选项，有风险。** 默认**不装**，除非用户明确要求钉版本。**必须问，默认答案是「先不装」。**

**为什么**：功能更新会把你从 24H2 推到 25H2，LTSC 用户多半不想。但钉版本会**同时屏蔽掉一部分
质量更新和驱动更新的可见性**，这是真实代价，不是零成本。

```powershell
# 先问：钉哪个版本？现在是什么版本？
(Get-CimInstance Win32_OperatingSystem).Version
```

| 原件 | 做什么 | 什么时候用 |
| :--- | :--- | :--- |
| `../files/windows-update/wu-stay-24h2-notify.reg` | 钉版本 + 下载/安装前通知 | 明确不想收到下一个功能更新 |
| `../files/windows-update/wu-notify-minimal.reg` | 只改通知策略，不钉版本 | 只想要「更新前先问我」 |

两个都是纯 ASCII、**CRLF** 行尾（根 `.gitattributes` 把 `*.reg` 钉成 `eol=crlf`，regedit 要的就是
CRLF），导入后重启或 `gpupdate /force` 生效。

> **这两个 `.reg` 里的版本号是写死的**（`ProductVersion "Windows 11"` / `24H2`）。在别的版本上导入
> 会得到一个你**没打算要**的钉版本策略。**先跑上面那条命令确认当前版本，再决定用哪个，
> 必要时先改文件。**

**撤回**：`reg import` 流程 0.5 导出的 `hklm-windowsupdate.reg`，或删掉这两个策略键后
`gpupdate /force`。若 0.5 报的是「键不存在」，说明这台机器本来就没有这套策略，
撤回就只是删键。

---

## 九、验证清单

全部执行并核对预期值。**任何一项不符，回到对应步骤，不要继续往下配。**

```powershell
# 1. 侧载的工具在位
#    预期：winget 输出 v1.x.y.z；Terminal 的 Version 非空
winget --version
(Get-AppxPackage Microsoft.WindowsTerminal).Version

# 1b. 依赖框架齐了
#     预期：三个都在（VCLibs.140.00 / VCLibs.140.00.UWPDesktop /
#            WindowsAppRuntime.1.8），版本不低于 2.2 的表
#     注意：Microsoft.WindowsAppRuntime.CBS 不算，它包名不同
Get-AppxPackage | Where-Object { $_.Name -match 'VCLibs|WindowsAppRuntime' } |
    Select-Object Name, Version

# 2. 联网可用（LTSC 没有 Store，msstore 源是死的，显式指定源）
#    预期：返回结果列表，不报源不可用
winget search --id Microsoft.PowerShell --source winget

# 3. profile 加载没有报错
#    预期：无异常。加载一次静默失败是最常见的翻车方式
pwsh -NoProfile -Command 'exit 0'   # 确认 -NoProfile 干净
pwsh -Command '$PROFILE; . $PROFILE; "profile loaded"'   # 预期打印 profile 路径和 loaded

# 4. 控制台编码生效
#    预期：全部 65001；CurrentUICulture 是 en-US
chcp
[Console]::InputEncoding.CodePage
[Console]::OutputEncoding.CodePage
[Threading.Thread]::CurrentThread.CurrentUICulture.Name

# 5. PSReadLine 键位真的绑上了（不是文件写了但没生效）
#    预期：逐条列出绑定；没有输出说明 profile 没加载成功
Get-PSReadLineKeyHandler -Chord 'Alt+b'
Get-PSReadLineKeyHandler -Chord 'Alt+w'
Get-PSReadLineOption | Select-Object EditMode

# 6. 幽灵键盘布局清干净了
#    预期：Preload 里只剩装过的语言，没有 de-DE / el-GR / ru-RU 这类
(Get-ItemProperty 'HKCU:\Keyboard Layout\Preload').PSObject.Properties |
    Where-Object { $_.Name -notmatch '^PS' } | Select-Object Name, Value

# 7. 右键菜单词条注册成功（数量对上，且 -p 的名字是本机的）
#    预期：两个词条各报 n/5。5 是 7.4 的全集；少于此说明只注册了一部分。
#    注意：不要用正则扫 HKCU:\Software\Classes 全树。叶子名匹配会命中
#    Local Settings\MrtCache\...\resources.pri 和 PackagedCom\Package\... 这些无关键，
#    2026-10-19 在 Windows 11 Pro 实测：6 行输出里只有 2 行是真词条，其余是噪声。
$roots = 'DesktopBackground', 'Drive', 'Drive\Background', 'Directory', 'Directory\Background'
foreach ($v in 'WindowsTerminal', 'OpenInWSL') {
    $found = @($roots | Where-Object { Test-Path "HKCU:\Software\Classes\$_\shell\$v" })
    "{0,-15} {1}/5  {2}" -f $v, $found.Count, ($found -join '  ')
}

# 7b. 命令里的 -p 名字必须能在 Terminal 的 profile 列表里找到。否则 wt 静默回落到默认
#     profile，「Open in WSL」打开的就是 PowerShell（见 7.1）——只扫键名是查不出来的。
#     这条必须自己报「没找到 -p」。只匹配 -p "名字"（带引号）的话，命令写成
#     -p 名字 或 --profile 时正则一条都不中，整段没有任何输出，看上去像「检查通过」。
$st = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (-not (Test-Path $st)) { $st = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json" }
$profNames = @((Get-Content $st -Raw | ConvertFrom-Json).profiles.list.name)

$cmds = @($roots | ForEach-Object { "HKCU:\Software\Classes\$_\shell\OpenInWSL\command" } |
    Where-Object { Test-Path $_ } | ForEach-Object { (Get-Item $_).GetValue('') })

# -p "x" / -p x / --profile "x" / --profile=x 都认；带空格的 profile 名要靠引号那一支
$profiles = @($cmds | ForEach-Object {
    [regex]::Matches($_, '(?:-p|--profile)[=\s]+(?:"([^"]+)"|([^\s"]+))') |
        ForEach-Object {
            if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
        }
} | Sort-Object -Unique)

if ($profiles.Count -eq 0) {
    "  没找到 -p / --profile：这条没有检查到任何东西，不是通过。"
    $cmds | ForEach-Object { "    command: $_" }
} else {
    $profiles | ForEach-Object {
        if ($profNames -contains $_) { "  -p '$_'  本机 profile 存在" }
        else { "  -p '$_'  不存在 <- wt 会回落，Open in WSL 会打开 PowerShell" }
    }
}

# 8. Update 策略落地
#    预期：TargetReleaseVersion 是你选的；NoAutoReboot 存在
reg query 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

# 9. 这套策略对 WSL 完全无效
#    预期：确认 WSL 发行版仍能正常用；Windows 的更新策略管不到 WSL 的内核更新
wsl --status
```

> 第 3 条那个 `pwsh -NoProfile -Command 'exit 0'` 值得单独说一句：**`-NoProfile` 干净退出、
> 带 `-Command` 就报错**，说明错误确实来自 profile，而不是环境本身。这个对照能把问题定位到文件。

---

## 十、常见问题

**`wt --version` 什么都不打印**
正常。`wt.exe` 是 GUI 应用，没有控制台输出。用 `Get-AppxPackage` 查版本。

**`Add-AppxPackage` 报 `0x80073CF0 ... 0x800700D 打开文件失败`**
九成是下载到了 9 字节的 `Not Found` 页而不是包——资源名拼错了，回 2.1 现查。

**`Add-AppxPackage` 报 `0x80073CF3 ... depends on a framework that could not be found`**
**依赖框架缺失，不是包坏了。** 回 2.2 按清单补齐（多半是
`Microsoft.WindowsAppRuntime.1.8`），再重试装主包。注意别被
`Microsoft.WindowsAppRuntime.CBS` 骗了——包名不同，部署校验不认。

**`curl : schannel: failed to receive handshake`**
代理做 HTTPS 中间人。传输层用 `curl.exe -kSL` 绕过，但**包体签名照验**，见 2.3。

**改了 `$PROFILE` 但按键完全没反应**
profile 没加载。先 `Test-Path $PROFILE` 确认路径对，再看是不是 PowerShell 5.1 和 7 各有一份
（`$PROFILE` 是按 host 分的，5.1 在 `Documents\WindowsPowerShell\`，7 在 `Documents\PowerShell\`）。

**`Ctrl+Shift` 轮一圈回不到中文**
幽灵键盘布局，见步骤 5。

**右键「Open in WSL」打开的是 PowerShell**
`-p` 传的 profile 名不存在，wt 回落到了默认 profile。现查，见 7.1。

**中文脚本输出乱码**
控制台代码页不是 65001。profile 第 0 节应该已经设了，确认它加载了；
`Set-Content` 写文件还有 BOM 和行尾两个独立的坑，见
[`../powershell/cjk-command-io.md`](../powershell/cjk-command-io.md) 第 4 节。

**报错是中文，$PSUILanguage 设了 en-US 也没用**
只有 `CurrentUICulture` 管这个，见 3.3 的说明。

---

## 十一、相关文件

| 文件 | 是什么 |
| :--- | :--- |
| [`../files/powershell/Microsoft.PowerShell_profile.ps1`](../files/powershell/Microsoft.PowerShell_profile.ps1) | 步骤 3 的原件 |
| [`../files/ime-keyboard/fix-keyboard-layouts.ps1`](../files/ime-keyboard/fix-keyboard-layouts.ps1) | 步骤 5 的脚本 |
| [`../files/windows-update/`](../files/windows-update/) | 步骤 7 的两个 `.reg` |
| [`../powershell/profile-features.md`](../powershell/profile-features.md) | profile 功能的 canonical 文档 |
| [`../powershell/powershell-scripting-pitfalls.md`](../powershell/powershell-scripting-pitfalls.md) | 用 shell 驱动 PowerShell 时自己骗自己的地方 |
| [`../powershell/cjk-command-io.md`](../powershell/cjk-command-io.md) | 编码、报错语言、BOM 与行尾 |
| [`../context-menu/README.md`](../context-menu/README.md) | 右键菜单全表 + 换机器差异 |
| [`../terminal/windows-terminal-system32-auto-home.md`](../terminal/windows-terminal-system32-auto-home.md) | `settings.json` 改法与注册表配方 |
| [`../terminal/winget-and-terminal-without-store.md`](../terminal/winget-and-terminal-without-store.md) | 侧载细节与资源名变更史 |
| [`../ime-keyboard/stray-keyboard-layouts.md`](../ime-keyboard/stray-keyboard-layouts.md) | 幽灵键盘布局的排查 |
| [`../../agent/windows-agent/ghost-commands.md`](../../agent/windows-agent/ghost-commands.md) | 哪些命令不能探测、为什么 |
