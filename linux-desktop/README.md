# 原生 Linux 桌面开发环境配置与踩坑指南

本文档记录在原生物理机 Linux 桌面系统（以 **Linux Mint 22 / Ubuntu 24.04 noble 底座** 为例）上，复刻部署本仓库开发环境、四层 Shell 分层、开发工具链及 AI Agent 基础设施时的关键配置细节与踩坑取证结论。

---

## 零、物理机 Linux 桌面与 WSL2 的环境共性与差异

本仓库原本围绕 **Windows 11 + WSL2** 体系构建。在原生 Linux 桌面（如 Linux Mint 22）上迁移部署时，核心架构体系完全通用，但有若干环境假定发生变化：

1. **四层 Shell 配置分层完全通用**（原件与分层说明在 [`../shell/`](../shell/)）：
   - `~/.zshenv`（轻量非交互入口）
   - `~/.shell_wslfn`（互操作函数定义，内置 `/proc/version` 早退守卫）
   - `~/.shell_common`（环境变量、PATH、代理、输入法、Keyring 的唯一真相来源）
   - `~/.zshrc` / `~/.bashrc`（专属交互配置）
   在非 WSL 的原生 Linux 环境下，`~/.shell_wslfn` 与 `~/.shell_common` 会自动跳过 Windows 路径探测与 `.exe` 桥接，保持环境绝对纯净。
2. **WSL2 虚拟化机制不必部署**：
   - Windows 宿主端的 `%USERPROFILE%\.wslconfig`
   - Linux 侧虚拟化配置文件 `/etc/wsl.conf`
   - Windows 固定盘跨文件系统挂载 `/etc/fstab`（`/mnt/c`、`/mnt/d`、`/mnt/e`）
   - `systemd-binfmt` 与 `/mnt/wsl` 共享守护服务
   原生物理机拥有独立的 ext4 根文件系统与完整的内核命名空间，上述规避 WSL 虚拟化陷阱的组件无需配置。
3. **输入法与图形环境**：
   - 原生桌面直接运行 X11 / Wayland 与系统的 Fcitx / Fcitx5 守护进程，无需 WSLg 桥接与 Weston 窗口规则。

---

## 一、镜像源与工具链配置规范

### 1. 软件源与镜像策略
- **npm / pnpm**：使用 `npmmirror`（`https://registry.npmmirror.com/`），在 `~/.npmrc` 中全局固化。
- **Python (uv / pip)**：使用清华大学 TUNA 镜像源（`https://pypi.tuna.tsinghua.edu.cn/simple`），分别配置于 `~/.config/uv/uv.toml` 与 `~/.config/pip/pip.conf`。
- **Node (nvm)**：使用 npmmirror 官方 Node 镜像（`https://npmmirror.com/mirrors/node`），由 `~/.shell_common` 导出 `NVM_NODEJS_ORG_MIRROR`（避免清华 nodejs-release 源同步滞后缺失高版本）。
- **APT 软件包**：采用清华 TUNA 双轨镜像。Linux Mint 将官方源收敛在 `/etc/apt/sources.list.d/official-package-repositories.list`，必须同时将 **Mint 专属桌面源**（`https://mirrors.tuna.tsinghua.edu.cn/linuxmint`）与 **Ubuntu 上游基础源**（`https://mirrors.tuna.tsinghua.edu.cn/ubuntu`）均重定向至 TUNA，避免官方海外源 300 kB/s 限速与更新器超时中断。

### 2. Python 隔离纪律
严格遵循 PEP 668：
- 系统 `/usr/bin/python3` 专属于 OS 与 apt 基础包，严禁使用 `pip` 全局安装或 `--break-system-packages`。
- 业务与日常开发统一通过 `uv python install 3.12` 进行旁路管理。
- 在 `~/.config/uv/.python-version` 中写入 `3.12`，统一使用 `uv run --python 3.12` 执行。

### 3. Node.js 与 pnpm 12 安装规范及 Vibe Coding 个人机直通策略
- **Node.js 运行时基准**：
  - 物理机与 WSL 环境一律标准化为 **Node 24 LTS**（`v24.21.0`+）。
  - 通过 `nvm install 24 && nvm alias default 24` 锁定全局默认，避免现代 AI CLI 工具（如 MiniMax Code / Claude Code 等）要求 Node ≥ 22.19/24 时的兼容性断层。
- **pnpm 12 独立二进制安装**：
  - 默认直接通过官方独立脚本 `curl -fsSL https://get.pnpm.io/install.sh | sh -` 安装最新版 pnpm 12 二进制。
  - 独立二进制落地于 `$PNPM_HOME/bin/pnpm`（即 `~/.local/share/pnpm/bin/pnpm`）。
  - 绝不通过 npm 全局安装，完全保持与 Node 版本的生命周期解耦。
- **Vibe Coding 个人开发机直通放行策略（可选）**：
  - pnpm 11/12 默认开启严格的供应链安全防御：拦截未审批的构建脚本（`pnpm approve-builds` 交互弹窗），并强制执行 `minimumReleaseAge: 1440`（发布未满 24 小时的新版本禁止解析）。
  - 若为**个人开发电脑、仅用于敏捷 Vibe Coding / AI Agent 工具链迭代**，无需企业级冷冻防御，可开启全局直通策略，消除弹窗中断并即刻安装最新发布版：
    在 `~/.config/pnpm/config.yaml` 与 `~/.npmrc` 中配置：
    ```yaml
    dangerouslyAllowAllBuilds: true
    minimumReleaseAge: 0
    ```
    详见踩坑索引 2.16 节；不采用该配置时，改用 `pnpm add -g --allow-build=<具体包名>` 逐包放行（2.16 节第 4 条）。

### 4. 终端仿真器与 Shell 交互增强规范
- **终端仿真器**：推荐使用现代化 GPU 加速终端 **Ghostty**，原生完整支持 ANSI OSC 52 剪贴板协议与 Kitty Graphics 行内图像渲染协议。
- **按键解绑与重映射规范**：在 `~/.config/ghostty/config` 中将默认劫持全屏的 `Ctrl+Enter` 解绑透传（`ctrl+enter=unbind`），并将全屏切换改绑为 Linux 通用键（`f11=toggle_fullscreen`）。
- **文件管理器上下文菜单（右键在 Ghostty 中打开）**：在 Nemo 文件管理器中通过 Nemo Action 机制，配置 `open_in_ghostty.nemo_action`（右键选中文件夹）与 `open_in_ghostty_bg.nemo_action`（右键当前目录空白处），实现在文件管理器中右键启动 Ghostty。
- **Shell 插件**：在 Oh-My-Zsh 中启用 `git`、`zsh-autosuggestions`（智能补全）与 `zsh-syntax-highlighting`（实时语法高亮），注意语法高亮插件必须置于插件列表末位。

