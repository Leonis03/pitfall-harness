# Windows 端 AGENTS.md 应该多写什么

面向**在原生 Windows 上跑 AI agent**的场景，回答一个问题：共享的全局约定
（[`../claude-code/claude-global.md`](../claude-code/claude-global.md)、
[`../antigravity/agents-brave-uv.md`](../antigravity/agents-brave-uv.md)）
之外，Windows 侧还得补哪些内容，以及**每一条的实测依据**。

数据来自 2026-10-17 在一台 Windows 11 IoT Enterprise LTSC 26100 上的逐项验证，
PowerShell 7.6.7 Core。凡标「实测」的都跑过，没跑过的明确标了。

现成的成品见 [`../minimax-code/agents-windows.md`](../minimax-code/agents-windows.md)——
那是已经部署到本机的那份原件，本文是它的设计说明与取舍记录。

幽灵命令的**排查步骤、清除方式、以及哪些别名不能关**，是操作手册，见
[`ghost-commands.md`](ghost-commands.md)。本文只给结论和依据。

---

## 一、为什么不该直接往共享文件里追加

仓库已经用「每环境一份原件」了：`agents-brave-uv.md`（WSL）与
`agents-brave-uv-desktop.md`（Linux 桌面）同构不同值。Windows 侧照此办理。

理由不是洁癖，是**照抄会写出用不上的规则**：

- 共享文件整节要求 `uv run --python 3.12`——本机当时**根本没装 uv**，
  一个照做的 agent 第一步就卡住。
- `bx ... | jq -r` 那个核心套路当时**没有 jq**，整节示例跑不了。
- 全文 bash 代码块，而本机默认 shell 是 PowerShell。

反过来也要注意：这些工具链**会漂**（见第二节），所以"本机没有"这个结论本身
也是有保质期的。写进全局约定的东西，要么是跨环境成立的规则，要么带上
「先探测再使用」的指令，别把一次性的盘点结果固化成永久事实。

---

## 二、环境事实：先探测，别信记忆

> **这台机器的工具链在漂。** 2026-10-17 当天，`uv`、`bx`、`jq`、WSL 组件
> 在相隔几小时的两次检查之间先后出现，Node.js 则是用 EXE 安装包装的、
> 不在任何包管理器眼里。**`Get-Command` 仍然能解析一个已经不能用的命令。**

### 幽灵命令：0 字节不等于坏

全 PATH 扫出 13 个 0 字节可执行入口。逐个实跑（每个最多等 6 秒）：

| 命令 | exit | 判定 |
| :--- | :---: | :--- |
| `jq` | 0 `jq-1.8.2` | ✅ **能用**——winget portable shim |
| `winget` | 0 `v1.29.290` | ✅ 能用——App 执行别名 |
| `wt` | 0 空输出 | ✅ 能用，但 `--version` **什么都不打印**（GUI 应用） |
| `python3.12` | 0 `3.12.15` | ✅ uv 装的，**正好是规则 pin 的版本** |
| `python` | 0 `3.13.16` | ✅ 真二进制 103 KB |
| `wsl` | 0 `3.0.1.0` | ⚠️ 引擎能跑，**0 个发行版** |
| `wslconfig` | 被 kill | ⚠️ 弹 GUI，agent shell 里无意义 |
| `python3` | **9009** | ❌ 幽灵，无人遮蔽 |
| `bash` | 1 | ❌ 幽灵（无发行版） |

**关键结论：文件大小完全不能判真假。** `jq` 和 `bash` 都是 0 字节重解析点，
一个能用一个不能用，从文件系统上看一模一样。唯一判据是执行一次：

```powershell
$c = Get-Command <name> -ErrorAction SilentlyContinue
$c.Source; (Get-Item $c.Source).Length      # 0 字节 => 只是线索
& $c.Source --version                       # <- 这才是判据
```

另有 4 个**绝对不能探测**：`ActionsMcpHost`、`ShellMcpServers.Packaging`、
`WindowsPackageManagerMCPServer`、`WindowsPackageManagerServer`——
MCP/COM 服务器，一启动就常驻，会把会话卡死。

### PATH 顺序决定谁赢

