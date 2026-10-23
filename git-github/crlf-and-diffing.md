# 换行符与「只看对方改了什么」

> 从建模项目的跨平台协作笔记里抽出来的通用部分。场景是：协作者在 Windows 上工作，你在 WSL/Linux 上合并他们的改动。

---

## 问题

Windows 上编辑过的文件带 CRLF 行尾，Linux 上是 LF。直接 diff 会把**整个文件报成重写**，于是「只看对方改了什么」这件事彻底失效——真正的几行改动淹没在几百行假 diff 里。

### 先分清三层，别看到 CRLF 就报警

2026-10-17 排查过一次「谁把 LF 变成 CRLF」的疑问，结论是**没有任何 PR 干过这事**：

| 层 | 当时的状态 | 是否问题 |
| :--- | :--- | :--- |
| 仓库 blob（历史与提交） | 193 个 blob 全是 LF，`git grep -e $'\r' HEAD` 零命中 | ✅ 没问题 |
| Windows 工作区 | 191 个文件是 CRLF | ⚠️ `core.autocrlf=true` 的正常产物 |
| WSL / Linux 工作区 | LF | ✅ 没问题 |

`git clone` **会**把 LF 转成 CRLF 写进 Windows 工作区，但**永远不会改写仓库里的对象**。
所以「clone 下来是 CRLF」和「仓库被 CRLF 污染了」是两件事——前者是设计，后者才是事故。

判断方法（比翻 diff 可靠）：

```bash
git grep -I -l -e $'\r' HEAD --        # 仓库里有没有 CR
git status --short                     # 0 条 = 工作区和 HEAD 一致
```

`git status` 干净但工作区是 CRLF，说明只是检出转换，仓库是干净的。

## 走 Git 的情况：`.gitattributes` 能挡住

仓库根现在有一个 `.gitattributes`（2026-10-17 加入），关键几行：

```gitattributes
* text=auto eol=lf
*.sh text eol=lf
*.bat text eol=crlf
*.cmd text eol=crlf
*.reg text eol=crlf
```

`text=auto` 让 Git 在入库时把文本文件统一成 LF；`eol=lf` 再把检出端也钉死成 LF，
**这样行为由仓库规则决定，而不是由每台机器的 `core.autocrlf` 决定**。

Windows 原生格式（`.bat` / `.cmd` / `.reg`）单独给 `eol=crlf`：**工作区保持 CRLF，
但入库仍然是 LF**，跨平台 diff 依旧干净。

> ⚠️ 不要写 `*.ps1 text eol=crlf`。`eol=crlf` 的含义是「在**所有**平台都检出成 CRLF」，
> 包括 Linux 和 WSL——那里的 shell 脚本会直接跑不动。本仓库的 `.ps1` 用默认的 LF。

### 为什么属性文件比 `core.autocrlf` 更可靠

实测（`core.autocrlf=false`，从一个 CRLF 工作区提交）：

| 有无 `.gitattributes` | 提交进仓库的 blob |
| :--- | :--- |
| 无 | **CRLF 永久进入历史** |
| 有（`* text=auto`） | `git add` 时被归一化成 LF，`git status` 报 `nothing to commit` |

**属性文件的优先级高于 `core.autocrlf`**，所以它能挡住「autocrlf 被改成 false 就把
CRLF 提交进去」这条唯一的污染路径。

### 改完配置后，怎么把已有工作区转成 LF

改 `core.autocrlf` **不会**重写磁盘上已有的文件，而且下面这些命令**都没用**——
git 认为文件没变，就直接跳过，不会重新跑 smudge：

```bash
git checkout -f HEAD          # 无效
git checkout-index -a -f      # 无效
git reset --hard              # 无效
```

实测可靠的做法是先移除再检出，让 git 按当前规则重新生成：

```bash
git rm -r -q -f . && git checkout -q HEAD -- .
```

工作区干净时执行它，**`git status` 保持 0 条改动**——因为 CRLF→LF 的转换对 git 不可见，
这正是转换成功的标志，不是没生效。

### Windows 上写文件：哪些写法必产 CRLF

实测（PowerShell 7.6.7）：

| 写法 | 行尾 |
| :--- | :--- |
| `[IO.File]::WriteAllText($p, "a`nb`n")` | **LF** ✅ |
| `[IO.File]::WriteAllLines` | CRLF ❌ |
| `Set-Content` / `Out-File`（含 `-Encoding ascii`） | CRLF ❌ |
| `cmd /c echo` | CRLF ❌ |
| Windows PowerShell 5.1 的 `Set-Content` | CRLF ❌ |

`WriteAllText` 之所以行，是因为它把你给的字符串**原样**写进文件（含 `\n`）；
其余几个都走 `Environment.NewLine`，在 Windows 上就是 CRLF。

另外：**按子串替换的编辑工具会把替换内容归一化到文件既有的行尾**，
所以逐行改一个 CRLF 文件，它会永远是 CRLF。要改行尾只能整文件重写。

## 不走 Git 的情况：`.gitattributes` 不生效

**这是最容易栽的地方。** 协作者有时是用**目录拷贝或 zip** 把改动交回来的——完全没经过 Git，`.gitattributes` 无从介入，CRLF 原样落到你的工作区。

这时 diff 必须显式忽略行尾差异：

```bash
diff -r --strip-trailing-cr old_dir/ new_dir/
git diff --ignore-cr-at-eol                    # 已在工作区里的话
```

不加这个参数，你会看到整个文件被标成改动，然后花半小时找"对方到底改了啥"。

## 判断文件当前是什么行尾

```bash
file somefile.py                    # 会说 "with CRLF line terminators"
grep -c $'\r' somefile.py           # 数带 CR 的行
```

批量转换：

```bash
sed -i 's/\r$//' file               # CRLF -> LF
dos2unix file                       # 同上，需要装 dos2unix
```

## 顺带：路径也别硬编码

三台机器（Windows 的 `E:/...`、WSL 的 `~/code/...`、云端的 `/data/...`）意味着：

- **文档里一律用仓库相对路径**，复现命令写成从仓库根起的 `cd <subdir>`
- 引用位置用 `文件:行号` 形式，跨平台通用
- **代码里不要硬编码任一平台的路径**——最典型的是字体路径，见 [`../agent/skills/linux-cjk-font/`](../agent/skills/linux-cjk-font/)

---

## 相关

- [`README.md`](README.md) —— GitHub 隐私邮箱、gh 登录与凭据、代理调优
- [`email-scrub-runbook.md`](email-scrub-runbook.md) —— 清洗历史里的真实邮箱