### 5. 中文输入法体系与字体渲染规范（Fcitx 5 + Rime + 更纱黑体）
- **框架与引擎选型**：使用 **Fcitx 5** 现代化框架与 **Rime（雾凇拼音）** 方案，安装 GTK 4 原生模块（`fcitx5-frontend-gtk4`），使 Ghostty 等现代终端与应用完美支持中文输入。
- **环境接管与防断层**：通过 `im-config -n fcitx5` 接管桌面输入法框架，并在 `/etc/environment` 与 `~/.xprofile` 固化环境变量，防止非终端 GUI 应用环境变量丢失。
- **按键冲突防范与光标编辑**：
  - 在 `~/.config/fcitx5/conf/chttrans.conf` 中置空简繁转换热键，避免 `Ctrl+Shift+F` 劫持全局搜索。
  - 在 `~/.config/fcitx5/config` 中清空 `AltTriggerKeys`，防止左 Shift 抢占 Rime 的字母直接上屏（`commit_code`）。
  - 在 `default.custom.yaml` 中配置 `"selector/linear/bindings"`，解绑横向候选栏左右键拦截，允许左右方向键在拼音串中自由穿梭并支持就地增删改。
- **系统级中文字体与 Fontconfig 防旧字形**：
  - 在 `/etc/fonts/conf.d/64-default-cjk-sc.conf` 与 `~/.config/fontconfig/fonts.conf` 中配置规范，自动将现代 Web BCP-47 `zh-Hans` 归一化，置顶 `Noto Sans CJK SC`（无衬线）与 `Noto Serif CJK SC`（衬线），彻底压制包含台版/旧字形的 `Droid Sans Fallback`。
- **终端等宽字体**：终端仿真器（Ghostty / GNOME Terminal）统一采用半角全角严格 1:2 等宽对齐的 **Sarasa Term SC**（更纱黑体终端版），彻底解决制表符与表格线错位。
- **独立打包与原生应用适配**：对 WPS Office（独立打包 Qt5）与微信桌面版（Chromium/CEF）提供启动包装器，强制透传输入法环境变量。
- **专题指南**：完整配置复刻步骤与 8 大输入法踩坑详见独立专题文档 [**`gui-and-ime.md`**](gui-and-ime.md)。

### 6. Linux 桌面高频生产力与 Windows 习惯对齐工具链
针对 Windows 用户初入 Linux Mint（Cinnamon 桌面）的高频交互对标方案：
- **桌面快捷方式创建**：
  - 应用程序：按 `Super` 键呼出开始菜单，右键目标软件 -> 选择「添加到桌面」或「添加到面板/任务栏」。
  - 文件 / 文件夹：在 Nemo 文件管理器中，按住 `Ctrl + Shift` 鼠标拖拽目标到桌面即可生成快捷方式软链接；或按快捷键 `Ctrl + M` 生成链接；终端执行 `ln -s <目标路径> ~/Desktop/<快捷方式名>`。
- **剪贴板历史记录（对标 Win+V）**：
  - **Fcitx 5 原生内置**：默认快捷键 `Ctrl + ;`，随处呼出带数字序号的剪贴板历史弹窗，零额外资源开销。
  - **CopyQ（全功能进阶替代）**：支持图文预览、多标签分类、拼音搜索、无限历史记录。执行 `sudo apt install -y copyq`，偏好设置中将唤出热键绑定为 `Meta+V`（即键盘 `Win+V`）。
  - **Cinnamon 任务栏 Applet**：右键面板 ->「小工具」->「下载」搜索安装 `Clipboard Indicator`，常驻任务栏管理。
- **任务管理器与进程监控（对标 Task Manager）**：
  - **图形化系统监视器**：系统预装 `gnome-system-monitor`。在「系统设置」->「键盘」->「快捷键」->「自定义快捷键」中添加命令 `gnome-system-monitor`，绑定键位为 `Ctrl + Shift + Escape`，完全还原 Windows 肌肉记忆。
  - **终端现代化监控**：安装高性能交互式 TUI 监视器 `btop`（`sudo apt install -y btop`），支持 CPU/内存/磁盘/网络实时折线图与进程树杀进程。
- **极速文件检索器（对标 Everything）**：
  - **FSearch**：Linux 界的 Everything。纯 C 编写、GTK 现代化界面，为本地全盘文件系统建立轻量索引，键入即出结果，支持通配符、正则与大小写过滤，毫秒级响应。通过 PPA 安装：`sudo add-apt-repository ppa:christian-boxdoerfer/fsearch-daily -y && sudo apt update && sudo apt install -y fsearch`。
  - **Nemo 内置即时搜索**：文件管理器当前目录下直接按 `Ctrl + F`。
  - **CLI 极速检索工具**：`plocate`（基于数据库秒查：`locate <文件名>`）与 `fd`（比原生 `find` 快数倍：`sudo apt install -y fd-find`）。

---

## 二、新装系统踩坑索引与根因排查

> 💡 **关于中文输入法框架（Fcitx5）、Rime（雾凇拼音）、更纱黑体终端等宽对齐、WPS/微信启动包装及 Shift 抢占冲突的完整专题指南，详见独立文档 [`gui-and-ime.md`](gui-and-ime.md)。**

### 2.1 桌面会话下 `chsh` 切换默认 Shell 后重启终端窗口仍为 Bash

#### 症状
执行 `sudo chsh -s $(which zsh) <your-linux-user>` 成功修改系统登录 Shell，核对 `/etc/passwd` 已更新为 `/usr/bin/zsh`。但关闭 GNOME Terminal 窗口再次重新打开时，依然进入原来的 Bash 环境。

#### 根因剖析
Linux 图形桌面会话（X11 / Wayland，由 LightDM / GDM 等 Display Manager 管理）具有**环境变量固化传播机制**与终端**Client/Server 长驻架构**的双重阻隔：
1. **PAM 会话固化**：Display Manager 引导桌面时，读取 `/etc/passwd` 并向整个桌面会话树（包括 X11 根会话、systemd user session、D-Bus 会话总线）固化注入了 `SHELL=/bin/bash`。
2. **GNOME Terminal 守护进程长驻**：GNOME Terminal 并不是一个独立的瞬时进程，其核心是后台长驻的 `/usr/libexec/gnome-terminal-server`。当关闭最后一个终端窗口时，该服务端进程依然在内存中存活，并一直缓存着启动时的 `SHELL=/bin/bash` 环境变量。
3. **重新打开终端窗口只是向长驻 Server 发起 RPC 请求**：Server 派生新 Tab/Window 时，直接使用自身环境中的 `SHELL` 变量，因此不会重新查询 `/etc/passwd`。

#### 解决方案
- **彻底生效路径**：注销当前图形桌面会话（Log Out）并重新登录，或重启计算机。
- **免注销即时生效方案（无需重启）**：
  1. 更新 systemd 与 D-Bus 会话总线环境变量：
     ```bash
     systemctl --user set-environment SHELL=/usr/bin/zsh
     dbus-update-activation-environment --systemd SHELL=/usr/bin/zsh
     ```
  2. 配置 GNOME Terminal 默认 Profile 显式启用 Zsh：
     ```bash
     PROFILE_ID=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')
     gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:${PROFILE_ID}/ use-custom-command true
     gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:${PROFILE_ID}/ custom-command '/usr/bin/zsh'
     gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:${PROFILE_ID}/ login-shell true
     ```
  完成配置后，在终端按 `Ctrl + Shift + T` 或新开窗口即可即时进入 Zsh。