`python` 有两个：WindowsApps 里的 0 字节 Store 桩，和 `D:\APP\python313\python.exe`。
后者排在前面所以能用。**这是排序的运气，不是设计**——PATH 顺序一变，
`python` 也会跟着坏。

---

## 三、六类必写规则

### A. Shell 引号与转义

- **含 `$` 的一律单引号。** 双引号里 `\$SQL2016` 展开成空，账户名悄悄变错。
- PowerShell 转义符是反引号，不是反斜杠。
- Git Bash 里 `"$D\\$f.sql"` 是三重陷阱：`\\` 吃掉反斜杠，`$` 又抑制展开。
- GNU `printf` 把 `\E` 展开成 ESC，Windows 路径变成 `D:\SQLData<ESC>3.sql`，
  **不报任何错**。Windows 路径用带引号的 heredoc（`<<'EOF'`）。
- 管道会改掉退出码：`$LASTEXITCODE` 是**最后一个**命令的。

### B. 路径

- **正斜杠在很多 Windows CLI 里是选项前缀。** `sqlcmd -i "D:/data/x.sql"`
  会把 `/U` 当成 `-U`，报「The -E and the -U/-P options are mutually exclusive」。
  用反斜杠或 `Join-Path`。
- 必须是字面路径时用 `$env:USERPROFILE` / `$env:LOCALAPPDATA`，别用 `~`。
- worktree 里 `.git` 是**文件**不是目录，走目录树的脚本要同时加 `--exclude`。

### C. 编码与语言（三层，互不相干）

| 层 | 由什么决定 | 本机原值 |
| :--- | :--- | :--- |
| 控制台代码页 | `chcp`、`[Console]::OutputEncoding` | 936 |
| .NET / 文件编码 | `$OutputEncoding`、`Get-Content` | UTF-8 |
| 报错语言 | `CurrentUICulture` | zh-CN |

- **控制台代码页属于控制台，不属于进程。** 实测：子进程 `chcp 936` 之后父进程
  立刻看到 936，反之亦然。所以「同一命令第一次坏第二次好」是真实存在的现象——
  先查残留状态，别怀疑代码。
- **编码 ≠ 语言。** 乱码查编码，中文报错查 UI culture，调 `chcp` 永远改不出英文报错。
- **`$PSUILanguage` 不是那个开关。** PowerShell 7.4 引入它，实测 7.6.7 上设成
  `en-US` 变量确实变了，报错**仍是中文**。只有
  `[Threading.Thread]::CurrentThread.CurrentUICulture` 真起作用，且不影响编码。
- **别把非 ASCII 管道进原生 exe。** 实测经 `cmd`/`findstr` 往返会多出一个
  U+FEFF，5 个字符进 6 个出；而 `.Trim()` 会把 U+FEFF 当空白吃掉，
  于是 `-eq` 比较**报假阳性**。给程序路径，让它自己开文件。
- **写文件只有 `[IO.File]::WriteAllText($p, $s)` 且内容含显式 `\n` 才出 LF。**
  `Set-Content` / `Out-File` / `WriteAllLines` 全走 `Environment.NewLine`，必产 CRLF。
- **按子串替换的编辑工具会把替换内容归一化到文件既有行尾**，所以逐行改一个
  CRLF 文件，它会永远是 CRLF。改行尾只能整文件重写。
- **BOM 要求在消费方之间是相反的**：Python `json.load()` 遇 BOM 直接崩，
  `sqlcmd -i` 反而偏好有 BOM。写之前先问「谁读它」。
- pwsh 7 的 `Get-Content` 按 UTF-8 解 GBK 文件，返回乱码；PS 5.1 正好相反。

### D. Git on Windows

- **没有任何 `core.autocrlf` 设置会改变仓库里存的东西。** 三个选项只差在工作区。
  `false` + CRLF 工作区是唯一会永久污染历史的路径。
- **`.gitattributes` 优先级高于 `core.autocrlf`。**
- **改配置不重写工作区，而且 `checkout -f` / `checkout-index -a -f` /
  `reset --hard` 全部无效**——git 跳过它认为未变更的路径，不重跑过滤器。
  实测有效的是 `git rm -r -q -f . && git checkout -q HEAD -- .`，
  之后 `git status` 保持空。
