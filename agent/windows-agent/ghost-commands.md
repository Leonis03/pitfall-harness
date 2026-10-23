# 排查与清除幽灵命令

「幽灵命令」= **在 PATH 上、`Get-Command` 找得到、但一执行就失败或弹商店**的命令。
本文是操作手册：怎么找出来、怎么确认它是不是幽灵、怎么清除，以及**哪些不能清**。

数据来自 2026-10-17 在 Windows 11 IoT Enterprise LTSC 26100 上的实测。
配套：[`agents-additional.md`](agents-additional.md) 是设计依据，
[`../minimax-code/agents-windows.md`](../minimax-code/agents-windows.md) 是会读这条的全局约定。

---

## 一、为什么不能只看文件大小

Windows 上同一个命令名背后可能是三种东西：

| 形态 | 特征 | `Get-Item` 报的大小 |
| :--- | :--- | :--- |
| **App Execution Alias** | `%LOCALAPPDATA%\Microsoft\WindowsApps\<name>.exe`，`ReparsePoint` | **0** |
| **winget portable shim** | `...\WinGet\Links\<name>.exe`，`ReparsePoint` | **0** |
| **Store 桩（未安装）** | 同上路径，指向一个不存在的包 | **0** |
| 真实二进制 | 普通文件 | 真实大小 |

**前三种都是 0 字节。** 这台机器上：

```
jq    -> WinGet\Links\jq.exe            0B  ✅ 正常，jq-1.8.2
bash  -> WindowsApps\bash.exe           0B  ❌ 幽灵（无发行版）
```

**从文件系统看，它们一模一样。** 所以大小只是线索，唯一判据是**执行一次**。

---

## 二、排查步骤

### 第 1 步：找出所有 0 字节的可执行入口

```powershell
$dirs = (($env:Path -split ';') +
         ([Environment]::GetEnvironmentVariable('Path','Machine') -split ';') +
         ([Environment]::GetEnvironmentVariable('Path','User') -split ';')) |
        Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique

foreach ($d in $dirs) {
    Get-ChildItem $d -File -Force -EA SilentlyContinue |
        Where-Object { $_.Length -eq 0 -and $_.Extension -match '^\.(exe|cmd|bat|com)$' } |
        ForEach-Object { "{0}  <-  {1}" -f $_.Name, $d }
}
```

这台机器命中 13 个：12 个在 `WindowsApps`，1 个在 `WinGet\Links`。

### 第 2 步：先看属性，区分别名与桩

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WindowsApps" -File -Force |
    ForEach-Object {
        [PSCustomObject]@{
            Name  = $_.Name
            Bytes = $_.Length
            Kind  = if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { 'ALIAS' } else { 'PLAIN' }
        }
    } | Format-Table -AutoSize
