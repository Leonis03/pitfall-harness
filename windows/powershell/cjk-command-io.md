# 中文命令 I/O：控制台编码、报错语言与 BOM

本文记录在中文 Windows（`zh-CN` 显示语言、`zh-SG` 区域、非 Unicode ACP = 936）上，
让命令行的中文**进出都正确、报错保持英文 ASCII** 的做法与实测结论。

数据来自 2026-10-17 在一台 Windows 11 IoT Enterprise LTSC 26100 上的逐项验证，
PowerShell 7.6.7。凡是写「实测」的，都是跑出来的，不是读文档读来的。

> 相关：[`profile-features.md`](profile-features.md)（profile 功能清单）、
> [`../terminal/windows-terminal-and-wsl-configuration.md`](../terminal/windows-terminal-and-wsl-configuration.md)（终端路径继承）、
> [`../../git-github/crlf-and-diffing.md`](../../git-github/crlf-and-diffing.md)（行尾）、
> skill `run-sql-file`（同一个坑族在 sqlcmd 上的完整版，含 WSL/Linux 侧）

---

## 一、先分清三层，别把编码和语言当一回事

排查「中文乱码 / 报错是中文」时，先确定是哪一层坏了。三层互相独立：

| 层 | 由什么决定 | 本机实测默认值 | 坏了的症状 |
| :--- | :--- | :--- | :--- |
| **控制台代码页** | `chcp`、`[Console]::OutputEncoding` | 936（未配置时） | 原生命令输出乱码 |
| **.NET / 文件编码** | `$OutputEncoding`、`Get-Content`、`[Console]::InputEncoding` | UTF-8 | 管道进原生 exe 坏掉、读文件猜错编码 |
| **报错语言** | `CurrentUICulture` | `zh-CN` | cmdlet / provider 报错是中文 |

**最常见的误判**：把「报错是中文」当成编码问题去调 `chcp`。这跟编码无关，
`chcp` 调多少次都不会让 PowerShell 的报错变英文。

实测基线（配置前，`zh-CN` 显示语言）：

```
Get-Culture            : en-US
Get-UICulture          : zh-CN
CurrentUICulture       : zh-CN
InstalledUICulture     : en-US
PowerShell 自带资源     : en-US / zh-Hans / zh-Hant   （在 System.Management.Automation.dll 旁边）
```

注意 `InstalledUICulture` 是 en-US——这就是为什么 .NET 异常消息本来就是英文，
而 PowerShell 自己的消息是中文：**两者的本地化来源不同**。

---

## 二、控制台代码页是跨进程共享的

这是本文档里最反直觉、也最有用的一条。

Windows 的控制台代码页属于**控制台本身**，不属于进程。实测：

```powershell
# 子进程里
chcp 936 | Out-Null
# 父进程里
chcp            # 936  ← 跟着变了
```

反向也一样。反推出来的机制：任何进程调用 `SetConsoleOutputCP`，
**同一控制台上的所有进程立刻看到新值**，包括宿主进程和它的所有子孙。

两个直接后果：

1. **在 `$PROFILE` 里设 `[Console]::OutputEncoding` 会影响整台机器上共用这个控制台的程序**，
   不只是当前那个 pwsh。这通常是**想要的**——它把 Trap 0 类问题从根上消掉了。
2. **某个工具跑完把代码页留在脏状态上，会污染下一个命令。** 所以排查乱码时，
   「同样的命令第一次坏、第二次好」是个真实存在的现象，先怀疑残留状态，别怀疑自己的代码。

---

## 三、`$PROFILE` 第 0 节做了什么

```powershell
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$env:PYTHONUTF8 = "1"

[Threading.Thread]::CurrentThread.CurrentUICulture =
    [Globalization.CultureInfo]::GetCultureInfo('en-US')
```

前四行把控制台和管道统一到 UTF-8；最后一行只管语言。实测效果：

```
chcp                : 936 -> 65001
[Console]::InEnc    : utf-8 / CP65001
[Console]::OutEnc   : utf-8 / CP65001
$OutputEncoding     : utf-8 / CP65001
PYTHONUTF8          : '1'
```

同时提供两个手动切换的函数：`Use-UTF8`（`chcp 65001`）与 `Use-GBK`
（`chcp 936`，并把 `PYTHONUTF8` 置 0）。需要跟老程序打交道时用。

