# 原生 Linux 桌面图形环境与中文输入法/字体配置

> **适用环境**：Linux Mint 22 (Wilma, 基于 Ubuntu 24.04 Noble) / Ubuntu 24.04 / Debian 12 + X11 / Wayland
> **适用场景**：原生 Linux 桌面配置 Fcitx 5 现代化框架、Rime（雾凇拼音）生态、等宽字体（更纱黑体 Sarasa Term SC）、独立打包 Qt5 应用（WPS Office）与 Electron/Chromium 应用（微信桌面版）中文输入调优。
>
> 2026-10-03 在原生 Linux Mint 物理机上逐条复核验证。

---

## 一、踩坑与根因剖析

### 坑 1：全局桌面会话环境变量断层（`~/.xinputrc` 的 `run_im none` 陷阱）

* **症状**：终端中输入法正常（因为 `~/.shell_common` 中导出了环境变量），但在任何从桌面应用菜单、快捷方式、文件管理器双击启动的 GUI 程序中，按下 `Ctrl+Space` 完全唤不出输入法，仅能打出 ASCII 英文字符。
* **根因剖析**：
  1. Linux Mint / Ubuntu 的图形登录管理器（LightDM / Cinnamon / GNOME）通过 `/etc/X11/Xsession.d/70im-config_launch` 初始化会话的输入法环境。
  2. 若系统安装时打开过输入法设置工具，可能在用户主目录下生成 `~/.xinputrc`，其内容被固化为 `run_im none`。
  3. `70im-config_launch` 读取到 `run_im none` 后，**直接跳过** `/usr/share/im-config/data/23_fcitx5.rc`，不导出 `GTK_IM_MODULE`、`QT_IM_MODULE`、`XMODIFIERS`。
  4. 随后运行的 `95dbus_update-activation-env` 将这套空环境变量同步给 systemd `--user` 与 D-Bus 激活总线。导致任何通过桌面启动器（GIO / D-Bus）拉起的用户态 GUI 进程完全缺失输入法环境变量。
* **解决**：
  1. 执行 `im-config -n fcitx5`，强行将 `~/.xinputrc` 固化为 `run_im fcitx5`。
  2. 在 `/etc/environment`、`~/.xprofile` 与 `~/.xsessionrc` 中兜底固化输入法变量。
  3. 运行时通过 `dbus-update-activation-environment` 与 `systemctl --user set-environment` 热注入当前会话。

---

### 坑 2：Qt5 / WPS Office 独立打包运行时输入法丢失（QPlatformInputContext 回退）

* **症状**：在 WPS Office（Writer / Spreadsheets / Presentation）中无法输入中文，按切换热键无响应，只能输入英文字符。
* **根因剖析**：
  1. WPS Office（版本 12.1+）自带独立的 Kingsoft 定制版 Qt5 运行时环境（`/opt/kingsoft/wps-office/office6/`）。
  2. 其输入上下文插件目录下同时存在两个关键插件：
     - `libfcitxplatforminputcontextplugin.so`（支持 `fcitx` 与 `fcitx5`）
     - `libcomposeplatforminputcontextplugin.so`（标准英文 / Compose 回退插件）
  3. 当桌面启动时未向 WPS 传递 `QT_IM_MODULE=fcitx`，Qt 在 `QApplication` 初始化瞬间探测不到指定模块，**自动回退加载 `compose` 插件**。
  4. **不可逆性**：Qt 的 QPlatformInputContext 插件在进程生命周期内只在启动时加载一次，运行期间无法动态热切换。只要启动时丢了变量，当前窗口永久无法输入中文。
* **解决**：
  在 `/usr/bin/wps`、`/usr/bin/et`、`/usr/bin/wpp`、`/usr/bin/wpspdf` 启动脚本入口顶部直接注入 `export XMODIFIERS="@im=fcitx"`、`export QT_IM_MODULE="fcitx"` 等变量；若已有进程在跑，保存后彻底退出重启。

---

### 坑 3：Electron / CEF 原生应用（如微信 4.x）输入法断连与启动包装

