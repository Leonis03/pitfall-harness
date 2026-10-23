# 荣耀平板 Linux 实验室：官方未覆盖的部分与实操踩坑

`com.hihonor.pcengine`（Linux 实验室）在 PRoot 用户态里跑 Ubuntu / Debian 桌面。宿主无 root，
私有目录受 Android 沙箱隔离，`/sdcard` 与容器之间只有一条直通路径。

本目录**不重复** [`agent/skills/honor-linuxlab/`](../agent/skills/honor-linuxlab/SKILL.md)
里已有的内容（架构认知、安全红线、Intent 注入、Debian 卡死、去 Snap 换源、数据保全 SOP）。
这里只放两类东西：

1. **官方知识库与官方助手都没有说的**——逆向结论、绕过校验、PRoot 特有陷阱；
2. **踩坑记录**——每条按「症状 → 根因 → 实证方法 → 处置」写，标注证据等级。

> **证据等级**：每条结论都带标签。`[实测]` = 在本机跑过命令验证过；`[推断]` = 由已知事实
> 推理得出，附推理链；`[未确诊]` = 现象已记录但根因未查明，**不要当结论用**。
> 未标标签的句子视为需要读者自己判断。

---

## 零、这个目录为什么存在：平板是第三类环境

仓库原本只有两类环境的模型，缺了第三类，直接导致过误配。

| | WSL2 | 物理机 Linux 桌面 | 荣耀平板 Linux 实验室 |
| :--- | :--- | :--- | :--- |
| 内核 | Windows 宿主的 WSL2 | 本机 | Android 宿主 + PRoot |
| `127.0.0.1` 指向 | Windows 宿主机（mirrored 模式）或 WSL 自己（NAT） | 本机 | **容器自己** |
| 代理软件装在哪 | Windows 宿主 | 本机 | **哪都没有** |
| 典型故障 | NAT 模式下代理全 refused | Clash 系统代理对 CLI 穿透失效 | 照抄别处的代理配置 → refused |
| 适用文档 | [`../wsl/`](../wsl/) | [`../linux-desktop/`](../linux-desktop/) | 本目录 |

关键差别在第三行：**平板容器里 `127.0.0.1` 就是容器自己**，没有宿主上的代理软件在监听。
把 `shell/files/shell_common` 里的代理段落原样搬进来，必然踩坑——2026-10-10 实测。

`../shell/files/shell_common` 的注释里其实已经写明了「NAT 模式下 127.0.0.1 指向自己、
所有代理请求 refused」，但那段注释属于 WSL 语境，读者在平板上不会往自己身上套。
`../shell/README.md` 又指向 `../wsl/setup/` 步骤 4 去调代理端口，而那一步是按 WSL 写的。

---

## 1. 已有的 skill

[`agent/skills/honor-linuxlab/`](../agent/skills/honor-linuxlab/SKILL.md) 覆盖架构与红线、
Intent 注入通道、Debian `xrdb` 卡死与 `AssetsPatcher` 绕过、Ubuntu 去 Snap 与清华源、
数据保全 SOP。它是给 agent 运行时加载的**可执行流程**。

本目录是给人读的**结论与背景**，两者互链，不复制长文。skill 改了这里要跟着改，反之亦然。

---

## 2. 踩坑

### 2.1 终端代理变量指向死端口：pnpm / npm 的 `tunnel error`

**症状**

```
$ pnpm add -g <pkg>
Error: ERR_PNPM_PACKAGE_MANAGER_ADD_RESOLVE_LATEST
  × Failed to resolve the latest version of <pkg>: Failed to fetch metadata from https://registry.npmmirror.com/
  │ error sending request: client error (Connect): tunnel error: failed to create underlying connection:
  │ tcp connect error: Connection refused (os error 111)

$ npm install -g <pkg>
⠏          # 一直转圈，Ctrl+C 才停
```

**关键判据：浏览器能上网，终端不行。** 这一条把范围从"网络坏了"缩到"终端环境变量坏了"——
Firefox 有自己的代理设置，不读 `http_proxy`。

**根因** `[实测]` 2026-10-10