### 报错语言：`CurrentUICulture`，**不是** `$PSUILanguage`

| 写法 | 变量值 | 报错语言 | 结论 |
| :--- | :--- | :--- | :--- |
| `$PSUILanguage = 'en-US'` | 确实变成 `en-US` | **仍是中文** | ❌ 不是这个开关 |
| `[Threading.Thread]::CurrentThread.CurrentUICulture = ...GetCultureInfo('en-US')` | `CurrentUICulture = en-US` | **英文** | ✅ 生效 |

PowerShell 7.4 引入了 `$PSUILanguage`，实测 7.6.7 上它**只影响帮助文本的界面语言，
不影响错误消息**。错误消息走的是 .NET 资源查找，跟随线程的 `CurrentUICulture`。
要用就用后者。

改完之后（四层全变）：

```
cmdlet error : A parameter cannot be found that matches parameter name 'BogusParameter'.
provider    : Cannot find drive. A drive with the name 'Q' does not exist.
.NET error  : Exception calling "ReadAllText" ... "Could not find a part of the path 'Z:\nope\x.txt'."
Win32 native: The system cannot find the path specified.
中文输出     : 正常，无变化
```

**对编码零影响**——切完 UI culture 之后 `Console.OutEnc` 仍是 65001，中文输出照常。
两件事正交，可以分别开关。

> `CurrentUICulture` 是**线程**属性，只影响当前线程。`Start-ThreadJob`、以及新建的
> PowerShell 实例不继承它；需要全局就写进 `$PROFILE`。

---

## 四、写文件：行尾与 BOM 两个独立的坑

### 4.1 行尾——`edit` 类工具会归一化，改行尾只能整文件重写

实测（PowerShell 7.6.7）：

| 写法 | 行尾 |
| :--- | :--- |
| `[IO.File]::WriteAllText($p, "a`nb`n")` | **LF** ✅ |
| `[IO.File]::WriteAllLines` | CRLF ❌ |
| `Set-Content` / `Out-File`（含 `-Encoding ascii`） | CRLF ❌ |
| `cmd /c echo` | CRLF ❌ |
| Windows PowerShell 5.1 的 `Set-Content` | CRLF ❌ |

`WriteAllText` 之所以行，是因为它把你给的字符串**原样**写进文件；
其余几个都走 `Environment.NewLine`，在 Windows 上必然是 CRLF。

配套的一条：**按子串替换的编辑工具会把替换内容归一化到文件既有的行尾**。
所以对着一个 CRLF 文件逐行改，它会永远是 CRLF——实测在 CRLF 文件上用 CRLF 匹配、
用纯 LF 替换，结果出来仍是 3 CRLF / 0 裸 LF，**不会产生混合行尾，但也不换**。

要改行尾只能 `write` 整文件重写。详见
[`crlf-and-diffing.md`](../../git-github/crlf-and-diffing.md)。

### 4.2 BOM：同一条命令，"对" 和 "错" 取决于你有没有看字节

**陷阱：`.Trim()` 会把 U+FEFF 当空白吃掉，掩盖 BOM 的存在。**

实测 `中文ABC`（5 字符）经原生管道往返：

```
findstr /R .*  ->  长度 6，首字符 U+FEFF
                  去 BOM 后与源串相等 = True
```

第一版测试写的是 `-eq $S`，而 `$S` 经 `.Trim()` 后恰好相等，于是**报了个假阳性**。
换成不 Trim、直接看长度和首字符码位才看出问题。**测编码永远不要用字符串相等判断**，
要看长度和字节：

```powershell
$b = [Text.Encoding]::UTF8.GetBytes($s)
(($b[0..7] | ForEach-Object { $_.ToString('X2') }) -join ' ')   # 前 8 字节
$s.Length                                                       # 字符数
[int]$s[0]                                                      # 首字符码位
```

**推论：不要把中文管道进原生 exe。** 给它一个文件路径，让它自己打开。

### 4.3 工具之间对 BOM 的要求是相反的