---

### 2.2 Clash Verge 桌面系统代理对 CLI 穿透失效及 ureq socks5h 陷阱

#### 症状
在 Linux 桌面启动 Clash Verge Rev 后，Firefox 等桌面浏览器能够正常访问外网，但原生终端内执行 `curl`、`git clone` 或 `uv` 下载却无法访问；而若在终端强行设置 `ALL_PROXY=socks5h://127.0.0.1:<proxy-port>`，单二进制搜索工具 `bx`（Brave Search CLI）直接崩溃报错：
```
error: io: Connection refused
exit 5
```

#### 根因剖析
1. **桌面系统代理模式 vs TUN 虚拟网卡**：
   Clash Verge 在 Linux 上默认以「系统代理」模式运行，即通过 GSettings 设置 GNOME 桌面网络代理。GUI 浏览器会主动读取桌面配置，而 Linux 原生命令行程序（CLI）与子进程并不监听桌面 GSettings，必须依赖环境变量（`http_proxy`、`https_proxy`）。
2. **Rust `ureq` 对 `socks5h` 协议的不兼容性**：
   `bx` 由 Rust 编写，底层 HTTP 客户端基于 `ureq`。官方构建时未启用 SOCKS 特性，且 `socks5h://` 为 curl 专属协议头，`ureq` 解析该协议头失败后会**静默回退为直接连接（Direct）**，直接连接触发网络阻断返回 Connection Refused。

#### 解决方案
1. **环境变量多层固化**：
   在 `~/.shell_common` 中规范导出 HTTP 代理入口与精确的 `NO_PROXY` 白名单：
   ```sh
   export host_ip="127.0.0.1"
   export proxy_port="<proxy-port>"
   export HTTP_PROXY="http://${host_ip}:${proxy_port}"
   export HTTPS_PROXY="http://${host_ip}:${proxy_port}"
   export http_proxy="http://${host_ip}:${proxy_port}"
   export https_proxy="http://${host_ip}:${proxy_port}"
   export ALL_PROXY="socks5h://${host_ip}:${proxy_port}"
   export all_proxy="socks5h://${host_ip}:${proxy_port}"
   export NO_PROXY="localhost,127.0.0.1,::1,.local"
   export no_proxy="localhost,127.0.0.1,::1,.local"
   ```
2. **`bx` 专用 Wrapper 隔离**：
   在 `~/.local/bin/bx` 构建 Wrapper 拦截器，将真实二进制重命名为 `bx-bin`，在子进程内执行时动态清除 `ALL_PROXY`，使 `ureq` 安全回退走 `HTTPS_PROXY`（详见 `agent/brave-search/bx-cli.md`）。
3. **需要覆盖不读取代理变量的程序时，开启 TUN 模式**：
   若需接管原生不读取代理变量的守护程序或复杂容器流量，在 Clash Verge 客户端中显式开启 **TUN Mode**。

---

### 2.3 Linux Mint 22 (noble) 官方软件源结构与 Ubuntu 换源差异及更新器超时陷阱

#### 症状
1. **换源失效 / 冲突**：按传统 Ubuntu 24.04 指南修改 `/etc/apt/sources.list.d/ubuntu.sources` 后，执行 `apt update` 报错或发现 Linux Mint 自身的桌面组件（Cinnamon、mintupdate、mintinstall 等）无法获取更新或提示包冲突。
2. **图形更新管理器超时中断**：未换源前，Linux Mint 桌面「更新管理器」（`mintupdate` / Synaptic 后台）刷新包列表时，直接连接海外官方源 `archive.ubuntu.com` 与 `security.ubuntu.com`。下载速率常年被掐在 300~400 kB/s 且频繁丢包，极易触发 TCP 超时断流，弹出「下载软件包信息失败」的红色报错弹窗。

#### 根因剖析
Linux Mint 22 虽然以 Ubuntu 24.04 (noble) 为底层，但其包管理器架构与 Ubuntu 原厂有显著区别：
1. Ubuntu 24.04 官方已全面转向 `deb822` 格式（即 `.sources` 格式）。
2. Linux Mint 22 仍使用传统 one-line-style list 格式，且将源统一收敛在 `/etc/apt/sources.list.d/official-package-repositories.list`。
3. 该文件内明确拆分为两套源：
   - **Mint 主仓库**：`packages.linuxmint.com <codename> main upstream import backport`（根据当前系统代号为 `wilma` 或 `zena`）
   - **Ubuntu 上游仓库**：`archive.ubuntu.com/ubuntu noble main restricted universe multiverse` 等
如果仅覆写 Ubuntu 仓库，Mint 仓库未换源仍会受限于海外连接速度；若误删或覆盖该文件，则会导致 Mint 专属桌面套件脱落；如果保持出厂配置，图形更新器拉取全量 50MB+ 索引时便必然遭遇长时阻塞甚至超时中断。

#### 解决方案
直接编辑 `/etc/apt/sources.list.d/official-package-repositories.list`，将其双轨重定向至清华大学 TUNA 镜像：
```list
deb https://mirrors.tuna.tsinghua.edu.cn/linuxmint zena main upstream import backport #id:linuxmint_main

deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble-backports main restricted universe multiverse

deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble-security main restricted universe multiverse
```

#### 实测效果对比
* **换源前（直连海外源）**：下载速率徘徊在 368 kB/s，更新管理器极易中断报错。
* **换源后（清华 TUNA 镜像）**：
  ```text
  Fetched 53.2 MB in 9s (6,039 kB/s)
  Reading package lists... Done
  ```
  全量 53.2 MB 索引数据在 9 秒内传输完成，平均速率 6,039 kB/s（峰值 8.7 MB/s），**提速逾 16 倍**，彻底消除图形更新管理器由于网络超时造成的报错。

---

### 2.4 安装脚本对 Shell rc 文件的追加污染与防线

#### 症状
执行 `pnpm setup` 或 `nvm` 安装脚本后，`~/.bashrc` 尾部被强制注入了若干重复的 `export PNPM_HOME` 与 `PATH` 修改块，破坏了配置的分层单一性。

#### 根因剖析
主流工具安装程序（pnpm、nvm、conda 等）默认假定用户采用「所有配置堆在单个 `.bashrc`」的反模式，因此在执行安装或初始化时会自动探测并向 rc 文件的末尾追加 PATH 与环境变量代码。

#### 解决方案
1. **安装参数防御**：
   - Oh-My-Zsh：使用 `--unattended --keep-zshrc` 参数执行安装脚本，防止其强行覆盖预置的 `~/.zshrc`。
2. **集中收敛至 `~/.shell_common`**：
   - `PNPM_HOME` 与 `NVM_DIR` 统一在 `~/.shell_common` 中通过 `_path_prepend` 幂等注入 PATH。
   - 工具安装完毕后，主动检查并清理 `~/.bashrc` 或 `~/.zshrc` 尾部的自动注入残留，确保配置文件的纯粹性与可维护性。

