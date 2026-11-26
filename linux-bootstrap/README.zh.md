# linux-bootstrap -- 新机器的开机部署

*中文 · [English](README.md) · 返回 [仓库 README](../README.zh.md)*

## 这个目录是什么

给刚装好的机器用的部署脚本：换源、基础包集、node 与 python 工具链、git 身份、
带 oh-my-zsh 和两个推荐插件的 zsh，以及 [`../shell/`](../shell/) 的四层 shell 配置。

它的来源是六台机器真实的 shell 历史。出处、逐台清单，以及**刻意没有采纳的部分**，见
[history-inventory.md](history-inventory.md)。

历史回答了「装什么」，仓库自己的笔记回答了「按什么顺序装」和「中途会踩什么」。两者单独
都不够，凑一起才是模板。

## 文件

| 文件 | 部署到 | 作用 |
| :--- | :--- | :--- |
| [`files/bootstrap-linux.sh`](files/bootstrap-linux.sh) | 执行它 | 部署本身，**会修改机器** |
| [`files/check-bootstrap.sh`](files/check-bootstrap.sh) | 执行它 | 只读探针，报告结果 |

[`../os-install/files/`](../os-install/files/) 的约定是「脚本只读不改」。**这个目录是故意
破例的**：部署脚本不改机器就不叫部署。只读的那一半单独放在 `check-bootstrap.sh`，这样
「脚本跑过了」和「机器处于预期状态」仍然是两个独立的问题。

## 三层结构

shell 历史是「发生了什么」的记录，不是「应该怎么做」的方案。挖历史会挖出三类材料，只有前
两类该进模板：

| 层 | 长什么样 | 怎么处理 |
| :--- | :--- | :--- |
| **通用核心** | 同一个包或工具在五台不同机器上都装过 | 变成一个阶段 |
| **机器特定** | 某一台的镜像源、输入方法、代理端口 | 变成占位符或运行时探测 |
| **一次性** | 租用的 GPU 主机、模型下载、下载器登录 | 丢弃 |

清单里带计数，所以这个拆分是可审计的，不是凭感觉。

## 阶段

| 阶段 | 做什么 | 说明 |
| :--- | :--- | :--- |
| 0 预检 | 读 `/etc/os-release`，找包管理器、WSL、Wayland、桌面 | 不改任何东西 |
| 1 换源 | apt/dnf 源 -> 国内镜像 | **会验证，镜像不工作就还原原源** |
| 2 软件包 | 基础包集 | apt 名和 dnf 名不一样，两套都列了 |
| 3 node | nvm、node LTS、corepack、pnpm | 用 corepack，不再装第二个 pnpm |
| 4 python | uv，钉在 3.12 | Fedora 的 uv 不被告知就拒绝下载 Python |
| 5 git | 身份，**仅当尚未设置时** | 绝不覆盖已有身份；在 `--yes` 下或没有终端时跳过并给出警告 |
| 6 zsh | zsh、oh-my-zsh、两个插件、`chsh` | 带 `--keep-zshrc`，手写的 `.zshrc` 不会被覆盖 |
| 7 shell | `../shell/files` 的四层配置 | 也会替换 `~/.bashrc`（先备份）；同时更新桌面会话的 `SHELL` 快照 |
| 8 桌面 | fcitx5、Ghostty、Nemo 动作 | 只在有桌面的机器上执行；在 Plasma Wayland 上会提醒你把虚拟键盘选成 Fcitx 5 |

每个阶段都是幂等的：该做的已经做了，就报 `SKIP` 并以 0 退出。

2026-11-22 在 Debian 13（trixie）容器里验证过，分别以 root 和带免密 `sudo` 的普通用户各跑两遍：
阶段 0-4、6、7 正常，阶段 5 跳过（身份事先设好），阶段 8 跳过（没有桌面），第二遍跳过了第一遍
做过的事。当时 `check-bootstrap.sh` 报了三个假失败和一个假跳过，现已修复（见下面坑表最后两行）。

## 顺序有讲究，而历史里的顺序不是那个顺序

历史呈现的是工作**实际发生的**顺序，不是它**应该发生**的顺序。模板里固化了两个例子：

- **换源在最前面。** 每台机器都是先换源再装东西，而装东西是每个会话里最慢的一段。
- **shell 配置在 shell 存在之后。** 历史里的顺序是装 zsh → 装 oh-my-zsh → 克隆插件 → 最后
  才写一份列出插件的 `.zshrc`；先写 `.zshrc` 再克隆插件，会得到一个起不来的 shell。