* **症状**：原生 Linux 微信（4.x 版，基于 Chromium / CEF / XIM）输入法无法唤起；或者在输入法服务热重启（如 `fcitx5-remote -r`）后输入法彻底失效。
* **根因剖析**：
  1. 微信由桌面软链接 `/usr/bin/wechat -> /opt/wechat/wechat` 启动，二进制文件本身不带环境包裹；若桌面启动器未透传环境变量，Chromium 无法初始化 XIM/GTK 输入上下文。
  2. 若 Fcitx5 守护进程被替换重启，基于旧连接句柄的 Chromium 客户端不会自动重连，必须赋予标准变量并重启进程。
* **解决**：
  将 `/usr/bin/wechat` 改造为携带标准环境变量的 Shell 包装脚本，并同步更新 `wechat.desktop`。

---

### 坑 4：Fcitx5 框架层与 Rime 方案层按键冲突（左 Shift 强制上屏首选字，拦截 commit_code）

* **症状**：用户期望按 Shift 键时将当前打出的英文字母（原始拼音编码）直接送入文本框（`commit_code`），但在方案内无论如何配置，按左 Shift 依然总是上屏第 1 个候选汉字。
* **根因剖析**：
  1. **两层截获机制冲突**：Fcitx5 框架层与 Rime 方案层各自拥有一套按键处理逻辑。
  2. Fcitx5 框架全局配置 `~/.config/fcitx5/config` 的 `[Hotkey/AltTriggerKeys]` 默认将 `0=Shift_L` 绑定为输入法切换热键。
  3. 当用户在输入状态下按下左 Shift 时，Fcitx5 框架层抢先截获该按键，强行将输入法从 `rime` 切换为系统默认键盘（`keyboard-us`）。
  4. 在切换输入法的瞬间，Fcitx5 底层动作是**强制提交当前首选候选词（汉字）**，导致按键根本无法触达 Rime 的 `ascii_composer` 引擎。
* **解决**：
  在 `~/.config/fcitx5/config` 中清空 `[Hotkey/AltTriggerKeys]`（移除 `0=Shift_L`），使 Shift 键完整透传给 Rime，由 Rime 内部配置 `Shift_L: commit_code`。

---

### 坑 5：默认输入法状态为未激活/英文（ActiveByDefault 陷阱）

* **症状**：打开任何新应用、切换窗口或新建标签页时，输入法始终处于未激活（英文字符）状态，每次都要额外按一次 `Ctrl+Space` 才能进入拼音。
* **根因剖析**：
  Fcitx5 全局行为 `ActiveByDefault` 默认为 `False`，新上下文默认挂起输入法。
* **解决**：
  在 `~/.config/fcitx5/config` 的 `[Behavior]` 中设置 `ActiveByDefault=True`，并在 `~/.config/fcitx5/profile` 中将 `rime` 排在首位并设为 `DefaultIM=rime`。

---

### 坑 6：Rime（雾凇拼音）配置覆盖与升级冲突（零侵入 Patch 机制）

* **症状**：直接编辑 `default.yaml` 或 `rime_ice.schema.yaml` 定制候选词数或快捷键后，一旦使用 plum 更新雾凇拼音，所有定制内容被 git pull / install 强行冲刷覆写。
* **根因剖析**：Rime 的方案文件属于上游维护的代码资产，本地定制必须走 Patch 补丁机制。
* **解决**：
  所有候选词数量、翻页键、中英切换逻辑均写在 `~/.local/share/fcitx5/rime/default.custom.yaml` 中，通过 `rime_deployer --build` 编译生成 `build/default.yaml`。

---

### 坑 7：终端中文等宽渲染错位（更纱黑体 Sarasa Term SC vs Mono SC 选型）

* **症状**：终端（Ghostty / GNOME Terminal）中中英文混排、Vim 状态栏、CLI Agent 表格线或制表符错位。
* **根因剖析**：
  普通中文字体或更纱黑体的 `Sarasa Mono SC` 模式在标点符号上采用东亚全角模式，部分 CLI 程序与现代 GPU 终端按单字符单元格计算时会出现不对齐。
* **解决**：
  终端必须选用专为终端优化、半角全角严格遵循 1:2 等宽对齐的 **`Sarasa Term SC`**。