---

### 2.5 CLI Agent / 终端快捷键粘贴（Ctrl+V / Alt+V）报错 `no supported clipboard tool found`

#### 症状
在 Claude Code、Antigravity 等终端 CLI Agent 中按 `Ctrl+V` 或 `Alt+V` 粘贴剪贴板文本或图片时，终端报出警告：
```text
no supported clipboard tool found (install wl-clipboard or xclip)
```

#### 根因剖析
1. **WSL2 与原生 Linux 剪贴板生态差异**：
   - 在 WSL2 环境下，Linux 默认没有独立的物理显示会话与剪贴板服务，剪贴板由宿主 Windows 管理。本仓库通过 `shell_wslfn` 将 `clip` 桥接至 `/mnt/c/Windows/System32/clip.exe`，或者通过 `powershell.exe Get-Clipboard` 跨界传递。
   - 在原生 Linux 物理机桌面下，不存在 Windows 宿主与任何 `.exe` 桥接。终端进程直接依附于本地 X11 或 Wayland 显示服务（Linux Mint 22 默认使用 X11，`$XDG_SESSION_TYPE` 为 `x11`）。
2. **现代 CLI 工具的剪贴板探测机制**：
   - 现代 CLI Agent（如 Claude Code 内置的富文本/图片粘贴模块）在 Linux 平台下检测系统剪贴板时，硬编码依赖系统级 CLI 工具：X11 下调用 `xclip`（或 `xsel`），Wayland 下调用 `wl-clipboard`（`wl-paste` / `wl-copy`）。
   - Linux 发行版的基础桌面镜像通常不会默认预装这些底层 CLI 工具，导致终端交互层触发按键时探测失败。

#### 解决方案
安装原生剪贴板工具链（同时兼顾 X11 与 Wayland 环境）：
```bash
sudo apt-get install -y xclip xsel wl-clipboard
```
- Linux Mint 22 默认 X11 环境下 `xclip` / `xsel` 负责接管剪贴板读写。
- 安装 `wl-clipboard`，使切换到 Wayland 会话后剪贴板命令仍可用。

> **[!IMPORTANT] 进程生命周期陷阱**：
> 如果 CLI Agent（如 `agy`）在执行 `apt install` 之前就已经在终端中运行，由于 Go 语言底层剪贴板库（如 `atotto/clipboard`）在进程引导的 `init()` 阶段仅探测一次 `exec.LookPath` 并固化在进程内存中，后装的命令无法被当前运行中的进程动态感知，调用 `/copy` 依然会报无可用剪贴板。**必须退出当前会话并重新启动 CLI（例如重启 `agy` 后通过 `/resume` 恢复）**，新进程启动后即可正常访问剪贴板。

---

### 2.6 CLI `/copy` 命令提示复制成功但系统剪贴板无内容（GNOME Terminal 静默丢弃 OSC 52）

#### 症状
在 Antigravity CLI 等现代终端工具中执行 `/copy` 命令，界面正常显示 `Copied ... to clipboard.`，但在系统外部程序（浏览器、编辑器）中按 `Ctrl+V`，剪贴板依然为空或保持上一次复制的内容。

#### 根因剖析
1. **读写分离与协议脱节**：
   - 终端工具读取剪贴板（如按 `Ctrl+V` 粘贴图片/文本）通常直接调用本地系统的 `xclip` 或 `wl-paste` 进程；
   - 但向系统剪贴板写入（如 `/copy`）为了兼容 SSH 远程跳转等无本地 X11 的场景，通常采用 ANSI **OSC 52** 控制转义码（`\033]52;c;<base64>\007`），请求宿主终端仿真器协助将数据写入宿主系统的剪贴板。
2. **GNOME Terminal (libvte) 长期缺乏 OSC 52 写入支持**：
   - Linux Mint 与 Ubuntu 默认的 GNOME Terminal 底层基于 GNOME 虚拟终端库 `libvte`。
   - VTE 社区长年因安全策略考虑（防止恶意脚本在终端中静默覆盖用户剪贴板）一直未实现 OSC 52 写入协议（Issue #2495 至今未合入）。
   - 当 `agy` 向标准输出发送 OSC 52 转义码时，向 PTY 写字符永远返回成功，因此 CLI 报复制成功；但 GNOME Terminal 遇到未实现的转义序列直接**静默丢弃**。

#### 解决方案
1. **改用 Ghostty（推荐）**：
   采用 Mitchell Hashimoto 开发的现代化终端 **Ghostty**，原生完整支持 OSC 52 剪贴板读写与 Kitty Graphics 图像协议：
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
   ```
   安装后 Ghostty 自动挂载系统的默认 Zsh 与 Oh-My-Zsh 配置，`/copy` 原生直达系统剪贴板。
2. **GNOME Terminal 兼容方案（CLI_CLIPBOARD_FILE 桥接）**：
   若必须在 GNOME Terminal 中使用，可利用 `agy` 内置的逃逸变量 `export CLI_CLIPBOARD_FILE="$HOME/.cache/agy_clipboard"`，并配合系统 `systemd --user` 路径监听自动将写入内容通过 `xclip` 刷入剪贴板。

---

### 2.7 多设备历史命令迁移冷启动与 Zsh `corrupt history file` 崩溃

#### 症状
为了让新系统的 `zsh-autosuggestions` 获得旧工作机（如台式机 WSL、笔记本）的完整肌肉记忆，直接将各处的 `.bash_history` 与 `.zsh_history` 拷贝或拼接至新系统的 `~/.zsh_history`，启动 Zsh 时报错：
```text
zsh: corrupt history file /home/<user>/.zsh_history
```

#### 根因剖析
1. **截断与空字节（NULL bytes）污染**：
   在 WSL 异常终止、非正常关机或跨文件系统归档传输时，历史文件末尾或特定行常产生连续的 `\x00` 空字节。C 语言底层字符串以 `\0` 为终止符，Zsh 的 `readhistline()` 遇到 `\x00` 解析结构断裂，立即将整个历史文件判定为 Corrupt。
2. **Bash 纯文本与 Zsh 扩展格式冲突**：
   Oh-My-Zsh 默认启用 `setopt extended_history`，要求历史文件符合严格的 `: <timestamp>:0;<command>` 规范；若混入原始未加时间戳的 Bash 行，可能造成解析错乱。

#### 解决方案
在迁移多设备历史时，编写 Python 脚本清洗合并：
1. 过滤全部 `\x00` 字节；
2. 提取并归一化为标准的 `: <timestamp>:0;<command>` 格式；
3. 去重并按时间戳升序排序，确保最近使用的命令在历史末尾，最优先触发 `autosuggestions` 灰色幽灵词推荐；
4. 权限设为 `chmod 600 ~/.zsh_history`。

---

### 2.8 `sudo` 清洗代理环境变量导致 APT 与海外源超时（`env_reset` 陷阱）

#### 症状
终端用户 Shell 中已经正常配置并导出了 `http_proxy` 与 `https_proxy`，普通命令（如 `curl -I https://downloads.typora.io/...`）能正常秒连，Clash Verge 也处于运行中；但一旦执行 `sudo apt update` 或 `sudo apt install`，拉取海外源（如 Typora `downloads.typora.io`、Google Chrome 等）时频繁报连接超时：
```text
Err:9 https://downloads.typora.io/linux ./ InRelease
  Could not connect to downloads.typora.io:443 (31.13.95.18), connection timed out
W: Failed to fetch https://downloads.typora.io/linux/./InRelease Could not connect to downloads.typora.io:443 (...), connection timed out
```

