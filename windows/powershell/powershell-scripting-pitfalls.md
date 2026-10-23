# 用 shell 工具驱动 PowerShell 时，自己骗了自己的那些地方

本文记录在 Windows 上用 PowerShell 写一次性脚本时，**工具给出了看起来正确、
实际错误的结果**的那些坑。全部来自 2026-10-17 一次实际会话，每个都有当时的报错原文。

> 和 [`cjk-command-io.md`](cjk-command-io.md) 的分工：那篇讲**数据**的编码（字节、
> 语言、行尾），这篇讲**脚本**写错——循环、变量、参数、以及最要命的那类：
> **命令失败了但你没发现，于是把错误结论当成了事实。**

---

## 一、最贵的一类：拿到了错的答案，还以为是对的

这类不会抛异常。它们安静地返回 0 个结果、或者全量误报，然后你把结论写进了文档。

### 1. 匹配模式里的 CR 被中间层吃掉

想在 bash 里找带 CR 的行：

```bash
git grep -Il --text $'\r$' -- .
```

当脚本**经由另一个 shell 调用**（比如从 PowerShell 用 `bash -c "..."` 传进去），
`\r` 在传递过程中丢失，pattern 退化成 `$`——**匹配每一行**。结果：203 个文件
被报成 CRLF，而实际只有 3 个。

真实的行尾只有 3 个，两个是 `.gitattributes` 刻意指定的 `.reg`。

**规则：不要把二进制控制字符穿在 shell 字符串里传递。** 用不需要转义的工具读行尾——
`git ls-files --eol` 直接给出 `i/lf w/crlf attr/...`，没有任何 quoting 可错。

### 2. `git ls-files` 没有 `--exclude-dir`

```bash
git ls-files --exclude-dir=.git --exclude-dir=tmp -- '*.md'
# fatal: unknown option `exclude-dir'
git ls-files --exclude-dir=.git --exclude-dir=tmp -- '*.md' 2>/dev/null
# （无输出，exit 0）
```

`--exclude-dir` 是 **`git grep`** 的选项。写给 `git ls-files` 会直接失败，而
`2>/dev/null` 把错误吞掉，于是调用方收到"0 个文件"，并且**每一项检查都报告 ok**——
它们什么都没查。

这条在 `skills/distill-session/scripts/verify-change.sh` 里真实发生过：ASCII、
frontmatter、链接三项检查全部空跑，而输出看起来是干净的通过。

**规则：`2>/dev/null` 会把"命令不存在"和"没有匹配"变成同一种结果。**
计数为 0 时要区分「确实没有」和「根本没跑」——脚本里显式断言一次非空。

### 3. 嵌套管道里 `$_` 被内层覆盖

```powershell
Get-ChildItem $d -Recurse -File | Where-Object {
    $i = 0
    Get-Content $_.FullName | ForEach-Object {     # <-- 内层 $_
        $i++
        "  $($_.FullName):$i  $_"                  # <-- $_ 已是字符串，没有 FullName
    }
} | Select-String 'pattern'
```

内层 `ForEach-Object` 把 `$_` 重新绑定成了一行文本。外层的文件对象没了，
`$_.FullName` 在字符串上调用 → *不能对值为 Null 的表达式调用方法*，或者更糟：
不报错、输出为空。

**规则：两层以上嵌套不要用 `$_`。** 外层先存进具名变量
（`$f = $_`），内层只用 `$f`。

### 4. 过滤器把目标全排除了

统计仓库里的行尾时，我用相对路径做过滤：

```powershell
Get-ChildItem $repo -Recurse -File | Where-Object {
    $_.FullName.Substring($repo.Length+1) -notmatch '^tmp[\\/]'
}
```

当时 `$repo` **本身就在 `tmp/` 下面**（一个演练用的 worktree），于是每个文件的
相对路径都以 `tmp\` 开头，全被过滤掉。计数器打印 0 LF / 0 CRLF，我读成了
「没有 CRLF」。

**规则：过滤条件会把「目标 0 个」伪装成「检查通过」。** 计数为零时，把参与扫描的
文件总数一起打出来。

### 5. `$script:x++` 累加，打印的是局部变量

```powershell
$lf = 0
... ForEach-Object { $script:lf++ }
Write-Output "纯LF=$lf"      # 0
```

在某些调用上下文里 `powershell -Command` 的作用域和 `$script:` 不一致，累加的
值打印不出来。

**规则：跨管道累加器用 `[ref]`、`List<T>.Add()` 或一个 `foreach` 循环，

### 6. 凭记忆认标识符——同一类里栽得最狠的一次

又是一次。我看到一个 GUID，就断言它是「旧版微软拼音 3.0」，并据此告诉用户
「两个中文输入法都是微软的」。**用户发来键盘布局面板截图，第二项写着「搜狗拼音输入法」。**

错在两处：一是我没验证过那个 GUID 到名字的映射；二是——**查不到，不等于不存在**。
`HKLM\SOFTWARE\Microsoft\CTF\Assemblies` 里查不到这两个 TIP，我当时的结论是
「注册在别处」，然后就顺势采信了记忆，而不是继续找能自证的字段。

能自证的东西一直都在，只是不在我第一次找的地方：

```powershell
# 卸载项：DisplayName 是中文，InstallLocation 才指出它装在哪
Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' |
  ForEach-Object { $p = Get-ItemProperty $_.PSPath
                   if ($p.DisplayName -match 搜狗) { $p.InstallLocation } }