---

### 坑 8：Rime 横向候选栏下左右方向键被 `selector` 拦截，无法在拼音串中移动光标就地编辑

* **症状**：输入长拼音（如 `nihaoshijie`）时，按下左方向键 `←` 或右方向键 `→`，光标无法在拼音字母串中间穿梭以修改或插入字母，而只能在下方横向候选词列表之间跳转。
* **根因剖析**：
  1. Rime 引擎内部流水线顺序为：`key_binder` -> `speller` -> `punctuator` -> `selector` -> `navigator` -> `express_editor`。
  2. `navigator` 处理器原本负责处理输入缓冲区内光标的左右移动（`rewind` / `forward` / `left_by_char`），支持就地修改拼音。
  3. 但 `selector`（选词处理器）运行在 `navigator` 之前。在 Fcitx5 默认的横向单行候选框（`Horizontal | Linear`）模式下，`selector` 的 C++ 底层硬编码将 `Left` 绑定为 `PreviousCandidate`，`Right` 绑定为 `NextCandidate`。
  4. 候选词一旦显示，用户按下的左右方向键直接被 `selector` 截获消费，导致按键事件根本无法向下传递给 `navigator`。
* **解决**：
  在 `~/.local/share/fcitx5/rime/default.custom.yaml` 的 patch 块中，显式覆盖 `selector/linear/bindings`，将选词操作解绑并交由 `Tab` / `Shift+Tab` 处理，从而将 `Left` / `Right` 按键完整释放给 `navigator`：
  ```yaml
  patch:
    # 释放左右键给光标移动：解绑 selector 默认对横向候选条左右键的拦截
    "selector/linear/bindings":
      Shift+Tab: previous_candidate
      Tab: next_candidate
  ```
  执行 `rime_deployer --build ...` 重新编译后，左方向键 `←` 和右方向键 `→` 即可在拼音字母间随意穿梭，配合 `Backspace`/`Delete` 即可实现拼音的原地无损修改。

---

## 二、完整复刻与配置步骤

以下步骤可在原生 Linux Mint / Ubuntu 上依序执行。

### 步骤 1：安装 Fcitx 5 基础套件与前端模块

```bash
sudo apt update
sudo apt install -y fcitx5 fcitx5-chinese-addons \
    fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
    fcitx5-frontend-qt5 fcitx5-frontend-qt6 \
    fcitx5-rime librime-bin \
    fcitx5-config-qt im-config
```

### 步骤 2：全局会话环境接管与防断层配置

```bash
# 1. 切换系统输入法接管框架为 fcitx5（覆写 ~/.xinputrc）
im-config -n fcitx5

# 2. 全局系统级环境变量（PAM 登录阶段加载）
sudo bash -c 'cat << "EOF" >> /etc/environment
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
EOF'

# 3. 用户级 X11 会话环境变量（LightDM / Cinnamon 会话启动阶段加载）
cat << "EOF" > ~/.xprofile
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus
EOF
cp ~/.xprofile ~/.xsessionrc

# 4. 当前运行会话热注入
dbus-update-activation-environment --systemd GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx SDL_IM_MODULE=fcitx GLFW_IM_MODULE=ibus
systemctl --user set-environment GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx SDL_IM_MODULE=fcitx GLFW_IM_MODULE=ibus
```

### 步骤 3：Fcitx 5 框架核心行为调优（默认中文 + 释放 Shift 冲突）

修改 `~/.config/fcitx5/config` 与 `~/.config/fcitx5/profile`：

