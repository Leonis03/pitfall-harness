# pitfall-harness

*[English](README.md) · 中文*

给 AI 编程 agent 搭环境时踩过的坑。每条都写明症状、根因和实证方法——配置是鱼，排查的方法才是渔。
内容来自一个人的几台机器，主力工具是 Claude Code 与 Antigravity CLI，网络走本地代理。
skill 另有单独的仓库可直接安装：[pitfall-harness-skills](https://github.com/Leonis03/pitfall-harness-skills)。

---

## 项目理念：Agent 作为系统操作员的闭环沉淀

把 Agent 当成真实的**系统操作员**，人类通过自然语言提出目标，驱动 Agent 在真实环境进行 vibe 式探索；一旦通过实证把方案跑通，就把探索结果沉淀为可验证、可复现、可部署的 Markdown、配置、脚本和 Skill，从而让下一次 Agent 不必重新探索。

```text
自然语言提出目标 → Agent 直接操作真实系统并执行命令 → 观察症状 → 定位并实证根因 → 得到可工作的配置/操作方案 → 把方案固化成配置、脚本、README、Skill 和验证方法 → 下次由 Agent 按这些确定性知识复现。

一次性的 Agent 探索
        ↓
       经验
        ↓
     结构化结论
    ↙    ↓    ↘
Config README Skill
    ↘    ↓    ↙
     可执行规范
        ↓
  下一次 Agent 复用
```

### 文档受众与语言规范

仓库内的 Markdown 文档严格按受众划分为两类：
- **给 Agent 读写的**：使用对 Agent 最舒适、上下文最严谨、Token 效率最高的方式——**英文（English）**。
- **给人读的**：中文版作为人类参考，**使用直译**，满足人类能读懂即可。
- **统一以英文版为基准**：编辑或新增文档时，**一律先写给 Agent 读的英文版**，再直译生成中文版；废除旧有「先写中文正本」的流程。

---

| 环境 | 在哪 |
| :--- | :--- |
| Windows 11 + WSL2（Ubuntu 24.04 → Fedora 44 迁移中） | [`wsl/`](wsl/) · [`windows/`](windows/) |
| Windows 11 + 同一台机器上的 Linux 发行版（双系统） | [`os-install/`](os-install/) |
| 原生 Linux 桌面（Linux Mint 22） | [`linux-desktop/`](linux-desktop/) |
| 上面两者共用的 bash / zsh 四层配置 | [`shell/`](shell/) |
| Android（Termux root chroot） | [`agent/skills/`](agent/skills/) 下的 `android-chroot-debian` 等 skill |
| 荣耀平板 Linux 实验室（PRoot 容器） | [`honor-linuxlab/`](honor-linuxlab/) · [`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/) |
| 租用的云 GPU（DeepLN） | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) · [`gpu-cuda-checks/`](agent/skills/gpu-cuda-checks/) |

> **AI agent 请先读 [`AGENTS.md`](AGENTS.md)**：目录地图、「要做 X 改哪些文件」对照表、必须一起改的文件、提交前检查。

> **WSL 迁移中**：**Ubuntu 24.04** 是此前的主力发行版，现在日常工作已转到 **Fedora 44**，正在把配置向它对齐。
> 两边并存：`wsl -l -v` 里 Ubuntu 仍是默认（那个 `*`），但实际敲命令的地方是 Fedora。
> 四层 shell 配置的核心三个（`.zshenv` / `.shell_wslfn` / `.shell_common`）两边同哈希，剩下的差异要么是
> 发行版本身决定的（Fedora 的 fcitx5 块、`/etc/bashrc`），要么还在收敛。
> 具体差异与「哪些可避免、哪些不可避免」见 [`wsl/distro-differences.md`](wsl/distro-differences.md)。
>
> 文档里写 Ubuntu 的地方多数仍然成立——差异都在 `distro-differences.md` 里单独记着。

内容分两类：**能直接复制部署的配置文件**，以及**排查过程留下的结论**——后者往往比配置本身更值钱，因为它记录了「为什么是这样」。

> 所有路径、用户名、机器标识、端口与时间戳均已脱敏（`$HOME`、`<your-linux-user>`、
> `<your-windows-user>`、`<vm-1>`、`<proxy-port>`、`<ssh-port>`、`<t-created>`），邮箱写作
> `your-old-email@example.com` 占位。部署前按自己的环境替换。
>
> `wsl/storage/forensics/` 里的 `<t-...>` 是**稳定**占位符：同一个 token 在哪出现都指同一时刻，
> 所以取证块之间的时间列比对仍然成立，事件间隔在正文里用时长说明。

---

## 从哪开始

| 你想做什么 | 去哪 |
| :--- | :--- |
| **在新的 Windows 机器上复刻 WSL 环境** | [`wsl/setup/`](wsl/setup/) —— 复刻指南，可整份交给 agent 执行 |
| **在 Windows 旁边装第二个系统，并让两边时钟一致** | [`os-install/`](os-install/) —— 跨越安装边界的契约；当前是双系统的 RTC/UTC 时钟契约 |
| 在原生 Linux 桌面上复刻 | [`linux-desktop/`](linux-desktop/)，shell 配置用 [`shell/`](shell/) |
| 配 Git 与 GitHub（含隐私邮箱） | [`git-github/`](git-github/) |
| 配 Claude Code | [`agent/claude-code/`](agent/claude-code/) |
| 找一个现成的 skill，或把 skill 同步到本机 | [`agent/skills/`](agent/skills/) —— 部署走 `tools/sync-skills.sh`，不是 `cp` |
| 查某个具体的坑 | 见下面的「踩坑索引」 |
| 让 AI agent 在这个仓库里改东西 | [`AGENTS.md`](AGENTS.md) —— 英文，给 agent 读的入口 |
| 了解这里的写作与发布规矩 | [`conventions.zh.md`](conventions.zh.md) —— ASCII 边界、命名、`tmp/`、发布门禁、双仓同步 |
| 搞懂占位符体系：为什么仓库里没有真用户名，部署却能解析 | [`redaction.zh.md`](redaction.zh.md) —— 三类值的决策树与两条流水线 |

---

## 目录

除 `tmp/` 外，每个顶层目录都有一个 `README.md` 做索引；带 `files/` 的目录，`files/` 下是可直接部署的原件，其余是文档。

### [`shell/`](shell/) —— bash / zsh 四层配置（WSL 与原生 Linux 共用）

`~/.zshenv` → `~/.shell_wslfn` → `~/.shell_common` ← `~/.zshrc` / `~/.bashrc`。分层设计与三条硬规则
（共用文件只放两边都合法的语句、`conda init` 不共用、用函数不用 alias）写在 README，原件在 `files/`。
WSL 专属的互操作函数在原生 Linux 上靠 `/proc/version` 检测自动跳过。

### [`wsl/`](wsl/) —— WSL2

| 目录 | 内容 |
| :--- | :--- |
| [`setup/`](wsl/setup/) | **环境复刻指南**。`.wslconfig`、`/etc/wsl.conf`、fstab、binfmt 与 `/mnt/wsl` 守护、apt 换源、工具链。`files/` 下是 WSL 专属原件 |
| [`distro-differences.md`](wsl/distro-differences.md) | Ubuntu 24.04 与 Fedora 44 的差异 |
| [`gui-ime/`](wsl/gui-ime/) | WSLg 图形应用与 fcitx5 中文输入法 |
| [`uninstall-cleanup.md`](wsl/uninstall-cleanup.md) | 卸载单个发行版或整个 WSL、残留清理、验证与重装 |
| [`storage/`](wsl/storage/) | 发行版迁移到非系统盘、pnpm/npm 磁盘清理；`forensics/` 是一次 `E_ACCESSDENIED` 故障的原始取证记录 |

核心是 **`appendWindowsPath=false` + 显式函数桥接**：不注入 Windows 的几百个 PATH 条目，只把真正需要的几个 `.exe` 包成 shell 函数。

### [`windows/`](windows/) —— Windows 侧

[`setup/`](windows/setup/)（LTSC 环境配置 runbook，可整份交给 Agent 执行）· [`files/`](windows/files/)（可部署原件）· [`terminal/`](windows/terminal/)（Windows Terminal 配置）· [`powershell/`](windows/powershell/)（PowerShell 7 profile、PSReadLine、一键关闭所有资源管理器窗口、关闭 / 强制关闭 Typora）· [`ime-keyboard/`](windows/ime-keyboard/)（卸载语言后残留的键盘布局、拼音首字母漏成英文的排查清单）· [`context-menu/`](windows/context-menu/)（右键菜单项排查与优化）· [`windows-update/`](windows/windows-update/)（把功能更新钉在 24H2，但保留更新可见性）

### [`os-install/`](os-install/) —— 系统安装

只因为「两套系统共用同一台机器」才存在的主题。当前是双系统 Windows 与 Linux 之间的
**时钟契约**：RTC 约定、8 小时偏差的特征、自动校正与有意漂移的取舍，以及与快速启动的
相互作用。`files/` 里的只读探针报告两侧状态；每个修复都是一条命令，写在支撑它的实测
数据旁边。

### [`linux-desktop/`](linux-desktop/) —— 原生 Linux 桌面

Linux Mint 22（Ubuntu 24.04 noble 底座）上的复刻记录：换源、代理与 `sudo`、`chsh`、fcitx5、剪贴板、
Ghostty 与 Nemo 右键菜单、多设备历史命令迁移。`files/` 下是 Ghostty 配置与 Nemo action 原件。

### [`honor-linuxlab/`](honor-linuxlab/) —— 荣耀平板 Linux 实验室

第三类环境，也是最容易配错的一类：PRoot 容器里 `127.0.0.1` 就是容器自己，全机没有任何代理软件。
记录官方内置知识库与官方助手都没覆盖的部分——终端代理变量层、locale 与输入法的冲突，
以及 28 个官方知识单元的逐条覆盖度比对（见 [`docs-gap.md`](honor-linuxlab/docs-gap.md)）。
可执行的流程在 [`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/)。

### [`agent/`](agent/) —— AI 工具链

| 目录 | 内容 |
| :--- | :--- |
| [`claude-code/`](agent/claude-code/) | `settings.json`、全局约定原件 `claude-global.md`（部署为 `~/.claude/CLAUDE.md`）、状态栏脚本 |
| [`skills/`](agent/skills/) | 全部 skill，同时供 `~/.claude/` 与 `~/.gemini/config/`。仓库是脱敏的，部署与核对走 [`tools/sync-skills.sh`](tools/sync-skills.sh) |
| [`antigravity/`](agent/antigravity/) | `~/.gemini/config/AGENTS.md` 原件（强制走 `bx`）、`agy` CLI 使用与图片交接 |
| [`brave-search/`](agent/brave-search/) | `bx` CLI 与 Brave Search MCP 接入 |

### [`git-github/`](git-github/) · [`tools/`](tools/) · `tmp/`

Git 隐私配置与历史脱敏 runbook（含 GitHub 文件大小的四道门槛）；Python 与远程执行的踩坑；
Docker；[`tools/latex/`](tools/latex/)（VS Code LaTeX Workshop 工具链，以及 ChkTeX 为什么在中文环境必须关掉）；
以及三个维护本仓库的脚本——[`tools/privacy-gate.sh`](tools/privacy-gate.sh)（发布前的脱敏门禁）、
[`tools/sync-skills.sh`](tools/sync-skills.sh)（skill 的渲染式部署与核对）和
[`tools/publish.sh`](tools/publish.sh)（导出到两个公开仓库）。两类内容的区分见 [`tools/README.md`](tools/README.md)。

`tmp/` 是**临时工作区**，已 gitignore，一切临时编辑、脚本试跑、覆盖前的备份都在里面做。
三者均见 [`conventions.zh.md`](conventions.zh.md)。

---

## 踩坑索引

这些是排查花了时间、结论又不显然的条目。

| 坑 | 症状 | 在哪 |
| :--- | :--- | :--- |
| **非交互 shell 不展开 alias** | 脚本和 AI agent 报 `command not found`，你自己敲却好好的 | [`shell/`](shell/) 三条硬规则 |
| **wslu 在 systemd 下误报** | `WSL Interoperability is disabled`，但 `wsl.conf` 明明是对的 | [`git-github/README.md`](git-github/README.md) 二.3 |
| **`filter-repo` 静默毁改动** | 重写历史后未提交的已跟踪修改消失，且无提示 | [`git-github/email-scrub-runbook.md`](git-github/email-scrub-runbook.md) 第 2 节 |
| **`no_proxy` 通配符失效** | 访问本机服务却穿了代理，报 502 空体像"请求失败" | [`tools/python/`](tools/python/) 第 1 节 |
| **f-string 引号规则** | `invalid syntax`，且 3.10 与 3.12 行为不同 | [`tools/python/`](tools/python/) 第 2 节 |
| **numpy 2 不会让纯 Python 循环变快** | 热点在 Python 循环里时，为提速升级 numpy 毫无作用；同一个任务从 3.10 换到 3.12 快了 1.4 倍，输出逐字节相同 | [`tools/python/`](tools/python/) 第 3 节 |
| **`uv run` 一声不吭地卡住** | 平时几秒的命令没有输出、不报错，几分钟不结束：卡在解析依赖的联网检查上。依赖都在缓存里时加 `--offline` | [`tools/python/`](tools/python/) 第 4 节 |
| **`pkill -f` 杀掉自己** | 返回 255，看起来像 SSH 断连 | [`tools/remote-ssh.md`](tools/remote-ssh.md) 第 2 节 |
| **Python 里设线程数太晚** | BLAS 已初始化，48 worker 开 3077 线程，慢 227 倍 | [`tools/remote-ssh.md`](tools/remote-ssh.md) 第 3 节 |
| **heredoc 脚本里的 `ssh` 吞掉后面的脚本** | 第一条 `ssh` 之后的命令全都没执行，退出码 0：`ssh` 会转发标准输入，而 heredoc 里标准输入就是脚本本身。加 `ssh -n` | [`tools/remote-ssh.md`](tools/remote-ssh.md) 第 8 节 |
| **`set -e` 加 `\| grep`，没匹配就中止** | 脚本停在一条其实成功了的命令后面：用来过滤的 `grep` 没匹配到，返回了 1 | [`tools/remote-ssh.md`](tools/remote-ssh.md) 第 9 节 |
| **`rsync` 拉回覆盖了本地更新的文件** | 本地重新生成过的报告悄悄变回远端的旧版本。先 `-n --itemize-changes` 预览；用 `--ignore-existing` 或 `--update` | [`tools/remote-ssh.md`](tools/remote-ssh.md) 第 10 节 |
| **盘符路径在 WSL 恒不存在** | `C:/Windows/Fonts/...` 找不到字体，静默出豆腐块且不报错 | [`agent/skills/linux-cjk-font/`](agent/skills/linux-cjk-font/) |
| **写死的 Windows 账户名会过期** | 同样是静默豆腐块：`/mnt/c/Users/<旧机器的账户名>/...` 在本机不存在。WSL 里没有 `%USERPROFILE%`，该用 `glob("/mnt/c/Users/*/...")` | [`agent/skills/README.md`](agent/skills/README.md) |
| **drvfs 大小写不敏感，会把写死的账户名藏起来** | 比上一条更阴：本机 Windows 账户名与 `$USER` 只差大小写，字符串相等判断为假，但 `/mnt/c/Users/$USER/...` 照样 stat 成功——于是「用 `$USER` 拼 Windows 家目录」这个错做法在本机**一直是通过的**，换台名字真不同的机器才静默失效 | [`wsl/setup/`](wsl/setup/) 常见问题 |
| **zsh 在 `for` 列表里遇到无匹配 glob 会中止整个文件** | 同一份 `~/.shell_common` 被 bash 和 zsh 共用；bash 把字面量原样传下去，zsh 直接 `no matches found` 退出，后面的配置全不执行 | [`wsl/setup/`](wsl/setup/) 常见问题 |
| **zsh 里 `echo ======` 报错** | `zsh: = not found`，同一行后面的命令也不执行：以 `=` 开头的词会被展开成命令路径。加引号 | [`shell/`](shell/) |
| **非交互 bash 没有 `.zshenv` 的对等物** | zsh 侧的互操作函数覆盖到了脚本和 agent，bash 侧没有：`bash -c` 和 `#!/bin/bash` 两个启动文件都不读。验收清单历史上写的是 `bash -ic`，带 `-i` 恰好把缺口盖住了。出口是 `BASH_ENV` | [`wsl/setup/`](wsl/setup/) 验证清单第 3 条 |
| **`.gitattributes` 管不到 zip** | 整个文件被报成重写，真改动淹没在假 diff 里 | [`git-github/crlf-and-diffing.md`](git-github/crlf-and-diffing.md) |
| **`/reg:64` 重定向** | 注册表键"明明存在却找不到" | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **`binfmt_misc` 跨发行版全局** | 启停另一个发行版后，Windows 命令突然 `exec format error`，且看不出关联；还没法用互操作自救 | [`wsl/setup/`](wsl/setup/) 步骤 1.3 |
| **`accept4 110` 有两种病因** | 照"换 socket"的通行处方修，所有 socket 同样失败，白烧一小时 | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **`wsl -l -v` 的星号是「默认」不是「当前」** | 把它读成"你在这儿"，`-d <别的发行版>` 就静默回到了你已经在的那个。跨发行版写标记再读回来，测试完美通过——那是你自己的文件。只有 `stat -c %d` 露馅。判据是 `$WSL_DISTRO_NAME` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) 第 1 节 |
| **跨发行版传文件绕了 Windows** | 能跑，但同一批文件慢 23 倍（0.97 s vs 22.5 s）。`/mnt/wsl` 是 shared tmpfs，bind 到它下面就直通，不必走 `\\wsl.localhost` 的 9p | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) 第 2 节 |
| **`--terminate` 不释放被别人 bind 的盘** | `wsl -l -v` 显示 `Stopped`，另一个发行版照样往它的 ext4 里写，下次启动东西就在那儿；VHDX 也一直挂着，压缩必须 `--shutdown` | [`agent/skills/wsl-windows-command/references/cross-distro.md`](agent/skills/wsl-windows-command/references/cross-distro.md) 第 5 节 |
| **systemd ≥ 256 在 WSL 起不了 user session** | `Failed to spawn executor: Device or resource busy`；Ubuntu 255 没事，Fedora 259 必炸 | [`wsl/distro-differences.md`](wsl/distro-differences.md) |
| **cmd.exe 拒绝 UNC 工作目录** | 静默回退到 `C:\Windows`，路径相关操作全错却不报错 | [`agent/skills/wsl-windows-command/`](agent/skills/wsl-windows-command/) |
| **WSL 不走 Windows Update** | Windows 锁了版本，却以为 WSL 也一起锁住了；实际两个渠道互不相干 | [`wsl/setup/`](wsl/setup/) 维护节 |
| **`.wslconfig` 不在仓库里，代理就必然坏** | `host_ip="127.0.0.1"` 只在 `networkingMode=mirrored` 下成立。复刻时漏掉这个 Windows 侧文件，WSL 退回 NAT，`127.0.0.1` 指向它自己，所有代理请求 connection refused——而报错离原因很远，`~/.shell_common` 里没有任何线索 | [`wsl/setup/`](wsl/setup/) 步骤 0.1 |
| **ChkTeX 在中文文档刷屏误报** | `Use "'" (ASCII 39) instead of "´"` 刷满输出，真错误被淹没。它逐字节扫描而非 UTF-8 解码，汉字的后续字节落在 `´`(0xB4) 位上就被当成排版错误。改规则集没用，只能关掉 | [`tools/latex/`](tools/latex/) |
| **`-Source` 给了仍然去连网** | 离线装 Windows 中文字体包，ISO 都挂好了还是失败——`Add-WindowsCapability` 不加 `-LimitAccess` 会先去问 Windows Update | [`tools/latex/`](tools/latex/) · [`agent/skills/linux-cjk-font/`](agent/skills/linux-cjk-font/) |
| **pnpm 拦掉 postinstall 但不报错** | `pnpm update -g --latest` 退出码 0、看着装好了，命令却跑不起来——pnpm 10 起默认不执行生命周期脚本。要 `--allow-build=<包名>` 显式放行 | [`wsl/storage/pnpm-npm-cleanup-20260920.md`](wsl/storage/pnpm-npm-cleanup-20260920.md) 3.2 |
| **脱敏占位符借用了 `$HOME`** | 同一个记号既表示"待替换的家目录"，又表示真正的 shell 变量；一渲染就把 `set-deepln.sh` 里的 `$HOME` 硬编码成本机路径，脚本到了租来的 GPU 机上全错。判据应该是"会不会被 shell 展开"，不是文件类型 | [`agent/skills/README.md`](agent/skills/README.md) |
| **DeepLN 实例之间走公网域名不通** | 在一台租用机上 `ssh`/`rsync` 另一台的 `<实例>.deepln.com:<端口>` 一直超时，两个方向都一样。集群内要走 pod 内网 IPv4（`hostname -I`）的 22 端口，配 `ssh -A` 借本地密钥，实测 145–204 MB/s，约为家里上行的 100 倍 | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) 第 5.3 节 |
| **DeepLN「保存数据」快照多一层 `data/`** | 按常见写法 `tar xvf - -C /data/coding` 解开，文件落到 `/data/coding/data/coding/...`：压缩包是整个 `/data`。在 `-C /` 后加一个空格，写成 `-C / data/coding`：只解项目目录、不套娃；不加 `data/coding` 解到 `/` 又会覆盖新实例自己的 alist 配置 | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) 第 5.2 节 |
| **DeepLN 的 CPU 实例有两种规格** | 没有 GPU 的租用机要么是 1 核 / 2 GiB 的中转机，要么是 24 核 / 47 GiB 的计算机，`nproc`（80 或 256）看不出是哪种。按错的规格安排任务，不是饿死就是浪费。看 cgroup 配额 | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) 第 5.1 节 |
| **uv 的设置随租期消失** | 换租后 `uv pip install` 又变慢：TUNA 索引写在 `~/.config/uv/uv.toml`，它不在 `/data` 下。uv 的 Python、缓存、虚拟环境放 `/data`，配置由安装脚本每次重写 | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) 第 6 节 |
| **停掉的 DeepLN 实例换了主机密钥** | 实例关机或换租后 ssh 报 `REMOTE HOST IDENTIFICATION HAS CHANGED`。这时是正常的，但 `ssh-keygen -R` 之前先在控制台确认，不要条件反射地接受 | [`agent/skills/deepln-setup/`](agent/skills/deepln-setup/) 第 0 节 |
| **skill 的 `description` 里有 `: `，严格解析器静默丢掉整个 skill** | Claude Code 里好好的，`npx skills add --list` 却少两个、不报错。不加引号的 YAML 值里 `: ` 不合法，Claude Code 宽松放行，严格解析器直接跳过。改成 ` -- ` 或加引号 | [`agent/skills/README.md`](agent/skills/README.md) 约定 |
| **jq 路径写错静默出 0 行** | 对 `bx news` 用 `.web.results[]`，exit 0 无报错，看起来像"这话题没结果" | [`agent/brave-search/bx-cli.md`](agent/brave-search/bx-cli.md) 第 6 节 |
| **搜索前置 skill 成了固定税** | CLAUDE.md 每会话常驻、skill 正文按需加载，把 2.2k 的 skill 设成 `bx` 前置，成本结构正好反了 | [`agent/claude-code/README.md`](agent/claude-code/README.md) |
| **强推清掉了 `Co-Authored-By`，Contributors 里还挂着 Claude** | 远端历史已经干净，又推了新提交也不变；REST 的 contributors 接口只列作者，从头到尾都没有 Claude，页面上却一直显示。那个框是缓存，要把默认分支改名再改回来才会重算 | [`agent/skills/github-coauthor-scrub/`](agent/skills/github-coauthor-scrub/) |
| **脱敏正则反复漏网** | 同一个值换种渲染方式（大小写、列对齐、另一条命令的输出格式、换语言的标签）就逃过检查，5 轮都栽在这 | [`tools/privacy-gate.sh`](tools/privacy-gate.sh) 头部注释 |
| **Wayland 下输入法绑不上** | Electron 应用跑得好好的就是打不出中文，flag 怎么调都没用。Weston 把 `input_method` 留给自己的 IME 客户端，WSLg 又不跑它；更坑的是 fcitx5 撞上 error 71 会**整个进程退出**，连 X11 侧输入法一起没 | [`wsl/gui-ime/`](wsl/gui-ime/) 第 1、9 节 |
| **`wmctrl` 在 WSLg 全废** | 窗口摆放脚本静默空转、什么也没发生。Weston WM 不导出 `_NET_CLIENT_LIST`，`wmctrl -l` 恒失败，而脚本恰好用它找窗口 | [`wsl/gui-ime/`](wsl/gui-ime/) 第 8 节 |
| **机器换了、文档没换** | 一份「部署总结」里的显示参数、文件角色、修复方案全对不上本机。用首次运行留下的痕迹（`Crashpad/client_id`）与文档落款比时间，就能判定它根本不是在这台机器上写的 | [`wsl/gui-ime/`](wsl/gui-ime/) 第 5、8 节 |
| **PRoot 下 xrdb 无超时挂死整个桌面** | 荣耀平板 Linux 实验室切 Debian 永久卡在「加载中」，`xrdb -merge` 系统调用死锁阻断 `StartFinished` 握手信号；修改 `start` 会被 `AssetsPatcher` 校验覆写，需用子程序 wrapper 拦截规避 | [`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/) |
| **ARM64 换 Ubuntu 镜像源必须用 ubuntu-ports** | 平板换清华源后 `apt update` 报 404 找不到 `binary-arm64/Packages`，因为非 x86 架构在独立路径下 | [`agent/skills/honor-linuxlab/`](agent/skills/honor-linuxlab/) |
| **`execve` 与 `/proc/self/exe` 解耦** | 命令执行报 `readlink /proc/self/exe: no such file`，误以为内核无法派生进程。Linux `execve(2)` 本身不依赖 `/proc`，是 Go/CLI 运行器做自省与路径解析时受阻，挂载 `/proc` 仅是满足运行时自省而非提权 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **清华源只镜像 PyPI，不镜像解释器** | `pypi.tuna.tsinghua.edu.cn/simple` 是 200，而 `github-release/astral-sh/python-build-standalone` 是 404，所以 `python-install-mirror` 不能指清华——那是根本没有，不是慢。另外 `python-install-mirror` 必须是纯字符串，写成 `[python-install-mirror]` 表会报 `invalid type: map, expected a string`，且**整个 uv.toml 一起失效**，连索引也不生效 | [`tools/python/`](tools/python/) 第 5 节 |
| **CPython 出了新补丁版要先升 uv** | CPython 3.12.15 于 2026-09-30 发布，但 uv 0.12.18（2026-09-22 构建）最高只列到 3.12.14：下载清单是编译进二进制的，不是运行时查的。上游已 release ≠ 本机装得上 | [`tools/python/`](tools/python/) 第 5 节 |
| **`unshare -m` 隔绝了父子会话挂载** | 宿主更新了 chroot 挂载且 `--check` 通过，已运行的 agent 依然报 `open /dev/ptmx: no such device`。`unshare -m` 创建了独立 Mount Namespace，旧终端里的 `bash` 未退出导致重启的 agent 仍困在旧命名空间 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **Android Termux 报 `required file not found`** | 执行官方安装的 CLI 工具报文件未找到，但 `ls` 明明在；`readelf -l` 发现其 `PT_INTERP` 请求 `/lib/ld-linux-aarch64.so.1`，而 Android 原生使用 Bionic libc（`/system/bin/linker64`），内核找不到 glibc 解释器返回 ENOENT，必须用 chroot/glibc 容器 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **代理变量指向一个会消失的端口** | 代理是宿主 Android 上的一个**应用**，而 chroot 与宿主共享 network namespace，所以 `127.0.0.1:<端口>` 能通到它——但只在应用运行时。把它关掉，所有走代理的请求立刻 refused，而直连本来是通的。更坑的是 **TUN 模式下代理正常工作、端口却始终不开**，于是端口探测会把一个活着的代理报成 refused：先测请求通不通，再看端口 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **一个端口不能同时当 HTTP 和 SOCKS** | `ALL_PROXY=socks5h://...:<端口>` 报 "Connection reset by peer"，而同一端口上的 `HTTP_PROXY` 正常。WSL 原配置用的是混合端口，但本机这个代理软件占两个口：HTTP 一个、SOCKS5 另一个（握手分别是 `05 00` 和 `HTTP/1.1 200 Connection established`）。一个端口一个变量，永远分开写 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **写死的 messaging socket 路径让会话互相挤掉** | 第二个实例死于 "--messaging-socket-path points to a live socket"，而 peer 通知全落进持有该路径的那个会话，于是另一个 Termux session 看起来被消息刷屏。CLI 自己的约定是每个会话在 `cc-socks` 目录下各占一个 socket 文件，靠扫描目录发现 peer；写死文件名把两件事都破坏了。另外 `CLAUDE_CODE_MESSAGING_SOCKET` 的优先级高于命令行参数 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **`${PATH#...}` 删掉的不止它匹配的那一段** | 为把某个目录提到 PATH 最前面而重排，会静默丢掉另一个目录：`#` 剥离的是**最短**前缀，排在匹配段之前的那个条目会一起没了。这里整个 pnpm bin 目录消失，`mcode`、`mcode-tools`、`pnpm`、`pnpx` 一并不见。要移动就按段重建整个列表 | [`agent/skills/android-chroot-debian/`](agent/skills/android-chroot-debian/) |
| **热插拔移动硬盘在 chroot 隔离中失明** | 进入 Debian 容器后再插入移动硬盘，Android 正常识别但容器内 `/android/mnt/media_rw` 为空。`unshare -m` 与 `rprivate` 阻断了挂载传播，需通过 `nsenter -t 1 -m` 穿透宿主命名空间动态桥接挂载 | [`agent/skills/termux-debian-external-drive/`](agent/skills/termux-debian-external-drive/) |
| **NTFS 权限伪造阻断 SSH 密钥认证** | 移动硬盘上私钥执行 `chmod 600` 虽返回 0 但底层 FUSE 驱动固化为 `770`，触发 OpenSSH 门禁拒连；必须用 `tar` 归档保留 POSIX 权限并在本地 Linux 文件系统解压 | [`agent/skills/termux-debian-external-drive/`](agent/skills/termux-debian-external-drive/) |
| **Android Bionic Linker 命名空间断裂与 Magisk 桩覆写** | 在 Debian chroot 内直接调用宿主 `/system/bin/settings` 报 `cannot execute` 或动态链接器崩溃（`file offset for libutils.so >= file size: 0 >= 0`）。Magisk tmpfs 覆写了动态库且链接器缺少运行时拓扑，必须使用单维度 `nsenter -t 1 -m` 穿透宿主 Mount Namespace 执行 | [`agent/skills/android-miui-settings/`](agent/skills/android-miui-settings/) |
| **MIUI 专有高刷投票覆盖 AOSP 设置** | 单纯修改 `system` 表的 `peak_refresh_rate` 无法锁定 120Hz，系统打字或静止时频繁掉帧。MIUI 框架在 `DisplayModeDirector` 插入了 `PRIORITY_MIUI_REFRESH_RATE` 专属投票，需联动设置 `secure miui_refresh_rate 120` 与 `system is_smart_fps 0` | [`agent/skills/android-miui-settings/`](agent/skills/android-miui-settings/) |
| **桌面会话下 `chsh` 换 Shell 不即时生效** | 修改登录 Shell 后重启终端仍进入 Bash；`gnome-terminal-server` 后台长驻缓存登录 PAM 变量 | [`linux-desktop/`](linux-desktop/) 第 2.1 节 |
| **代理明明在监听却 `Connection refused`（Windows 上的 `bx`）** | 与下一行同为 `socks5h` 根因，但 Windows 上该变量写在用户环境变量里，且系统还缺 `jq`，两个无关的报错看起来像同一个网络故障。`curl --noproxy` 返回 `000`、走代理返回 `301` 即可区分；给 `bx-bin.exe` 套 `bx.cmd` / `bx` wrapper 修复 | [`agent/brave-search/bx-cli.md`](agent/brave-search/bx-cli.md) 第 3 节 |
| **Clash 桌面系统代理对 CLI 穿透失效** | 桌面浏览器能翻墙但终端直连超时；`bx` 遇 `socks5h` 报 exit 5 | [`linux-desktop/`](linux-desktop/) 第 2.2 节 |
| **Linux Mint 22 换源脱靶与更新超时** | 误改 ubuntu.sources 丢 Mint 桌面仓库；官方海外源 300 kB/s 掐断更新器。双轨切清华 TUNA 源提速 16 倍 | [`linux-desktop/`](linux-desktop/) 第 2.3 节 |
| **安装脚本污染 Shell 四层分层** | `pnpm setup` 与 nvm 自动追加 rc 文件破坏单一真相来源 | [`linux-desktop/`](linux-desktop/) 第 2.4 节 |
| **终端粘贴快捷键提示无剪贴板工具** | CLI 按 Ctrl+V/Alt+V 报 `no supported clipboard tool`（agy），或在 Claude Code 里静默失败——只弹一句 `No image found in clipboard.`，那句 `Image in clipboard` 提示永不出现；原生桌面缺 `xclip`/`wl-clipboard`。Claude Code 每次按键现取工具，装完无需重启（Go 系 CLI 则在 init 期缓存 `LookPath`） | [`linux-desktop/`](linux-desktop/) 第 2.5 节 |
| **GNOME Terminal 静默丢弃 OSC 52 剪贴板** | `/copy` 提示复制成功但系统剪贴板为空；VTE 长期缺 OSC 52 写入，推荐 Ghostty | [`linux-desktop/`](linux-desktop/) 第 2.6 节 |
| **历史命令迁移引发 Zsh corrupt history** | 拼接多设备历史后 Zsh 启动崩溃；包含 `\x00` 空字节破坏解析，需清洗归一化 | [`linux-desktop/`](linux-desktop/) 第 2.7 节 |
| **`sudo` 清洗代理导致 APT 海外源超时** | 普通终端能翻墙但 `sudo apt` 连 Typora 超时；`env_reset` 剥离变量，需设 `sudoers` 白名单 | [`linux-desktop/`](linux-desktop/) 第 2.8 节 |
| **Fcitx 5 默认 profile 缺失拼音** | 新装 Fcitx 5 重启后按快捷键无反应；默认模版仅含 `keyboard-us`，需补 `pinyin` | [`linux-desktop/`](linux-desktop/) 第 2.9 节 |
| **Ghostty 默认 Ctrl+Enter 劫持全屏** | CLI/编辑器多行换行误触全屏；需 `keybind = ctrl+enter=unbind` 改绑 F11 | [`linux-desktop/`](linux-desktop/) 第 2.10 节 |
| **Nemo 文件管理器缺失 Ghostty 右键菜单** | 无法直接在文件夹中拉起 Ghostty；需配置 Nemo Action 并区分目录选中与背景空白 | [`linux-desktop/`](linux-desktop/) 第 2.11 节 |
| **AI Agent 执行 `sudo` 永久阻塞等待密码** | 非交互子进程没有 TTY 接收密码提示，命令无限挂起。在 `/etc/sudoers.d/nopasswd-<user>` 一次性授予 `NOPASSWD: ALL`，只需手工输入一次密码 | [`linux-desktop/`](linux-desktop/) 第 2.12 节 |
| **pnpm 12 全局安装弹出交互式 build 审批，且 Node 缺失致 postinstall 失败** | `pnpm add -g` 弹出复选框交互界面，AI Agent 无法应答；即使加了 `--allow-build`，若 nvm 未初始化仍报 `node: not found`（exit 127）。先用 nvm 装好 Node，再逐包传 `--allow-build=<具体包名>`；可选的全局直通见第 2.16 节 | [`linux-desktop/`](linux-desktop/) 第 2.13 节 |
| **Fcitx 5 桌面会话环境变量断层（`run_im none`）** | 终端输入正常但 WPS/微信/桌面 GUI 无法呼出输入法；`~/.xinputrc` 设为 `none` 抑制会话导出。执行 `im-config -n fcitx5` 并在 `/etc/environment` 与 `~/.xprofile` 固化 | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) 坑 1 |
| **WPS Linux 丢输入法（QPlatformInputContext 回退）** | WPS Office 无法输入中文；缺失 `QT_IM_MODULE=fcitx` 致定制 Qt 回退 `compose` 插件且进程生命周期不可逆。在 `/usr/bin/wps` 等入口注入变量并重启 | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) 坑 2 |
| **Fcitx 5 AltTriggerKeys 劫持左 Shift 字母直接上屏** | 按左 Shift 强制上屏汉字首选词而非字母；Fcitx 5 `AltTriggerKeys` 抢先拦截导致 Rime `commit_code` 无法执行。清空 `~/.config/fcitx5/config` 的 `AltTriggerKeys` | [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) 坑 4 |
| **Fontconfig 缺字回退跌入繁体/旧字形与衬线体失配** | 优先级 65 的 Droid Sans Fallback 抢跑 Noto CJK（优先级 70）引入台版旧字形；归一化 zh-Hans 并顶置 Noto Sans/Serif SC | [`linux-desktop/`](linux-desktop/) 第 2.14 节 |
| **Fcitx 5 Rime 横向候选栏劫持左右键阻断拼音编辑** | 横向单行候选条下 selector 抢先拦截左右方向键致无法在拼音串中移动光标；覆盖解绑 selector 恢复原地修改 | [`linux-desktop/`](linux-desktop/) 第 2.15 节 · [`linux-desktop/gui-and-ime.md`](linux-desktop/gui-and-ime.md) 坑 8 |
| **pnpm 12 默认阻断构建脚本与 24 小时发布冷却门禁** | `pnpm add -g` 弹出 `approve-builds` 交互选择并拦截 24 小时内新包（`minimumReleaseAge`）。**可选**，仅适用于只跑个人 Vibe Coding 的机器：配置 `dangerouslyAllowAllBuilds: true` 与 `minimumReleaseAge: 0` 直通放行；不采用则改用 `pnpm add -g --allow-build=<具体包名>` 逐包放行 | [`linux-desktop/`](linux-desktop/) 第 2.16 节 |
| **荣耀平板：代理变量指向死端口** | pnpm 报 `tunnel error ... connection refused (os error 111)`、npm 一直转圈，但浏览器和 `apt` 都正常——`~/.shell_common` 把代理导出到了一个没人监听的本地端口，而浏览器用自己的设置、无视这些变量。先探测端口：refused 就清变量，open 就别动 | [`honor-linuxlab/`](honor-linuxlab/) 第 2.1 节 |
| **荣耀平板：fcitx5 不出候选词** | `Ctrl+空格` 能切换但无候选词。两条根因叠加：`~/.config/fcitx5/profile` 的活动组首项是 `keyboard-us` 而不是 `pinyin`；缺 `~/.config/fcitx5/config` 则只剩出厂的 `Ctrl+空格`，而这个键在实体外接键盘上被 MagicOS 拦成系统语言切换。**与 locale 无关**——locale 改动发生在故障报出 20 分钟之后，只因紧接着被问起才看起来像因果 | [`honor-linuxlab/`](honor-linuxlab/) 第 2.2 节 |
| **荣耀平板：某些组合键根本进不到容器** | 输入要穿过 Android 宿主、X server、应用三层，宿主对部分组合键有独占定义。`Ctrl+Shift+V` 在实体键盘上是死的（连 Qt 快捷键编辑器都收不到事件），而 `Ctrl+Shift+C` 等其它字母正常。`xdotool key` 可以用来区分是第 1 层还是第 2、3 层。解法是换到空闲字母，**容器内改任何配置都碰不到第 1 层** | [`honor-linuxlab/`](honor-linuxlab/) 第 2.3 节 |
| **Node 大版本升级作废全部原生模块** | Node 22 一变 24，`better_sqlite3.node was compiled against NODE_MODULE_VERSION 127 ... requires 137` 当场炸；报错却归咎于 npm 构建脚本，提示传 `--allow-scripts`——而包其实是 pnpm 装的、脚本当初成功跑过，照做全无用处。每次升 Node 大版本后，必须把所有带原生依赖的全局包重装一遍 | [`linux-desktop/`](linux-desktop/) 第 2.17 节 |
| **Ghostty 静默忽略未知配置键** | `shell = /usr/bin/zsh` 不报错、也毫无效果——该键名是 `command`，而 Ghostty 1.3.1 对不认识的键一声不吭。`+show-config` 同样分辨不出；只有 `+validate-config` 会带行号报出 `unknown field` | [`linux-desktop/`](linux-desktop/) 第 2.18 节 · [`linux-desktop/files/ghostty/config`](linux-desktop/files/ghostty/config) |
| **Clash Verge Rev 把自己的失败当成功上报** | 连接面板永远空白、托盘菜单失效，全程没有任何报错：WebSocket 连接失败被吞成每秒重连，托盘找不到时直接 `Ok(())`。静默失败是上游写进政策的，不是个案——85 个百行级 Rust 文件里 48 个零测试，Linux 只被编译和发布，从不做功能测试 | [`linux-desktop/`](linux-desktop/) 第 2.19 节 |
| **更新器的「镜像不可达」横幅是误报** | 界面指控镜像连不上，同一时刻 apt 正在从该镜像满速下载：探测是一次零重试的 HEAD，且只在「官方源成功、镜像失败」时才弹——横幅指向的方向和真实故障正好相反 | [`linux-desktop/`](linux-desktop/) 第 2.20 节 |
| **更新管理器卡死时后台 `aptk` 仍占着 dpkg 锁** | 更新窗口都关了，`apt-get install` 仍报 "Could not get lock /var/lib/dpkg/lock-frontend ... held by process (aptk)"——持锁的是后台 daemon 而非窗口本身。可用 `apt-get download` + `dpkg-deb -x` 解包进 `/usr/local/bin` 绕行，锁释放后再 `dpkg -i` 正式登记 | [`linux-desktop/`](linux-desktop/) 第 2.21 节 |
| **桌面会话脚本写死 `SHELL`，`/etc/passwd` 永远到不了终端** | `usermod -s <shell>` 执行成功、`/etc/passwd` 里也确认改了，可终端开出来还是旧 shell——LinuxLab 的 `start-desktop.sh` 在 LXQt 起来之前直接 `export SHELL=/bin/bash`，整棵会话树都继承了它。**重启桌面也救不回来** | [`honor-linuxlab/`](honor-linuxlab/) 第 2.4 节 |
| **Linux Lab 里 `chsh` 必然失败** | `Password: chsh: PAM: System error`，且 `/etc/passwd` 毫无变化：容器不跑 PAM，`chsh` 每次都卡在认证阶段。改用 `sudo usermod -s`；注意它只修 `/etc/passwd`，会话那一层还得单独处理 | [`honor-linuxlab/`](honor-linuxlab/) 第 2.5 节 |
| **没有 `add-apt-repository`，且所有 keyserver 都不可达** | 那个二进制是个拦截壳，真实目标并不存在；而 `keyserver.ubuntu.com`、`launchpad.net`、`keys.openpgp.org` 一律返回 `000`，只有 `ppa.launchpadcontent.net` 返回 `200`。唯一出路是 `[trusted=yes]`，这是**主动的安全降级**，必须当降级记录下来 | [`honor-linuxlab/`](honor-linuxlab/) 第 2.6 节 |
| **`[pip] index-url` 管不到 uv 自己的解析器** | `uv pip install` 走镜像，`uv add` / `uv sync` / `uv run --with` 却仍打 pypi.org：它们读的是 `[[index]]`，是另一张表。两个都配，再用 `uv -v` 确认实际连的是哪个域名 | [`tools/python/`](tools/python/) 第 5 节 |
| **仓库自带的两道门禁缺输入时会静默降级** | 缺 `tools/.sync-map` → `sync-skills.sh` 直接 exit 2，skill 核对与部署能力整体失效；缺 `tools/.privacy-names` → `privacy-gate.sh` 打印 `the literal-name check was skipped` 后**照样 exit 0**。两者第一眼都不像故障 | [`tools/README.md`](tools/README.md) |
| **`bash -lc` 与 `bash -ic` 解析出的 PATH 不是一回事** | Debian 的 `~/.bashrc` 对非交互 shell 提前 return，于是「登录但非交互」的 shell 根本不读 `~/.shell_common`：nvm 缺失，`node` 回落到 `/usr/bin/node`（交互 shell 报 v24 时它还是 v22）。用一种形式验证、在另一种形式里使用，就会得出「改动没生效」的错误结论 | [`shell/`](shell/) |
| **`Add-AppxPackage` 说的是「缺框架」而不是「包坏了」** | 装 winget v1.29.380 报 `0x80073CF3 ... depends on a framework that could not be found`，而机器上明明已经列出了 `WindowsAppRuntime` —— 那是 `.CBS` 变体，包名不同，部署校验不认 | [`windows/terminal/winget-and-terminal-without-store.md`](windows/terminal/winget-and-terminal-without-store.md) 第 2.2 节 |
| **双系统开机差 8 小时，几分钟后又自己好了** | 时钟只在网络起来之前是错的，于是看起来像同步问题：RTC 里存的是本地时间，Windows 却被告知它存的是 UTC（`RealTimeIsUniversal=1`），每次开机都被 NTP 悄悄修好。屏幕在骗人，硬件没有 | [`os-install/dual-boot-time-sync.md`](os-install/dual-boot-time-sync.md) 第 2 节 |

