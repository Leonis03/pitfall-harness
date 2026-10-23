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

### 2.5 CLI Agent / 终端快捷键粘贴（Ctrl+V / Alt+V）缺剪贴板后端（`no supported clipboard tool found` 或静默失败）

#### 症状
1. **Go 系 CLI 明确报错**：在 Antigravity 等终端 CLI Agent 中按 `Ctrl+V` 或 `Alt+V` 粘贴剪贴板文本或图片时，终端报出警告：

   ```text
   no supported clipboard tool found (install wl-clipboard or xclip)
   ```

2. **Claude Code 完全不报错，按 `Ctrl+V` 静默无反应**（2026-10-21 实测，Claude Code 2.1.304）：
   - 粘贴截图后，界面上既没有图也没有错误，只有一句 `No image found in clipboard.`；
   - 更隐蔽的是那句主动提示 `Image in clipboard · ctrl+v to paste` **永远不会出现**——读剪贴板的那条命令本身就是死的，监视器根本读不到内容；
   - 文字粘贴同样失效，`Ctrl+V` 粘不出任何文本。

   **没有报错不代表剪贴板是空的**，只代表探测命令没跑成。这是本节最容易误判的地方。

#### 根因剖析
1. **WSL2 与原生 Linux 剪贴板生态差异**：
   - 在 WSL2 环境下，Linux 默认没有独立的物理显示会话与剪贴板服务，剪贴板由宿主 Windows 管理。本仓库通过 `shell_wslfn` 将 `clip` 桥接至 `/mnt/c/Windows/System32/clip.exe`，或者通过 `powershell.exe Get-Clipboard` 跨界传递。
   - 在原生 Linux 物理机桌面下，不存在 Windows 宿主与任何 `.exe` 桥接。终端进程直接依附于本地 X11 或 Wayland 显示服务（Linux Mint 22 默认使用 X11，`$XDG_SESSION_TYPE` 为 `x11`）。
2. **现代 CLI 工具的剪贴板探测机制**：
   - 现代 CLI Agent（如 Claude Code 内置的富文本/图片粘贴模块）在 Linux 平台下检测系统剪贴板时，硬编码依赖系统级 CLI 工具：X11 下调用 `xclip`（或 `xsel`），Wayland 下调用 `wl-clipboard`（`wl-paste` / `wl-copy`）。
   - Linux 发行版的基础桌面镜像通常不会默认预装这些底层 CLI 工具，导致终端交互层触发按键时探测失败。

   Claude Code 把这条探测链硬编码成了下面这几段命令（从 2.1.304 的二进制里原样挖出来的）：

   ```bash
   # 读文字：依次尝试 wl-paste -> xclip -> xsel，第一个退出码为 0 的即采用
   wl-paste --no-newline
   xclip -selection clipboard -o
   xsel --clipboard --output

   # 检测剪贴板里有没有图片（xclip 优先，wl-paste 兜底）
   xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)" || wl-paste -l 2>/dev/null | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"

   # 取出图片字节落盘
   xclip -selection clipboard -t image/png -o > <文件> 2>/dev/null || wl-paste --type image/png > <文件> 2>/dev/null || xclip -selection clipboard -t image/bmp -o > <文件> 2>/dev/null || wl-paste --type image/bmp > <文件>
   ```

   `ctrl+v` 绑定的动作是 `chat:imagePaste`：先读文字，读到非二进制内容就当文本粘；否则跑图片检测，**退出码非 0 就直接判定「剪贴板里没有图」并返回**。X11 会话下 `wl-paste` 兜不了底，`xclip` 一缺，三条命令全灭 → 静默失败。

#### 解决方案
安装原生剪贴板工具链（同时兼顾 X11 与 Wayland 环境）：
```bash
sudo apt-get install -y xclip xsel wl-clipboard
```
- Linux Mint 22 默认 X11 环境下 `xclip` / `xsel` 负责接管剪贴板读写。
- 安装 `wl-clipboard`，使切换到 Wayland 会话后剪贴板命令仍可用。
- **装了 `wl-clipboard` 不会在 X11 下顶掉 `xclip`**：读文字的命令链是「试 `wl-paste` → 试 `xclip` → 试 `xsel`，谁退出码为 0 用谁」，而没有 Wayland 会话时 `wl-paste` 直接非 0 退出，自动落到 `xclip`。
- 若 `apt install` 报 dpkg 锁被占用，见第 2.21 节。