#### 根因剖析
1. **`sudo` 的安全环境变量重置（`env_reset`）**：
   Linux `sudo` 出于最小特权与安全性考虑，默认启用了 `env_reset` 策略。当普通用户切换到 root 权限执行命令时，`sudo` 会自动剥离绝大多数环境变量，其中包括 `http_proxy`、`https_proxy`、`all_proxy` 等。通过 `sudo env | grep -i proxy` 验证可发现输出为空。
2. **APT 缺乏专属代理配置时的直连回退**：
   APT 拥有独立的网络配置（`/etc/apt/apt.conf.d/`）。当 APT 既没有在专用配置中指定代理、外部环境变量又被 `sudo` 剥离为空时，APT 会直接回退为底层 TCP 直连模式（DIRECT），从而撞上 GFW 阻断导致连接超时。

#### 解决方案
- **方案 A（全局推荐：配置 `sudoers` 环境变量白名单）**：
  在 `/etc/sudoers.d/proxy` 中显式指定保留代理环境变量，使所有 `sudo` 命令（`sudo apt`、`sudo git`、`sudo curl` 等）无感继承当前用户的代理设置：
  ```bash
  echo 'Defaults env_keep += "http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY"' | sudo tee /etc/sudoers.d/proxy
  sudo chmod 0440 /etc/sudoers.d/proxy
  sudo visudo -cf /etc/sudoers.d/proxy
  ```
- **方案 B（APT 专属持久化代理配置）**：
  在 `/etc/apt/apt.conf.d/99proxy` 中写入 APT 专属代理（配合 Clash Verge 规则模式，国内清华源命中 DIRECT，海外源命中 PROXY）：
  ```apt
  Acquire::http::Proxy "http://127.0.0.1:7897";
  Acquire::https::Proxy "http://127.0.0.1:7897";
  ```
- **方案 C（单次临时透传）**：
  执行 `sudo -E apt update`（`-E` 参数指示 sudo 临时保留当前环境变量）。

---

### 2.9 Fcitx 5 全新安装后默认 Profile 缺失拼音引擎导致打不出中文

#### 症状
按规范安装 `fcitx5` 与 `fcitx5-chinese-addons` 并通过 `im-config -n fcitx5` 切换重启后，系统后台 `fcitx5 -d` 正常运行，`im-config -m` 也确认当前为 `fcitx5`。但在任何应用程序中按下 `Ctrl+Space` 或 `Shift` 均毫无反应，无法唤出中文输入法候选框。

#### 根因剖析
1. **Fcitx 5 首次初始化的默认组陷阱**：
   Fcitx 5 在首次被用户拉起时，自动在 `~/.config/fcitx5/profile` 生成初始配置。但默认模版**仅将 `keyboard-us`（美式英文键盘）填入了活动输入法组**：
   ```ini
   [Groups/0]
   Name=Default
   Default Layout=us
   DefaultIM=keyboard-us

   [Groups/0/Items/0]
   Name=keyboard-us
   Layout=
   ```
2. 虽然底层 `fcitx5-pinyin` 二进制和词库均已就绪（`fcitx5-remote -m pinyin` 可正确返回），但由于未加入 `[Groups/0/Items]` 激活列表，输入法切换快捷键仅仅在单个英文键盘内部循环，导致输入法看似彻底失效。

#### 解决方案
1. **修改 Profile 或调用 D-Bus 补充拼音引擎**：
   在 `~/.config/fcitx5/profile` 的 `[Groups/0]` 节点下追加拼音条目：
   ```ini
   [Groups/0/Items/1]
   Name=pinyin
   Layout=
   ```
   或直接通过 D-Bus 接口即时写入：
   ```bash
   gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
     --method org.fcitx.Fcitx.Controller1.SetInputMethodGroupInfo "Default" "us" "[('keyboard-us', ''), ('pinyin', '')]"
   gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller \
     --method org.fcitx.Fcitx.Controller1.Save
   ```
2. **解除 `Ctrl+Shift+F` 简繁转换热键劫持**：
   Fcitx 5 默认将 `Ctrl+Shift+F` 绑定为简繁中文切换，会拦截 VS Code 与终端的全局文件/历史搜索。在 `~/.config/fcitx5/conf/chttrans.conf` 中显式置空解除占用：
   ```ini
   # Translate engine
   Engine=OpenCC

   [Hotkey]
   ```
   随后执行 `gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller --method org.fcitx.Fcitx.Controller1.ReloadAddonConfig "chttrans"` 即可热生效。

---

### 2.10 Ghostty 终端默认 `Ctrl+Enter` 劫持全屏阻断多行输入 / 改绑 `F11` 规范

#### 症状
在 Ghostty 终端中进行日常操作，尤其是在 AI Agent CLI（如 Antigravity / Claude Code）或多行代码编辑中按下 `Ctrl+Enter` 期望插入换行或提交指令时，Ghostty 窗口意外切换为全屏显示。

#### 根因剖析
Ghostty 在 Linux 平台的官方默认快捷键表（通过 `ghostty +list-keybinds` 可核对）中，将 `Ctrl+Enter` 默认绑定为了 `toggle_fullscreen`：
```text
ctrl + enter = toggle_fullscreen
```
这导致任何向子进程发送 `Ctrl+Enter` 控制字符的交互均被终端仿真器截获并转为全屏切换。

#### 解决方案
在 Ghostty 配置文件 `~/.config/ghostty/config` 中，显式将 `ctrl+enter` 解绑透传，并将全屏功能重定向到 Linux 通用的 `F11` 键位：
```ini
keybind = ctrl+enter=unbind
keybind = f11=toggle_fullscreen
```
- **`unbind` 的作用**：移除 Ghostty 自身对按键的拦截，将其原样透传给终端内部运行的 Shell 或 CLI 程序。
- **配置生效**：在已打开的 Ghostty 窗口内按下 **`Ctrl+Shift+,`**（逗号）即可免重启即刻热重载生效，或新开终端窗口生效。

---

### 2.11 Nemo 文件管理器右键添加「Open in Ghostty」上下文菜单规范

#### 场景与诉求
在原生 Linux Mint (Cinnamon) 桌面环境中，系统默认文件管理器为 **Nemo**。默认右键菜单仅有「在终端中打开」（指向系统默认终端）。若日常主力切换为现代化终端 **Ghostty**，需要能在文件管理器中右键任意目录或当前窗口空白处直接拉起 Ghostty 并定位到对应工作目录。

