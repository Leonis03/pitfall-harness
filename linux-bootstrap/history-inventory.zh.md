# 历史清单 —— 部署脚本背后的 shell 历史

*中文 · [English](history-inventory.md) · 返回 [linux-bootstrap/](README.zh.md)*

## 这个文件为什么存在

[`files/bootstrap-linux.sh`](files/bootstrap-linux.sh) 不是凭空写出来的，它是从移动硬盘上
若干台机器的 shell 历史里挖出来的。本文件记录那些历史里到底有什么，好让后来的 agent
可以核对这份挖掘、提出异议、或者扩充它，而不必重新读一遍 200 KB 的历史。

各文件在硬盘上的位置这里不记录：硬盘上的目录名就是设备名。下文只需要知道：某些路径下有
`.bash_history`、`.zsh_history` 或 `.zsh_history.bak.<时间戳>`。

## 硬盘上有什么

**16 份历史文件、7,186 条命令、202 KB**，来自 8 个机器档案。zsh 历史带时间戳，bash 历史
不带——这是 bash 文件最先暴露的能力上限。

| 文件名 | 份数 | 命令数 | 字节 |
| :--- | ---: | ---: | ---: |
| `.bash_history` | 9 | 5,604 | 139,518 |
| `.zsh_history` | 6 | 1,536 | 65,398 |
| `.zsh_history.bak.<时间戳>` | 1 | 46 | 1,885 |

zsh 时间戳的跨度是 2026-05-29 .. 2026-10-19。

并非每个档案都是独立机器，把副本计入会把本文件里所有数字都放大：

- 有一对是**另一个档案家目录的副本**，躺在某个 git 仓库里（1,700 条 bash、255 条 zsh，
  和原件一样，只少几条）。那是那台机器的备份，不是另一台机器。
- 另有两份是同一个家目录的带日期快照。

所以真实的机器档案是 **6 台**，不是 8 台。

## 第一层：通用核心

出现在不止一台机器上的命令。这些变成了部署脚本的各个阶段。

| 内容 | 出现在哪 | 变成了 |
| :--- | :--- | :--- |
| `apt update` / `apt install` | Ubuntu（3 台）、WSL（2 台）、Fedora（0 台，它用 dnf） | 阶段 2，两套包名词表 |
| 基础编译集：`build-essential`、`gcc`、`curl`、`git`、`unzip`、`zstd` | 每台 apt 机器 | 阶段 2 |
| 媒体/开发库：`ffmpeg`、`libicu-dev`、`libcurl4-openssl-dev`、`zlib1g-dev`、`libkrb5-dev` | Ubuntu，WSL 上是同一份清单 | 阶段 2 |
| JDK（`default-jdk`）、`python3-pip` | Ubuntu、WSL | 阶段 2 |
| 剪贴板三件套：`xclip`、`xsel`、`wl-clipboard` | Ubuntu | 阶段 2 |
| 密钥环三件套：`gnome-keyring`、`libsecret-1-0`、`dbus-x11` | Ubuntu（连同 WSL 专用的 `wslu`） | 阶段 2 |
| `nvm` + `nvm install` + `corepack enable` + `pnpm` | 每台装了 node 的机器 | 阶段 3 |
| `uv` 安装脚本、`uv python install` | Fedora、Ubuntu、WSL | 阶段 4 |
| `git config --global user.name` / `user.email` | Ubuntu、WSL | 阶段 5 |
| `zsh` + oh-my-zsh 安装脚本 + 两个插件 | 每台机器 | 阶段 6 |
| `chsh` 切到 zsh | WSL、Fedora | 阶段 6 |
| `fcitx5` + `im-config -n fcitx5` | Ubuntu | 阶段 8 |
| `dnf copr enable scottames/ghostty` + `dnf install ghostty` | Fedora | 阶段 8 |

去重后的安装命令词汇表：**apt 25 条、apt-get 3 条、pnpm 4 条、uv 2 条、pip 2 条、npm 1 条**。
这就是可复用的全部表面面积。7,186 条命令里的其余部分，要么机器特定，要么一次性。

## 第二层：机器特定

真实存在，但绑在某一台机器上。在模板里它们变成占位符或运行时探测，绝不是写死的值：

- **代理。** 一台机器把代理脚本写进 `/etc/profile.d/`，另一台用协议握手探测候选端口，只
  导出真正应答的那些。后者就是仓库 `shell/files/shell_common` 的做法，也是模板依赖的做法
  ——模板里没有任何端口号。
- **apt 镜像。** 一台把 `deb.debian.org` 改成国内镜像，另一台改 `archive.ubuntu.com`。两者
  是同一个操作，区别只在源文件布局不同。
- **输入方法。** Ubuntu 上是 `im-config -n fcitx5`；Fedora 上什么都没有，那个包自带
  `/etc/profile.d/fcitx5.sh`。
- **第三方应用仓库。** 有一台手工装了 Typora 的 apt key。已丢弃：那是一个应用，不是环境。

## 第三层：一次性，已丢弃

历史里有一些东西**绝对不该**变成模板：

- 租用的 GPU 主机：带每次不同端口的 `ssh`、`ssh-copy-id`、`rsync` 模型目录、
  `proxychains4`。
- 应用登录与下载：某个下载器的登录、启动一个编辑器、带会话 id 的 `--conversation` 续跑。
- 一个 Java 项目构建、一个 Python 环境激活、一个 `conda` 环境。
- 单条调试命令：`file`、`dpkg -S`、`apt-cache depends`。

这些都不是环境配置，是干活。

## 历史告诉不了我们的三件事

这三条限制塑造了模板的形状，值得记下来：

1. **历史里的顺序是事情发生的顺序，不是应该发生的顺序。** 有两台机器在换源之前就装了包，
   两台都慢。所以模板故意把换源放在最前。
2. **bash 历史没有时间戳。** 8 个档案里有 4 个只有 bash，那些文件的顺序完全无从得知，只剩
   命令集合。是带 `: <epoch>:<elapsed>;` 前缀的 zsh 历史，才让「顺序」这个问题有解。
3. **历史只记录成功的命令，不记录失败的。** 一条失败后重试过的命令会出现一次或两次，且毫
   无标记。所以 [`README.md`](README.zh.md) 里的那些坑来自仓库自己的笔记，而不是来自历史。

## 脱敏

原始文件里有账户名、邮箱、主机名、端口和路径，这里一概不收录；文件在硬盘上的位置也不收录，
因为目录名能认出是哪台设备——见 [`../redaction.zh.md`](../redaction.zh.md)。