```

**注意分桶顺序**：先判 `ReparsePoint`，再判大小。我第一次写成先判 `size -eq 0`，
结果把 12 个重解析点全归进了「0 字节」桶，结论全错。

### 第 3 步：实跑，但**必须带超时**

`Start-Process` + `WaitForExit(ms)`，否则 GUI 程序或服务器会把会话卡死：

```powershell
function Probe([string]$exe, [string[]]$argv) {
    $o = "$env:TEMP\probe.out"; $e = "$env:TEMP\probe.err"
    $p = Start-Process -FilePath $exe -ArgumentList $argv -NoNewWindow -PassThru `
                       -RedirectStandardOutput $o -RedirectStandardError $e
    if ($p.WaitForExit(6000)) {
        "exit=$($p.ExitCode)  '$(((Get-Content $o -Raw) + ' ' + (Get-Content $e -Raw)) -replace '\s+',' ')'"
    } else {
        try { $p.Kill() } catch {}
        "!! 6s 未退出：挂起或弹了 GUI"
    }
}
```

⚠️ **变量名别撞车**：我把输出文件名也用 `$exe` 拼，结果生成了
`C:\...\Temp\ghostprobe\C:\...\jq.exe.out` 这种路径而整体失败。

### 第 4 步：这几个**绝对不能探测**

启动即常驻，或一弹窗就没了，探测会拖死会话：

- `ActionsMcpHost.exe` — Windows Actions MCP 宿主
- `ShellMcpServers.Packaging.exe` — Shell MCP 服务器
- `WindowsPackageManagerMCPServer.exe` — WinGet MCP 服务器
- `WindowsPackageManagerServer.exe` — WinGet 的 COM 后端
- `wslconfig.exe` — 弹 GUI

---

## 三、实测结果（2026-10-17）

| 命令 | exit | 判定 |
| :--- | :---: | :--- |
| `jq` | 0 `jq-1.8.2` | ✅ 能用（winget shim） |
| `winget` | 0 `v1.29.290` | ✅ 能用（别名） |
| `wt` | 0 空输出 | ✅ 能用，但 `--version` 不打印（GUI） |
| `python` | 0 `3.13.16` | ✅ 能用（真二进制） |
| `python3` | **9009** | ❌ 幽灵：Store 桩，无人遮蔽 |
| `bash` | 1 | ❌ 幽灵（WSL 无发行版） |

**`exit 9009` 是本机的幽灵指纹**：它就是 PowerShell 说的「未找到」。
如果报的是别的码，别套用这张表，去看输出里到底写了什么。

---

## 四、清除：App Execution Alias 是系统设置，不是 PATH

设置 → 应用 → 高级应用设置 → 应用执行别名。

**关掉一个别名 = 删掉那个 reparse point**，所以结果只有两种：

- 命令**消失**（没有退路）
- 命令**落到 PATH 里另一个真身**（有退路）

这台机器上两种都发生了，所以**关之前必须先查有没有退路**：

| 别名 | PATH 里有真身吗 | 关掉的后果 |
| :--- | :--- | :--- |
| `wt.exe` | ❌ 只有 WindowsApps | **命令消失** |
| `winget.exe` | ❌ | **命令消失** |
| `WindowsPackageManagerServer.exe` | ❌ | winget 的 COM 后端，**别动** |
| `ShellMcpServers.Packaging.exe` / `ActionsMcpHost.exe` | ❌ | harness 的 MCP 宿主，**别动** |
| `wsl.exe` / `bash.exe` / `wslconfig.exe` | ✅ `C:\WINDOWS\system32\` 有真身 | 无差别 |
| `python.exe` / `python3.exe` | `python` 有；`python3` 没有 | 关掉正是我们要的 |

查退路的方法：

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')
foreach ($n in @('wt','wsl','bash')) {
    $c = Get-Command $n -EA SilentlyContinue
    "{0,-8} -> {1}  [{2}B]" -f $n, $c.Source, (Get-Item $c.Source).Length
}
```

---

## 五、两条替代路线

### A. 用硬链接补一个真身（已采用）

别名关掉、`WindowsApps` 里已经没有 `python3.exe` 之后，直接给已有的真身加一个名字：

```powershell
New-Item -ItemType HardLink -Path 'D:\APP\python313\python3.exe' `
                        -Target 'D:\APP\python313\python.exe'

fsutil hardlink list 'D:\APP\python313\python.exe'
#  \APP\python313\python3.exe
#  \APP\python313\python.exe      同一文件，不占额外磁盘
```

**必须用硬链接，不能用 `.cmd` shim。** Windows 的 `CreateProcess` 只在无扩展名时
补 `.exe`，**不解析 `.CMD`**——所以 `python3.cmd` 在 PowerShell 里能用，
但 `subprocess.run(['python3', ...])` 会失败。实测：

```powershell
python -c 'import subprocess,sys; r=subprocess.run([sys.executable.replace("python.exe","python3.exe"),"-c","print(1+1)"],capture_output=True,text=True); print(r.returncode, r.stdout.strip())'
# rc=0 2      硬链接能被 CreateProcess 直接启动
```

### B. 调 PATH 顺序让遮蔽生效

PATH 里有多个目录时，**靠前的赢**。这台机器的顺序：

```
15. D:\APP\python313\          ← python 真身
17. ...\Microsoft\WindowsApps  ← 别名
20. ...\.local\bin             ← uv / bx / jq
```

所以在 `.local\bin` 放 `python3.cmd` **会输给** WindowsApps 的别名——
`jq` 能被找到只是因为 WindowsApps 里**没有** `jq.exe`，不是靠顺序赢的。
要让用户工具目录统一压过 Store 桩，就得把 `.local\bin` 提到 WindowsApps 之前。
代价是动了全局 PATH，影响面比方案 A 大。

---

## 六、验证清单

改完之后逐条跑，别只看一个：

```powershell
# 1. 解析到哪里（是否还有 0 字节桩）
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')
foreach ($n in @('python','python3','wt','wsl','bash','winget','jq')) {
    $c = Get-Command $n -EA SilentlyContinue
    if ($c) { "{0,-8} -> {1}  [{2}B]" -f $n, $c.Source, (Get-Item $c.Source).Length }
}

# 2. 真的能执行吗（不能只看解析成功）
python  --version; python3 --version; jq --version; winget --version

# 3. 能不能被 CreateProcess 直接启动（.cmd shim 在这一步才暴露）
python3 -c 'import subprocess,sys; print(subprocess.run(["python3","-c","print(7*6)"],capture_output=True,text=True).stdout.strip())'
```

第 3 步是最容易被跳过、也最能暴露假修复的一步。

---

## 七、顺带记一笔：环境会漂

排查期间（同一台机器，几小时内）发生了这些：

- `uv`、`bx`、`jq`、WSL 组件先后出现
- 一个 Debian 13 发行版被装上，`bash` 从「无发行版」变成可用
- `python3` 从 exit 9009 变成可用（因为别名被关 + 加了硬链接）

**所以任何「本机有/没有 X」的结论都有保质期。** 写进长期文档时，
要么带上验证日期，要么写成「先探测再使用」的指令。
这条同样适用于全局约定文件——见
[`../minimax-code/agents-windows.md`](../minimax-code/agents-windows.md) 开头的警告。