```bash
mkdir -p ~/.config/fcitx5

# 1. 全局配置：开启默认激活，清空 AltTriggerKeys 避免截胡 Shift
cat << "EOF" > ~/.config/fcitx5/config
[Hotkey]
EnumerateWithTriggerKeys=True
EnumerateForwardKeys=
EnumerateBackwardKeys=
EnumerateSkipFirst=False

[Hotkey/TriggerKeys]
0=Control+space
1=Zenkaku_Hankaku
2=Hangul

[Hotkey/AltTriggerKeys]

[Hotkey/EnumerateGroupForwardKeys]
0=Super+space

[Hotkey/EnumerateGroupBackwardKeys]
0=Shift+Super+space

[Behavior]
ActiveByDefault=True
ShareInputState=No
PreeditEnabledByDefault=True
ShowInputMethodInformation=True
CompactInputMethodInformation=True
DefaultPageSize=5
AutoSavePeriod=30
EOF

# 2. 输入法分组配置：置顶 Rime，作为默认激活输入法
cat << "EOF" > ~/.config/fcitx5/profile
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=rime

[Groups/0/Items/0]
Name=rime
Layout=

[Groups/0/Items/1]
Name=keyboard-us
Layout=

[GroupOrder]
0=Default
EOF

# 3. 解除 Ctrl+Shift+F 简繁转换热键劫持（避免冲突 IDE 全局搜索）
mkdir -p ~/.config/fcitx5/conf
cat << "EOF" > ~/.config/fcitx5/conf/chttrans.conf
# Translate engine
Engine=OpenCC

[Hotkey]
EOF
```

### 步骤 4：部署 Rime 雾凇拼音与 Patch 补丁

使用 Rime 官方包管理器 `plum` 安装雾凇拼音方案：

```bash
# 1. 拉取 plum 与 rime-ice
git clone --depth 1 https://github.com/rime/plum.git ~/plum
cd ~/plum
./rime-install iDvel/rime-ice:others/recipes/full

# 2. 编写全局定制补丁 default.custom.yaml
cat << "EOF" > ~/.local/share/fcitx5/rime/default.custom.yaml
patch:
  # 仅保留雾凇拼音全拼
  schema_list:
    - schema: rime_ice
  # 候选词数量设为 9
  "menu/page_size": 9
  # 增加逗号句号翻页
  "key_binder/bindings/+":
    - { when: paging, accept: comma, send: Page_Up }
    - { when: has_menu, accept: period, send: Page_Down }
  # Shift 键行为：字母直接上屏（commit_code），右 Shift 屏蔽
  "ascii_composer/switch_key":
    Shift_L: commit_code
    Shift_R: noop
    Caps_Lock: clear
  # 释放左右键给光标移动：解绑 selector 默认对横向候选条左右键的拦截
  "selector/linear/bindings":
    Shift+Tab: previous_candidate
    Tab: next_candidate
EOF

# 3. 编译部署 Rime 配置
rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data ~/.local/share/fcitx5/rime/build

# 4. 热重载 Fcitx5
fcitx5-remote -r
```

> **中英切换四大模式（switch_key 参数说明）**：
> - `commit_code`：**输入的拼音字母直接上屏**，并切换为英文状态（打字最自然，不吞字、不上错字）。
> - `commit_text`：**强制把第 1 个候选汉字上屏**，并切换为英文状态。
> - `clear`：**清除当前拼音串**，不向屏幕输出任何字符，直接切换为英文状态。
> - `noop`：**空操作**，按键被忽略，不改变输入法状态。

### 步骤 5：独立打包应用（WPS Office 与微信）启动包装

#### 1. WPS Office（Writer / Spreadsheets / Presentation）
针对 `/usr/bin/wps`、`/usr/bin/et`、`/usr/bin/wpp`、`/usr/bin/wpspdf`，在脚本首行 `#!/bin/bash` 之后注入环境变量：

```bash
for app in wps et wpp wpspdf; do
  sudo sed -i '1a \
# Force Fcitx / Fcitx5 input method module\
export XMODIFIERS="@im=fcitx"\
export QT_IM_MODULE="fcitx"\
export GTK_IM_MODULE="fcitx"\
export SDL_IM_MODULE="fcitx"\
export GLFW_IM_MODULE="ibus"\
' /usr/bin/$app
done
```

#### 2. 原生微信桌面版（Linux 4.x）
将 `/usr/bin/wechat` 替换为包装脚本：

