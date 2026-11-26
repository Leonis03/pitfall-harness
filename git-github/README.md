# GitHub 隐私保护与 GitHub CLI (gh) 配置与运维指南

本指南整合了 GitHub 邮箱隐私保护、WSL 环境下的浏览器唤起、GitHub CLI (`gh`) 登录与凭证管理、Git 代理网络调优、历史提交真实邮箱清洗脱敏以及仓库私有化管理的全套可复现方案。

---

## 目录

1. [本地 Git 隐私提交身份配置](#一本地-git-隐私提交身份配置)
2. [WSL 环境浏览器联动配置 (用于 CLI 登录)](#二wsl-环境浏览器联动配置-用于-cli-登录)
3. [GitHub CLI (gh) 登录与 Git 凭证助手集成](#三github-cli-gh-登录与-git-凭证助手集成)
4. [代理环境下的 Git 网络传输调优](#四代理环境下的-git-网络传输调优)
5. [清洗历史 Commit 中的真实邮箱 (git-filter-repo)](#五清洗历史-commit-中的真实邮箱-git-filter-repo)
6. [个人仓库批量转为 Private 及验证](#六个人仓库批量转为-private-及验证)
7. [日常检查与验证命令速查](#七日常检查与验证命令速查)
8. [文件大小限制](#八文件大小限制)

---

## 一、本地 Git 隐私提交身份配置

### 1. 原理
GitHub 提供了 **"Keep my email addresses private"**（保持邮箱地址私有）功能。开启后：
* GitHub 在 Web 端操作（如网页创建、合并、编辑）时会自动使用形如 `ID+Username@users.noreply.github.com` 的匿名邮箱。
* 在本地命令行执行 `git commit` 时，必须显式将 `user.email` 设置为该匿名地址，否则真实的个人邮箱会被永久固化在 commit 元数据中。
* 提交者的名字（`user.name`）主要用于显示，不影响 GitHub 账号的关联统计，可使用网名或昵称。

### 2. 可复现配置命令

```bash
# 设置全局 Git 提交邮箱为 GitHub noreply 隐私邮箱
git config --global user.email "28289630+Leonis03@users.noreply.github.com"

# 设置全局 Git 提交用户名（可使用昵称）
git config --global user.name "Leo"

# 验证配置
git config --global user.email
git config --global user.name
```

---

## 二、WSL 环境浏览器联动配置 (用于 CLI 登录)

### 1. 背景问题
在 WSL 环境中，若 `/etc/wsl.conf` 配置了 `appendWindowsPath = false`（防止 Windows 环境变量污染 Linux PATH），Linux 终端无法直接通过 `cmd.exe` 或默认 `wslview` 唤起 Windows 浏览器完成网页授权登录（如 `gh auth login`）。

### 2. 解决方案与命令
创建 `/usr/local/bin/wslview` 独立脚本，使用 Windows 绝对路径调用 `rundll32.exe`，并将其配置为全局 `BROWSER`。

```bash
# 1. 创建独立唤起脚本
sudo tee /usr/local/bin/wslview <<'EOF' >/dev/null
#!/bin/sh
# 调用 Windows 默认浏览器打开 URL
if [ $# -eq 0 ]; then
    echo "Usage: wslview <url>" >&2
    exit 1
fi
cd /mnt/c/Windows/Temp 2>/dev/null || cd /mnt/c
exec /mnt/c/Windows/System32/rundll32.exe url.dll,FileProtocolHandler "$1"
EOF

# 2. 赋予可执行权限
sudo chmod +x /usr/local/bin/wslview

# 3. 设置默认浏览器环境变量（写入 ~/.bashrc 并立即生效）
grep -q 'BROWSER=wslview' ~/.bashrc 2>/dev/null || echo 'export BROWSER=wslview' >> ~/.bashrc
export BROWSER=wslview

# 4. 测试唤起 Windows 浏览器
wslview "https://github.com"
```

### 3. 故障排查与已知坑

#### (a) `wslview` 报 "WSL Interoperability is disabled" —— 多半是假错

新版 WSL 把 binfmt_misc 的互操作处理器从 `WSLInterop` 改名为 `WSLInterop-late`，而 wslu 仍硬编码检查旧名，于是在 `systemd=true` 的发行版上误报：

```
grep: /proc/sys/fs/binfmt_misc/WSLInterop: No such file or directory
WSL Interopability is disabled. Please enable it before using WSL.
```

> [!IMPORTANT]
> 这条报错极具误导性 —— 它会把人引去改 `/etc/wsl.conf` 里**本来就正确**的 `enabled=true`。真正该查的是 binfmt_misc 里的注册名。
> 在 Ubuntu 24.04 干净装 wslu 的场景下，`wslview` 可能每次执行都崩溃，并级联报出 `/mnt/c/Windows/System32/reg.exe: No such file or directory`。

诊断：

```bash
ls /proc/sys/fs/binfmt_misc/
# 含 WSLInterop        -> 不受影响
# 只有 WSLInterop-late -> 命中该 bug
```

持久化修复（systemd 原生，重启后仍生效）：

```bash
echo ':WSLInterop:M::MZ::/init:P' | sudo tee /etc/binfmt.d/99-WSLInterop.conf
sudo systemctl restart systemd-binfmt
```

直接写 `/proc/sys/fs/binfmt_misc/register` 也能修，但那是虚拟文件系统，WSL 重启即失效。

追踪：[microsoft/WSL#13449](https://github.com/microsoft/WSL/issues/13449)、[#13390](https://github.com/microsoft/WSL/issues/13390)、[Ubuntu wslu #2125223](https://bugs.launchpad.net/ubuntu/+source/wslu/+bug/2125223)。

> **台式机实测状态（2026-09-19，WSL2 / Ubuntu noble / systemd=true / wslu 3.2.3）**：注册名为旧名 `WSLInterop`，**不受影响**，`wslview`、`rundll32` 方案、`xdg-open` 三种方式均实测可唤起 Chrome。

#### (b) 用 alias 包装 Windows 命令对 `gh auth login` 无效

`alias open='explorer.exe'` 这类写法**只在你手敲命令时生效**。`gh` 内部起子 shell 调用浏览器时别名不传递，授权页面依然打不开。必须走 `BROWSER` 环境变量或 PATH 上的可执行脚本 —— 这正是本节采用 `/usr/local/bin/wslview` 脚本 + `BROWSER` 而非 alias 的原因。

#### (c) `appendWindowsPath=false` 下所有 .exe 都必须用绝对路径

Windows PATH 不再注入，`reg.exe`、`rundll32.exe`、`powershell.exe` 直接敲都会 `command not found`。只有由 Linux 包提供的包装器（如 wslu 的 `/usr/bin/wslview`）不受影响。

```bash
reg.exe query ...                          # ✗ command not found
/mnt/c/Windows/System32/reg.exe query ...  # ✓
```

#### (d) 从 Linux 路径直接执行 .exe 会触发 UNC 警告

```
CMD.EXE was started with the above path as the current directory.
UNC paths are not supported. Defaulting to Windows directory.
```

WSL 的 Linux 路径在 Windows 侧是 `\\wsl.localhost\...` UNC 路径。规避办法就是上文脚本里那句 `cd /mnt/c/Windows/Temp` —— 先切到 Windows 侧路径再 exec。

#### (e) `BROWSER` 应加存在性守卫

裸写 `export BROWSER=wslview`，在 wslu 未装或被卸载后会让 `BROWSER` 指向不存在的命令。建议：

```bash
if command -v wslview >/dev/null 2>&1; then
  export BROWSER=wslview
fi
```

---

## 三、GitHub CLI (gh) 登录与 Git 凭证助手集成

### 1. 版本来源：发行版仓 vs GitHub 官方源

`gh` 的版本号跟着**上游发布**走，但发行版仓里的包是**打包时就冻结**的，之后不再跟进。
Debian / Ubuntu 的 `gh` 尤其旧，而 Go 写的工具**安全修复常常也不 backport**。

2026-10-25 实测：

| 来源 | 命令 | 装出来的版本 | 对应上游发布日 | 落后最新（2.103.2） |
| :--- | :--- | :--- | :--- | :--- |
| Debian 13 (trixie) apt | `sudo apt install gh` | **2.46.0-3** | 2024-03-20 | **80 个版本 / 19 个月** |
| Ubuntu 24.04 (noble) apt | `sudo apt install gh` | **2.45.0-1ubuntu0.3** | 2024-03-04 | 81 个版本 |
| Fedora 44 dnf | `sudo dnf install -y gh` | **2.97.0-2.fc44** | 2026-07-31 | 9 个版本 |
| GitHub 官方 apt 源 | 见 2.1 | **2.103.2** | 2026-10-23 | 0 |

> **`gh --version` 里括号中的日期是打包日，不是上游发布日。**
> Debian 包打印 `(2025-01-13 Debian 2.46.0-3)`，而上游 v2.46.0 实际发布于 **2024-03-20**。
> 差一年多，只看这一行会以为它还挺新。

**结论：Fedora 用 dnf 自带的就够，不必换源；Debian / Ubuntu 才需要。** 理由见 2.2。

差距具体落在哪些功能上（引入版本取自上游 release notes）：

| 能力 | 引入版本 | apt 2.46.0 | dnf 2.97.0 | 官方源 2.103.2 |
| :--- | :--- | :--- | :--- | :--- |
| `gh attestation`（产物签名校验） | 2.49.0 | 无 | 有 | 有 |
| `gh agent-task`（给 Copilot coding agent 派任务） | 2.80.0 | 无 | 有 | 有 |
| `gh pr create --reviewer @copilot` | 2.87.0 | 无 | 有 | 有 |
| `gh skill`（装 agent skill 到 Claude Code / Codex 等） | 2.90.0 | 无 | 有 | 有 |
| 转义序列注入修复（`gh run view --log`） | 2.92.0 | **无** | 有 | 有 |
| 转义序列注入修复（`gh api` / `gh pr diff` / `gh gist view` 等） | 2.97.0 | **无** | 有 | 有 |
| `gh pr checkout --worktree` | 2.98.0 | 无 | **无** | 有 |
| `gh pr create --attach`（截图进 PR） | 2.99.0 | 无 | **无** | 有 |

两处转义序列修复对「**让 agent 读 PR / CI 输出**」的场景是实打实的风险：
外部仓库的 PR 内容会被 `gh pr diff`、`gh api` 原样打印出来，旧版本不中和其中的 ANSI 转义。

### 2. 安装

#### 2.1 Debian / Ubuntu（apt）：换到 GitHub 官方源

官方源是 GitHub 自己签名的 apt 仓，涉及三个文件，全部可回退。

```bash
# 1. 签名 key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

# 2. 源
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list

# 3. 装
sudo apt update
sudo apt install -y gh
```

装完确认候选来自官方源：

```bash
apt-cache policy gh
```

预期两张版本表：官方源 `2.103.2`（优先级 500）在上，发行版仓 `2.46.0-3`（优先级 100）在下。
**候选是官方源那个**——之后 `sudo apt upgrade` 会自动跟上，不必再记专门的更新命令。

**代理环境下这一步会卡住。** apt **不读** `http_proxy` / `https_proxy` 环境变量，
而 `cli.github.com` 直连不稳（2026-10-25 实测：4 次里 1 次连接重置或超时）。
解法是给 apt 单独配代理，并且**只写这一台主机**，别拖累走直连的镜像源：

```bash
echo 'Acquire::http::Proxy::cli.github.com "http://127.0.0.1:<proxy-port>";' \
  | sudo tee /etc/apt/apt.conf.d/99-github-cli-proxy
```

主机名写在配置项名里，就只对 `cli.github.com` 生效。
`<proxy-port>` 换成实际端口（`shell/files/shell_common` 探测的那个）。

#### 2.2 Fedora（dnf）：不用换源

```bash
sudo dnf install -y gh        # 2.97.0
sudo dnf upgrade gh           # 日常更新走这条
```

两条理由：

* dnf 源**跟随上游**（Fedora 44 的是 2026-07-31 的 2.97.0），落下的 9 个版本里
  只有 `gh pr checkout --worktree`（2.98.0）和 `gh pr create --attach`（2.99.0）两个功能；
* GitHub **只提供 apt 仓库**（`cli.github.com/packages` 只有 deb 布局，RPM 仓库路径 404）。
  每次发布虽然带一个 `.rpm` 文件，但那是静态文件，装上不会自动更新——为了两个功能不值得。

真要最新版的话，从 release 页面取 `.rpm` 手动装：

```bash
# https://github.com/cli/cli/releases/latest 上取 gh_<version>_linux_amd64.rpm
sudo dnf install -y ./gh_<version>_linux_amd64.rpm
```

#### 2.3 更新与回退

```bash
# 只升级 gh（不动别的包）
sudo apt update && sudo apt install -y --only-upgrade gh

# 只刷新官方源这一个源的索引，不动其他源
sudo apt-get update \
  -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/github-cli.list \
  -o Dir::Etc::sourceparts=/dev/null \
  -o APT::Get::List-Cleanup=0

# 回退到发行版仓的版本
sudo rm /etc/apt/sources.list.d/github-cli.list
sudo apt update
sudo apt install -y gh/<suite>    # suite 随发行版走：Debian 是 trixie，Ubuntu 是 noble
```

### 3. 登录

#### 3.1 浏览器 OAuth（默认）

使用 `gh` 进行命令行授权，免去手动生成与维护 GitHub Personal Access Token (PAT) 的繁琐步骤。

```bash
# 发起登录授权
gh auth login
```
**交互选项说明**：
* *What account do you want to log into?* → **`GitHub.com`**
* *What is your preferred protocol for Git operations on this host?* → **`HTTPS`**
* *Authenticate Git with your GitHub credentials?* → **`Yes`**
* *How would you like to authenticate GitHub CLI?* → **`Login with a web browser`**
* 按回车复制一次性验证码，浏览器自动打开，粘贴验证码完成授权。

这条路拿到的 OAuth token，scope 是**固定**的（实测 `gist` `read:org` `repo` `workflow`），
等价于一个 classic PAT 勾了这四项，覆盖你所有能访问的仓库。

#### 3.2 用 token 登录

```bash
gh auth login --with-token < <token-file>
```

`gh auth login --help` 的原话：最小 scope 是 `repo` + `read:org` + `gist`；
并提醒 **fine-grained PAT 走 `--with-token` 可能「行为令人困惑」**，那种场景改用环境变量
`GH_TOKEN`（或 `GITHUB_TOKEN`）更稳：

```bash
export GH_TOKEN="$(cat <token-file>)"
gh api user
```

两种 token 的区别：

| | classic PAT | fine-grained PAT |
| :--- | :--- | :--- |
| 前缀 | `ghp_` | `github_pat_` |
| 粒度 | scope 列表，账号级 | **按仓库选**，逐项选权限 |
| 有效期 | 可设成不过期 | **有强制过期时间**，到期静默失效 |
| 改权限 | 得重新生成 token | 界面上直接改，token 串不变 |

#### 3.3 fine-grained PAT 的权限怎么对应 gh 的命令

fine-grained 界面里那列勾选框**不是** gh 的 scope 列表，一一对应关系是：

| 界面里的权限 | 等级 | gh 用在哪 |
| :--- | :--- | :--- |
| Metadata | Read-only（灰，强制） | 前提，所有仓库操作都要 |
| Contents | Read and write | `git push`、`gh pr create` 读 diff、`gh api` 读写文件 |
| Pull requests | Read and write | `gh pr create / merge / checkout / diff` |
| Issues | Read and write | `gh issue` |
| Actions | Read and write | `gh run`、`gh workflow` |
| Workflows | Write-only | 推 `.github/workflows/*.yml`（对应 OAuth 的 `workflow` scope） |
| Administration | Read and write | `gh repo edit --visibility`、`gh repo delete`、改默认分支 |
| Repository creation | Read and write | `gh repo create` |

外加 organization 侧 **Members: Read-only**（对应 `read:org`）。

**`repo` scope 是 aggregate 的**：它把上面几乎每一项都覆盖了，所以 classic 那边勾一个 `repo`
就够了；fine-grained 这边必须**逐项勾**，漏一项就少一块能力。

#### 3.4 验证 token 到底能干什么

**别只看 `gh auth status`** —— 对 fine-grained PAT 它不打印 scope 列表（这种 token 没有 scope
概念），只显示 token 前缀。要验权限就直接打 API：

```bash
gh api repos/<owner>/<repo>/pulls                # Pull requests 权限
gh api repos/<owner>/<repo>/actions/workflows   # Actions 权限
gh api repos/<owner>/<repo>/actions/secrets     # Secrets 权限（是独立的一项）
```

403 的消息是固定的：`Resource not accessible by personal access token`。
**它说的是权限不够，不是 token 无效** —— 别去重登，重登一百遍也是这个结果。
`gh` 会把它原样打出来，例如 `failed to get secrets: HTTP 403: ...`。

**验写权限而不产生副作用**：用一个必然被参数校验拦下的请求。权限不够会先吃 403，
权限够了才会走到校验那一步：

```bash
gh api -X POST user/repos -f name="" -f private=true
# 权限够 -> 422 "New repository name must not be blank"（没建出仓）
# 权限缺 -> 403 "Resource not accessible by personal access token"
```

2026-10-25 实测踩到的两件事：

* 这个 token 一开始漏了 **Actions**，`gh api repos/.../actions/workflows` 报 403，
  而 `gh run list` 因为这个仓没有 workflow 而什么也不打印——**看着像「这仓没 CI」，
  其实是权限不足**；
* **Secrets 是另一项独立权限**。Actions 给足了 `gh run` 能用，`gh secret` 照样 403。

#### 3.5 换 token 后不用重跑 setup-git

credential helper 指向的是 `gh auth git-credential`（不是 token 本身）：

```bash
git config --global --get credential.https://github.com.helper
# 预期输出: !/usr/bin/gh auth git-credential
```

所以换 token 后 helper 配置不用动，`git push` 会自动用当前登录的那个 token。

### 4. 配置 Git Credential Helper
让本地 `git clone` / `git push` 自动借用 `gh` 的 OAuth 令牌进行免密认证：

```bash
gh auth setup-git

# 验证 helper 配置是否成功
git config --global --get credential.https://github.com.helper
# 预期输出: !/usr/bin/gh auth git-credential
```

---

## 四、代理环境下的 Git 网络传输调优

### 1. 问题背景
在本地开启代理（如 Clash 监听 `127.0.0.1:<proxy-port>`）的环境下，Git 默认基于 GnuTLS/HTTP2 协议访问 GitHub 时，极易出现 `GnuTLS recv error (-110): The TLS connection was non-properly terminated` 或握手挂起。

### 2. 优化命令
全局将 Git HTTP 协议版本强制指定为兼容性最佳的 `HTTP/1.1`：

```bash
# 全局设置 HTTP/1.1 协议
git config --global http.version HTTP/1.1

# 检查当前配置
git config --global --get http.version
```

> 这条只治 GnuTLS 握手那一种症状。本机 2026-10-23 实测：把 `http.version` 设成
> `HTTP/1.1` **不能**解决下面的 `Connection was reset`——那是链路被干扰，不是协议
> 协商失败。遇到 reset 先按第 3 节量，别急着改协议。

### 3. 端点可达性不同：`api.github.com` 通不代表 `github.com` 通

`gh` 走 `api.github.com`，`git` 走 `github.com` 的 smart-HTTP 端点
（`/info/refs?service=git-upload-pack`）。这两个域名在同一台机器上的可达性
**不是一回事**，于是会出现"`gh` 正常、`git` 连不上"——与工具本身无关。

2026-10-23 12:32 前后实测（同一时刻，同一台机器）：

| 目标 | 直连结果 |
| :--- | :--- |
| `https://api.github.com` | `HTTP/1.1 200 OK` |
| `https://github.com`（网页根） | 无响应 |
| `https://github.com/<repo>.git/info/refs?service=git-upload-pack` | 无响应 |
| 同一个 git 端点经本地代理 | `HTTP/1.1 200 Connection established` |
| `git ls-remote` 直连 | `Recv failure: Connection was reset`；另一次 `Failed to connect to github.com:443 after 21s` |
| `git ls-remote` 经 `http.proxy` | 成功 |

**而且它是间歇性的**：约一小时后，同一台机器上直连连续 4 次 `curl`、3 次 `git`
全部成功。所以**一次失败的 fetch 不能证明配置错了**——先量再判：

```bash
# 绕开代理环境变量，看直连到底通不通
env -u http_proxy -u https_proxy -u all_proxy \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    git ls-remote --heads origin main
```

### 4. git 不读 Windows 的系统代理

Windows 的「系统代理」是 **WinINET 级**的（`HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`
下的 `ProxyEnable` / `ProxyServer`），只有用 WinINET 的程序会读它（浏览器、.NET GUI
应用）。**git 完全不读系统代理**：它只认自己的 `http.proxy` 配置，或
`http_proxy` / `https_proxy` 环境变量。而 `netsh winhttp show proxy` 那一条还是
`Direct access`（无代理），所以 `Invoke-WebRequest` 同样不会自动走系统代理。

这就是「浏览器能开 GitHub、`git` 却连不上」的机制。`git` 要么显式配代理：

```bash
# 临时
git -c http.proxy=http://127.0.0.1:<proxy-port> ls-remote --heads origin main

# 全局
git config --global http.proxy http://127.0.0.1:<proxy-port>
```

要么靠环境变量——但那又牵扯下一节。

### 5. 环境变量是「启动那一刻的快照」

`HKCU\Environment` 改过之后，**已经跑着的进程仍然拿着旧环境**，由它派生的子进程
也一样。本机实测：桌面应用的子进程里 `HTTP_PROXY` 为空，于是它派生的 `git` 直连
失败；同一台机器上，用户在终端里敲的 `git` 正常。

刷新路径的作用范围各不相同：

| 做法 | 作用范围 |
| :--- | :--- |
| `setx`（广播 `WM_SETTINGCHANGE`） | **之后新启动**的应用会拿到 |
| 重启应用 / 注销重登 | 该应用自己拿到 |
| **已经跑着的进程** | **拿不到**，必须重启它 |

Windows 侧写这六个值（`ALL_PROXY`/`all_proxy`、`HTTP_PROXY`/`http_proxy`、
`HTTPS_PROXY`/`https_proxy`）用
[`../windows/files/powershell/set-proxy-env.ps1`](../windows/files/powershell/set-proxy-env.ps1)：
它先探测端口是否真的在监听——端口没人监听时，变量会把每个走代理的请求变成立刻被拒，
而直连其实通着——再写入，并广播 `WM_SETTINGCHANGE`。

Linux 侧是同一个问题的另一面，见
[`../agent/skills/android-chroot-debian/references/proxy-and-socket-pitfalls.md`](../agent/skills/android-chroot-debian/references/proxy-and-socket-pitfalls.md)：
那里记的是「代理软件在宿主上、会被关掉」与「TUN 模式下根本没有端口可指」两种情况，
处置同样是**先探测再决定要不要导出变量**。

---

## 五、清洗历史 Commit 中的真实邮箱 (git-filter-repo)

> [!IMPORTANT]
> **要实际执行清洗，请用 [`email-scrub-runbook.md`](email-scrub-runbook.md)，不要直接照抄本节。**
> 本节讲的是原理与命令形态；runbook 里有本机的待清仓库清单、前置门禁，以及一个本节没提、会**静默销毁未提交修改**的坑（已实测确认）。

> [!WARNING]
> 重写 Git 历史会修改所有受影响 Commit 的 SHA-1 哈希值。强制推送（Force Push）会覆盖远端历史，操作前请确认仓库无他人协作。

### 1. 安装 git-filter-repo
`git-filter-repo` 是官方推荐取代过时 `git filter-branch` 的高效重写工具：

```bash
sudo apt update && sudo apt install -y git-filter-repo
git filter-repo --version
```

### 2. 批量重写与推送流程

```bash
# 1. 创建干净的临时重写工作区
mkdir -p /tmp/gitrewrite && cd /tmp/gitrewrite

# 2. 编写 mailmap 文件（格式：新昵称 <新隐私邮箱> <旧真实邮箱>，可同时统一名字与邮箱）
cat > mailmap <<'EOF'
Leo <28289630+Leonis03@users.noreply.github.com> <your-old-email@example.com>
EOF

# 3. 指定需要重写历史的远端仓库列表（以空格隔开）
TARGET_REPOS=("repo-a" "repo-b" "repo-d")

# 4. 执行克隆、脱敏重写并强制镜像推送
for repo in "${TARGET_REPOS[@]}"; do
  echo "==================== 处理仓库: $repo ===================="
  # 以 bare 模式克隆所有分支与标签
  git clone --bare "https://github.com/Leonis03/$repo.git" "$repo.git"
  cd "$repo.git"
  
  # 执行历史重写
  git filter-repo --mailmap /tmp/gitrewrite/mailmap --force
  
  # 打印重写后所有提交身份，确认真实邮箱已被清除
  echo "--- 重写后身份列表 ---"
  git log --all --format='author: %an <%ae> | committer: %cn <%ce>' | sort -u
  
  # 重新绑定远端地址并全量覆盖推送
  git remote add origin "https://github.com/Leonis03/$repo.git"
  git push --force --mirror origin
  
  cd /tmp/gitrewrite
done

# 5. 清理临时文件夹
rm -rf /tmp/gitrewrite
```

### 3. 本地独立仓库单步清洗（尚未绑定远端）

若仓库仅在本地未推送到 GitHub（例如新建的 `model/b`），可直接在仓库根目录就地清洗：

```bash
cd /path/to/local/repo

# 1. 创建备份（安全起见）
cp -r .git .git.bak

# 2. 准备 mailmap 映射
cat > /tmp/mailmap <<'EOF'
Leo <28289630+Leonis03@users.noreply.github.com> <your-old-email@example.com>
EOF

# 3. 就地重写并验证
git filter-repo --mailmap /tmp/mailmap --force
rm -f /tmp/mailmap

# 4. 确认所有提交作者已脱敏
git log --all --format='author: %an <%ae> | committer: %cn <%ce>' | sort -u
```


---

## 六、个人仓库批量转为 Private 及验证

### 1. 批量设置私有可见性

```bash
REPOS=("repo-a" "repo-b" "repo-c" "repo-d")

for repo in "${REPOS[@]}"; do
  echo "Setting Leonis03/$repo to private..."
  gh repo edit "Leonis03/$repo" --visibility private
done
```

### 2. 验证仓库私有状态与远端 Commit 邮箱

```bash
# 验证仓库 visibility 与 private 状态
for repo in "${REPOS[@]}"; do
  gh api "repos/Leonis03/$repo" --jq '"\(.name): visibility=\(.visibility), private=\(.private)"'
done

# 抽样检查远端实际 Commit 记录的作者邮箱是否均为隐私邮箱
for repo in "${REPOS[@]}"; do
  echo "=== $repo 远端 Commit 邮箱 ==="
  gh api "repos/Leonis03/$repo/commits?per_page=20" --jq '.[] | "\(.commit.author.name) <\(.commit.author.email)>"' 2>/dev/null | sort -u
done
```

---

## 七、日常检查与验证命令速查

| 检查项 | 命令 | 预期安全值 / 输出 |
| :--- | :--- | :--- |
| **全局 Git 提交邮箱** | `git config --global user.email` | `28289630+Leonis03@users.noreply.github.com` |
| **全局 Git 提交用户名** | `git config --global user.name` | `Leo` |
| **当前仓库生效身份** | `git config user.email` | （同上，无仓库级别泄漏覆盖） |
| **Git 凭证助手状态** | `git config --global credential.https://github.com.helper` | `!/usr/bin/gh auth git-credential` |
| **Git 网络传输协议** | `git config --global http.version` | `HTTP/1.1` |
| **gh 登录账号状态** | `gh auth status` | `Logged in to github.com account Leonis03` |
| **最近一次 Commit 身份** | `git log -1 --format='%an <%ae>'` | 提交者与提交邮箱均为隐私设置 |

---

## 八、文件大小限制

四道门槛，单位是 **MiB 不是 MB**（GitHub 官方文档用的就是 MiB）：

| 大小 | 会发生什么 |
| :--- | :--- |
| ≤ 25 MiB | 网页端 `Add file → Upload files` 可传 |
| 25 – 50 MiB | 网页端**不让传**，但 `git push` 正常 |
| 50 – 100 MiB | 能推，但 Git 会给**警告**。历史里留着会拖慢每一次 clone |
| > 100 MiB | **直接拒绝**。必须改用 Git LFS，或换分发方式 |

**Release 附件是另一套规则**：仓库总量不限，但**单个文件必须 < 2 GiB**。发大文件（模型权重、安装包、数据集）走 Releases 比塞进 Git 历史合适——历史里的大文件删不掉，只能重写历史。

被 100 MiB 挡住时的选择顺序：

1. **这个文件该不该进版本库**——构建产物、缓存、下载的依赖都不该进，加进 `.gitignore` 即可
2. **能不能走 Releases 附件**——发布物、二进制分发首选
3. **确实需要版本化的大文件**才上 Git LFS

> 已经推上去再想删，靠 `git rm` 没用——文件还在历史里。得 `git filter-repo` 重写，注意它
> 会**静默丢弃未提交的已跟踪修改**，见
> [`email-scrub-runbook.md`](email-scrub-runbook.md) 第 2 节。
