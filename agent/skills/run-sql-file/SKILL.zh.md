# 用 sqlcmd 运行 .sql 文件（中文版）

> **路径。** 下面的辅助命令用 `~/.agents/skills/run-sql-file/`。装在哪都行：也可以用
> `~/.claude/skills/run-sql-file/`、`~/.gemini/config/skills/run-sql-file/`，或者写相对本 SKILL.md 的
> 路径 —— 三处有任一处存在就能执行。

> 本文件为中文参考版。主入口为 `SKILL.md`（英文），加载时以 `SKILL.md` 为准。

## 用法 —— 一行搞定，不需要任何转换

**用 PowerShell 工具跑 sqlcmd，不要用 Bash 工具。** sqlcmd 的输出编码取决于宿主进程的控制台代码页：PowerShell 工具是 65001，中文正常；Bash 工具是 **936**，所有中文都是乱码。这是本机最容易白白浪费半天的坑 —— 见**陷阱零**。

**UTF-8 with BOM（新建文件首选）—— 完全不需要编码参数：**

```powershell
sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i "D:\path\script.sql" -W -s"|" -w 400
```

**GBK（`<your-sql-dir>\` 下的旧脚本）—— 需要声明输入代码页：**

```powershell
sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i "D:\path\script.sql" -f i:936 -W -s"|" -w 400
```

输出直接是 UTF-8，中文完好。**不需要临时文件，不需要 UTF-16 中转。** 在 PowerShell 5.1 和 pwsh 7 下实测输出逐字节相同。

靠四条规则：

1. **宿主用 PowerShell。** 控制台代码页决定输出编码，只有 PowerShell 工具的是 65001（陷阱零）。
2. **新建文件一律存 UTF-8 with BOM。** sqlcmd 会自动识别 BOM，`-f` 参数直接消失 —— 少一个出错点，陷阱一也变得无法触发。
3. **确实需要 `-f` 时，只写 `-f i:<cp>`** —— 只声明**输入**代码页。绝不要写裸的 `-f 936`，也绝不要写 `-f o:<cp>`（见陷阱一）。
4. **让 sqlcmd 自己读文件（`-i`）** —— 绝不要把脚本文本用管道喂给它（见陷阱二）。

### 控制不了 shell、或者想把结果落盘时

`-o <file> -u` 输出 **UTF-16LE + BOM**，编码无歧义，且完全不受控制台状态影响。这是实测中唯一在任何控制台代码页下都给出相同结果的调用方式：

```powershell
sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i "D:\path\script.sql" -o "$env:TEMP\out.txt" -u -W -s"|" -w 400
[IO.File]::ReadAllText("$env:TEMP\out.txt", [Text.Encoding]::Unicode)
```

```bash
# 在 bash 里：用 -f UTF-16（不是 UTF-16LE），让 iconv 吃掉 BOM 而不是输出 U+FEFF

sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i 'D:\path\script.sql' -o 'C:\Temp\out.txt' -u -W -s"|" -w 400
iconv -f UTF-16 -t UTF-8 < /c/Temp/out.txt
```

## 环境（2026-09-15 本机已验证；控制台/编码部分 2026-09-22 重新验证）

- **sqlcmd**：`C:\Program Files\Microsoft SQL Server\110\Tools\Binn\SQLCMD.EXE`，11.0.2100.60 NT x64，已在 PATH
- **实例**：`<your-host>\SQL2016`（本机唯一；服务 `MSSQL$SQL2016`，虚拟账户 `NT Service\MSSQL$SQL2016`）
- **服务器**：SQL Server 2016 企业版 13.0.1601.5，服务器排序规则 `Chinese_PRC_CI_AS`
- **认证**：Windows 集成认证（`-E`），当前账户 `<your-host>\<your-windows-user>`，本机管理员。`LoginMode = 2`，即**混合验证已开、SQL 登录可用** —— 这对 WSL/Linux 客户端很关键，它们用不了 `-E`。
- **TCP**：已启用，但走**动态端口**（`IPAll` 下的 `TcpDynamicPorts`，当前 8217，**服务一重启就变**）。SQL Browser 在运行，所以优先用实例名解析，不要写死端口。
- **控制台**：取决于宿主进程，**不是一个全局事实**（2026-09-22 重新验证）：

  | 宿主 | `chcp` | `[Console]::OutputEncoding` | sqlcmd 中文输出 |
  |---|---|---|---|
  | Claude Code **PowerShell 工具**（pwsh 7.6.5 Core，stdout 重定向） | 65001 | 65001 | **正常** |
  | Claude Code **Bash 工具**（Git Bash / MSYS） | **936** | 不适用 | **乱码** |
  | 从任一宿主派生的子 `pwsh -Command` | 启动时 65001 | 65001，但见陷阱一 | 正常，除非 `-f` 改动了它 |

- **系统非 Unicode 程序 ACP = 936**（`HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage\ACP`），而 `CurrentCulture.TextInfo.ANSICodePage` 报的是 1252 —— 这是两个不同的设置，别读错。
- 本机 `.sql` 文件是 **GBK（CP936）、无 BOM**。

## 陷阱零：Bash 工具会毁掉所有中文

Bash 工具的控制台代码页是 **936**。sqlcmd 按这个代码页写输出，Git Bash 再把字节交给 UTF-8 消费方，于是 `计算机`（GBK `BC C6 CB E3 BB FA`）变成 `�����`。查询本身完全正常，坏的只是显示，而且错误流里没有任何提示。

**请改用 PowerShell 工具。** 如果确实只能待在 bash，上面的 `-o <file> -u` 是唯一可靠的办法。`| iconv -f CP936 -t UTF-8` 管道在**当下**也能work，但有两个问题：

- **跨次调用不稳定** —— 见陷阱一里 `-f o:` 的「延迟一次」现象。同一条命令可能这次需要 iconv、下次反而被 iconv 搞坏。
- **管道会吃掉 `-b` 的退出码。** `sqlcmd -b ... | iconv` 返回的是 `iconv` 的状态（恒为 0）。要用 `${PIPESTATUS[0]}`，或者干脆不用管道。

另外四个 bash 专属的坑，全部是静默失败：

| 你写的 | 实际发生了什么 |
|---|---|
| `-i "C:/Users/.../x.sql"` | sqlcmd 11 把 `/X` 当**选项前缀**，`/Users` 被解析成 `-U` → `Sqlcmd: The -E and the -U/-P options are mutually exclusive.` **一律用反斜杠。** |
| `"$D\\$f.sql"` | `\\$` 序列既吃掉反斜杠又阻止展开，结果是字面量 `...sqlprobe$f.sql`。Windows 路径要在单引号里拼。 |
| `printf '...D:\\SQLData\\E3.sql...'` | GNU printf 把 `\E` 展开成 ESC，路径静默变成 `D:\SQLData<ESC>3.sql`。Windows 路径用带引号的 heredoc（`<<'EOF'`），不要用 printf。 |
| 管道里接 `head`/`sed` | 会改变 sqlcmd 看到的是控制台还是管道，进而改变输出编码。请用 `od -An -tx1` 比对原始字节，不要看渲染后的文字。 |

## 陷阱一：`-f` 改的是**下一个**进程的控制台，不是当前这个

旧版本把这个现象归咎于 pwsh 7 的 .NET 缓存。真实机制更简单也更糟：**`-f <cp>` 和 `-f o:<cp>` 会调用 `SetConsoleOutputCP` 且从不恢复，而 sqlcmd 自己的输出用的是它启动那一刻读到的代码页。** 所以你传的参数总是晚生效一轮。

可稳定复现（Bash 工具，先强制控制台为 936）：

| 轮次 | 命令 | 输出 |
|---|---|---|
| 1 | `-f o:65001 -Q "select Dname ..."` | **乱码**（仍是 936） |
| 2 | *完全相同的命令* | **正常**（用上了第 1 轮留下的 65001） |
| — | `chcp 936` 复位 | |
| 3 | 不带 `-f` 的 `-Q` | **又是乱码** |

后果：

- **同一条命令连续两次跑出不同结果。** 输出编码看起来在抖，原因就在这里 —— 不要去 SQL 里找 bug。
- **`chcp` 看不出来。** 上表每一行 `chcp` 都报 936，包括那次输出 UTF-8 的。测 `chcp` 只会把你带偏。
- **绝不要用裸的 `-f <cp>` 或 `-f o:<cp>`。** `-f i:<cp>` 只碰输入侧，不留残留。这本来就是第 3 条规则，上面才是它真正的理由。
- **泄漏会跨进程。** 子 `pwsh -Command` 里跑 `-f 936 -o file -u -i script.sql`，结束时 `[Console]::OutputEncoding` 停在 936，之后连纯字符串字面量都按 GBK 打印（`系编码` → `ϵ����`；GBK 的 `CF B5` 按 UTF-8 解正好是 U+03F5 `ϵ`）。而在 Claude Code 的 PowerShell 工具里跑同样的命令，它停在 65001 —— 因为那个宿主把编码钉死了且 stdout 被重定向。**也就是说 harness 会帮你挡住这个陷阱，直到它挡不住。** 不要依赖这份免疫。

## 陷阱二：绝不要把中文用管道喂给原生 exe

**两边都坏**，只是坏法不同 —— 用 `系编码` 做往返测试：

| shell | `$OutputEncoding` | 结果 |
|---|---|---|
| PS 5.1 | CP20127（US-ASCII） | `FFFD,003F,003F,003F` —— 出口处被编码成 `?` |
| pwsh 7 | CP65001 | `7EEF,8364,7D2A,942E,003F` —— UTF-8 字节被 exe 按 OEM 重新解码 |

永远给程序传**路径**，让它自己打开文件。

## 为什么必须声明输入代码页

不加 `-f i:936` 时，sqlcmd 会把这些 GBK 脚本当 UTF-8 读。中文标识符和字符串常量变成乱码，`WHERE Ttitle='教授'` 这类条件匹配不到任何行 —— 查询**执行成功并返回 0 行**，而不是报错。是静默的错误答案，不是崩溃。

## 5.1 与 pwsh 7 的差异（会咬人的那些）

| 行为 | PS 5.1 (Desktop) | pwsh 7 (Core) |
|---|---|---|
| `Encoding::Default` | CP936（系统 ACP） | 恒为 UTF-8 |
| `Get-Content` 默认读 GBK 文件 | **解对** | **解错** |
| `Out-File` / `>` 默认 | UTF-16LE + BOM | UTF-8，无 BOM |
| `Set-Content -Encoding utf8` | UTF-8 **带** BOM | UTF-8 **不带** BOM |
| `$OutputEncoding` | US-ASCII | UTF-8 |
| 含中文字面量、无 BOM 的 `.ps1` | 按 CP936 读 | 按 UTF-8 读 |
| `-f` 的控制台泄漏（陷阱一） | 同样泄漏，但 5.1 启动时缓存一次，自己的输出不受影响 | 同样泄漏，且自己的输出会跟着泄漏后的代码页走 |

实际影响：要在 5.1 下运行且含中文的 `.ps1`，**必须存成 UTF-8 with BOM**；在 pwsh 7 里读 GBK 文件必须显式指定编码。最稳的做法是**脚本里根本不放中文字面量**（用码点构造，如 `[char]0x7CFB`），这样脚本文件自身的编码就不再重要。

## 在 WSL / Linux 上运行（2026-09-22 实测）

陷阱 0/1/2 这一整家子都是 **Windows 控制台**的产物。Linux 客户端通过 socket 讲 TDS，
没有控制台代码页这个概念，所以那些坑在那边根本不存在。端到端实测：
拿一个真实脚本的只读部分（13 条查询），Windows sqlcmd 11 与 Linux sqlcmd 18
跑出来的**数据行逐行一致** —— 各 54 行（空白归一后），`diff` 干净。

### 用 `mssql-tools18`，不要用 `go-sqlcmd`

| 客户端 | CP936 `varchar` → UTF-8 | 中文列别名表头 | 结论 |
|---|---|---|---|
| **`mssql-tools18`**（`sqlcmd 18.7.0001.1`，ODBC） | 正确 | **各种长度全部正确** | **用这个** |
| `go-sqlcmd`（`v1.10.0`，go-mssqldb） | 正确 | **坏 —— 见下** | 只能配 `-h -1` 用 |
| `pymssql`（FreeTDS） | 正确 | 不适用 —— 表格是你自己打印的 | 适合脚本化 / CI |
| `usql` | 未测 | 未测 | Ubuntu 的打包版没编译 mssql 驱动 |

```bash
export SQLCMDPASSWORD='...'          # 命令行绝不出现 -P，更不要写进文件
/opt/mssql-tools18/bin/sqlcmd -S '127.0.0.1\SQL2016' -U <login> -d study -C -b -W -s"|" -w 400 \
  -i /mnt/d/path/script.sql