---

## 许可证

版权所有 © 2026 Leo `<28289630+Leonis03@users.noreply.github.com>`

**代码与配置走 [MIT](LICENSE)，文档走 [CC BY 4.0](LICENSE-DOCS)。** 两者都允许商用、允许再分发、都要求注明来源。

| 范围 | 许可证 | 覆盖什么 |
| :--- | :--- | :--- |
| 代码与配置 | [MIT](LICENSE) | 所有**非** `.md` 的文件——`tools/` 与 `agent/skills/*/scripts/` 下的 `.sh` / `.py`、`windows/files/` 下的 `.ps1` 与 `.reg`、`shell/files/`、`wsl/setup/files/`、`linux-desktop/files/` 下的配置原件、`.gitignore` |
| 文档 | [CC BY 4.0](LICENSE-DOCS) | 所有 `.md` 文件——两个 README、各目录的说明、skill 正文、踩坑记录与取证分析 |

拆开是因为 **Creative Commons 自己不建议把 CC 用于软件**，FSF 亦然（CC BY 4.0 虽是自由许可证、也兼容 GPL，但「should not be used on software」），而 OSI 从未批准过任何 CC 许可证。CC BY 4.0 §2(b)(2) 明示**不授予专利权**，§6(a) 规定违约**自动终止**（§6(b) 给 30 天补救），§2(a)(5)(B) 还禁止施加技术保护措施——这些条款对散文无害，对会被反复复制的脚本是真麻烦。

