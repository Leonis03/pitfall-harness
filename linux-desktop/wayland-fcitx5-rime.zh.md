# 原生 Wayland 桌面上的 Fcitx5 + Rime（KDE Plasma 6）

> **适用环境**：Fedora 44、KDE Plasma 6.7、**Wayland** 会话（`XDG_SESSION_TYPE=wayland`），
> 同时保留 XWayland 供传统 X11 应用使用。
> **适用场景**：安装 Fcitx5 + Rime（雾凇拼音），并尝试让 **原生 Wayland 客户端**
> （Chromium/Chrome、Firefox）与 X11/D-Bus 客户端（Konsole、Dolphin、Plasma 搜索框）都能正常输入中文。
>
> 本文是 [`gui-and-ime.md`](gui-and-ime.md) 的 Wayland 原生版对应文档——后者覆盖的是 X11 路线
> （`im-config`、`~/.xinputrc`、`imsettings`）。两条路线在**Fcitx5 由谁启动、设置哪些环境变量**上
> 截然不同，配错之后只会**一部分**应用失效，这正是它难以定位的原因。
>
> 下文涉及的全部配置，其仓库原件位于 [`files/fcitx5-wayland/`](files/fcitx5-wayland/)：
> `environment`、`fcitx5-config`、`fcitx5-profile`、`default.custom.yaml`、`rime_ice.custom.yaml`。
>
> **状态（2026-11-22）**。之后在同一台机器上又做了两轮核实。第二轮找到了浏览器打不了字的原因：
> **Fcitx5 不是 KWin 的输入法**（[根因四](#根因四fcitx5-不是-kwin-的输入法)）。在 Plasma 的虚拟键盘里
> 选中 Fcitx 5 之后，Chrome 和 Firefox 在原生 Wayland 下都能打中文 —— Chrome 不用加任何参数，
> Firefox 设不设 `GTK_IM_MODULE` 都行。根因一、根因三和 XIM 服务器名成立；根因二无论往哪个方向
> 都不是原因。这台台式机上的 Fedora 已于 2026-11 弃用，本文是一份时间点记录。

---

## 触发本文的现象

终端、Plasma 搜索框、Dolphin 里中文输入都正常，**唯独 Chrome 和 Firefox 不行**。
软件全都装好了；`fcitx5-remote` 显示守护进程活跃、当前输入法是 `rime`；不报任何错。

这种"分裂"本身就是指纹。`fcitx5-diagnose` 会给每个输入上下文标出创建它的前端：

```text
IC [..] program:org.kde.konsole frontend:dbus    cap:e001820832   <- 正常
IC [..] program:dolphin          frontend:dbus    cap:1e001800032   <- 正常
IC [..] program:google-chrome    frontend:wayland cap:1072         <- 坏了
```

`frontend:dbus` 意味着该应用是通过 **D-Bus** 前端接入 Fcitx5 的（`im-fcitx5.so` 的 GTK/Qt 模块路径）；
`frontend:wayland` 意味着应用走的是 **Wayland 输入法协议**（`zwp_input_method_v2`，
由 Fcitx5 的 `libwaylandim.so` 提供）。

也就是说，能用的应用和坏掉的应用**根本不是同一条代码路径**。这就是全部诊断：
**坏掉的应用正是走 Wayland 路径的那些**。这条路径为什么什么也送不出来，最后查明是根因四：
KWin 没有把输入法协议交给 Fcitx5。最先怀疑的根因二并不是原因。

---

## 根因一：整个会话的 `XMODIFIERS=@im=none`

**症状**。Fcitx5 已安装并启动了，可是什么都没继承到可用的输入法。
`fcitx5-diagnose` 报：

```text
**Environment variable XMODIFIERS is "@im=none" instead of "@im=fcitx".**
```

**成因**。Fedora 不用 `im-config`，用的是 **imsettings**。Plasma 会话会执行
`/etc/xdg/plasma-workspace/env/xinput.sh`（指向 `/etc/X11/xinit/xinitrc.d/50-xinput.sh` 的软链），
由它决定用哪个输入法。但这个脚本里有一道**语言代码闸门**：

```bash
_im_language_list="as bn gu hi ja kn ko mai ml mr ne or pa si ta te th ur vi zh"
for i in $_im_language_list; do
    if echo $tmplang | grep -q -E "^$i"; then source "$SYS_XINPUTRC"; ...; fi
done
if [ $_sourced_xinputrc -eq 0 ]; then
    source /etc/X11/xinit/xinput.d//none.conf      # XIM=none, GTK_IM_MODULE=gtk-im-context-simple
fi
```

`LANG=en_US.UTF-8` 时语言代码永远匹配不上，脚本就落到 `none.conf`，
**会话在完全没有输入法的情况下启动**。系统的 `xinputrc` 本身已经指向
`fcitx5.conf`（`/etc/alternatives/xinputrc` -> `/etc/X11/xinit/xinput.d/fcitx5.conf`），
但闸门让**系统级文件根本没被读取**。

**为什么看不见**。桌面照常启动，照常有终端，照常有浏览器。丢的只是输入法。

**修法**。给 imsettings 一份**用户级** `xinputrc`。它在被闸门拦住的系统级文件**之前**读取，
因此能绕过闸门：

```bash
ln -sfn /etc/X11/xinit/xinput.d/fcitx5.conf ~/.config/imsettings/xinputrc
```

不要改系统 `xinputrc`，也不要靠改会话语言代码来绕。

这台机器上的用户级文件最后是一个 207 字节的普通文件，而不是这个软链；里面还带着
`IMSETTINGS_IGNORE_SESSION=*-wayland`、`GTK_IM_MODULE=fcitx` 和 `QT_IM_MODULE=fcitx`。
核实时会话环境里仍然存在的那两个工具链变量（根因二），很可能就是从这两行来的 —— 未验证。

---

## 根因二（未获确认）：全局设置的 `GTK_IM_MODULE` / `QT_IM_MODULE`

> **无论往哪个方向，它都不是原因。** 下面是最初的理解，作为记录保留。去掉这两个变量没有让浏览器
> 打出字；第一轮核实得出的相反结论（"能打字的浏览器恰恰保留着 `GTK_IM_MODULE=fcitx`"）也不成立：
> Fcitx5 成为 KWin 的输入法之后，Firefox 设不设这个变量都能打字。真正的原因是
> [根因四](#根因四fcitx5-不是-kwin-的输入法)。不要把下面的 `/etc/environment` 改动当作浏览器的修法来部署。

**症状**。根因一已修好，`XMODIFIERS` 现在是 `@im=fcitx` —— 终端、Dolphin、Plasma 搜索框都正常了，
**但 Chrome 和 Firefox 依然不行**。

**成因**。在 Wayland 上，原生客户端本该通过 Wayland 输入法协议与 Fcitx5 通信。
而设置 `GTK_IM_MODULE=fcitx` / `QT_IM_MODULE=fcitx`，等于让*工具链*改走 Fcitx5 的
X11 时代模块——在原生 Wayland 客户端上那是错误的路径。Fcitx5 自己在启动时弹出的通知里说得很清楚：

> **Wayland Diagnose** —— 检测到 `GTK_IM_MODULE` 与 `QT_IM_MODULE` 已被设置，
> 且 Wayland 输入法前端工作正常。建议使用 Wayland 输入法前端。

Fcitx5 自己的 `--verbose` 日志也是同一句话：

```text
waylandmodule.cpp:702] Using Wayland native input method protocol: 1
waylandmodule.cpp:706] GTK_IM_MODULE=fcitx
waylandmodule.cpp:707] QT_IM_MODULE=fcitx
```

**这些变量从哪来**。`fcitx5-autostart` 附带 `/etc/profile.d/fcitx5.sh`，每次图形登录都会导出它们：

```bash
if [ ! "$XDG_SESSION_TYPE" = "tty" ]; then
    export INPUT_METHOD=fcitx
    export GTK_IM_MODULE=fcitx
    export QT_IM_MODULE=fcitx
    export XMODIFIERS=@im=fcitx
fi
```

这个文件是软件包提供的，升级就会被覆盖，所以**不要改它**。最初的修法是在会话层面中和掉这些变量、
只保留 `XMODIFIERS` —— 核实发现它既没有完全生效，也没有修好浏览器：

```bash
# /etc/environment
XMODIFIERS=@im=fcitx
```

务必验证**新登录实际继承到的**值——`/etc/environment` 由 PAM 施加，但
`/etc/profile.d/*.sh` 之后仍会对登录 shell 执行：

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin XDG_SESSION_TYPE=wayland \
  bash -c 'for f in /etc/profile.d/*.sh; do [ -r "$f" ] && . "$f"; done;
           echo "GTK_IM_MODULE=[$GTK_IM_MODULE] QT_IM_MODULE=[$QT_IM_MODULE] XMODIFIERS=[$XMODIFIERS]"'
```

核实时这条命令仍然打印 `GTK_IM_MODULE=[fcitx] QT_IM_MODULE=[fcitx]`：软件包提供的 `profile.d`
文件在 `/etc/environment` 之后执行，登录 shell 又拿回了这两个变量。`systemctl --user show-environment`
里也仍然有这两个变量。只有 Fcitx5 守护进程本身启动时不带它们（它的 `/proc/<pid>/environ`
里只有 `XMODIFIERS`，启动警告也不再出现）。

### 第一轮核实（2026-11-21）—— 已被根因四取代

> 这一轮做的时候，Fcitx5 是由 imsettings 启动的，不是 KWin；它得出的结论 ——"是这个变量让浏览器
> 能打字"—— 没能经受住第二轮。保留它，是因为它说明了：对一次真实测量的合理解读，照样可能是错的。

在同一台机器上实测 —— Chrome 156.0.8078.47、Plasma 6.7、fcitx5 5.1.23 —— 由人来打字：

| 客户端 | 从哪里启动 | 进程环境里的 `GTK_IM_MODULE` | `fcitx5-diagnose` 里的输入上下文 | 中文输入 |
| :--- | :--- | :--- | :--- | :--- |
| Firefox，原生 Wayland | 面板 | `fcitx` | `frontend:dbus` 和 `frontend:wayland` | **正常** |
| Chrome，原生 Wayland | 一个会去掉该变量的 shell | 无 | 只有 `frontend:wayland cap:1072` | 无 |
| Chrome，原生 Wayland，加 `--enable-wayland-ime` | 同一个 shell | 无 | 只有 `frontend:wayland cap:1072` | 无 |
| XWayland 下的 Chrome：`GTK_IM_MODULE=fcitx google-chrome --ozone-platform=x11` | shell，只给这个进程设了变量 | `fcitx` | 未记录 | **正常** —— 出现 Rime 候选框 |

这说明：

- 这台机器上真正能把字送出去的，是走 D-Bus 的工具链模块路径，而它只在客户端环境里有
  `GTK_IM_MODULE=fcitx` 时才存在。两个浏览器里都出现了 `frontend:wayland` 上下文；
  只有这一个上下文的 Chrome，什么也打不出来。
- 所以根因二的结论 —— 去掉这两个变量、让应用走原生 Wayland 路径 —— 在这里正好反了。
  最初 Chrome 的症状（`frontend:wayland cap:1072 <- 坏了`）从来没被修好：核实时还是同一行。
- Chrome 那几行和 Firefox 那一行不是严格的对照：Chrome 是从一个没有该变量的 shell 里启动的。
  能把这个变量单独隔离出来的，是 XWayland 那一行。

这一轮留下了两个问题 —— 去掉变量后的 Firefox，以及 KWin 到底有没有把输入法协议交给 Fcitx5。
第二轮把两个都回答了：见[根因四](#根因四fcitx5-不是-kwin-的输入法)。

这里测到的 XWayland 路线依然有效，在用不了虚拟键盘设置的会话里可以作为后备：

```bash
GTK_IM_MODULE=fcitx google-chrome --ozone-platform=x11
```

---

## 根因三：`default.custom.yaml` 的补丁到不了生效的方案

**症状**。Rime 引擎已加载、方案是 `rime_ice`，但 `default.custom.yaml` 里对
`ascii_composer/switch_key` 的补丁**毫无效果** —— Shift 依然上屏首选字，而不是原始拼音。

**成因**。`rime_ice.schema.yaml` **没有 `extends:` 行**，因此它并不继承 `default.yaml`。
`default.custom.yaml` 里的补丁只会作用到 `default.yaml`。某些键看上去仍然生效
（`menu/page_size`、`selector/linear/bindings`），是因为 Rime 会把 `default.yaml`
作为*标准*段落的基底合并进来 —— 但 `ascii_composer` 不在其列。

**取证**。在两个文件里各放一个唯一标记，然后重新编译：

```bash
# default.custom.yaml
patch:
  "menu/marker_in_menu": 111
# rime_ice.custom.yaml
patch:
  marker_only_in_schema: 67890

rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data \
              ~/.local/share/fcitx5/rime/build
grep -n 'marker' ~/.local/share/fcitx5/rime/build/rime_ice.schema.yaml
```

结果：`marker_in_menu` 与 `marker_only_in_schema` 都在编译后的方案里；
而放在 `default.custom.yaml` **顶层**的标记则不在。

**修法**。方案级补丁要放在 `~/.local/share/fcitx5/rime/rime_ice.custom.yaml`，
文件名按**方案 id** 而非方案文件名来定：

```yaml
# ~/.local/share/fcitx5/rime/rime_ice.custom.yaml
patch:
  "ascii_composer/switch_key":
    Caps_Lock: clear
    Shift_L: commit_code
    Shift_R: noop
    Control_L: noop
    Control_R: noop
```

文件名必须是 `<方案id>.custom.yaml`（即 `rime_ice.custom.yaml`）。
Rime 的构建信息会记录它实际消费了哪个文件：

```yaml
__build_info:
  timestamps:
    default.custom: 1792775136
    rime_ice.custom: 1792828172      <- 非零表示该文件被读取
    rime_ice.schema: 1792775133
```

`rime_ice.custom: 0` 意味着这个文件被忽略了 —— 例如错写成
`rime_ice.schema.custom.yaml` 时就是如此。

**另外要验的是编译产物，不是源文件**。引擎加载的是编译后的方案：

```bash
grep -A 6 'switch_key' ~/.local/share/fcitx5/rime/build/rime_ice.schema.yaml
```

---

## 根因四：Fcitx5 不是 KWin 的输入法

由第二轮核实发现（2026-11-22；Plasma 6.7.5、fcitx5 5.1.23、Chrome 156、Firefox 158）。

**症状**。根因一、根因三都已修好，`XMODIFIERS` 也是对的，可 Chrome 在原生 Wayland 下照样打不出字：
它唯一的输入上下文是 `frontend:wayland`。设不设 `GTK_IM_MODULE` 都改变不了这一点。

**成因**。在 Plasma Wayland 上，KWin 只把输入法协议交给被选为**虚拟键盘**的那个程序
（`kwinrc` 里的 `[Wayland] InputMethod`）。这台机器上这个键写的是 Plasma 自己的屏幕键盘
（`org.kde.plasma.keyboard.desktop`），而 Fcitx5 是由 `systemd --user` 下的 XDG 自启动拉起来的。
KWin 从来没把协议交给它，所以客户端的 `frontend:wayland` 上下文虽然存在，却什么也送不出来。

**修法**。系统设置 -> 键盘 -> 虚拟键盘 -> **Fcitx 5**，应用，然后注销再登录。用图形界面改，
不要手写 `kwinrc` —— 和 [`fedora/README.zh.md`](fedora/README.zh.md) 4.8 节是同一个教训。

```bash
kreadconfig6 --file kwinrc --group Wayland --key InputMethod   # 现在写的是 Fcitx 5 的那一项
ps -o args= -p "$(ps -o ppid= -p "$(pgrep -x fcitx5)" | tr -d ' ')"   # kwin_wayland
```

改完之后 XDG 自启动项照样会触发；它启动的那个实例会报 `Unable to request dbus name. Is there
another fcitx already running?` 然后退出，最后只剩 KWin 启动的那一个，所以不必删掉自启动项。

**改完之后的实测**，每个客户端都用全新的配置目录，文本框有焦点：

| 客户端 | 输入上下文（`focus:1`） | 中文 | Shift 切换 | Ctrl+C / Ctrl+V |
| :--- | :--- | :--- | :--- | :--- |
| Chrome，原生 Wayland，不加参数 | `frontend:wayland cap:80072` | 能 | 能 | 能 |
| Chrome，`--enable-wayland-ime` | `frontend:wayland cap:80072` | 能 | 能 | 能 |
| Chrome，`--enable-wayland-ime --wayland-text-input-version=3` | `frontend:wayland` | 能 | 能 | 能 |
| XWayland 下的 Chrome，`GTK_IM_MODULE=fcitx --ozone-platform=x11` | `frontend:dbus` | 能 | 能 | 能 |
| Firefox，原生 Wayland，不设工具链变量 | `frontend:wayland cap:72` | 能 | 能 | 能 |
| Firefox，原生 Wayland，`GTK_IM_MODULE=fcitx` | `frontend:dbus` | 能 | -- | -- |
| Konsole | `frontend:wayland cap:72` | 能 | 能 | 不适用（Ctrl+C 是 SIGINT） |
| Dolphin 地址栏和搜索框 | `frontend:wayland` | 能 | -- | -- |
| KRunner | `frontend:dbus` | 能 | -- | -- |
| 开始菜单（Kickoff）搜索框 | -- | 能，手敲 | -- | -- |

由此可得：

- Fcitx5 成为 KWin 的输入法之后，Chrome 在 Plasma Wayland 上不需要任何参数。第一轮的 XWayland
  路线只是后备，不是修法。
- `GTK_IM_MODULE=fcitx` 对浏览器没有影响：Firefox 设了它（走 D-Bus）和不设它（走 Wayland）都能打字。
  仓库的共用 shell 文件继续导出它，是因为 X11 会话需要。
- Shift 是 Rime 的 `ascii_mode` 切换，按输入上下文分别记忆，所以在一个窗口里切的中英文不会带到下一个窗口。

**自动化测试时要注意**。`ydotool type` 走 uinput，和真实键盘是同一条路径，可以用来驱动这些测试 ——
但只能用人手的速度。默认每键 20 ms，甚至 110 ms，客户端收键都比输入法往返快：Firefox 会丢键，
text-input-v3 下的 Chrome 会把每个字母单独上屏，开始菜单搜索框在第一个键之后就丢了输入法，而手敲时
它完全正常。把按键间隔调到 130-140 ms，上面每个客户端都能正常转换。`xdotool` 在这个桌面上根本打不了字，
见 [`wayland-clipboard-automation.zh.md`](wayland-clipboard-automation.zh.md)。

---

## 安装软件包

Fedora 的包名与 Debian/Ubuntu 不同，其中两个很容易漏：

```bash
sudo dnf install -y \
    fcitx5 fcitx5-autostart fcitx5-chinese-addons \
    fcitx5-gtk3 fcitx5-gtk4 fcitx5-qt5 fcitx5-qt6 \
    fcitx5-rime librime librime-tools brise \
    fcitx5-configtool kcm-fcitx5
```

| Debian/Ubuntu | Fedora | 备注 |
| :--- | :--- | :--- |
| `fcitx5-frontend-gtk3` | `fcitx5-gtk3` | |
| `fcitx5-frontend-gtk4` | `fcitx5-gtk4` | |
| `fcitx5-frontend-qt5` | `fcitx5-qt5` | |
| `fcitx5-frontend-qt6` | `fcitx5-qt6` | |
| `librime-bin` | `librime-tools` | 含 `rime_deployer`、`rime_dict_manager`、`rime_patch` |
| `brise` | `brise` | Rime 官方词典包 |
| `im-config` | *（不存在）* | Fedora 用 **imsettings** —— 见根因一 |

`fcitx5-autostart` 负责把 Fcitx5 注册进会话（**自启动项** + `/etc/profile.d/fcitx5.sh`）。
少了它，Fcitx5 只能手动启动，重启后也就没了。

---

## 部署 Rime 雾凇拼音

`plum` 会装进 **Fcitx5** 的 Rime 目录，与 IBus 的路径不同：

```bash
cd ~/plum
env rime_dir="$HOME/.local/share/fcitx5/rime" \
    ./rime-install iDvel/rime-ice:others/recipes/full
```

`rime_dir` 必须显式指定。不指定时 `plum` 会猜成 **Ibus** 路径
（`~/.config/ibus/rime`），Fcitx5 于是永远看不到这个方案。猜测逻辑在 `plum` 的
`scripts/frontend.sh`：

```bash
fcitx/fcitx-rime | fcitx5-rime)  export rime_dir="$HOME/.local/share/fcitx5/rime" ;;
rime/ibus-rime | ibus-rime)      export rime_dir="$HOME/.config/ibus/rime" ;;
```

编译，然后**验证编译后的方案**（根因三）：

```bash
rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data \
              ~/.local/share/fcitx5/rime/build