```

- **必须写 `-S '127.0.0.1\SQL2016'`，不能写 `localhost\SQL2016`。**
  `msodbcsql18` 会优先把 `localhost` 解析成 IPv6 `::1`，而实例没有监听 IPv6，
  于是报 `TCP Provider: Error code 0x2749` / `Login timeout expired`。
  `go-sqlcmd` 解析成 IPv4，**不受影响** —— 这会让人误以为是服务端问题，其实是解析器问题。
- **实例名优于端口。** `\SQL2016` 走 SQL Browser（UDP 1434）解析，重启不受影响；
  TCP 端口是动态的。注意 `/dev/tcp` 这类**只能测 TCP** 的探针**看不到 SQL Browser**，它是 UDP。
- **没有 `-E`。** 非域机器，Linux 侧用不了 Windows 集成认证，必须用 SQL 登录 ——
  本机 `LoginMode = 2` 所以可行。除非确实要写，否则只给 `db_datareader`。
- **带 BOM 的 UTF-8 文件 `-i` 没问题。** 已显式验证：BOM 被客户端吃掉，不会发给服务器。
  同一脚本的带 BOM / 不带 BOM 两个版本都 `exit=0` 且输出一致，
  所以 Windows 侧「一律加 BOM」的规矩在 Linux 上同样安全。

### go-sqlcmd v1.10.0 会截断中文列别名

**表头输出的是别名的前 N 个字节，N = 别名的字符数**（列宽按 rune 算、切片按 byte 切）。
数据行完全不受影响，坏的只有表头那一行。

| 别名字数 | UTF-8 字节 | 实际输出的字节 | 看到的是 |
|---|---|---|---|
| 2 | 6 | `e5 a7` | **纯乱码**，一个完整字都没有 |
| 3 | 9 | `e5 b7 a5` | 只剩第一个字 —— **静默截断，最危险** |
| 4 | 12 | `e9 83 a8 e9` | 一个字 + 半个字节 |
| 6 | 18 | `e5 a7 93 e5 90 8d` | 只剩前两个字 |

这对本项目是致命的：作业脚本大量使用中文别名 —— `E2.sql` 50 处（28 个不同），
`E3.sql` 39 处（16 个）—— 而**最常见的 2 字别名恰好落在最坏的一格**。
改 ASCII 别名可以，`-h -1` 抑制表头也可以，但题目本身要求中文列名时，两条路都走不通。

`mssql-tools18` 这些全部渲染正确。它唯一的瑕疵是：下划线按**字符数**生成，
一个字一条 `-`，在等宽字体下比全角汉字短一截。**那是对齐问题，不是数据损坏** ——
不要为此去改排序规则或加 charset 参数。

## 关键参数

| 参数 | 作用 |
|---|---|
| `-S '<your-host>\SQL2016'` | 实例名。PowerShell 里**必须单引号** —— 见下方 `$` 陷阱 |
| `-d <db>` | 初始数据库；不指定会落在 `master`，未限定表名将失败 |
| `-E` | Windows 集成认证 |
| `-b` | **SQL 出错时返回退出码 1**。不加它，失败和成功看起来一样 |
| `-i <file>` | 输入脚本（可重复）。**只能用反斜杠路径** —— `/` 是选项前缀（陷阱零） |
| `-f i:936` | **只**设输入代码页。UTF-8 用 `i:65001`；UTF-16/带 BOM 则省略 |
| ~~`-f 936`~~ ~~`-f o:65001`~~ | **禁用。** 改的是下一个进程的控制台而不是当前这个（陷阱一） |
| `-W` | 去掉列尾空格 |
| `-s"\|"` | 列分隔符，便于解析成表格 |
| `-w 400` | 行宽；默认 80 会截断 |
| `-h-1` | 不输出列标题 |
| `-Q "..."` | 执行单条内联查询后退出 |
| `-o <file>` `-u` | 输出 UTF-16LE + BOM 到文件。`-u` 必须配 `-o`。**唯一不受控制台影响的输出路径** —— 编码一有疑问就用它 |

## 判断文件编码

```powershell
(([IO.File]::ReadAllBytes($p)[0..3]) | ForEach-Object { $_.ToString('X2') }) -join ' '
```

| 开头字节 | 编码 | 用法 |
|---|---|---|
| `EF BB BF ...` | 带 BOM 的 UTF-8 | **省略 `-f`** |
| `FF FE ...` | UTF-16 LE | 省略 `-f` |
| 全 ASCII | ASCII | 怎么都行 |
| 有高位字节且无 BOM | **GBK**（本机旧文件） | `-f i:936` |
| 有高位字节、无 BOM 且是合法 UTF-8 序列 | 无 BOM 的 UTF-8 | `-f i:65001` |

最后两行肉眼无法区分 —— 靠**严格** UTF-8 解码来判定（`UTF8Encoding($false, $true)`），抛异常就是 GBK。`Run-SqlFile.ps1` 就是这么做的。

### 实测行为矩阵

用一条谓词含中文的查询（`where Dname='计算机'`）做判据：解对返回 1 行，解错返回 0 行。

| 文件编码 | 不加 `-f` | 加 `-f i:<cp>` |
|---|---|---|
| **UTF-8 with BOM** | **1 行** | 1 行 |
| UTF-8 无 BOM | **0 行** | 1 行（`i:65001`） |
| GBK | **0 行** | 1 行（`i:936`） |

这说明两件事：

- **BOM 能让参数彻底消失。** sqlcmd 11.0 认 UTF-8 BOM。
- **无 BOM 的 UTF-8 在本机是最差选择** —— 比 GBK 还差。sqlcmd 的输入代码页默认跟随**系统 ACP（936）**，不是控制台 CP（65001），所以无 BOM 的 UTF-8 会被当成 GBK 读。而 GBK 文件至少在 SSMS 里是对的（SSMS 同样回退到 ACP）。

两个失败格子都是**静默失败**：标识符和字符串常量变乱码后匹配不到任何行，查询「成功」返回 0 行。所以遇到 0 行，先排除编码问题，再相信数据是空的。

补充一点：同样的乱码**也可能报 `Msg 102 ... Incorrect syntax`**，不一定是 0 行。区别在于变乱的字节落在**标识符/别名**上（`select Dname as 中文别名`）还是只落在字符串常量里。根因相同，只是后者更吵、更容易发现。

## 创建 / 编辑 .sql 文件

`Edit` 和 `Write` 工具**只会写无 BOM 的 UTF-8**。两个后果：

- **绝不要用它们碰 GBK 文件** —— 整个文件会被重写成 UTF-8，中文全毁。
- **用它们改 UTF-8+BOM 文件会把 BOM 抹掉**，悄无声息地把一个「零参数」文件降级成需要 `-f i:65001` 的文件。

**新建文件时不要用 here-string 手拼正文** —— 超过 20 行就很痛苦，而且会正好撞上下面的行尾符坑。用 `Write` 工具正常写，再第二步补 BOM：

```powershell
$p = 'D:\path\script.sql'
$t = [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
(([IO.File]::ReadAllBytes($p)[0..2]) | ForEach-Object { $_.ToString('X2') }) -join ' '   # EF BB BF
```

唯一没有例外的禁令是：**绝不要用 `Edit` / `Write` 碰已存在的 GBK 文件**，那会把整个文件重写成 UTF-8、毁掉所有中文。先转换，或者走 PowerShell 读写：

```powershell
# 新建 / 重写为 UTF-8 with BOM

[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($true)))

