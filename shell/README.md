# Shell 配置：四层分层

bash 与 zsh 共用的 shell 配置原件。**WSL（Ubuntu / Fedora）与原生 Linux 桌面部署的是同一套**：
WSL 专属的部分（Windows 互操作函数、VS Code 路径探测）用 `grep -qi microsoft /proc/version`
守着，在原生 Linux 上自动跳过。

- WSL 上怎么装：[`../wsl/setup/`](../wsl/setup/) 步骤 3–4
- 原生 Linux 桌面上的差异（`chsh` 不生效、安装脚本往 rc 里追加）：[`../linux-desktop/`](../linux-desktop/) 第 2.1、2.4 节
- 发行版之间的差异（Fedora 的 `/etc/bashrc` 链、`~/.profile` 不被读）：[`../wsl/distro-differences.md`](../wsl/distro-differences.md)

## 文件

`files/` 下是可直接复制的原件（已脱敏，不含凭据；注释一律纯 ASCII 英文）：

| 仓库中的文件 | 部署到 | 作用 |
| :--- | :--- | :--- |
| `files/shell_common` | `~/.shell_common` | **bash 与 zsh 共用**的环境变量、PATH、代理、输入法、keyring |
| `files/shell_wslfn` | `~/.shell_wslfn` | Windows 互操作**函数**定义。非 WSL 直接 `return`；除末尾 export 一个 `BASH_ENV` 指回自己（给非交互 bash 用）外无副作用，所以够轻，敢从 `~/.zshenv` 里 source |
| `files/zshenv` | `~/.zshenv` | 每次 zsh 启动都会读，**包括非交互**（脚本 / AI Agent） |
| `files/zshrc` | `~/.zshrc` | zsh 专有：oh-my-zsh、主题、PROMPT |
| `files/bashrc` | `~/.bashrc` | bash 专有：PS1、历史、补全 |
| `files/profile` | `~/.profile` | 登录 shell 入口 |

```bash
cd <本仓库>/shell/files
mkdir -p ~/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)
cp ~/.zshrc ~/.bashrc ~/.profile ~/.dotfiles-backup/*/ 2>/dev/null || true
cp shell_common ~/.shell_common
cp shell_wslfn  ~/.shell_wslfn
cp zshenv       ~/.zshenv
cp zshrc        ~/.zshrc
cp bashrc       ~/.bashrc
cp profile      ~/.profile
```

部署后要按本机调整的位置（代理端口、VS Code 探测、keyring）见 [`../wsl/setup/`](../wsl/setup/) 步骤 4。
凭据放 `~/.shell_secrets`（`chmod 600`），`~/.shell_common` 末尾自动 source，永远不进版本库。

## 分层设计（先理解，再动手）

这是本环境与「把所有东西堆进 `.bashrc`」最大的区别。四层，各司其职：

```
~/.zshenv          每次 zsh 启动都读（含非交互）-> 只放函数定义，必须轻量
   |
   +-> ~/.shell_wslfn      Windows 互操作函数（explorer / cmd / reg / powershell ...）
                             |    ^
                             |    | 也被 shell_common 引用
                             +--> export BASH_ENV=$HOME/.shell_wslfn
                                  bash 没有 .zshenv 的对等物，这是非交互 bash
                                  唯一的入口（`bash -c` / `#!/bin/bash` 脚本）
~/.zshrc  --+                     |
            +--> ~/.shell_common --+   环境变量、PATH、代理、输入法、keyring