#### 机制剖析：Nemo Actions 扩展模型
Nemo 提供了比传统 `.desktop` 快捷方式粒度更细的扩展机制 —— **Nemo Action**（位于 `~/.local/share/nemo/actions/`）。
与 Nautilus 脚本或全局服务相比，Nemo Action 具备以下特征：
1. **右键目标严格区分**：
   - **右键选中的文件夹**：需要设置 `Selection=s`（单选），`Extensions=dir;`（仅对目录生效），并通过变量 `%F` 传入选中对象的绝对路径。
   - **右键当前窗口空白处**：需要设置 `Selection=none`（未选中任何项），`Extensions=any;`，并通过变量 `%P` 传入当前所在父目录的绝对路径。
2. **免重启热生效**：Nemo 会使用 inotify 监听 `~/.local/share/nemo/actions/` 目录，放置 `.nemo_action` 文件后无需重启文件管理器进程，下一次右键即刻加载生效。

#### 解决方案与配置文件

在 `~/.local/share/nemo/actions/` 下部署两个 action 文件（仓库原件见 [`linux-desktop/files/nemo/actions/`](files/nemo/actions/)）：

1. **右键选中文件夹打开**：`~/.local/share/nemo/actions/open_in_ghostty.nemo_action`
   ```ini
   [Nemo Action]
   Name=Open in Ghostty
   Name[zh_CN]=在 Ghostty 中打开
   Comment=Open Ghostty terminal in the selected folder
   Comment[zh_CN]=在选中的文件夹中打开 Ghostty 终端
   Exec=ghostty --working-directory=%F
   Icon-Name=com.mitchellh.ghostty
   Selection=s
   Extensions=dir;
   Quote=double
   ```

2. **右键当前目录空白背景打开**：`~/.local/share/nemo/actions/open_in_ghostty_bg.nemo_action`
   ```ini
   [Nemo Action]
   Name=Open in Ghostty
   Name[zh_CN]=在 Ghostty 中打开
   Comment=Open Ghostty terminal in current folder
   Comment[zh_CN]=在当前文件夹中打开 Ghostty 终端
   Exec=ghostty --working-directory=%P
   Icon-Name=com.mitchellh.ghostty
   Selection=none
   Extensions=any;
   Quote=double
   ```

- **参数细节**：
  - `Exec=ghostty --working-directory=%F`：%F 展开为选中的文件/文件夹路径（由 `Quote=double` 自动引号转义防空格）。
  - `Exec=ghostty --working-directory=%P`：%P 展开为当前窗口打开的主目录路径。
  - `Icon-Name=com.mitchellh.ghostty`：自动关联 Ghostty 官方桌面图标，右键菜单显示美观一致。
---

### 2.12 AI Agent 执行 `sudo` 命令时无限阻塞（NOPASSWD 配置）

#### 症状
AI Agent（如 Claude Code、Antigravity CLI 等）在后台任务或子进程中执行带 `sudo` 的命令（如 `sudo apt install`、`sudo tee /etc/...`）时，命令挂起不返回。日志停留在 `[sudo] password for <your-linux-user>:`，Agent 无法向该提示符写入响应，任务永久阻塞直至超时或手动 kill。

#### 根因剖析
1. **`sudo` 默认要求 TTY 密码交互**：`sudo` 默认启用密码认证策略。非交互式进程（Agent 通过 subprocess / `bash -c` 派生的子进程）缺乏可供 `sudo` 写入提示符并读取响应的 TTY，密码提示永久阻塞进程。
2. **Agent 进程链无法响应 PTY 提示**：Agent 通常通过管道或伪终端封装子进程，但密码输入场景需要用户在真实终端手工键入；Agent 没有向该 PTY 注入键盘事件的能力。

#### 解决方案
在 `/etc/sudoers.d/nopasswd-<your-linux-user>` 中为当前用户授权 `NOPASSWD: ALL`。此步骤本身需要一次人工密码输入，一次配置永久生效：
```bash
echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopasswd-$(whoami)
sudo chmod 0440 /etc/sudoers.d/nopasswd-$(whoami)
sudo visudo -cf /etc/sudoers.d/nopasswd-$(whoami) && echo "OK"
```
验证：`sudo -n true && echo "no-password OK"`（`-n` 即 non-interactive，有密码要求时直接报错而非阻塞）

> **安全边界**：仅适用于个人单用户开发机。多用户或生产服务器环境下应精细化配置允许的命令范围，而非 `ALL`。

---

### 2.13 pnpm 12 全局安装 CLI 工具时交互式 build 提示阻塞 & Node.js 缺失导致 postinstall 失败

#### 症状
1. 执行 `pnpm add -g @anthropic-ai/claude-code` 或其他含 postinstall 的全局包时，命令等待交互输入：
   ```
   Choose which packages to build (<space> to select, <enter> to confirm):
   > [ ] @anthropic-ai/claude-code
   ```
   AI Agent 无法向该提示发送 space / enter，任务永久阻塞。
2. 即使通过 `--allow-build=<pkg>` 绕过交互，若 Node.js 未安装或不在 PATH 中，postinstall 失败：
   ```
   .../@anthropic-ai/claude-code postinstall$ node install.cjs
   │ sh: 1: node: not found
   └─ Failed in 6ms
   Error: ERR_PNPM_EXECUTOR_LIFECYCLE_SCRIPT_FAILED  exit 1
   ```

#### 根因剖析
1. **pnpm 10+ 的 lifecycle scripts 安全策略**：pnpm 10 起对全局包的 postinstall / build 脚本默认要求用户显式授权，防止供应链攻击自动执行任意脚本。不带 `--allow-build` 参数时，pnpm 12 会启动交互式授权 UI；在非交互式环境（AI Agent 子进程）中该 UI 无限等待输入。
2. **pnpm 独立二进制不捆绑 Node.js**：通过 `get.pnpm.io/install.sh` 安装的 pnpm 是独立可执行文件，不包含 Node.js 解释器。postinstall 执行 `node install.cjs` 依赖系统 PATH 中的 `node`；若 nvm 尚未初始化或 Node.js 未安装，postinstall 以 exit 127 失败。

#### 解决方案
1. **安装顺序：Node.js 先于 pnpm 全局包**：在安装任何含 postinstall 脚本的全局包之前，先通过 nvm 安装并激活 Node.js：
   ```bash
   export NVM_DIR="$HOME/.nvm"
   . "$NVM_DIR/nvm.sh"
   nvm install --lts
   ```
2. **始终附加 `--allow-build=<pkg>` 参数**：对需要 postinstall 的包，在 `pnpm add -g` 时显式声明：
   ```bash
   pnpm add -g --allow-build=@anthropic-ai/claude-code @anthropic-ai/claude-code
   pnpm add -g --allow-build=opencode-ai opencode-ai
   ```
   包名须与 `--allow-build` 参数完全一致（精确匹配 `package.json` 中的 `name` 字段）。

> **与 2.16 的关系**：逐包 `--allow-build=<pkg>` 是本节的默认做法，作用域可控，团队机与生产环境用这一条即可。若这台电脑只跑自己的 Vibe Coding / AI Agent 工具链，也可以选用 2.16 节的全局直通配置（`dangerouslyAllowAllBuilds: true` + `minimumReleaseAge: 0`）一次性免掉每次的 `--allow-build`；该配置为**可选**，会放行全部依赖的构建脚本并取消新版本冷却期，共享机与 CI 不要照搬。
---