| 目标消费方 | 要什么 | 原因 |
| :--- | :--- | :--- |
| `Write` / `Edit` 这类编辑工具 | 无所谓，但产出是 **无 BOM** | 工具本身不带 BOM |
| Python `json.load()`（默认 `utf-8`） | **必须无 BOM** | 有 BOM 直接 `JSONDecodeError: Unexpected UTF-8 BOM` |
| Python `.py` / PowerShell `.ps1` | **必须无 BOM**（在 pwsh 7 上） | 带 BOM 无害但多余；PS 5.1 上反过来必须有 BOM 才认 UTF-8 |
| sqlcmd 11 的 `-i` | **反而偏好有 BOM** | 无 BOM 时它按系统 ACP(936) 读，UTF-8 文件被当 GBK |

同一台机器上，JSON 配置要无 BOM、`.sql` 要有 BOM。**这不是矛盾，是消费方不同。**
写文件前先问一句"谁读它"。

### 4.4 `Get-Content` 在 pwsh 7 上读 GBK 会读错

本机非 Unicode ACP 是 936，旧的 GBK 文件很常见。实测：

```powershell
$gbk = [IO.File]::ReadAllText($p, [Text.Encoding]::GetEncoding(936))   # 正确
$gbk = Get-Content $p -Raw                                             # 错（pwsh 7 上）
```

pwsh 7 的 `Get-Content` 默认按 UTF-8 解，Windows PowerShell 5.1 反而默认按 ACP 解对。
**跨 5.1 和 pwsh 7 的脚本，读非 ASCII 文件必须显式给编码。**

顺带：`[Text.Encoding]::GetEncoding(936)` 在 .NET Core 上要先注册 provider：

```powershell
[Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
```

---

## 五、判定一个文件是什么编码

```powershell
$head = (([IO.File]::ReadAllBytes($p))[0..3] | ForEach-Object { $_.ToString('X2') }) -join ' '
```

| 前几个字节 | 编码 |
| :--- | :--- |
| `EF BB BF ...` | UTF-8 **带 BOM** |
| `FF FE ...` | UTF-16 LE |
| 纯 ASCII | 随便怎么读都行 |
| 高位字节 + 合法 UTF-8 序列，无 BOM | UTF-8 无 BOM |
| 高位字节，无 BOM，**不是**合法 UTF-8 | GBK（本机旧脚本就是这种） |

最后两种**肉眼看不出来**，用严格解码判定——抛异常就是 GBK：

```powershell
try {
    [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false, $true))) | Out-Null
    'UTF-8'
} catch {
    'GBK or other legacy'
}
```

第二个参数 `$true` 是 `throwOnInvalidBytes`，不传就永远解不出来。

---

## 六、验证清单

| 检查项 | 命令 | 期望 |
| :--- | :--- | :--- |
| profile 已加载 | `$PROFILE` | 指向 `Documents\PowerShell\...` |
| 控制台编码 | `chcp` | `65001` |
| .NET 编码 | `[Console]::OutputEncoding.CodePage` | `65001` |
| 管道编码 | `$OutputEncoding.CodePage` | `65001` |
| Python | `$env:PYTHONUTF8` | `1` |
| 报错语言 | `try { Get-Item -BogusParameter } catch { $_.Exception.Message }` | 英文 |
| 中文直出 | `Write-Output "中文测试：，。！？「」【】—— 混排 English 123"` | 无乱码 |
| 文件往返 | `[IO.File]::WriteAllText` 写入再 `ReadAllText` 读回 | 相等且长度一致 |

一键跑完：

```powershell
& "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"  # 手动重载
. $PROFILE
```

---

## 七、几条通用原则

1. **编码 ≠ 语言。** 乱码查编码，中文报错查 UI culture，两条线不要交叉。
2. **控制台代码页是共享状态。** 「同一命令第一次坏第二次好」先查残留，别查代码。
3. **验证要看字节。** 字符串相等会被 `.Trim()`、BOM、各种归一化骗过去。
4. **给程序文件路径，别给它管道里的中文。** 它自己打开、自己猜。
5. **同一台机器上不同工具的 BOM 要求相反**，先问消费方是谁。
6. **「跑完没报错」不算验证。** 按关键词抽查、按字节比对、按长度对账。

第 6 条的完整版（连同"不要拿真实脚本当一次性测试输入"这个真实事故）见 skill
`run-sql-file` 的 Notes 一节。