# 读 GBK 文件

[Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
$text = [IO.File]::ReadAllText($path, [Text.Encoding]::GetEncoding(936))

# 原地把 GBK 转成 UTF-8 with BOM

$t = [IO.File]::ReadAllText($p, [Text.Encoding]::GetEncoding(936))
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
```

转换后重跑脚本并与转换前的输出做比对 —— 正确的 GBK→UTF-8+BOM 转换应当逐字节一致。

### 坑：行尾符

用 PowerShell here-string 写出的文件是 **LF**，不是 CRLF。之后若按 CRLF 做字符串替换，会匹配不到、**静默失败** —— 脚本照样能跑，看不出任何异常，只是那次编辑根本没生效。替换前先探测真实行尾：

```powershell
$nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
```

更稳妥：按 `"`r?`n"` 切分成数组、插入、再用探测到的行尾 join 回去。

## 运行含 DML 的脚本但不提交

脚本里有 `INSERT`/`UPDATE`/`DELETE`/`SELECT INTO`，而你想在真正改数据**之前**验证语法、约束和影响行数时，把它套进事务再回滚。`:r` 是 sqlcmd 的文件包含指令；被包含文件里的 `go` 正常切批，事务因为在同一连接上而跨批次保持。

```sql
-- dryrun.sql（纯 ASCII，自身编码永远不会成为问题）
set xact_abort on;
begin transaction;
go
:r D:\path\script.sql
rollback transaction;
go
print '--- ROLLED BACK ---';
go
```

```powershell
sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i "D:\path\dryrun.sql" -W -s"|" -w 400
```

所有 `SELECT` 结果和每一条 `(N rows affected)` 都能看到，数据库分毫不动。跑完再用一条计数查询确认。几点说明：

- 若某批在 `-b` 下失败，sqlcmd 退出、连接断开，服务器会自动回滚 —— 不可能留下悬挂事务。
- 包装器里 `select ... into T` 之后再 `insert into T` 没问题，回滚会把表一并删掉。
- 它验证的是**按顺序执行**的结果。如果脚本的 DML 有顺序依赖（先 `+1000` 再 `×1.05`），之后单独挑几条执行，数字不会一样。
- `:r` 是 **sqlcmd 指令，不是 T-SQL**。这个 dryrun 包装器**不能直接粘进 SSMS**。要在 SSMS 里做同样的事，就粘目标脚本本身，再手写 `begin tran` / `rollback tran` 包住它。

## 可选辅助脚本 —— 需要落盘时用

`scripts\Run-SqlFile.ps1` 会自动识别编码（用严格 UTF-8 解码来区分"无 BOM 的 UTF-8"和 GBK），始终使用安全的 `-f i:<cp>` 形式，并把结果转成 UTF-8。适用于：需要**保存**结果、输出非常大、或者希望退出码和服务器报错文本放在一起。只是想看结果的话，上面那行更简单。

```powershell
& "~/.agents/skills/run-sql-file/scripts/Run-SqlFile.ps1" -Path "D:\path\script.sql" -Database study
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `-Path` | *（必填）* | `.sql` 文件路径 |
| `-Database` | `master` | 传入实际数据库，如 `study` |
| `-Server` | `<your-host>\SQL2016` | 本机唯一实例 |
| `-InputEncoding` | `auto` | 可覆盖为 `936`、`65001`、`1252`、`utf16` |
| `-Separator` | `\|` | 列分隔符 |
| `-Width` | `400` | 行宽 |
| `-NoHeaders` | 关闭 | 等价于加 `-h-1` |
| `-OutDir` | `$env:TEMP` | UTF-8 输出目录 |

SQL 报错时脚本仍正常返回（`ExitCode 1`），服务器报错写在输出文件里。

## 排错

**输出乱码** —— 三种完全不同的成因，按这个顺序排查：

1. **你在 Bash 工具里。** 概率最高。它的控制台是 936（陷阱零）。改用 PowerShell 工具，或者用 `-o <file> -u`。
2. **上一次 sqlcmd 用了裸 `-f <cp>` 或 `-f o:<cp>`，把控制台代码页留歪了**（陷阱一）。典型症状：**同一条命令第二次跑就对了**。只用 `-f i:<cp>`。
3. **输入文件编码声明错了**，此时乱码在你发出去的数据里，不在收回来的结果里。查文件开头字节。

`chcp` 区分不了这三种 —— 三种情况它报的值都一样。请比对原始字节（`od -An -tx1`）：GBK 的 `计算机` 是 `BC C6 CB E3 BB FA`，UTF-8 是 `E8 AE A1 E7 AE 97 E6 9C BA`。

**查询返回 0 行但数据明明存在** —— 漏了 `-f i:936`。见上。

**`Sqlcmd: The -E and the -U/-P options are mutually exclusive.`** —— 你用了正斜杠路径。sqlcmd 11 会把 `C:/Users/...` 里的 `/U` 当成 `-U` 选项。改用反斜杠。

**`decimal` 的零显示成 `.00` 而不是 `0.00`** —— sqlcmd 渲染 `decimal` 时会掐掉前导零。值本身是对的，SSMS 里显示正常。不是算错，也不值得再去核对一遍。

**`Msg 451 ... Cannot resolve collation conflict between "Latin1_General_CI_AS_KS_WS" and "Chinese_PRC_CI_AS"`** —— 把 `SERVERPROPERTY(...)` 和本服务器 `Chinese_PRC_CI_AS` 下的目录视图列拼接时触发。分列查询，或加 `COLLATE DATABASE_DEFAULT`。

**附加数据库时 `FCB::Open failed ... OS error: 5(Access is denied)`** —— 服务以虚拟账户 `NT Service\MSSQL$SQL2016` 运行，**不**被 `Authenticated Users` / `Users` 的 ACE 覆盖。显式授权：

```powershell
icacls "D:\folder" /grant 'NT SERVICE\MSSQL$SQL2016:(OI)(CI)(F)' /T
```

**PowerShell 把 `$SQL2016` 吃掉** —— 双引号里会展开成空变量，账户名静默变错。含 `$` 的参数一律用**单引号**。

## 注意

- 运行前先读脚本。通常是只读 `SELECT`，但要检查有没有 `DROP`/`DELETE`/`UPDATE`，有的话先说明再执行。
- **绝不要拿真实的项目脚本当一次性测试输入。** 在试参数、编码、路径时，很容易顺手抓一个磁盘上已有的 `.sql` 来用 —— 但 `-i` 是**执行**它，含 DML 的脚本会静默提交，而真正有意思的输出正好从屏幕上滚过去，看起来就像"测试结果"。本机已经真实发生过：两次编码探测用了一个作业脚本，导致其中的 `UPDATE` 被执行了两遍（工资加了两次 `+1000`，`*1.05` 也叠加了一次）。请临时造一个探针，`select Dname from D where Dnum='D01'` 就够了；或者套上上面的回滚包装器。
- 任何可能写库的运行，**前后都要**做一次行数快照（`select count(*) from T`、`sum(Tsalary)`、`object_id('S_1','U')` 等）。只有比对差异才能可靠地发现意外提交；"输出看起来对"是发现不了的。
- 服务端失败的真实错误在 ERRORLOG，客户端消息不一定看得到：
  `C:\Program Files\Microsoft SQL Server\MSSQL13.SQL2016\MSSQL\Log\ERRORLOG`
- 默认数据/日志目录：`C:\Program Files\Microsoft SQL Server\MSSQL13.SQL2016\MSSQL\DATA\`（已带服务账户 ACE）。