> **[!IMPORTANT] 进程生命周期陷阱（仅限 Go 系 CLI）**：
> 如果 CLI Agent（如 `agy`）在执行 `apt install` 之前就已经在终端中运行，由于 Go 语言底层剪贴板库（如 `atotto/clipboard`）在进程引导的 `init()` 阶段仅探测一次 `exec.LookPath` 并固化在进程内存中，后装的命令无法被当前运行中的进程动态感知，调用 `/copy` 依然会报无可用剪贴板。**必须退出当前会话并重新启动 CLI（例如重启 `agy` 后通过 `/resume` 恢复）**，新进程启动后即可正常访问剪贴板。
>
> **这一条不适用于 Claude Code。** Claude Code 是**每次按键现 spawn** 一次 `xclip`，不做启动期缓存，因此工具链装好后，**当前正在运行的会话立刻就能粘贴，不需要重启**。判断依据：装完 `xclip` 后，在**没有重启过**的 Claude Code 会话里直接执行 `xclip -selection clipboard -t TARGETS -o` 已经能读出内容，而这条命令正是粘贴动作内部执行的那一条。

#### 验证是否真的修好

装完不要凭「没报错」下结论——按第 2.18 节的老办法，**主动制造一个可判定的输入**：

```bash
# 1) 确认工具都在 PATH 里
command -v xclip xsel wl-paste

# 2) 用截图工具 Copy to Clipboard 之后，确认剪贴板里确实有图片
xclip -selection clipboard -t TARGETS -o | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"
# 期望输出：image/png

# 3) 确认能原样取出图片字节
xclip -selection clipboard -t image/png -o > /tmp/clip-check.png && file /tmp/clip-check.png
# 期望输出：PNG image data, 宽 x 高, 8-bit/color RGB, non-interlaced
```

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
  在 `/etc/apt/apt.conf.d/99proxy` 中写入 APT 专属代理（配合 Clash 系客户端的规则模式，国内清华源命中 DIRECT，海外源命中 PROXY）：
  ```apt
  Acquire::http::Proxy "http://127.0.0.1:<proxy-port>";
  Acquire::https::Proxy "http://127.0.0.1:<proxy-port>";
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

### 2.17 Node 大版本升级作废原生模块：ABI 127 → 137，而报错指向 npm

#### 症状

把 Node 从 22 升到 24 之后，原本好好的全局 CLI 一启动就崩：

```text
MCode could not load its native SQLite dependency.
If npm reported blocked install scripts, the installation needs explicit script approval.
Reinstall with the original installer. For npm installations, run:
  npm install --global @minimax-ai/code@0.6.5 --ignore-scripts=false \
    --include=optional --allow-scripts=... --registry https://registry.npmjs.org/