`$HOME/.shell_common` 第 5 节导出了代理变量，指向一个**没有进程监听的本地端口**。
所有走 HTTP CONNECT 的请求瞬间被拒，pnpm 报 `tunnel error`，npm 则表现为挂起。

**实证方法**（对照实验比单次报错可靠）

```bash
# 1. 端口到底有没有人监听
timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/<proxy-port>' && echo OPEN || echo refused

# 2. 带代理 vs 清代理，同一条命令
npm view <pkg> version                          # 挂住 / refused
env -u http_proxy -u https_proxy -u all_proxy \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    npm view <pkg> version                      # 几秒返回版本号

# 3. 非交互 shell 看不到代理变量，不代表没有
bash -ic 'printf "%s" "$http_proxy"'
```

> `env` 在部分受限 shell 里会被当成特权包装器直接拒掉，用 `printf` 或 `bash -ic` 代替。

**处置**：注释掉 `$HOME/.shell_common` 第 5 节的 `export`，保留 `NO_PROXY` / `no_proxy`
（无代理时完全惰性，重新启用代理时正是靠它做 bypass）。已开着的终端要重开或 `source`。

**必须区分两类故障** `[实测]` 2026-10-14

| 类型 | 特征 | 处置 |
| :--- | :--- | :--- |
| 死代理（配置遗留） | 端口 refused；来源是 shell 配置文件 | 注释导出 / 清变量 |
| 活代理（运行时注入） | 端口有监听；请求 200 | **不要清**，直连和代理都通 |

同一天实测：干净登录 shell 里没有任何代理变量，`npm view` 直连成功；而 agent 进程环境里
带着 `http_proxy=http://127.0.0.1/<proxy-port>`，该端口**有监听**且 `curl -x` 返回 200。
旧的死端口则已经 refused。**注入方尚未定位**（YOYO Claw 还是 Linux Lab），两个观测到的
端口值也不同，像是按会话动态分配。`[未确诊]`

因此**不要无脑清空全部代理变量**——可能把一条可用路径也砍掉。判据是上表第一行那个
`/dev/tcp` 探测。

### 2.2 fcitx5 不出候选词：profile 首项 + 触发键被宿主截胡

**现象** `[实测]` 2026-09-30 会话记录

用户在平板 Linux 实验室里用 fcitx5，`Ctrl+空格` 切不出候选词。

**时间线**（顺序不能倒，这决定了归因）

| 时间 | 事件 |
| :--- | :--- |
| 14:01 | 用户报"我不能用输入法" |
| 14:19 | 用户问怎么让终端全英文、且不影响系统默认语言 |
| 14:21 | 往 `$HOME/.shell_common` 第 6 节写入 `LANG` / `LC_MESSAGES` / `LANGUAGE` |
| 14:24 | 用户问本仓库里有没有"系统设英文导致输入法失效"的记录 |

**14:21 那次 locale 改动是事后动作，不是原因**——故障在 14:01 就报出来了。
这段配置自带注释 `never use LC_ALL=C or LC_CTYPE=C which breaks CJK` 并以
`unset LC_ALL` 开头，说明改动当时已意识到 CJK 风险；14:24 用户回头来仓库找这条记录，
是因为当时仓库里没有。两个问题混在一起问，才让 locale 背了锅。

**根因** `[实测]` 2026-09-30 排障记录，两条叠加

1. **活动组首项错了。** `$HOME/.config/fcitx5/profile` 的 `[Groups/0/Items/0]` 是
   `keyboard-us`，`pinyin` 排在第二。新开窗口或切应用时默认落到英文键盘布局，
   直接输出字母；而且**纯英文键盘模式下单按 `Shift` 不会切出拼音**，必须走触发键。