### 2.14 Fontconfig 缺字回退优先级错乱致中文字体呈现繁体/台湾旧字形与衬线体失配

#### 症状
1. **中文字体呈现繁体 / 旧字形**：在主系统语言为英文（`LANG=en_US.UTF-8`）的机器上，使用 Google Chrome 访问未声明 `<html lang="zh-CN">` 的网页（如 GitHub、Reddit、英文技术文档中的中文评论，或使用现代 BCP-47 标准 `<html lang="zh-Hans">` 的站点），以及在 Linux 原生微信中，中文字体出现明显的古板感、日式或台湾旧字形特征（如「骨」上部左折、「关」首两笔为点撇、「门」带点等）。
2. **衬线体（Serif）中文字体回退失配**：当网页指定 `font-family: serif` 时，中文内容没有匹配到思源宋体，而是跌落到等宽字体。

#### 根因剖析
通过深入排查 Fontconfig 的规则优先级与解析流水线（`fc-match -v`），确认存在三大底层诱因：
1. **`65-droid-sans-fallback.conf` 优先级抢跑**：系统预装了 `fonts-droid-fallback`，其规则位于 `/etc/fonts/conf.d/65-droid-sans-fallback.conf`，为 `sans-serif` 注入了 `<prefer><family>Droid Sans Fallback</family></prefer>`。该规则优先级为 65，早于系统默认 Noto CJK 的 70。`Droid Sans Fallback` 诞生于 2008 年早期 Android 时代，其中大量字符采用了台湾教育部标准与传统旧字形，缺字回退时被优先调用。
2. **`70-fonts-noto-cjk.conf` 规则覆盖过于严苛**：官方规则只严格匹配了 `lang="zh-cn"` 这一个字符串。现代 Web 广泛采用的标准 `zh-Hans` 或通用 `zh` 声明无法命中该规则，直接跌落至 `Droid Sans Fallback`。
3. **缺少系统级 Serif CJK 回退链**：Fontconfig 原生配置中没有为泛指的 `serif` 挂载对应的简体中文宋体。

#### 解决方案
在系统级 `/etc/fonts/conf.avail/64-default-cjk-sc.conf`（并在 `/etc/fonts/conf.d/` 启用，同步至 `~/.config/fontconfig/fonts.conf`）注入规则：
1. **BCP-47 规范归一化**：自动将 `zh-hans` 模式重定向归一至 `zh-cn`。
2. **无后缀别名补齐**：将通用的 `Noto Sans CJK` 与 `Noto Serif CJK` 强行绑定至 `SC`（简体中文，TTC Index 2）。
3. **回退队列置顶**：在 `sans-serif` 与 `serif` 的 `<prefer>` 队列中将 `Noto Sans CJK SC` 与 `Noto Serif CJK SC` 放在最前端，彻底压制并淘汰 `Droid Sans Fallback`。
4. **保留正规繁体支持**：若网页显式声明 `zh-tw` / `zh-hk`，依然能够正确调用 `Noto CJK TC/HK`（Index 3/4）。

完整配置原件：
```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- 0. Normalize BCP-47 zh-Hans to zh-cn -->
  <match target="pattern">
    <test name="lang" compare="contains"><string>zh-hans</string></test>
    <edit name="lang" mode="assign"><string>zh-cn</string></edit>
  </match>

  <!-- 1. Map generic CJK families without region suffix to SC -->
  <match target="pattern">
    <test name="family"><string>Noto Sans CJK</string></test>
    <edit name="family" mode="assign" binding="strong"><string>Noto Sans CJK SC</string></edit>
  </match>
  <match target="pattern">
    <test name="family"><string>Noto Serif CJK</string></test>
    <edit name="family" mode="assign" binding="strong"><string>Noto Serif CJK SC</string></edit>
  </match>

  <!-- 2. Language-based matching for Simplified Chinese and generic Chinese -->
  <match target="pattern">
    <test name="lang"><string>zh</string></test>
    <test name="family"><string>sans-serif</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK SC</string></edit>
  </match>
  <match target="pattern">
    <test name="lang"><string>zh-cn</string></test>
    <test name="family"><string>sans-serif</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK SC</string></edit>
  </match>
  <match target="pattern">
    <test name="lang"><string>zh</string></test>
    <test name="family"><string>serif</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Serif CJK SC</string></edit>
  </match>
  <match target="pattern">
    <test name="lang"><string>zh-cn</string></test>
    <test name="family"><string>serif</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Serif CJK SC</string></edit>
  </match>

  <!-- 3. Default fallback order for generic font families -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
      <family>Noto Sans CJK SC</family>
      <family>Noto Sans CJK TC</family>
      <family>Noto Sans CJK JP</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>Noto Serif CJK SC</family>
      <family>Noto Serif CJK TC</family>
      <family>Noto Serif CJK JP</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
</fontconfig>
```

#### 实测验证矩阵
执行 `sudo ln -sf /etc/fonts/conf.avail/64-default-cjk-sc.conf /etc/fonts/conf.d/64-default-cjk-sc.conf && fc-cache -f` 后，全场景命中检验：
```text
类型         | 检索 Target / 属性       | 实际匹配字体          | TTC Index
---------------------------------------------------------------------------------
sans-serif | sans-serif:charset=9aa8 | Noto Sans CJK SC    | Index 2 (简体中文)
sans-serif | sans-serif:lang=zh-Hans | Noto Sans CJK SC    | Index 2 (简体中文)
serif      | serif:charset=9aa8      | Noto Serif CJK SC   | Index 2 (简体中文)
serif      | serif:lang=zh-Hans      | Noto Serif CJK SC   | Index 2 (简体中文)
direct     | Noto Sans CJK           | Noto Sans CJK SC    | Index 2 (简体中文)
fallback   | sans-serif:lang=zh-tw   | Noto Sans CJK TC    | Index 3 (繁体中文)
```

---

### 2.15 Fcitx 5 Rime 横向候选栏劫持左右方向键阻断拼音就地编辑

#### 症状
使用 Fcitx 5 + Rime（雾凇拼音）输入长拼音串（例如打出 `nihaoshijie`）时，按下键盘左方向键 `←` 或右方向键 `→`，光标无法在拼音字母之间穿梭以修改或插入字母，而是在下方的横向候选词列表之间高亮跳转。

#### 根因剖析
1. Rime 输入引擎流水线顺序为：`key_binder` -> `speller` -> `punctuator` -> `selector` -> `navigator` -> `express_editor`。
2. 负责处理输入缓冲区内光标移动的是 `navigator` 处理器（支持 `rewind` / `forward` / `left_by_char`）。
3. 但 `selector`（选词处理器）运行在 `navigator` 之前。在 Fcitx 5 默认的横向单行候选条（`Horizontal | Linear`）模式下，`selector` 的 C++ 底层硬编码将 `Left` 绑定为 `PreviousCandidate`，`Right` 绑定为 `NextCandidate`。
4. 候选词框一旦弹出，左右方向键直接被 `selector` 截获消费，导致按键事件根本无法向下传递给 `navigator`。