### 第三方内容

下列部分**不属于**上面两个许可证，版权归各自作者：

- `windows/files/reference/SamplePSReadLineProfile_GitHub.ps1` —— [PowerShell/PSReadLine](https://github.com/PowerShell/PSReadLine) 官方示例的逐字副本，729 行，Copyright (c) 2013 Jason Shirk，**BSD-2-Clause**。完整声明已写在该文件头部。
- `agent/skills/find-skills/` —— 取自 [vercel-labs/skills](https://github.com/vercel-labs/skills) 的 `skills/find-skills/`，**MIT**。单独发布的 skill 仓库不收录它。
- `agent/skills/skill-creator/` —— 取自 [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) 的 `plugins/skill-creator/skills/skill-creator/`，Copyright Anthropic，**Apache-2.0**（许可证全文随目录附在 `LICENSE.txt`）。原样拷贝、未修改；单独发布的 skill 仓库不收录它。
- `shell/files/bashrc` 保留了 Debian 出厂 `.bashrc` 的若干片段（`shopt -s checkwinsize`、`lesspipe`、`dircolors`、`alias ll=` 等）。
- `shell/files/` 下几个文件含安装器生成的块：oh-my-zsh 相关行、Antigravity CLI 的 PATH 块。

这些都是被广泛复制的模板片段，此处如实标注，不主张对它们的版权。