```bash
sudo rm -f /usr/bin/wechat
sudo bash -c 'cat << "EOF" > /usr/bin/wechat
#!/bin/bash
export XMODIFIERS="@im=fcitx"
export GTK_IM_MODULE="fcitx"
export QT_IM_MODULE="fcitx"
export SDL_IM_MODULE="fcitx"
export GLFW_IM_MODULE="ibus"
exec /opt/wechat/wechat "$@"
EOF'
sudo chmod 755 /usr/bin/wechat

# 同步修正 desktop 启动项
sudo sed -i 's|^Exec=.*|Exec=env XMODIFIERS="@im=fcitx" GTK_IM_MODULE="fcitx" QT_IM_MODULE="fcitx" /usr/bin/wechat %U|' /usr/share/applications/wechat.desktop
```

### 步骤 6：更纱黑体（Sarasa Term SC）终端等宽字体安装与配置

```bash
# 1. 安装字体到用户字体目录
mkdir -p ~/.local/share/fonts/sarasa
# 将下载或备份的 SarasaTermSC-*.ttf 放入该目录
cp <path-to-fonts>/SarasaTermSC-*.ttf ~/.local/share/fonts/sarasa/
fc-cache -f ~/.local/share/fonts/sarasa/

# 2. 校验字体注册名称
fc-list : family | grep -i "Sarasa Term SC"

# 3. 配置 Ghostty 终端
cat << "EOF" >> ~/.config/ghostty/config
font-family = "Sarasa Term SC"
font-size = 12
EOF

# 4. 配置 GNOME Terminal 默认 Profile
PROF=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')
gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:$PROF/ use-system-font false
gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles/:$PROF/ font 'Sarasa Term SC 12'
```

---

## 三、验证与自检清单

```bash
# 1. 检查环境变量是否成功注入 GUI 桌面环境
xargs -0 -L1 < /proc/$(pgrep -u $USER -x cinnamon-session || pgrep -u $USER -x gnome-session | head -1)/environ | grep -E 'IM_MODULE|XMODIFIERS'

# 2. 检查 Fcitx5 守护进程状态
fcitx5-remote                     # 2 代表已激活，1 代表非激活
fcitx5-diagnose | grep -A 5 "## Qt:"

# 3. 检查 WPS 运行时的插件加载
# 正确结果必须出现 libfcitxplatforminputcontextplugin.so；若出现 libcompose 则说明变量缺失
grep -i 'platforminput' /proc/$(pgrep -u $USER -f wpsoffice | head -1)/maps

# 4. 检查 Rime 编译状态
grep 'page_size' ~/.local/share/fcitx5/rime/build/default.yaml       # 输出 page_size: 9
grep 'commit_code' ~/.local/share/fcitx5/rime/build/default.yaml     # 输出 Shift_L: commit_code
```

---

## 四、日常使用速查

| 操作 | 快捷键 / 路径 | 说明 |
| :--- | :--- | :--- |
| **激活 / 挂起输入法** | `Ctrl + Space` | 默认启动已全局激活，无需频繁切换 |
| **中英临时切换** | 单按左 `Shift` | 打字过程中按左 Shift：**当前拼音原样上屏并切英文**；空闲时按左 Shift：直接切中英文 |
| **拼音光标穿梭与就地编辑** | `←` 与 `→` 方向键 | 解绑 selector 拦截后，直接在拼音字母间移动，支持 Backspace/Delete 与原地插入修改 |
| **候选词高亮切换** | `Tab` 与 `Shift + Tab` | 替代原本的左右方向键进行横向候选词选择 |
| **候选词上一页 / 下一页** | `-` 与 `=` 或 `,` 与 `.` | 逗号句号翻页已完全打通 |
| **自定义短语（邮箱、手机号等）** | `~/.local/share/fcitx5/rime/custom_phrase.txt` | 格式为 `短语<Tab>编码<Tab>权重`，免部署即刻生效 |
| **字体热重载（Ghostty）** | 在终端内按 `Ctrl + Shift + ,` | 修改 `~/.config/ghostty/config` 后免重启热更新 |
| **重新编译 Rime 方案** | `rime_deployer --build ...` | 修改 `default.custom.yaml` 后重新构建 |
| **热重载 Fcitx5 配置** | `gdbus call ... ReloadConfig` | 无损重载配置，不中断任何正在运行的应用连接 |