- 提交身份用 noreply 邮箱。
- HTTPS 推送可能需要先 `gh auth setup-git`。

### E. 验证纪律

- **「exit 0」不是验证。** 按已知关键词抽查、按字节比对、点数。
- **交互/GUI 命令在 agent shell 里没有意义。** 实测 `wt --version` 返回空。
  用 `Get-Command` / `where.exe` / `--help` 查存在性和版本。
- **测编码看字节数和首字节码位，永远不要用字符串相等。**
- **删除在 agent shell 里不可逆**，且 harness 常常拦下 `Remove-Item` / `cmd /c del`。
  先把要删的复制到 scratch 目录。

### F. GitHub / 输出投影

`bx` 的 JSON 很大（实测 3 条结果 31 KB）。jq 投影时，
**错误的 jq 路径并不总是静默**——实测 jq 1.8.2：

| 表达式 | exit | 输出 |
| :--- | :---: | :--- |
| `.web.results[].url` | 0 | 真 URL |
| `.results[].url`（键不存在 + 迭代） | **5** | `jq: error: Cannot iterate over null` |
| `.results.url`（键不存在，不迭代） | **0** | `null` —— 静默，这才是危险的那种 |

所以要查 exit code，并把打印出来的 `null` 当作查询失败。

> 共享文件里写的是「wrong path returns 0 rows at exit 0 with no error」。
> 在 jq 1.8.2 上，带 `[]` 的迭代情形并不静默。这条待更正。

---

## 四、「先读再跑」路由表

Windows 上**「跑起来了」不等于「跑对了」**：命令可以 exit 0，同时产出错误的字节、
错误的语言或错误的行尾。按信号触发，不要穷举——枚举永远不全，而且会让 agent 过度触发。

| 命令碰到这些 | 先读 |
| :--- | :--- |
| `wsl.exe`、`/mnt/c`、从 Linux 驱动 Windows | skill `wsl-windows-command` |
| `sqlcmd`、`.sql` 文件、任何 SQL Server | skill `run-sql-file` |
| 注册表 `.reg` 导入导出、右键菜单 | `windows/context-menu/README.md` |
| Appx 侧载、`winget`、`wt.exe` | `windows/terminal/winget-and-terminal-without-store.md` |
| 多行 PowerShell、任何编码或中文问题 | `windows/powershell/cjk-command-io.md` |
| Git 行尾、`.gitattributes`、CRLF | `git-github/crlf-and-diffing.md` |
| 微信 / QQ 数据导出 | skills `export-wechat-chat`、`export-qq-chat` |

外加三条通用检查：不把非 ASCII 管道进原生 exe；按字节而非字符串相等验证；
含 `$` 的 Windows 参数一律单引号。

---

## 五、部署与命名的两条教训

1. **原件不要叫 `AGENTS.md` / `CLAUDE.md`。** harness 会把这两个名字在子目录里的
   文件当指令自动加载。仓库里的写法是 `claude-global.md`、
   `agents-brave-uv.md`、`agents-windows.md`。
2. **不要用 `@路径` 做转发。** 根目录曾有一个 11 字节的 `CLAUDE.md`，内容只有
   `@AGENTS.md`，靠 Claude Code 的 import 语法把根 `AGENTS.md` 引过来。
   这类转发只有特定 harness 认，另一个 harness 看到的是一个 11 字节的空文件；
   而且它在公开仓库里也是个断链。已删除。**靠 harness 的魔法转发，不如让原件
   自己就是一个完整文件。**

---

## 六、自检清单

新写一份 Windows 全局约定后逐条过：

- [ ] 纯 ASCII，注释英文
- [ ] LF、无 BOM
- [ ] 文件名不叫 `AGENTS.md` / `CLAUDE.md`
- [ ] 内容里没有 `@xxx` 转发
- [ ] 每条环境相关断言都标了「实测」或明确标了「需探测」
- [ ] 没有把「本机没有 X」写成永久事实（X 会被别的会话装上）
- [ ] 引用的每个相对路径都能解析
- [ ] 部署位与原件字节一致（用哈希比，不要目视）