~/.bashrc --+                          （bash 与 zsh 的唯一真相来源）
```

### 三条硬规则

1. **只有两边都合法的语句才能进 `~/.shell_common`。**
   - oh-my-zsh / `ZSH_THEME` / `PROMPT` / `zstyle` -> 只能进 `~/.zshrc`
   - `PS1` / `shopt` / `HISTCONTROL` / bash-completion -> 只能进 `~/.bashrc`
   - `${PWD,,}` 是 bash 专有、`${PWD:l}` 是 zsh 专有，共用文件里一律改用 `tr` 转小写

2. **`conda init` 块绝不共用。** 两个 shell 的 hook 不同（`shell.zsh` vs `shell.bash`），必须各写各的。

3. **用函数，不要用 alias。**
   非交互 shell **默认不展开 alias**（bash 和 zsh 都一样）。这意味着 `alias cmd=...` 对脚本、cron、AI Agent 全部无效。函数则在任何模式下都有效。
   这也是 `~/.zshenv` 存在的唯一理由——它是非交互 zsh 会读的**唯一**启动文件。

> **为什么值得较真**：`gh auth login` 会起子 shell 调浏览器，alias 不传递，授权页面永远打不开。详见 [`../git-github/README.md`](../git-github/README.md) 第二节。

**安装脚本会破坏分层。** oh-my-zsh、`pnpm setup`、nvm、conda 默认往 `~/.bashrc` / `~/.zshrc` 末尾追加
PATH 块。oh-my-zsh 用 `--unattended --keep-zshrc` 装；其余装完后检查 rc 尾部，把追加的块删掉——
`PNPM_HOME`、`NVM_DIR` 已经在 `~/.shell_common` 里统一处理。

## 验证配置时，`bash -lc` 和 `bash -ic` 解析出的 PATH 不一样

Debian 的 `~/.bashrc` 开头会对**非交互** shell 直接 `return`
（`case $- in *i*) ;; *) return;; esac`）。于是：

| 调用形式 | 读到哪些文件 | `~/.shell_common` | node/nvm |
| :--- | :--- | :---: | :---: |
| `bash -ic ...` 交互 | `.bashrc` | ✅ | ✅ |
| `bash -lc ...` 登录但非交互 | `.profile` → `.bashrc`（立刻 return） | ❌ | ❌ 回落到 `/usr/bin/node` |
| `bash -c ...` 纯非交互 | 都不读 | ❌ | ❌ |

同一条 `bash -l`，只差一个 `-i`，node 版本就能是反的。实测同一天里
`bash -ic` 是 v24、`bash -lc` 是 v22，两边都"看起来对"，只有对照才发现矛盾。

**为什么值得记**：这不是配置的问题，是**验证方法**的问题。
用一种调用形式验证、在另一种形式里使用，就会得出"配置没生效"的错误结论，
然后去反复修改本来完全正确的配置——本次会话里就是这么把结论带偏的。

验证 shell 相关配置时，**用跟你实际使用它的方式一致的调用形式**：

- 终端里手敲 → `bash -ic`
- 脚本 / CI / agent 子进程 → `bash -c`，此时应当靠 `BASH_ENV` 兜住（见上面硬规则 3）
- 登录会话 → `bash -lic`

另外，**已经在跑的进程不受 rc 改动影响**。会话是在它启动那一刻就把环境快照下来的，
之后改 `.bashrc` / `.shell_common` / `/etc/passwd` 都不会回灌。要确认某个**活着的**进程
看到的环境，直接读它自己的 environ：

```bash
tr '\0' '\n' < /proc/$(pgrep -x lxqt-session)/environ | grep '^SHELL='
```

桌面会话里还有第三层：`/etc/passwd` 只是登录 shell 的**默认值**，任何在会话启动前
`export SHELL=...` 的脚本都能把它盖掉，而且完全静默。见
[`../honor-linuxlab/README.md`](../honor-linuxlab/README.md) 2.4。

## System32 自动回家

`~/.shell_common` 第 1 节：shell 启动时若当前目录在 `/mnt/<盘>/windows/system32` 或 `syswow64` 下，
就 `cd "$HOME"`（以管理员打开 Windows Terminal 时 WSL 会从 System32 起步）。

- **只在 shell 启动时判断一次**，之后手动 `cd /mnt/c/Windows/System32` 不会被弹回。
- 转小写用 `tr`，不用 `${PWD:l}` / `${PWD,,}`，原因见上面硬规则 1。
- Windows 侧（PowerShell `$PROFILE`）的对应做法见 [`../windows/terminal/`](../windows/terminal/)。

## zsh 会展开以 `=` 开头的词

zsh 默认开启 `EQUALS` 选项：以 `=` 开头的词会被替换成同名命令的路径（`=ls` → `/usr/bin/ls`）。所以 `echo ======` 在 zsh 里报 `zsh: = not found` 之类的错，而且**同一行后面的命令也没有执行**——和通配符无匹配时一样，整条命令行中止。bash 没有这个行为。

分隔线、以 `=` 开头的参数一律加引号：`echo '---'`、`echo '======'`。AI agent 的命令如果跑在 zsh 上（Claude Code 会用用户的登录 shell），也会碰到。

## zsh-autosuggestions 按键

`files/zshrc` 启用 `git`、`zsh-autosuggestions`、`zsh-syntax-highlighting`（语法高亮必须放在插件列表最后）。

| 按键 | 动作 |
| :--- | :--- |
| `→` / `End` / `Ctrl+E` / `Ctrl+F` | 采纳整条灰色建议 |
| `Alt+F` / `Alt+→` | 只采纳下一个词 |
| 继续输入 / `Backspace` | 不匹配时建议自动消失 |