```

---

## 验证整条链路

`fcitx5-diagnose` 是把两类客户端区分开的那台仪器。在 Plasma Wayland 上，先查 Fcitx5 是谁启动的
（根因四），再读其余几行：

```bash
kreadconfig6 --file kwinrc --group Wayland --key InputMethod
fcitx5-diagnose | grep -E 'Environment variable XMODIFIERS|Xim Server Name'
fcitx5-diagnose | grep -E 'IC \[' | grep -E 'dbus|wayland'
gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime \
    --method org.fcitx.Fcitx.Rime1.GetCurrentSchema
```

健康的 Wayland 会话应该是：

```text
Environment variable XMODIFIERS is set to "@im=fcitx" correctly.
Xim Server Name from Environment variable is fcitx.
```

浏览器的上下文可能是 `frontend:wayland`（原生）或 `frontend:dbus`（工具链模块，比如在 XWayland 下）；
根因四修好之后两种都能打字。如果一个原生 Wayland 客户端只有 `frontend:wayland`、却打不出字，先查根因四。

**XIM 服务器名是 `fcitx`，不是 `fcitx5`。** Fcitx5 把自己的 XIM 服务器注册在 `fcitx` 这个名字下；
`XMODIFIERS=@im=fcitx5` 是错的，`fcitx5-diagnose` 会直说
（`Environment variable XMODIFIERS is "@im=fcitx5" instead of "@im=fcitx"`）。
Fedora 自带的 `/etc/X11/xinit/xinput.d/fcitx5.conf` 里写的是 `XIM=fcitx5`，
会话脚本据此推导出 `XMODIFIERS=@im=$XIM` —— 所以在原版 Fedora 会话里，
**即便输入法本身是对的，`XMODIFIERS` 仍然是错的**。要验的是**运行时实际值**，而不是文件里的意图。

---

## 为什么值得记

这几个成因看起来都是"输入法装好了却没反应"，而症状（*只有浏览器坏*）又恰好把人引向相反方向。
真正缩小范围的，是读 `fcitx5-diagnose` 里每个输入上下文的 **frontend** 标签：
它把能用的应用与坏掉的应用分开了。

其中两个成因还有第二层误导。根因一让人怀疑输入法软件包，可软件包没问题 ——
是**会话脚本里的语言代码闸门**把它跳过了。根因三让人怀疑补丁文件，可补丁确实应用了 ——
只是应用到了一个方案根本不读的文件上。

而 Fcitx5 启动时弹出的那条通知，读起来就像答案：

> 检测到 `GTK_IM_MODULE` 与 `QT_IM_MODULE` 已被设置，
> 且 Wayland 输入法前端工作正常。建议使用 Wayland 输入法前端。

它指的方向是对的 —— 原生客户端应该走 Wayland 前端 —— 但没指出真正卡住的地方。这个前端只有在 KWin
把输入法协议交给 Fcitx5 之后才能用（根因四），而那是系统设置里的一个选项，不是环境变量。两轮核实都先去查了
变量，第一轮甚至得出了和通知相反的结论。工具给的建议只是假设，要等原本坏掉的客户端真的打出字才算数。