#### 解决方案
在 `~/.local/share/fcitx5/rime/default.custom.yaml` 的 patch 块中显式覆盖 `selector/linear/bindings`，将选词操作解绑并交由 `Tab` / `Shift+Tab` 处理，从而将 `Left` / `Right` 按键完整释放给 `navigator`：
```yaml
patch:
  # 释放左右键给光标移动：解绑 selector 默认对横向候选条左右键的拦截
  "selector/linear/bindings":
    Shift+Tab: previous_candidate
    Tab: next_candidate
```
执行 `rime_deployer --build ...` 重新编译并 `fcitx5-remote -r` 热重载后，左右方向键即可在拼音字母间随意穿梭，配合 `Backspace`/`Delete` 即可实现拼音就地无损修改。完整配置细节详见专题指南 [`gui-and-ime.md`](gui-and-ime.md) 坑 8。

---

### 2.16 pnpm 12 默认拦截依赖构建脚本与 24 小时发布冷却门禁（个人机 Vibe Coding 直通放行策略）

#### 症状
1. **全局安装弹出审批拦截**：在执行 `pnpm add -g <package>`（例如 `@minimax-ai/code` 或含有原生模块的工具）时，终端被阻塞并弹出交互式选择框：
   ```text
   Ignored build scripts: @minimax-ai/code@0.6.2, better-sqlite3@12.11.1.
   Run "pnpm approve-builds" to pick which dependencies should be allowed to run scripts.
   Choose which packages to build (<space> to select, <enter> to confirm):
   ```
   在自动化脚本或非交互环境中，安装会直接跳过构建脚本导致二进制无法运行，或直接报 `ERR_PNPM_IGNORED_BUILDS` 失败退出。
2. **最新发布的版本无法及时安装**：尝试安装刚刚发布（不足 24 小时或 48 小时）的包或补丁版本时，pnpm 的供应链策略会阻止解析该版本，提示：
   ```text
   passes supply-chain policies (verified ...)
   ```
   导致明明在 npm 网页上看到了最新版本，本地却解析不到。
3. **老版本 Node 下原生模块 postinstall 崩溃**：若本地 Node 仍为 `v22.16.0`（低于 22.19.0），在构建原生扩展（如 `@minimax-ai/code`）时直接报环境不受支持错误：
   ```text
   [MCode] Unsupported Node.js environment.
   Detected: linux-x64, Node 22.16.0 (ABI 127)
   Supported: Node 22.19+, 24, 25, or 26.
   ```

#### 根因剖析
1. **pnpm 11+ 安全模型升级（严格构建拦截）**：
   从 pnpm 11 开始，官方彻底移除了旧版的 `onlyBuiltDependencies`，改为默认实施严格的依赖构建控制（`strictDepBuilds: true`）。任何第三方 npm 包内部附带的 `preinstall`、`install`、`postinstall` 生命周期脚本默认全被拦截，强制要求开发者交互式批准。
2. **供应链防御默认开启（Minimum Release Age）**：
   为防御 npm 恶性供应链投毒攻击（黑客盗取凭据后在几分钟内发布投毒版本），pnpm 11 起默认开启 `minimumReleaseAge: 1440`（1440 分钟，即 24 小时冷却期）。新发布的包必须在公共注册表存在满 24 小时、经由社区安全检测后才被允许解析。
3. **个人电脑开发 vs 生产环境/企业 CI 的诉求冲突**：
   上述安全特性旨在保护严肃的企业级 CI/CD 管道与生产构建。但在**个人主力开发机、专用于敏捷 Vibe Coding / AI Agent 工具链日常开发**的场景下，开发者频繁安装最新版 AI CLI 工具、临时试验原型包，高频的命令行阻塞审批与长达 1~2 天的版本冷冻窗口严重破坏了心流与开发效率。

#### 解决方案与配置规范

##### 1. 运行时基准：标准化 Node 24 LTS
物理机与 WSL 环境统一升级并锁定至 **Node 24 LTS**（如 `v24.21.0`），并在 `~/.shell_common` 导出官方国内镜像以解决清华源历史版本滞后问题：
```bash
# 1. 升级并锁定全局 Node 24
nvm install 24
nvm alias default 24

# 2. 在 ~/.shell_common 中导出国内镜像
export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"
```

##### 2. Vibe Coding 个人机直通放行策略
在个人开发机全局配置中，开启所有构建脚本自动放行，并将发布冷却期置为 0：

* **方法一：通过 CLI 命令一键写入全局配置**：
  ```bash
  # 写入 ~/.config/pnpm/config.yaml
  pnpm config set dangerously-allow-all-builds true -g
  pnpm config set minimum-release-age 0 -g
  ```

* **方法二：直接维护配置文件**：
  1. 在 `~/.config/pnpm/config.yaml`（pnpm 官方全局配置文件，原件在 [`linux-desktop/files/pnpm/config.yaml`](files/pnpm/config.yaml)）：
     ```yaml
     dangerouslyAllowAllBuilds: true
     minimumReleaseAge: 0
     ```
  2. 在 `~/.npmrc` 中同步固化（兼顾读取 npm 格式工具链）：
     ```ini
     registry=https://registry.npmmirror.com/
     dangerously-allow-all-builds=true
     minimum-release-age=0
     ```

* **单项目 / Monorepo 级放行**（仅在特定工程需要时）：
  在项目根目录的 `pnpm-workspace.yaml` 中配置：
  ```yaml
  dangerouslyAllowAllBuilds: true
  minimumReleaseAge: 0
  ```

##### 3. 实测效果
配置后执行 `pnpm add -g @minimax-ai/code`，原生 C++ 扩展与 postinstall 脚本静默全自动编译完成，零交互弹窗、零延迟秒级装毕。

##### 4. 适用边界与不采用时的替代方案

上面的 `dangerouslyAllowAllBuilds: true` 与 `minimumReleaseAge: 0` 属于**可选配置**，只适合"这台电脑仅用于自己的 Vibe Coding / AI Agent 工具链"的场景。共享开发机、团队仓库与任何生产 / CI 环境**不要照搬**：`dangerouslyAllowAllBuilds` 会放行全部依赖的安装脚本，等于主动放弃 pnpm 的供应链防护；`minimumReleaseAge: 0` 则取消了新版本冷却期。

不采用全局直通时，按需逐包放行即可，效果等价但范围可控：

```bash
# 放行单个包的构建脚本（必须写准确的包名，不支持通配）
pnpm add -g --allow-build=better-sqlite3 <package>

# 交互式挑选要放行的依赖
pnpm approve-builds
```

`pnpm approve-builds` 是交互式弹窗，**AI Agent 无法应答、会永久阻塞**，自动化场景只能用 `--allow-build=<具体包名>` 逐个放行。若仍想保留供应链防护，只调低冷却门槛即可，不必置 0：

```bash
pnpm config set minimum-release-age 60 -g
```