## 这些坑是来源教出来的

模板里的每一条都因为有真实机器踩过：

| 坑 | 模板的做法 |
| :--- | :--- |
| `dnf list --available ghostty` 查不到，很容易读成「根本没有这个包」 | 从 COPR 装，官方安装页给 Fedora 指的就是这条路 |
| 上游只发 macOS 二进制 | 只能走发行版路线，脚本按发行版选路线 |
| apt 源布局变了：`sources.list` 与 deb822 的 `.sources` 并存 | 有哪些改哪些，只换主机名、保留路径 |
| TUNA 的 Fedora 树是 `releases/` 与 `updates/` 目录，**不发布 metalink** | 最直觉的 metalink 替换会 404；dnf 阶段改为写明确的 baseurl |
| Fedora 的 uv RPM 设了 `python-downloads = "manual"` | 用 `uv python install` 装一次解释器 |
| pnpm 10+ 默认跳过依赖构建脚本，pnpm 12 还会弹**交互式** approve-builds 提示，agent 无法回答 | 答案在仓库的 `linux-desktop/files/pnpm/config.yaml`，见那里的 2.16 |
| 在 Plasma Wayland 上，Fcitx 5 成为 KWin 的输入法之前，浏览器什么也打不出来；设不设 `GTK_IM_MODULE` / `QT_IM_MODULE` 都改变不了这一点 | 共用文件继续导出它们（X11 需要，Wayland 无所谓）；阶段 8 会打印虚拟键盘的提醒 —— 见 `../linux-desktop/wayland-fcitx5-rime.zh.md` 的根因四 |
| shell 会从父进程和桌面会话继承代理变量；探测时没有端口应答，旧值以前会原样保留 | 共用文件在探测前先清掉这六个代理变量 |
| README 让普通用户带 `sudo` 运行脚本，但最初的测试容器都是以 root 运行的 | TUNA 的 repo 文件改为经 `$RUN_AS tee` 写入；非 root 路径已在容器里用一个免密 sudo 用户测过 |
| `run_sh` 是一个全新的 `bash -c`，脚本自己 shell 里加载的 `nvm` 函数在那里不存在 | 每次 `run_sh` 调用内部都先加载 nvm，之后在父 shell 里重新加载；安装器失败时该阶段以明确的错误停止 |
| 桌面会话自带一份 `SHELL` 快照，从面板启动的终端在 rc 文件运行**之前**就继承它 | systemd 用户环境与 D-Bus 激活环境一起更新 |
| `ghostty +validate-config --config-file <path>`（空格分隔）对任何文件都退出 1 且不说话 | 脚本用 `--config-file=<path>` 粘连写法 |
| Ghostty 1.3.x 同时读 `config` 与 `config.ghostty`，且 GUI 首次运行会造一个空的 `config.ghostty` | 配置写到两个文件名，内容一致 |
| 检查脚本对 `/etc/apt/sources.list.d/` 用 `grep` 却没加 `-r`，Debian 13 的 deb822 `debian.sources` 永远匹配不上，能用的镜像被报成"厂商默认源" | `check-bootstrap.sh` 改为递归搜索这个目录 |
| 检查脚本在自己那个非交互 shell 里跑 `command -v node`，而它从不读 `~/.zshrc`，于是 bootstrap 刚成功，node、pnpm、uv 就被报成缺失 | `check-bootstrap.sh` 先从交互式 zsh 取 `PATH` |

## 怎么用

```bash
# 1. 先看计划，不改任何东西
bash files/bootstrap-linux.sh --dry-run

# 2. 跑（需要你拍板的步骤会问）
bash files/bootstrap-linux.sh

# 3. 只跑一部分
bash files/bootstrap-linux.sh --stage 2,3 --yes

# 4. 从仓库部署 shell 配置
bash files/bootstrap-linux.sh --stage 7 --shell-files ../shell/files

# 5. 从外部检查结果
bash files/check-bootstrap.sh
```

`--dry-run` 打印每一条命令，不动任何东西。脚本要改的文件会先备份到
`~/.bootstrap-backups/<时间戳>/`。

## 相关文档

- [history-inventory.md](history-inventory.md) —— 每一步的出处
- [`../shell/`](../shell/) —— 这里部署的四层配置
- [`../linux-desktop/`](../linux-desktop/) —— 桌面侧：字体、fcitx5、Ghostty、Nemo 动作
- [`../wsl/setup/`](../wsl/setup/) —— WSL 专属的复刻流程，与本目录互补