2. **触发键被宿主吃掉。** 当时缺少全局配置文件 `$HOME/.config/fcitx5/config`，
   fcitx5 只能用出厂默认的 `Ctrl+Space`。而**实体外接键盘上 `Ctrl+Space` 极易被
   Android 宿主拦截成系统语言切换**，事件进不了容器，于是"按了没反应"。
   详见 [2.3](#23-三层输入模型与宿主层独占组合键)。

两条都不在官方知识库覆盖范围内：知识库第 7 号单元「无法输入中文」的排查终点是
"确认有输入光标 + 按 `Ctrl+空格`"，既不知道 profile 首项的存在，也不知道触发键可能被
宿主截胡——照着它做完，故障不会好。

**处置**

```ini
# 1) $HOME/.config/fcitx5/profile —— 把 pinyin 提到活动组首位
[Groups/0]
Name=默认
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=pinyin
Layout=

[Groups/0/Items/1]
Name=keyboard-us
Layout=
```

```
# 2) $HOME/.config/fcitx5/config —— 显式声明触发键，不要依赖出厂默认
[Hotkey/TriggerKeys]
0=Control+space
1=Shift_L
```

改完 `fcitx5-remote -r` 热重载。**两个文件都要改**：只改 profile 不够——首项改成拼音后，
默认仍然处于激活态，但用户按的触发键必须先能进得来。

反向也可以：保持 `pinyin` 在第二位而用 `Shift_L` 切换。**不必强行把拼音设成首项**，
按个人习惯取舍——首项设拼音的好处是新窗口直接可打字，代价是敲英文命令前要先切一下。

---

### 2.3 三层输入模型与宿主层独占组合键

平板 Linux 实验室里跑的不是原生 Linux，是 Android 宿主 + PRoot 容器。
**输入事件要穿过三层，任何一层都可能吞掉你的按键**，而容器内的配置只能改到中间那层。

```text
[第 1 层] Android / MagicOS 宿主        <- 系统级组合键在这里被独占
              |  物理键盘 / 软键盘事件
              v
[第 2 层] X server (:99) + 窗口管理器    <- fcitx5、openbox、lxqt 全在这一层
              |  X11 事件 / XIM
              v
[第 3 层] 应用（qterminal、浏览器、TUI）  <- 应用自己的快捷键表
```

**关键推论：在容器里改任何配置都碰不到第 1 层。** 第 1 层的组合键被吃掉时，
你会看到"应用完全没反应"，但去翻应用配置会发现它写得好好的。

**已实测的宿主层独占组合键** `[实测]`

| 组合 | 现象 | 结论 |
| :--- | :--- | :--- |
| `Ctrl+Shift+V` | 实体键盘按了毫无反应；**Qt 快捷键编辑器里也收不到该事件** | 宿主层独占，容器内无解 |
| `Ctrl+空格` | 实体外接键盘上被当成系统语言切换 | 同上 |

`Ctrl+Shift+C` / `+W` / `+T` / `+N` / `+F` 等其它 `Ctrl+Shift+字母` 组合都正常，
说明宿主不是拦整个 `Ctrl+Shift` 组合，而是点名了具体键位。

**处置**：换键。`Ctrl+Shift+V` 在这台设备上永久不可用，不要再试。
qterminal 里把 Paste Clipboard 改到空闲组合即可（`Ctrl+Shift+Y`、`+D`、`+P` …），
`Shift+Ins` 绑的是 X11 PRIMARY 选择区，鼠标双击选中文字后可直接用，无需改配置。

**必须走应用 GUI 改快捷键** `[实测]` qterminal 只在启动时读快捷键，退出时还会用内存状态
覆写配置文件。手改 `$HOME/.config/qterminal.org/qterminal.ini` 会出现"文件已改、运行中不生效、
关窗口又被冲回去"的三方不一致。剪贴板管理器（Qlipper）同理：它没有设置窗口的命令行入口，
`.desktop` 的 `Exec` 遇单实例直接退出，只能从托盘图标右键进首选项。

#### 三种判别实验，各自能证明什么

排查"某个键没反应"时，选对工具可以一次定位到层：

| 手段 | 命令 / 做法 | 能证明 |
| :--- | :--- | :--- |
| **XTEST 注入** | `xdotool key --clearmodifiers <chord>` | 绕过第 1、2 层直达第 3 层。**能通 = 拦截在前两层**；不通 = 问题在应用或 X |
| **快捷键编辑器** | Qt 应用设置里的 Key 输入框，按该组合 | 编辑框**收不到事件** = 事件没进 X，锁定第 1 层 |
| **换字母对照** | 把绑定改到一个空闲字母，用实体键盘试 | 区分"拦整个组合"还是"点名某个键" |

三者组合使用可以在几分钟内把问题钉到某一层，而不必靠猜。

#### 两个走过的弯路（排查教训）

- **`pgrep` 的匹配式会漏。** 判断"本机有没有剪贴板管理器"时用了
  `clipman|parcellite|gpaste|klipper`，漏掉 `qlipper`，于是误报"本机没有装任何剪贴板管理器"，
  并据此给出了一条不合适的建议。**进程名匹配式一定要先 `ls` 确认候选集，别凭印象拼**。
- **二进制格式的 INI 不要用宽松正则扫。** 判断"哪个配置项绑了快捷键"时，
  脚本从 `items\1\content` 往后 900 字节找关键字，结果跨条目串到了 `items\3`，
  把一条剪贴板历史内容误读成"该条目的快捷键绑定"，进而得出错误归因并建议改配置。
  **Qt 的 `@Variant(...)` 里，位置相邻不代表语义相邻**；确认是绑定就逐字节确认长度前缀，
  确需改动就做等长替换（例如把 13 字节的 `ctrl+shift+v ` 换成同为 13 字节的 `ctrl+shift+b `）。
  不过结论先说：**Qlipper 的全局快捷键是 `Ctrl+Alt+V`**（首选项里可见），
  `ctrl+shift+v` 只是历史里一条被复制过的文本，从未是绑定。

**为什么值得记**：整个排查过程中，我先后把归因指向 Qlipper、再排除 Qlipper 转向 fcitx5、
再转向宿主层，中途给过一次基于错误证据的改配置建议。三次转向的共同原因是
**只用一个观测就下结论**，而不是先问"这个观测能排除什么、不能排除什么"。

### 2.4 `start-desktop.sh` 把 `SHELL` 写死成 bash：改对 `/etc/passwd` 也没用

#### 症状

`usermod -s /usr/bin/zsh <your-linux-user>` 执行成功，`getent passwd <your-linux-user>` 确认登录 shell
已变成 `/usr/bin/zsh`。**重新登录桌面**后再开终端，**依然是 bash**。
在会话里查更直接：

```bash
# 读 lxqt-session 自己的环境，而不是新起的 shell
tr '\0' '\n' < /proc/$(pgrep -x lxqt-session)/environ | grep '^SHELL='
# SHELL=/bin/bash
```

#### 根因剖析

Linux Lab 启动桌面的脚本里有这么一行：

```bash
# /usr/local/bin/start-desktop.sh:29
export SHELL=/bin/bash
```

它在 LXQt 会话**起来之前**执行，整棵会话树（`lxqt-session`、`openbox`、`dbus-daemon`、
面板、`pcmanfm`）全部继承这个值。终端应用又是从桌面会话里启动的，于是继承到的永远是 bash。
qterminal 读 `$SHELL` 来决定启动哪个 shell，它**不查 `/etc/passwd`**。

**这里最容易误判的地方**：很容易怀疑"是不是会话太老、没重新读 passwd"——毕竟上次改完只重启了
会话而不是重启容器。实测**重启桌面会话后依然是 bash**（本次会话中 `lxqt-session` 的启动时间
晚于 `usermod` 的执行时间），所以"重启一下就好"是错的。真正的顺序是
`passwd` 被改了，但 `start-desktop.sh` 的 `export` 发生在**之后**，直接盖掉。

#### 解决方案

两种，按影响面选：

**(a) 只修 qterminal（推荐，范围小，不用重启桌面）**。面板图标的
`Exec` 指向 `/usr/local/bin/linuxlab-qterminal-launch`，这是个包装脚本，
原本只归一化 Qt 缩放和 locale。加两行让它自己从 passwd 解析即可，下次开窗就生效：

```bash
_login_shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
[ -x "$_login_shell" ] || _login_shell=/bin/bash
export SHELL="$_login_shell"
```

**不要写死 `/usr/bin/zsh`**——从 passwd 取的好处是以后再换登录 shell，这个包装脚本不用跟着改。

**(b) 改 `start-desktop.sh:29`**，让整个桌面里所有终端（含将来任何读 `$SHELL` 的程序）
一次性都对。代价是要重启桌面，而且**没确认 Linux Lab 升级或重建容器时会不会把它写回去**，
所以改之前先想清楚。

Ghostty 不受这条影响：它有自己的 `command` 配置键，不读 `$SHELL`。

#### 为什么值得记

登录 shell 这件事有三层，每层都可能单独失效，而**现象完全一样**（终端里是 bash）：
`/etc/passwd`、会话环境变量、终端应用自身的选择逻辑。只改第一层就下结论"没生效"，
往往会误以为是操作失败，然后去反复执行 `usermod`。

---

### 2.5 Linux Lab 里 `chsh` 必然失败：没有 PAM，只能用 `usermod`

#### 症状

```bash
$ chsh -s /usr/bin/zsh
Password: chsh: PAM: System error
```

`/etc/passwd` **没有**任何变化。

#### 根因剖析

`chsh` 靠 PAM 做身份认证，而 PRoot 容器里根本没跑 PAM，于是它在校验阶段就报错退出。
这是容器环境的固有限制，**不是你哪里配错了**，重试多少次都一样。

注意 `chsh` 的报错信息有迷惑性：它先要密码（看着像密码输错了），然后才报
`PAM: System error`，容易让人以为是认证问题。

#### 解决方案

```bash
cp /etc/passwd /tmp/passwd.bak-$(date +%Y%m%d-%H%M%S)   # 改前备份
sudo usermod -s /usr/bin/zsh <your-linux-user>
```

`usermod` 直接改 passwd 文件，不经过 PAM，所以在这类容器里能用。

**这条只解决 `/etc/passwd`**。桌面会话里的终端仍然会是 bash，除非同时处理 2.4——
两件事要一起做，缺一个都不生效。

---

### 2.6 加第三方 PPA：没有 `add-apt-repository`，且所有 keyserver 都不可达

#### 症状

想装没有官方 Ubuntu 包的软件（本机遇到的是 Ghostty，官方不打包 Linux，
Ubuntu 侧走 `ppa:mkasberg/ghostty-ubuntu`）时：

```bash
$ add-apt-repository -y ppa:mkasberg/ghostty-ubuntu
/usr/local/bin/add-apt-repository: Permission denied
```

就算绕过去加源，签名密钥也拿不到：

| 端点 | 结果 |
| :--- | :--- |
| `keyserver.ubuntu.com` | 000（不可达） |
| `launchpad.net` | 000 |
| `keys.openpgp.org` | 000 |
| `ppa.launchpadcontent.net` | **200（通）** |

`apt-get update` 于是报 `NO_PUBKEY 57C8EF455CEAE491`。

#### 根因剖析

**第一层**：`/usr/local/bin/add-apt-repository` 是 Linux Lab 的拦截壳，它 `exec` 到
`/usr/bin/add-apt-repository`，而后者不存在——`software-properties-common` 没装。
拦截壳还要求通过 sudo 提权（`LINUXLAB_ELEVATED_VIA_SUDO=1`）。

**第二层**：包能下载（`ppa.launchpadcontent.net` 通），但**签名密钥的来源全断**。
Launchpad 的 InRelease 里不内嵌公钥，必须去 keyserver 取，而 keyserver 全不可达。

#### 解决方案

手工写 `/etc/apt/sources.list.d/<name>.list`。签名密钥拿不到时只能退让：

```
deb [trusted=yes] https://ppa.launchpadcontent.net/<owner>/<ppa>/ubuntu <series> main
```

**`[trusted=yes]` 是一个主动的安全降级，必须写下来**：传输层的 HTTPS 仍然校验，
系统 CA 信任链完整，跳过的是 **GPG 签名校验**——也就是"这个包确实由 PPA 主人签名"
这一层不再验证。风险面等于"信任这个 HTTPS 源"。keyserver 恢复后应改回正常校验。

#### 为什么值得记

这类妥协**最容易被后续的 agent 当成正常配置继承下去**。仓库里一个不带说明的
`[trusted=yes]`，半年后没人说得清它是权衡还是笔误。写下来的目的不是提供方案，
是让下一个人知道**这是妥协，不是最佳实践**。

顺带一提：`ppa.launchpadcontent.net` 通而 keyserver 不通，说明出问题的不是"网络整体不通"
（那 apt 装什么都装不了），而是**只有少数域名可达**。遇到装不上包时，先确认是哪个域名不通，
再决定是换源还是退让签名校验。

---

## 3. 荣耀官方知识库与官方助手

### 3.1 官方知识库在哪

随 YOYO Claw 安装包内置，账号目录下：

```bash
# linuxlab-user-guide：244 行 / 9 个 ## / 28 个 ###
$ACCOUNT_HOME/skills/linuxlab-user-guide/references/linuxlab-user-guide.md
```

本文档写作时（2026-10-14）的指纹：28 个知识单元，覆盖 9 个章节
（启动与更新、桌面与数据、输入与控制、文件与下载、网络与 VPN、显示音频与剪贴板、
Windows 应用与 Wine、故障安全与反馈、安装请求分流）。

**它会静默更新**（`updated_at` 变而内容不变，或直接换包），且**没有 changelog、没有
版本号、文档内 `grep -c http` 为 0**——无链接、无作者、无来源。用
[`files/linuxlab-kb-fingerprint.sh`](files/linuxlab-kb-fingerprint.sh) 检测内容变化。

> **不要用 `.magicore-seed-manifest.json` 里的 `current_sha256` 做变更检测。**
> 2026-10-14 实测该值与磁盘文件自身的 sha256 不符，四种常见复现方式（单文件、正反拼接、
> 去 CRLF）都算不出来，只能读不能复现。可用的是文件自身的 `sha256sum` + `mtime`。

### 3.2 覆盖度比对

28 个单元逐条与本仓库对照，结论见 [`docs-gap.md`](docs-gap.md)：

| 分级 | 数量 | 含义 |
| :--- | ---: | :--- |
| A | 15 | 官方已完整覆盖，本仓库不必重写 |
| B | 5 | 官方有操作步骤、无机制说明，补一层 |
| C | 6 | 官方零/近零覆盖，本仓库的核心价值 |
| D | 2 | 官方说法已过时或把排查引向死路 |

**最值得记的一条**：官方整节「网络与 VPN」的排查方向是"确认平板本身能联网"，
知识库里 `proxy` / `http` 命中均为 **0**——终端代理变量这一层根本不存在。
而 2.1 那次故障恰恰在这一层。

### 3.3 官方助手（Linux 用机助手）的能力边界

`YOYO Claw → Bot 市场 → Linux 用机助手`。2026-10-14 实测与提问取证：

- **知识库即上述那份**，28 个单元，播种于 2026-09-23，内容自那日起未变。
- **它有 Bash**，能读宿主私有目录、`/proc/mounts`，能跑任意命令——但官方知识库里
  第 25 号单元仍写着"不能直接读取当前设备状态"。**知识库与 agent 实际能力已脱节。**
  `[实测]`
- 官方唯一带日期要求的单元就是第 25 号，说明这条描述自播种起就没更新过。
- 它会给出可复现的原始输出、并主动把未经实测的推断标出来；涉及自身指令时拒绝逐字公布。
  作为**交叉校验源**可用，作为**权威来源**不可。

引用官方说法时**一律标注采集日期**，不要默认它描述的是当前能力。

---

## 4. 变更检测

```bash
bash honor-linuxlab/files/linuxlab-kb-fingerprint.sh           # 打印当前指纹 + 关键词覆盖
bash honor-linuxlab/files/linuxlab-kb-fingerprint.sh --save    # 更新基线
bash honor-linuxlab/files/linuxlab-kb-fingerprint.sh --check   # 有变化则退出码 1
```

YOYO Claw 装在别处时用 `LINUXLAB_CLAW_ROOT=<accounts 目录>` 覆盖默认路径。
脚本输出的账号 UUID 已做掩码，基线文件可安全入库。

---

## 索引

| 文档 | 内容 |
| :--- | :--- |
| [`docs-gap.md`](docs-gap.md) | 官方 28 个知识单元 × 本仓库覆盖度逐条比对 |
| [`../agent/skills/honor-linuxlab/SKILL.md`](../agent/skills/honor-linuxlab/SKILL.md) | 架构与红线、Intent 注入、Debian 卡死、去 Snap 换源、数据保全 SOP |
| [`files/linuxlab-kb-fingerprint.sh`](files/linuxlab-kb-fingerprint.sh) | 官方知识库指纹与变更检测 |