Original error: .../better-sqlite3/build/Release/better_sqlite3.node
was compiled against a different Node.js version using
NODE_MODULE_VERSION 127. This version of Node.js requires
NODE_MODULE_VERSION 137. Please try re-compiling or re-installing
the module (for instance, using `npm rebuild` or `npm install`).
```

#### 根因剖析

`NODE_MODULE_VERSION` 是 Node 的 **ABI 编号，每个大版本一条**：Node 22 是 127，Node 24 是 137。
原生插件（`.node` 文件）是编译产物，构建时的 ABI 被烧进了二进制。
**换 Node 大版本 = 换 ABI = 旧产物当场失效**，跟包本身好不好、装没装对毫无关系。

**报错开头的建议是误导。** 那段 "run npm install --global ... --allow-scripts=" 是
**npm 11 的通用模板**（`allow-scripts` 是 npm 11 的新特性），它假设"包是用 npm 装的、
且 postinstall 被拦了"。而实际情况是：

1. 包是 **pnpm** 装的（全局目录在 `~/.local/share/pnpm/global/v11`）；
2. install script **当初成功跑过**——它产出的二进制对当时的 Node 22 完全正确。

所以照着提示重装、放行构建脚本、开交互式 `approve-builds`，一个都不会有用。
**唯一有效的是为新 ABI 重新产出二进制。**

#### 最贵的一个陷阱：重装"看起来修好了"

本次实际发生的事，值得单独写出来：

- 重装确实跑通了，`mcode` 也能启动了——**但那次重装是在旧的 Node 22 下执行的**。
  那个终端是升级之前就开着的，PATH 里没有 nvm，所以拿到的是 `/usr/bin/node`（v22）。
  于是 postinstall 又产出了一份 **ABI 127** 的二进制，跟旧环境自然匹配，症状消失。
- 新开一个终端拿到的是 Node 24，**同一个错误原封不动地回来**。

也就是说，**"重装一次就好了"这个观测本身可能是假的**，它只证明了当前那个 shell 能用。
判定标准不是"命令能跑"，而是**确认重装是在新 Node 下做的**：

```bash
node -v            # 必须是升级后的版本
node -p process.versions.modules   # ABI 编号，和报错里的那个数对上
```

#### 解决方案

**升级 Node 大版本之后，把所有带原生依赖的全局包装一遍。** 找出来：

```bash
find ~/.local/share/pnpm/global -name '*.node' -newermt '-30 days'
```

最省事的做法是照 2.13 的路子重装一遍（pnpm 会重跑 postinstall）。
只想重编单个模块的话，删掉它的 `build/` 再重跑 install 脚本
（`prebuild-install || node-gyp rebuild --release`），比整体重装快得多。

#### 验证时的一个细节：`require()` 成功不算数

`better-sqlite3` 是**惰性加载** `.node` 的——`require()` 只加载了 JS 包装层，
真正 dlopen 发生在 `new Database()`。所以这样测**会误报成功**：

```bash
node -e "require('better-sqlite3')"     # 两个版本都"成功"，说明不了任何事
```

必须真的建库：

```bash
node -e "const D=require('better-sqlite3'); new D(':memory:').prepare('select 1 as v').get()"
```

#### 为什么值得记

这是 2.13 的**下半场**：2.13 说"装 pnpm 全局包之前必须先装 Node"，
这一条说"**换完 Node 之后必须重装那些带原生依赖的包**"。
两者都发生在同一条链路上，只记住前半句，后半句的坑会在下一次升级时原样复现。

---

### 2.18 Ghostty 静默忽略未知配置键：`shell` 不是键名，`command` 才是

#### 症状

想让 Ghostty 默认用某个 shell，于是在配置里写：

```ini
shell = /usr/bin/zsh
```

配置校验没报错，Ghostty 也正常启动了，**终端里却还是原来的 shell**。
`ghostty +show-config` 里也**根本看不到这一行**。

#### 根因剖析

两件事叠在一起：

1. **键名不对。** Ghostty 1.3.1 里这个键叫 **`command`**，`shell` 不是合法键名。
2. **未知键被静默忽略。** 实测往配置里塞一个纯属捏造的
   `this_key_is_bogus_xyz = 1`，Ghostty 同样**不报错、退出码 0**。

所以"没报错"完全不能作为"配置生效"的证据。而 `+show-config` 也不行——
它只打印**认识的**键，未知键不出现这件事，和"你根本没配"长得一模一样。

#### 解决方案

用 `ghostty +validate-config`，它会指名道姓地报出来：

```text
~/.config/ghostty/config:4:shell: unknown field
```

它还**会报行号**，所以配置文件里加注释、保留可读的说明，不影响校验。

#### 为什么值得记

这是一个通用失败类别：**配置被静默忽略**。验证它的通用手法是
**故意放一个明显不存在的键**，看校验器会不会报——

- 会报 → 校验器可信，"通过"才有意义；
- 不报 → 这个校验器根本不检查，"通过"是空的。

这个手法对任何"配置文件静默失效"的场景都适用，不限于 Ghostty。

---

### 2.19 Clash Verge Rev 在 Linux 上的静默失败面：连接面板空白、托盘失效与源码级取证

#### 症状
1. **「连接 / Connections」面板永远空白**：界面点进连接页，表格一行都没有，但代理本身完全正常——浏览器能翻墙、流量在跑、系统代理模式也开着。刷新页面、重启客户端都不解决。
2. **托盘菜单静默失效**：日志里只有一行 `WARN [Tray] Failed to update tray menu: tray not found`，托盘右键菜单点不动，界面上没有任何提示，客户端也不退出。
3. **「每次更新都出新 bug」的体感**能对上具体数字（见根因剖析第七点），不是错觉。

#### 根因剖析

**一、先证伪代理核心：mihomo 侧完全正常**

手工做一次 WebSocket 握手就能证明：核心返回 `101 Switching Protocols`，随后是实时的连接快照 JSON。所以问题**不在**代理核心、不在订阅、不在系统代理开关。把它当成"客户端坏了"去重装、去换订阅、去反复切系统代理，都是白费功夫。

**二、前端把连接失败吞成了每秒静默重连**

`src/hooks/use-connection-data.ts`：
- `:333` `} catch { scheduleReconnect() }`——裸 `catch`，连接失败后每秒重连一次，`console` 里一个字都不打。
- `:326` 收到 `'Websocket error'` 载荷，同样只是触发重连，不上报。
- `:322` 把 `socket = connected` 放在 `connected.addListener(...)` **之前**。若 `addListener` 抛错，`:333` 的 catch 会安排重连，但此时 `socket` 已非空，`connect()` 会卡在 `:310` 的 `if (socket || connecting) return` 直接返回——**永久死锁，页面永远空**。
- `src/pages/connections.tsx:159` 还带 `errorNotice: false`，连通知都不弹。

**三、可见性门控让"空页面"有第二种成因**

`src/pages/connections.tsx:85` `const pageVisible = useVisibility()`，`:98` 把它作为 `useConnectionData({ enabled: pageVisible })` 传下去。而 `use-connection-data.ts:415-421` 里，`enabled` 为假时 `subscribe` 直接返回 `() => {}`——**WebSocket 根本不会建立**，页面当然是空的。`useVisibility` 内部靠 `appWindow.isVisible()` 与 `document.visibilityState` 两个来源合成可见性，而这两者在 Tauri webview 里可以不一致。

**四、运行时证据：核心侧堆积孤儿连接**

核心的 unix socket 上 ESTAB 共 17 条，其中 **9 条的 peer inode 为 0**（对端已经关闭）且 **Recv-Q 挂着 30 字节永远没人读**；只有 8 条是 GUI 侧仍然活着的连接。GUI 那头关掉了连接，核心侧没收掉——**连接泄漏与静默重连互相喂**。这个"ESTAB 但 peer inode = 0"的形态，是判断"客户端是不是在偷偷重连"的直接证据。

**五、托盘是同一套病：失败被写成了成功**

`src-tauri/src/core/tray/mod.rs`：
- `:158-162` 托盘创建失败 → 记一条 WARN → `return Ok(())`。
- `:199-200` 更新菜单找不到托盘 → 记一行日志 → `return Ok(())`。
- 但同一文件 `:179` 的 `update_click_behavior` 却 `return Err("Failed to get main tray")`——**同一个文件两套失败语义**。
- 托盘是在 `src-tauri/src/utils/resolve/mod.rs:203` 异步创建的，任何并发的菜单更新都会和它竞态，于是"找不到托盘"成了常态路径。

**六、这不是维护者疏忽，是写进政策的**

上游 `AGENTS.md` 规则 4（`:33-39`）原文：

> Tests are justified, not default. Do not add tests, test scaffolding, or speculative defensive code unless the linked issue or stated task demands them. … Bulk test files and defensive programming for hypothetical failure modes are PR bloat, not rigor.

`CONTRIBUTING.md` 同调。实测后果（对着 v2.5.8 源码统计）：

| 维度 | 数字 |
| :--- | :--- |
| 手写代码总量 | 约 86,600 行（`src/` 48,621 + `src-tauri/` 38,596 + `crates/` 2,412） |
| ≥100 行且**零测试**的 Rust 文件 | **48 / 85** |
| 前端测试 | 10 个文件 / 822 行 / **20 个用例**，对着 45,237 行生产代码 |
| `core/tray/mod.rs` | 1010 行、10 个平台分支、**0 个测试** |
| Rust 生产代码 `unwrap()` / `expect(` | **1 个**（`main.rs:33`）/ 3 个；`Result<` 712 处 |
| 前端 `catch` 块 | 186 处，其中裸 `catch {` **32 处**、`.catch(() => {})` **15 处** |

Rust 侧的错误处理其实相当克制（生产代码只有 1 个 `unwrap()`），**问题集中在前端和测试策略上**。

**七、平台偏向 macOS：Linux 只被"编译"，不被"测试"**

- Rust 侧 230 个 `#[cfg]` 平台块：**macOS 156 / Windows 108 / Linux 66**。
- 平台相关单测：windows 5 / macOS 5 / **linux 5**。
- CI 确实有三平台矩阵（`cross_check.yaml:22-30`、`release.yml:186-198`），Linux **会被编译并发布**，但没有任何 Linux 专属功能测试。`core/sysopt.rs` 里 Linux 走的是**结构上不同**的分支（`:775` 的 `cfg(linux)`，对 3 处 `cfg(not(linux))`），天然更容易漂移。
- **churn 量化**：过去一年 1547 个 commit，其中 chore 514 / **fix 506** / refactor 176 / feat 134 / perf 58 / docs 43 / **revert 35**——fix 加 revert 占 **35%**。单版本 changelog 条目数：v2.5.4 **63 条**、v2.5.2 61 条、v2.5.0 18 条、v2.5.5 17 条。
- 真正烂掉的单文件是 `src-tauri/src/core/service.rs`：2719 行（生产代码 2053 行），6 个 `impl` 块，50 个 `#[cfg]`，`trusted_service_evidence()` 重复定义了 3 次（`:291` / `:326` / `:342`），`uninstall_service()` 4 次（`:596` / `:629` / `:688`）。

**八、插件层还有一处结构性脆弱**

Linux 上客户端不用 TCP 控制器，而是走 unix socket：`src-tauri/src/lib.rs:67-68` 把插件配成 `Protocol::LocalSocket`。插件侧 `get_websocket_url` 在这个分支里返回的是一个**假 URL** `ws://localhost/connections`（插件 `mihomo.rs:304`），再由 `client_async(request, stream)`（`mihomo.rs:432`）把它塞进一条真实 unix 连接。HTTP 与 SOCKS5 之外还有第三条 WebSocket 代码路径要维护，而它恰好是 Linux 独有的那条。

#### 重启为什么能"修"好：它是最强的证据，不是解决方案

关掉再打开客户端，连接面板就正常了。**这恰恰是这次排查的决定性证据**，但它不是修复。

重启清掉的是**前端模块级状态**。`src/hooks/use-connection-data.ts` 把连接状态放在模块作用域里（不是 React state，组件卸载也不会带走它）：

| 模块级变量 | 行 | 作用 |
| :--- | :--- | :--- |
| `socket` | `:272` | 当前 WebSocket 句柄 |
| `connecting` | `:273` | 连接中标志 |
| `connectionData` | `:39` | 累积的连接快照 |
| `flushTimer` / `lastFlushAt` | `:41` / `:43` | 节流状态 |

中毒路径正是前面那条：`:322` 先把 `socket = connected` 记下，`:323` 的 `addListener` 随后抛错 → `:333` 的裸 catch 安排重连 → 1 秒后 `connect()` 撞上 `:310` 的 `if (socket || connecting) return` 直接返回。于是**模块里躺着一个"连上了但没装监听器"的句柄**：核心侧照常推送连接快照，前端收到了却没有任何监听者去处理，表格永远空白；而此前每次重试留下的旧句柄再也没被 close，就成了核心侧那 9 条孤儿连接。

重启把 `socket` 复位成 `null`，于是连接重新建立、监听器装上、面板恢复。**在应用内点任何东西都救不回来**：翻页卸载会走 `stopIfIdle` → `closeSocket`，但那只能关掉被 `socket` 记住的那一条，泄漏出去的旧句柄一个都管不着；于是"关掉再开"成了唯一出口。

**重启前后的运行时计数**（同一台机、同一命令）：

| | 重启前 | 重启后 |
| :--- | ---: | ---: |
| 控制器 socket 上 ESTAB 总数 | 17 | 11 |
| 其中 peer inode = 0（对端已关的孤儿） | 9 | 3 |
| 其中 Recv-Q > 0（缓冲区有数据没人读） | **9** | **0** |
| 与 GUI 相连的活连接 | 8 | 8 |

`Recv-Q > 0` 从 9 归零是这张表里最说明问题的一行：那些**被推送了数据却没人读**的僵尸订阅，随进程一起消失了。活连接数前后都是 8，说明核心从头到尾都在正常推送——坏的只是前端那一侧的读取。

**所以"重启一下就好了"要反过来读**：

1. 它是**定位工具**，不是修复。重启能修，说明故障在**进程内存状态**里，不在网络、不在磁盘、不在数据。这个排除法比翻十遍日志都快。
2. 它同时是**证据销毁器**。重启把中毒的模块状态、泄漏的句柄、僵尸订阅全清掉，想复现就得从头再来。**所以顺序必须是：先取证，再重启。**
3. 它是**这个 bug 能活到今天的原因**。失败既不弹提示（裸 catch + `errorNotice: false`），又不留痕迹（没有一行日志），唯一的表现就是"界面空了"。用户只能重启，然后把"重启好了"当成解决方案——于是**永远没有人提 issue**。

第 3 点是重点：一个"重启能修"的问题，危害不在于它需要重启，而在于它**把用户训练成了重启，而不是一个提 issue 的人**。

#### 验证手法
三步都不需要改配置，全部只读：

```bash
# 1) 核心到底正不正常：手工做一次 WebSocket 握手
#    期望看到 101 Switching Protocols，后面跟着实时的连接快照 JSON
S="$HOME/.local/share/io.github.clash-verge-rev.clash-verge-rev/verge-mihomo.sock"
curl -sS -i --unix-socket "$S" \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  http://localhost/connections | head -3
```

```bash
# 2) 连接泄漏：ESTAB 总数 vs 其中"没人读"的条数
#    两者拉开差距 = 客户端在偷偷重连
ss -x | grep "$S" | awk '$2=="ESTAB"'            # 总数
ss -x | grep "$S" | awk '$2=="ESTAB" && $3+0>0' # Recv-Q>0 = 挂在缓冲区没人读
```

```bash
# 3) 排除"其实是代理没走通"：GUI 空白与 CLI 不通是两回事
#    混口的端口同时支持 HTTP 与 SOCKS5，见第 2.2 节
curl -sS -o /dev/null -w "%{http_code}\n" https://github.com/
curl -sS -o /dev/null -x http://127.0.0.1:<proxy-port> -w "%{http_code}\n" https://github.com/
```

第 1 步的"期望 101"是整段排查的**分水岭**：拿到 101 就说明核心无罪，问题在客户端自己的前端逻辑，可以停止折腾网络。

#### 解决方案

**一、给上游提 issue 时，把"静默失败"改写成"有提示的失败"**

最小改动集只有两处，但足以让下一个用户不再踩同一个坑：

| 位置 | 现状 | 建议 |
| :--- | :--- | :--- |
| `src/hooks/use-connection-data.ts:333` | 裸 `catch { scheduleReconnect() }` | 记日志并走一次 `errorNotice`，不要无声重试 |
| `src-tauri/src/core/tray/mod.rs:199-200` | 找不到托盘 → `Ok(())` | 与 `:179` 统一为 `Err(...)` |

注意上游流程约束：`AGENTS.md` 规则 1 要求**先有 issue 再提 PR**，规则 4 不接受"顺手补测试"，规则 8 不接受顺手重构。所以 issue 要写成"Linux 上连接面板静默空白"这样的可复现缺陷，别写成"顺便加测试"。

**二、不打算改上游时的自用绕法**

- 想要连接明细就别用 GUI 的连接页，改从核心控制器直接读（unix socket 无需 secret，实测带错 secret 也返回 200）：
  ```bash
  curl -sS --unix-socket "$S" http://localhost/connections | python3 -m json.tool | head -40
  ```
- 托盘失效不影响代理本身，右键菜单用不了时直接走系统代理开关即可，不必为此重启核心。
- 心跳式排查用上面第 2 步的 `Recv-Q` 计数，比翻日志快。

**三、要不要换 FlClash：先看数据**

以 GitHub release 资产下载量（近 111 / 73 个 release 的合计）为准：

| | FlClash | Clash Verge Rev |
| :--- | ---: | ---: |
| Stars | 57,262 | **152,943** |
| Linux 资产下载量 | 678,997（占其总量 4.0%） | **4,575,161（占 9.6%）** |
| Linux 每 release 平均下载 | 6,117 | **62,673** |
| 用户主体 | Android 51.9% | Windows 52.7% |

**Linux 上 Clash Verge 的下载量是 FlClash 的 6.7 倍，star 是 2.7 倍。** FlClash 的用户主要在 Android，Linux 是它的边角平台。**换过去的理由不是"FlClash 人更多"或"FlClash 更稳"，而是 Clash Verge 的失败不报障**——这一条已经用源码和运行时连接数证实了。

**供应链安全上 FlClash 反而更弱**：Clash Verge 的每个 Linux 资产都带 **minisign 签名**（`.sig`，`untrusted comment: signature from Tauri Secret key`），而 FlClash v0.9.1 **只有 `SHA256SUMS`，没有任何签名**。而 `SHA256SUMS` 与被校验的 `.deb` 同属一个 release、同一个账号——它只能证明"没被中间人改"，不能证明"来自作者"。所以装 FlClash 必须自己校验，方法见下。

**安装第三方 GUI 客户端前的通用校验手法**（一次跑完，三个独立来源互证）：

```bash
# 1) 本地哈希
sha256sum <下载的 .deb>

# 2) 上游 release 页的 SHA256SUMS
curl -sSL -o SHA256SUMS "<release 下载页>/SHA256SUMS"
sha256sum -c SHA256SUMS --ignore-missing

# 3) GitHub API 的 asset digest 字段（与 2) 是不同的来源）
curl -sS "<api>/repos/<owner>/<repo>/releases/tags/<tag>" \
  | python3 -c "import json,sys; [print(a['name'], a.get('digest')) for a in json.load(sys.stdin)['assets']]"
```

三者一致才算通过。有 `.sig` 的项目再补一步签名验证（minisign 需先装工具）。校验用 `<proxy-port>` 之类的占位符，别把真实端口写进任何会进版本库的文件。

**四、迁移注意**

FlClash 是 Flutter 应用（Dart 源码），托盘与系统代理的实现路径和 Clash Verge 完全不同，**配置与订阅要手动迁移**；它的更新节奏由 Android 侧需求驱动，Linux 未必更快。切换前先把 Clash Verge 的订阅链接和规则组导出一份留底。

#### 为什么值得记

这一类问题的通用形状是：**客户端把"我失败了"写成了"我成功了"，于是用户永远看不到错误，只能看到症状。**

Clash Verge Rev 把它同时用在了三个地方——WebSocket 连接失败、托盘创建失败、托盘菜单更新失败——而且还把这套做法写进了 `AGENTS.md` 变成政策（测试默认不写、防御性代码算 PR 膨胀）。所以「升级后冒出新毛病、还不告诉你」的体感不是错觉：**35% 的年度提交是 fix 或 revert，托盘那 1010 行代码一个测试都没有，而 Linux 相关的功能测试只有 5 个。**

排查这类问题的手法是通用的：**先证明下游是好的**（本次是手工握手拿到 101），**再在客户端自己的代码里找那个吞掉异常的地方**（本次是 `use-connection-data.ts:333` 的裸 catch），**最后用运行时计数交叉验证**（本次是核心侧 9 条 peer inode = 0 的孤儿连接）。三步都不需要猜。

"重启一下就好了"之所以能成为跨平台的通用偏方，也是同一个道理：桌面系统里相当大一部分"怪毛病"本质上是**长驻进程里的状态泄漏**，而重启一次性把所有进程状态归零。但这个偏方在本次案例里暴露的东西比它修好的更多——它同时是**最强的定位工具**（故障在进程内存里，不在网络和数据）、**最彻底的证据销毁器**（重启后无法复现）以及**问题长期存活的真正原因**（用户被训练成重启而不是提 issue）。**通用规矩只有一条：重启之前先取证。**

---

### 2.20 更新器的「镜像不可达」横幅是误报：单发 HEAD 探测与 IPv4/IPv6 不对称

#### 症状
Linux Mint 的更新管理器（`mintupdate`）顶部弹出橙色横幅：

```text
Please switch to another mirror
https://mirrors.tuna.tsinghua.edu.cn/linuxmint is unreachable.
```

反直觉的地方在于**同一时刻更新本身在正常下载**：进度条在跑、速率正常、包在往下装。点 OK 忽略后更新照常完成。换源、重启、重新登录都不影响它，或者过一会儿自己就好了。

> 与第 2.3 节是**同一个组件的两种不同故障**：2.3 是"更新器连得慢、超时中断"，这里是"更新器谎报连不上"。两者根因不同、处置也不同，不要混为一谈。

#### 根因剖析

**一、横幅的判定条件写反了方向**

`/usr/lib/linuxmint/mintUpdate/mintUpdate.py:1963` 的 `mirror_check()` 每次刷新时做两次探测：

- 官方源 `http://packages.linuxmint.com/db/version` → `mint_timestamp`
- 当前镜像 `<mirror>/db/version` → `mirror_timestamp`

`:1990-1997` 的分支写得很明确：

```python
if mirror_timestamp is None:
    if mint_timestamp is None:
        # 官方源和镜像都连不上 → 认定没有互联网，什么都不弹
        pass
    else:
        infobar_title = _("Please switch to another mirror")
        infobar_message = _("%s is unreachable.") % mirror_url
```

**只有"官方源成功、镜像失败"才会弹这条横幅。** 所以"国内镜像连不上、国外官方源却能连"不是矛盾，而是**这个判据的必然结果**——它写成了"对照组成功、实验组失败"。两个都失败反而什么都不弹。

`mirror_url` 是从 `/etc/apt/sources.list.d/official-package-repositories.list` 里那行含 `main upstream import` 的 Mint 源解析出来的（去掉末尾斜杠），所以横幅里显示的地址就是源文件里的地址。

**二、探测是单发 HEAD，零重试**

`mintUpdate.py:2030` 的 `get_url_last_modified()`：

```python
c.setopt(pycurl.CONNECTTIMEOUT, 10)
c.setopt(pycurl.TIMEOUT, 30)
c.setopt(pycurl.FOLLOWLOCATION, 1)
c.setopt(pycurl.NOBODY, 1)      # 只发 HEAD
c.setopt(pycurl.OPT_FILETIME, 1) # 靠响应的 Last-Modified 判定
```

**没有重试、没有退避、没有"上次成功过就放行"**。一次抖动 = 一次"镜像不可达"。而且它读的是响应头里的 `Last-Modified`——拿不到这个头就判失败，哪怕 HTTP 状态码是 200。

**三、IPv4/IPv6 的不对称把概率放大了**

| 域名 | 真 AAAA | 走哪一族 |
| :--- | :--- | :--- |
| `mirrors.tuna.tsinghua.edu.cn` | 有（`2402:f000:1:400::2`） | **IPv6** |
| `packages.linuxmint.com` | **没有**（`getent ahostsv6` 只回 v4-mapped 形式） | IPv4 |

家宽的 IPv6 由路由器 RA + DHCPv6 下发，链路一抖，挂掉的偏偏是走 IPv6 的 TUNA 那一次探测；走 IPv4 的官方源安然无恙。**两个条件叠加，正好命中横幅的判据。**

**四、本机实测（横幅弹出时）**

- 官方源探测：`200`，1.16 s
- TUNA 探测：`200`，0.23 s
- 复刻 `get_url_last_modified()` 连打 20 次：**0 失败**，延迟 0.18–2.77 s
- 同一时刻 apt 正通过 IPv6 从同一个 TUNA 稳定下载（连接 ESTABLISHED，速率正常）

也就是说，横幅弹出那一刻，**它要指控的那个镜像正在被它自己的兄弟进程正常下载着**。

#### 验证手法

```bash
# 1) 手动复刻 mintupdate 的那一次探测：HEAD、30 秒超时、零重试
curl -sS -I --max-time 30 https://mirrors.tuna.tsinghua.edu.cn/linuxmint/db/version | grep -i last-modified

# 2) 分开测两族：哪一族在抖，一目了然
curl -4 -sS -o /dev/null -w "v4 %{http_code} %{time_total}s\n" https://mirrors.tuna.tsinghua.edu.cn/linuxmint/db/version
curl -6 -sS -o /dev/null -w "v6 %{http_code} %{time_total}s\n" https://mirrors.tuna.tsinghua.edu.cn/linuxmint/db/version

# 3) 看两个域名有没有真 IPv6（getent ahostsv6 对纯 IPv4 域名会回 ::ffff: 形式）
getent ahostsv6 mirrors.tuna.tsinghua.edu.cn
getent ahostsv6 packages.linuxmint.com

# 4) 决定性的一条：业务此刻正不正常？——证明"不可达"是假的
IP=$(getent ahostsv6 mirrors.tuna.tsinghua.edu.cn | awk 'NR==1{print $1}')
sudo ss -tnp | grep "$IP"
```

第 4 步是分水岭：**同一时刻下载正常 = 这是误报**，该查的是探测路径，不是源。

#### 解决方案

1. **点 OK 忽略即可**，不影响更新本身。横幅是健康检查的结论，不是更新的前置条件。
2. **想让这次探测走 IPv4**：在 `/etc/gai.conf` 里加一条地址选择优先级
   ```text
   precedence ::ffff:0:0/96  100
   ```
   ⚠️ **注意：`apt.conf` 里的 `Acquire::ForceIPv4` 对它无效**——这次探测不走 apt，是 pycurl 直接发的，apt 的配置管不到它。想改探测行为，只能改系统级的地址选择。
3. **换镜像解决不了"单发探测"本身**。换一个源只是把同一个脆弱探测换了个地址去问。
4. **真正的根治在上游**：`get_url_last_modified()` 应当带一次有界重试，或者在探测失败时回退到"上次成功时间戳"做宽限；`:1993` 的分支也应当区分"刚刚失败一次"和"确实长期不可达"。

#### 为什么值得记

通用形状：**健康检查用单发无重试的探测，就会把偶发抖动翻译成"服务不可用"**。更巧的是这里的判据写成了"对照组成功、实验组失败"，于是横幅的内容方向和真实故障方向**正好相反**——它把"国内镜像"标成不可达，而真正脆弱的是那个判定逻辑本身。

可复用的判别法只有一条，看到"某镜像 / 某服务不可达"时：**先确认同一时刻实际业务是否正常。** 业务正常就是误报，此时该做的是去查探测路径（重试？超时？地址族？），而不是去换源、去重装、去改证书、去折腾 DNS。
### 2.21 更新管理器卡死时后台 `aptk` 长期占着 dpkg 锁，导致 apt 安装全线失败

#### 症状

想装一个小包，apt 直接拒绝：

```text
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process <pid> (aptk)
E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?
```

更迷惑的是：**图形更新管理器的窗口已经关了**，锁却还在，apt 依旧全线不可用。
本节对应的就是「更新管理器卡在下载上 → 顺手去装剪贴板工具 → 被 dpkg 锁挡住」这条真实链路（见第 2.5 节）。

#### 根因剖析

1. **持锁的不是窗口，是后台进程。** Linux Mint 更新管理器的后台组件是 `/usr/sbin/aptk`（Python 实现的 apt 封装）。它在抓取包索引、下载 deb 时会持有 dpkg 前端锁 `/var/lib/dpkg/lock-frontend`；窗口只是它的前端，**关窗口不等于终止它**。
2. **下载一卡，锁就不放了。** 本次实测：aptk 的子进程 `/usr/lib/apt/methods/https` 僵在传输上，`etime` 超过 16 分钟、CPU 时间几乎不动（典型 TCP 停滞），锁却一直攥着。释放条件只有 apt 正常结束或进程被杀，**没有超时兜底**。
3. **锁的粒度是全局的。** `apt install` / `apt upgrade` / `dpkg -i` 全都要这把锁。于是一个后台下载卡死，就能让整台机器装不了任何包——包括那些跟更新毫无关系的、随手要装的小工具。

#### 解决方案

先看清是谁在持锁，别去猜：

```bash
sudo fuser -v /var/lib/dpkg/lock-frontend
ps -o pid,etime,cmd -p <上面输出的 PID>
```

`cmd` 里是 `/usr/sbin/aptk` 就说明是更新管理器；再 `pgrep -P <PID>` 看子进程，若挂着 `/usr/lib/apt/methods/https` 且长时间不动，就是它卡在下载上。

三条路，按偏好挑：

1. **等它自己结束**（最省事）：更新管理器跑完 / 正常退出后锁自动释放。本次实测：更新管理器跑完并关闭后锁立刻释放，随后 `sudo dpkg -i` 一次成功。
2. **不想等时的绕行装法**：`apt-get download` **不取 dpkg 锁**，可以先把 deb 拉下来，再解包出二进制直接放进 PATH：

   ```bash
   mkdir -p /tmp/pkg-dl && cd /tmp/pkg-dl
   apt-get download xclip
   dpkg-deb -x xclip_0.13-3_amd64.deb x
   sudo install -m 0755 x/usr/bin/xclip /usr/local/bin/xclip
   ```

   `/usr/local/bin` 在默认 PATH 中排在 `/usr/bin` 前面，优先级更高。解包不写 dpkg 数据库，此时 `dpkg -l xclip` 仍是未安装状态；等锁释放后再补一句正式登记：

   ```bash
   sudo dpkg -i /path/to/xclip_0.13-3_amd64.deb
   ```

3. **确认卡死后直接了结它**：`sudo kill <aptk 的 PID>`。它只是更新管理器的后台组件，杀掉后可以从图形界面重新打开，**不影响任何已安装的软件包**。

#### 为什么值得记

「更新管理器已经关了，apt 还是说锁被占用」这种自相矛盾的现象，几乎总会被误判成「有别的 apt 进程在跑」，于是开始找幽灵进程。**持锁者是后台 daemon，不是窗口**——先把 PID 和它的完整 `cmd` 打出来，再决定是等、是绕行、还是杀。