# -> D:\APP\SogouInput    而我当时只在 C:\Program Files* 下找
```

顺带一个搜索坑：这台机器的第三方软件全装在 `D:\APP\`（git、nodejs、python、
搜狗都是），不在 `C:\Program Files\`。**先确认这台机器的软件落在哪，再决定去哪儿找。**

**规则：涉及 GUID、CLSID、注册表值名、文件布局这类「标识符的身份」时，
不要凭记忆认。** 按可信度依次找：

1. **UI 显示的名字** —— 输入法、协议、文件关联，最终以界面为准
2. **能自证的字段** —— 卸载项的 `DisplayName` / `InstallLocation`、实际加载的
   DLL 路径、服务名
3. **文档** —— 最后才看文档，而且要核对它针对的是哪个版本

同一台机器上的另一个反例：`bash` 和 `jq` **都是 0 字节重解析点**，
我据「0 字节」断定 `jq` 是坏桩，它却工作正常（见
[`../../agent/windows-agent/ghost-commands.md`](../../agent/windows-agent/ghost-commands.md)）。
**从文件属性推不出行为。**

### 7. 写完立刻验一遍字符本身

上面那条 `>` 变成 `]` 是在**写文件时**发生的：肉眼读起来完全正常，`Get-Content` 也
读得出内容，但任何 `.Contains('List<T>')`，包括用来定位插入点的锚点搜索，都匹配不到。

所以凡是文档里要写**尖括号、占位符、泛型、比较运算符**的地方，提交前扫一遍：

```powershell
# 逐个文件查可疑的尖括号误配（粗筛，会有正常用法串的误报，逐条看）
Select-String -Path <file> -Pattern '<[^<>]*\]' -AllMatches
# 再单独确认关键占位符真的存在
<your-home>
```

**规则：凡是文档里要写**尖括号、占位符、泛型、比较运算符**的地方，提交前扫一遍。**
肉眼和 `Get-Content` 都不会告诉你字符被换掉了，只有比对才会。

```powershell
# 粗筛可疑的尖括号误配（会有正常用法串的误报，逐条看）
Select-String -Path <file> -Pattern '<[^<>]*]' -AllMatches
```
不要指望 `$script:` 作用域。**

---

## 二、直接报错的那类：浪费轮次，但不污染结论

### 8. `[regex]::Replace` 的第 4 个位置参数是 `RegexOptions`，不是次数

```powershell
[regex]::Replace($t, '(?m)^(# .*)$', "`$1`n$note", 1)
# 这里的 1 被当成 RegexOptions.IgnoreCase，于是「只替换第一处」变成了「替换全部」
```

我在一个 SKILL.md 里插入 Paths 说明，结果**同一段说明被插了 5 次**——
因为文件里有 5 个一级标题。

单次替换要用 `[regex]::new($pattern).Replace($input, $repl, 1)`。

### 9. `-f` 格式化串里不能内联 `if`

```powershell
"{0,-3}| {1}" -f $i, (if ($lines -le 1) { "x" } else { "y" })   # 语法错误
```

PS 7 里 `if` 是语句不是表达式，**必须用 `$()` 包起来**：
`$(if ($c) { 1 } else { 0 })`。或者——更省事——先算好再传进 `-f`。

### 10. 变量名撞车：路径被当成文件名

```powershell
function Probe($exe, $arg) {
    $o = "$out\$exe.out"      # $exe 是完整路径 C:\...\jq.exe
}
# -> '文件名、目录名或卷标语法不正确。 C:\...\Temp\probe\C:\...\jq.exe.out'
```

参数名和派生文件名用了同一个变量。文件名部分要用 basename，
不要直接拼路径。

### 11. 匹配 `old_string` 时的三种对不上

用文件编辑工具做精确替换，`old_string` 必须逐字符相同：

- **前导空格数错**：我写 `  Non-ASCII in the wrong place`，文件里其实是
  `trigger matching). Non-ASCII`——同一个子串，但**不在行首**。
- **引号全角/半角**：文档里是中文 `“…”`，我写了 ASCII `"…"`。
- **行尾**：CRLF 文件用 `\n` 匹配必然失败（见
  [`cjk-command-io.md`](cjk-command-io.md) 4.1）。

**规则：替换失败不是"文件里没有这段"，先 `read` 一遍再写 `old_string`。**

### 12. 括号多一个也是语法错

`ForEach-Object { ... } }` 三个收尾花括号，报 `表达式或语句中存在意外的标记 }`。
这类错误 PowerShell 只报位置不给上下文，多半是多了一层嵌套。

---

## 三、流程性的一类：最贵的教训

### 13. 命令失败了要检查，再跑下一条

```powershell
git checkout -q main          # 因为本地有改动而失败
git reset -q --hard origin/main   # 我没看上一条的结果，把刚写的内容冲掉了
```

`checkout` 的非零退出码在输出里，但它**不是致命错误**，PowerShell 继续往下跑，
`reset --hard` 把未提交的编辑抹掉了。

**规则：`$ErrorActionPreference = 'Stop'` 只管 cmdlet，不管原生 exe。**
涉及 `checkout` / `reset` / `push` 这类会改状态的命令之后，
要么显式判 `$LASTEXITCODE`，要么分开成独立的调用。

### 14. 代理后面 API 调用会间歇失败

同一个下午，同一个 GitHub：

```
gh pr create  -> Post "https://api.github.com/graphql": EOF   # 4 次里 2 次
git push      -> 正常
git ls-remote -> schannel: failed to receive handshake
```

`git push` 走 HTTPS 没事，`gh` 的 GraphQL 会断。重试循环不是坏事，是必需的。

**更阴的一种：失败被当成成功。** `gh pr create` 第一次其实**创建成功了**，
只是响应被吞；重试拿到"already exists"，我据此以为第一次失败了。

### 15. 安全网关会在你意料之外的地方拦

- `Remove-Item`、`cmd /c del` 被拦（提示改用 `mavis-trash`）
- **改了工作目录之后再写文件**被拦（"write/delete targets cannot be verified safely
  after a command working directory change"）

所以 `Set-Location` 之后跟写操作，取决于它们在同一条命令里的位置。
用 `git -C`、`-File` 绝对路径代替 `Set-Location`，问题就没了。

### 16. 先删远端分支，再确认 PR head 已经改名

```
gh api -X PATCH .../pulls/31 -f new_head=skills/run-sql-file   # 返回的仍是旧 ref
git push origin --delete run-sql-file-skill                      # PR 被 GitHub 自动关闭
gh pr reopen 31  -> Could not open the pull request
```

改名没生效我没确认，先删了源分支。PR 的 head 分支没了，它就关掉了，而且**无法 reopen**。

**规则：改 PR 的 head 分支要等 API 返回新名字，再删旧分支。**
或者更省事：直接删掉 PR，从新分支重开一个。

---

## 四、自查清单

写完一段 PowerShell 之后过一遍：

- [ ] 原生命令的 `$LASTEXITCODE` 都判了吗，还是只在 cmdlet 上用了 `-ErrorAction Stop`
- [ ] 有没有 `2>/dev/null` / `2>$null` 盖住了一个**不存在的命令**
- [ ] 任何统计打印出来是 0 的话，同时打印了参与统计的总数吗
- [ ] 管道超过两层的地方，用了具名变量而不是 `$_` 吗
- [ ] 模式里有没有 `\r` 这类控制字符（应该改用 `git ls-files --eol`）
- [ ] `$x++` 累加的变量，最终打印的是同一个作用域吗
- [ ] 会改状态的 git 命令之后，检查过前一条的退出码吗
- [ ] `old_string` 是从 `read` 出来的那份，不是凭记忆写的吗
- [ ] 涉及 GUID / CLSID / 注册表值名的地方，我**验证过它是谁**，而不是记得它像谁
- [ ] 文档里写的尖括号、占位符、泛型，写完用脚本确认能原样读回来

最后一条是最贵的：**本篇里一半的条目，都是"我以为自己成功了"。**

其中两条（6 和 7）不是 PowerShell 的问题，是**我读错**——一次把 GUID 认成了另一个产品，
一次把 `>` 写成了 `]`。它们能被抓到，靠的都是同一件事：拿机器上的可验证字段去对，
而不是拿记忆里的映射去套。
