# Fedora 44 / KDE Plasma 桌面（原生 Linux，Wayland）

同级的 [`../README.md`](../README.md) 记录的是 **Linux Mint 22 / Cinnamon / X11** 那台机器。
这里记录的是 **Fedora 44 / KDE Plasma 6 / Wayland** 那台机器，两者的差别远不止换了发行版名字：
包管理器、文件管理器、终端、剪贴板后端、显示协议，以及桌面自身的代理配置，全都换成了不同的
组件。

Mint 那份文档里的绝大多数踩坑，在**根因层面**依然成立——变的只是执行者。本目录记录这台
Fedora 机器上实测到的环境、已配置并验证过的项目，以及哪些 Mint 踩坑在这里需要换一种写法。

> 范围说明：本机的中文输入法由另一个会话配置，本目录**刻意不覆盖**。Fcitx5 / Rime 属于
> [`../gui-and-ime.md`](../gui-and-ime.md)。
>
> **状态（2026-11-22）**。这台台式机上的 Fedora 装过，已于 2026-11 弃用，因此本目录是一份时间点记录，
> 不会再重新实测。弃用前在这台机器上做的核实确认了 4.1-4.4 与 4.7-4.10；4.5 的耗时在量级上没能复现
> （见该节）。Wayland 下的输入法见 [`../wayland-fcitx5-rime.zh.md`](../wayland-fcitx5-rime.zh.md)
> —— Fcitx 5 成为 KWin 的虚拟键盘之后，浏览器就能打字了（其中的根因四）。这个会话在剪贴板和自动化上做不到
> 什么，见 [`../wayland-clipboard-automation.zh.md`](../wayland-clipboard-automation.zh.md)；这台台式机的
> 磁盘与引导布局见 [`../../os-install/triple-boot-layout.zh.md`](../../os-install/triple-boot-layout.zh.md)。

---

## 一、环境实测

表中每一项都是从运行中的机器上读出来的，不是按发行版名字推断的。

| 项 | 实测值 | 怎么查的 |
| :--- | :--- | :--- |
| 发行版 | Fedora Linux 44，KDE Plasma 桌面版 | `/etc/os-release` |
| 会话 | **Wayland**（`XDG_SESSION_TYPE=wayland`），`LANG=en_US.UTF-8` | `env` |
| 包管理器 | `dnf5` 5.4.6，全部仓库走官方 **metalink** | `dnf --version`、`/etc/yum.repos.d/` |
| 文件管理器 | Dolphin 26.08 | `rpm -qa` |
| 终端 | Konsole 26.08；**Ghostty 1.3.1**，来自 `scottames/ghostty` COPR | `command -v`、`rpm -q ghostty` |
| Shell | **zsh 5.9** 是登录 shell（bash 仍在）；四层分层已部署——见 4.6 | `getent passwd`、`ls ~` |
| Node | v24.22.1，走 nvm（`nvm alias default` = 24） | `node -v`、`~/.nvm/alias/default` |
| pnpm | 12.15.0，独立二进制位于 `~/.local/share/pnpm` | `pnpm -v` |
| Python | 系统 `python3` 3.14.8（**没有 pip 模块**）；`uv` 0.12.24，旁路管理 CPython 3.12.15 | `python3 -V`、`uv python list` |
| 剪贴板后端 | **wl-clipboard** 2.2.1 在；`xclip` / `xsel` **不在** | `command -v`、`rpm -qf` |
| 代理客户端 | FlClash 0.9.1，混合端口 `<proxy-port>`，仅监听 `127.0.0.1` | `ss -tlnp`、`~/.local/share/com.follow.clash/config.yaml` |
| 桌面代理配置 | 三个存储、四个消费方 —— 见 4.3 | `~/.config/kioslaverc`、`gsettings`、`~/.bashrc.d/50-proxy.sh`、`systemctl --user show-environment` |
| 中文字体 | `Noto Sans/Serif/Mono CJK SC` 在，`Droid Sans Fallback` 在，**无更纱黑体** | `fc-list :lang=zh-cn` |
| 系统监视器 | `plasma-systemmonitor`（二进制名**不是** `systemmonitor`） | `rpm -ql plasma-systemmonitor` |
| 终端字体 | `Sarasa Term SC`（终端）与 `Sarasa Mono SC`（编辑器），装在 `~/.local/share/fonts/sarasa/` | `fc-list | grep -c Sarasa` |
| 剪贴板管理器 | CopyQ 17.0.0，热键 `Meta+V` | `copyq --version`、`~/.config/copyq/copyq.conf` |
| 搜索 CLI | `bx` 1.7.0 + 代理 wrapper，两套 API 计划 | `bx --version` |
| SSH | 一把 ed25519 私钥，`~/.ssh/config` 里三个主机 | `ssh-keygen -lf ~/.ssh/id_ed25519.pub` |

---

## 二、Mint 基线在本机上的对应关系

| Mint 基线 | Fedora / KDE 对应物 | 备注 |
| :--- | :--- | :--- |
| `apt` + Mint 双轨 TUNA 源 | `dnf5` + 官方 **metalink** | metalink 本就返回国内镜像，见 4.5 |
| `mintupdate`（图形更新器） | `dnf5` + `dnf5 update` | 没有 `aptk` 后台守护进程，也就没有 dpkg 锁那一类问题 |
| `chsh` + `gnome-terminal-server` 缓存 `SHELL` | 不适用 | Konsole 不是同一套架构；而且本机暂时没有 zsh 可切 |
| GNOME Terminal 丢弃 OSC 52 | Konsole | 实现完全不同，需另行验证 |
| Nemo Action「在 Ghostty 中打开」 | Dolphin 服务菜单 | COPR 包自带一份（`/usr/share/kio/servicemenus/`） |
| 剪贴板用 `xclip` / `xsel` | `wl-clipboard` | 会话是 Wayland，任何探测链都先命中 `wl-paste` |
| `gnome-system-monitor` | `plasma-systemmonitor` | 二进制名不同 |
| `fsearch`（Everything 替代） | 本发行版未打包 | 用 `plocate` + Dolphin 自带索引 |
| `im-config -n fcitx5` | 本目录不覆盖 | 另一个会话 |

---

## 三、已配置并验证的基线

共配置并验证了四项。下面每一行「验证」都是可以重跑的命令，没有任何一条是靠「文件看着对」
得出的结论。

### 3.1 npm 换源到 npmmirror

`~/.npmrc`：

```ini
registry=https://registry.npmmirror.com/
```

本机实测：

| 路径 | 吞吐（5.8 MB 的 tarball） |
| :--- | ---: |
| `registry.npmjs.org` 经代理 | 271 kB/s |
| `registry.npmmirror.com` 经代理 | 747 kB/s |
| `registry.npmmirror.com` 直连 | **2.9 MB/s** |

之后 `npm install typescript@5.4.5` 全程 **1.5 秒**。

### 3.2 pnpm 供应链键

`~/.config/pnpm/config.yaml`（由 [`../files/pnpm/config.yaml`](../files/pnpm/config.yaml) 部署）：

```yaml
dangerouslyAllowAllBuilds: true
minimumReleaseAge: 0
```

这就是 Mint 文档 2.16 节里那个「个人开发机」可选姿态。`pnpm config get` 确认两项都生效。
**不要再把这两个键抄进 `~/.npmrc`** —— 见 4.2。

### 3.3 GNOME 代理 schema

```bash
gsettings set org.gnome.system.proxy mode manual
gsettings set org.gnome.system.proxy.http enabled true
```

host/port 本来就在。注意 schema 的形状：**只有 `http` 子 schema 有 `enabled` 键**，
`org.gnome.system.proxy.https` 与 `...socks` 压根没有这个键。执行
`gsettings set org.gnome.system.proxy.https enabled true` 会直接报 usage 错误。

### 3.4 `sudo` 保留代理变量

`/etc/sudoers.d/proxy`（权限 `0440`，`visudo -cf` 解析通过）：

```
Defaults env_keep += "http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY"
```

没有它，`sudo` 的 `env_reset` 会剥掉代理变量，`sudo dnf` / `sudo git` 就退回直连。已验证：
`sudo env | grep -i proxy` 能列出全部八个变量，`sudo curl https://github.com/` 返回 200。

---

### 3.5 Python：uv，以及 Fedora 特有的一处「拒绝」

系统 `python3` 是 3.14.8，而且**根本没有 pip 模块**，所以 Mint 文档里那条 PEP 668 纪律
（「绝不用 pip 往系统 Python 里装东西」）在本机是天然满足的。旁路管理器用发行版自带的
`uv` 0.12.24。

Fedora 的 `uv` 包带了一份系统级配置，它改了一件事，必须知道：

```toml
# /etc/uv/uv.toml（RPM 包自带）
python-downloads = "manual"
python-preference = "system"
```

于是最顺手的第一次尝试会失败：

```text
$ uv run --python 3.12 python -V
error: No interpreter found for Python 3.12 in virtual environments, search path, or managed installations
hint: A managed Python download is available for Python 3.12, but Python downloads are set to
      'manual', use `uv python install 3.12` to install the required version
```

`uv python install 3.12` 仍然可用（「manual」说的就是这个），它把 CPython 3.12.15 装进
`~/.local/share/uv/python`，并软链到 `~/.local/bin/python3.12`。

镜像配在两处共享工具链会读的位置：

| 文件 | 内容 |
| :--- | :--- |
| `~/.config/uv/uv.toml` | `[[index]] url = "https://pypi.tuna.tsinghua.edu.cn/simple"`，`default = true` |
| `~/.config/uv/.python-version` | `3.12` |
| `~/.config/pip/pip.conf` | `index-url = https://pypi.tuna.tsinghua.edu.cn/simple` |

`[[index]]` 加 `default = true` 这段是关键：它同时覆盖 uv **自己的**解析器（`uv add`、
`uv sync`、`uv run --with`），而 `pip.conf` 的 `index-url` 管不到那些。

之后验证：`uv run python -V` 输出 `Python 3.12.15`——`.python-version` 这个钉子压过
`python-preference = "system"`，所以即使系统 Python 更新，跑的仍是钉住的版本。

### 3.6 终端字体：Sarasa Term SC——用测量而不是印象确认

Fedora 没有 `sarasa` 包，字体来自上游发布归档（`SarasaTermSC-TTF-*.7z` 与
`SarasaMonoSC-TTF-*.7z`）：每个归档各自解到独立空目录，把 `.ttf` 拷进
`~/.local/share/fonts/sarasa/`，再 `fc-cache -f`。

- **终端** → `Sarasa Term SC`（专为终端做的 Term 版）
- **编辑器 / 代码** → `Sarasa Mono SC`

Mint 文档强调半角与全角必须严格 1:2。这件事是可以量的，而不是审美问题，本机用
`fontTools` 量过：

```text
Sarasa Term SC     upem=1000 A=500 CJK=1000 fullwidth-comma=1000 CJK/A=2.0000
Sarasa Mono SC     upem=1000 A=500 CJK=1000 fullwidth-comma=1000 CJK/A=2.0000
```

全角逗号同样是 1000 单位，所以标点也不会把网格撑歪。

**Konsole**（本机两个终端之一）从 profile 里取字体：

- `~/.local/share/konsole/Sarasa.profile` —— profile 本身
- `~/.config/konsolerc` —— 新增一个 `[Desktop Entry]` 组：
  `DefaultProfile=Sarasa.profile`（这个文件同时存着 Konsole 自己的设置，所以要**合并**这一组，
  不要覆盖整个文件）

`Font` 属性用的是 Konsole 的 QFont 序列化格式：

```ini
Font=Sarasa Term SC,11,-1,5,50,0,0,0,0,0
```

即 `family,pointSize,pixelSize,styleHint,weight,style,underline,strikeOut,fixedPitch,rawMode`。

验证它需要两步，因为 Konsole 不通过 DBus 暴露字体属性：

1. **profile 生效了吗？** 问 Konsole 自己：
   ```bash
   gdbus call --session --dest org.kde.konsole-<pid> --object-path /Sessions/1 \
     --method org.kde.konsole.Session.profile      # -> ('Sarasa',)
   ```
2. **profile 里的字体真的生效了吗？** 截运行中窗口的图并放大：拉丁字形是 **Iosevka**
   （`l` 带尾钩、`i` 带衬线底、`1` 带底衬），那正是 Sarasa 的拉丁面。Noto Sans Mono 没有这些
   特征，所以确实是 Sarasa 生效了。

**Ghostty**（本机另一个终端，4.7 节）必须显式写出字体家族，因为它是通过 fontconfig 解析
`monospace` 的——落点是 **Noto Sans Mono**，而不是 Sarasa：

```bash
fc-match monospace              # -> Noto Sans Mono
fc-match "Sarasa Term SC"       # -> Sarasa Term SC
```

因此共享的那个 config 原件里带着一行，让这条比例在 Ghostty 上同样成立：

```ini
font-family = Sarasa Term SC
```

见 [`../files/ghostty/config`](../files/ghostty/config)。

### 3.7 Fontconfig：Fedora 需要的简体规则

规则文件是 [`files/fontconfig/64-default-cjk-sc-fedora.conf`](files/fontconfig/64-default-cjk-sc-fedora.conf)。
Fedora 没有 `/etc/fonts/conf.avail`，所以直接放进
`/etc/fonts/conf.d/64-default-cjk-sc-fedora.conf`（权限 `0644`），再 `fc-cache -f`。

之后的解析矩阵：

| 查询 | 结果 |
| :--- | :--- |
| `fc-match "sans-serif:lang=zh-Hans"` | `Noto Sans CJK SC`（原先是拉丁的 `Noto Sans`） |
| `fc-match "sans-serif:lang=zh-Hans-CN"` | `Noto Sans CJK SC` |
| `fc-match "sans-serif:lang=zh"` | `Noto Sans CJK SC`（原先是拉丁） |
| `fc-match "sans-serif:lang=zh-SG"` / `zh-MY` | `Noto Sans CJK SC` |
| `fc-match "serif:lang=zh-Hans"` | `Noto Serif CJK SC` |
| `fc-match "monospace:lang=zh-Hans"` | `Noto Sans Mono CJK SC` |
| `fc-match "sans-serif:lang=zh-Hant"` / `zh-TW` | `Noto Sans CJK TC` |
| `fc-match "sans-serif:lang=zh-HK"` | `Noto Sans CJK HK` |
| `fc-match "sans-serif:lang=zh-JP"` | `Noto Sans CJK JP` |
| `fc-match "sans-serif"` / `serif` / `monospace` | 不变（`Noto Sans` / `Noto Serif` / `Noto Sans Mono`） |

繁体仍然命中繁体字面，拉丁默认项也没被动——这些规则只补上了缺失的 BCP-47 形式。

### 3.8 剪贴板历史：CopyQ + `Meta+V` 热键

`dnf install copyq` 装的是 CopyQ 17.0.0。有两项设置，都不在 `copyq config` 命令管的范围内：

| 设置项 | 做法 |
| :--- | :--- |
| 随会话自启 | `copyq config autostart true` → 生成 `~/.config/autostart/com.github.hluk.copyq.desktop` |
| `Meta+V` 呼出历史 | `~/.config/copyq/copyq.conf` 的 `[Shortcuts]` 组 |

快捷键的键名是**动作名**，不是某个设置项名：

```ini
[Shortcuts]
Show/hide main window=Meta+V
```

CopyQ 下次写文件时会用 KConfig 的转义规则重新序列化这个键——这正是「动作名被认了、而不是
当成死键存下来」的证据：

```ini
[Shortcuts]
Show\hide%20main%20window=Meta+V
```

注意：Wayland 上全局快捷键需要 GlobalShortcuts portal。portal 不可用时 CopyQ 17 会打印
`Failed to create portal global shortcuts session`，所以热键不灵时先看
`~/.local/share/copyq/*.log`。

### 3.9 Brave Search CLI（`bx`）

用仓库自带的脚本安装，它负责 dnf 分支、把真二进制改名为 `bx-bin`、并写代理 wrapper：

```bash
sh agent/brave-search/files/setup-bx-linux.sh --skip-key
```

两个密钥文件要单独部署，因为它们是**两套不同的配额**：

| 文件 | 计划 | 调用方式 |
| :--- | :--- | :--- |
| `~/.config/brave-search/config.json` | Search（web / news / images / videos / places / context） | `bx web "..." --count 2` |
| `~/.config/brave-search/config-answers.json` | Answers（AI），独立配额 | `bx answers "..." --config ~/.config/brave-search/config-answers.json --no-stream` |

目录权限 `700`，文件 `600`。wrapper 的职责是只为 `bx` 这一个进程清掉 `ALL_PROXY`——`ureq`
解析不了 SOCKS5 代理 URL，会静默退回直连，于是即使代理明明在跑也会失败。已端到端验证：

```bash
bx web "Debian" --count 2 | jq -r '.web.results[]? | "[\(.title)] \(.url)"'
bx answers "What is 2+2?" --config ~/.config/brave-search/config-answers.json --no-stream \
  | jq -r '.choices[0].message.content'
```

每次都要配 `jq`；原始 JSON 一次调用就是几万 token。

### 3.10 SSH

密钥材料与主机配置部署到 `~/.ssh`，权限按常规来：目录 `700`，`id_ed25519` 与 `config` 为
`600`，`id_ed25519.pub` 与 `known_hosts` 为 `644`。

`ssh -G <host>` 不碰网络就能解析配置，是最省事的检查：

```bash
ssh -G p4 | head          # user / port / hostname 来自配置
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

部署当时，三个已配置的端点都没有应答（连接超时）——实例是停的。**部署**与**可达**是两个
问题；SSH 不是 HTTP，不走 `http_proxy`。

### 3.11 CLI 的代理变量是探测出来的，不是写死的

由 [`files/bashrc.d/50-proxy.sh`](files/bashrc.d/50-proxy.sh) 部署到 `~/.bashrc.d/50-proxy.sh`。
本机 `~/.bashrc` 里本来就有「逐个 source `~/.bashrc.d/*`」的钩子，所以别的都不用动。

探测逻辑逐字取自 [`../../shell/files/shell_common`](../../shell/files/shell_common) 第 5 节：
候选端口要**做协议握手**（SOCKS5 `05 01 00` → `05 00`，HTTP `CONNECT` →
`200 Connection established`），只有真正以代理身份应答的端口才会被导出；一个都不应答就
**什么都不导出**，走直连。

这一份与共享文件的差别有两点：只面向 bash，以及探测前先清掉继承来的变量——为什么这一步在
本机不是可选项，见 4.10。

两种状态都实测过（客户端运行 / 客户端停止）：

| 状态 | 导出的变量 | 直连 |
| :--- | :--- | :--- |
| 客户端运行 | `http_proxy`、`https_proxy`、`all_proxy`（含大写别名与 `no_proxy`） | —— |
| 客户端停止 | 只剩 `no_proxy` | 百度 / npm registry / github 均 200 |

`no_proxy` 取 `localhost,127.0.0.1,::1,.local`——主机名写全，不图省事用通配：`127.*`、
`*.local` 这类前缀通配在 `urllib` 里**不**被特殊对待，会把本机流量悄悄送进代理
（见 `tools/python/` 第 1 节）。

---

## 四、本机特有的踩坑

### 4.1 `org.gnome.system.proxy.http enabled` 并不拦 Firefox

**症状。** 桌面代理配在三个地方（4.3），其中 GNOME schema 那份带着 `http enabled = false`。
最自然的读法是「HTTP 代理被关掉了，所以 Firefox 直连」。这个读法是错的。

**根因。** libxul 读 GNOME schema 时只取**模式**和**各协议的 host/port**，根本不查 `enabled`
键；何况这个键只存在于 `http` 子 schema，`https` 与 `socks` 连这个键都没有。

**取证。** 用 headless Firefox 访问一个「不翻墙就访问不了」的站点，并把所有代理环境变量剥掉，
这样唯一剩下的代理来源就是 GNOME schema：

| 组 | GNOME schema | 结果 |
| :--- | :--- | :--- |
| A | `mode=manual`、`http enabled=false`、`https host/port` 已设 | 页面正常渲染 |
| B | `mode=manual`、`http enabled=true` | 页面正常渲染 |
| C | `mode=none` | **没有页面**，加载超时 |

**结论。** 本机浏览器不走代理时，要查的是 `mode`、`host`、`port`，不要盯着 `enabled`。把它
置为 `true` 本身无害、也让配置自洽，但它不是修复手段。

探测脚本见 [`files/ff-proxy-test.sh`](files/ff-proxy-test.sh)。

### 4.2 pnpm 12 不从 `~/.npmrc` 读供应链键

**症状。** Mint 文档 2.16 节给了两种做法：写进 `~/.config/pnpm/config.yaml`，或者「同步固化
到 `~/.npmrc`，兼顾读取 npm 格式的工具链」。同步那份不但没用，还会让每条 npm 命令都打印警告。

**根因。** pnpm 12 只从 `~/.config/pnpm/config.yaml` 读 `dangerouslyAllowAllBuilds` 与
`minimumReleaseAge`。实测把那个文件移走后，`.npmrc` 里明明还留着两个键，`pnpm config get`
两项却都返回 `undefined`。而 npm 11 确实读 `~/.npmrc`，但它不认识这两个键，于是每次都打印：

```
npm warn Unknown user config "dangerously-allow-all-builds". This will stop working in the
next major version of npm. See `npm help npmrc` for supported config options.
```

**结论。** `~/.npmrc` 只保留 registry 那一行；两个键只放 pnpm 的配置文件。

### 4.3 KDE 把桌面代理配置劈成了两半

**症状。** 「终端不走代理」「浏览器不走代理」「一开 TUN 就好了」——三个症状同一个根因：在
KDE 上桌面代理存在两个互不相通的存储里，而且它们都不管 CLI。

| 消费方 | 读哪里 |
| :--- | :--- |
| Firefox | GNOME `org.gnome.system.proxy.*`（libxul 不支持 KDE） |
| Chromium | `~/.config/kioslaverc`（`ProxyType=1`） |
| 终端 / CLI | 都不读 —— 只认环境变量 |
| 会话拉起的 GUI 应用 | `systemctl --user show-environment` |

FlClash 的「系统代理」开关在 KDE 上只写 `~/.config/kioslaverc`，完全不写 GNOME schema。
所以 GNOME 那一半必须手工配，CLI 那一半得靠一个**会探测**的来源（3.11）来给出
`http_proxy` / `https_proxy` / `all_proxy`。

**解法，以及它解释的那个不对称。** 两半的归属不同，所以劈裂表现为**两个浏览器之间的差异**：
GNOME schema 配好、而 FlClash 的「系统代理」开关**关着**时，Firefox 走代理而 Chromium 不走
——Chromium 读 `kioslaverc`，而开关刚把那里的 `ProxyType` 写成了 `0`。把开关**打开**，
让客户端自己持有 `kioslaverc`：它运行时写 `ProxyType=1`，停止时再收回去，于是 Chromium
永远不会被指向一个死端口。GNOME 那一半仍然手工配。

用 [`files/chrome-proxy-test.sh`](files/chrome-proxy-test.sh) 实测过：该脚本在剥掉代理环境变量
的 headless Chromium 里加载一个出口 IP 接口——开关开着时浏览器出口 IP 是代理的，关掉时是直连的。

TUN 模式会把这一切都盖住：它在内核层面接管路由，于是不管应用读哪一份存储都会走代理。所以
「打开 TUN 就好了」不是诊断结论。

### 4.4 Fedora 的 Noto CJK family 名自带 SC 后缀

**症状。** Mint 文档的 fontconfig 规则（2.14 节）是按「family 名是通用的 `Noto Sans CJK`、
简体字形在 TTC index 2」写的。Fedora 的可变字体按地区拆成了独立 family：
`Noto Sans CJK SC`、`Noto Serif CJK SC`、`Noto Sans Mono CJK SC`。于是那条匹配
`Noto Sans CJK` 字符串再改写成 `Noto Sans CJK SC` 的规则**根本匹配不到任何东西**，TTC index
那套推理也不成立。

本机实测：

| 查询 | 结果 |
| :--- | :--- |
| `fc-match "sans-serif:lang=zh-cn"` | `Noto Sans CJK SC`（正确） |
| `fc-match "serif:lang=zh-cn"` | `Noto Serif CJK SC`（正确） |
| `fc-match "sans-serif:lang=zh-Hans"` | **`Noto Sans`（拉丁）** —— BCP-47 形式没有被归一化 |

也就是说，简体这一档本来就是对的，剩下的缺口是现代网页常用的 `zh-Hans`（以及 `zh`）形式，
它会一路跌到拉丁 family。本机同样装了 `Droid Sans Fallback`，所以 Mint 文档里那条「旧字形」
的风险在这边依然存在。

### 4.5 dnf5 与 metalink

**实际发生了什么。** Fedora 系仓库用的是 `metalink=`，dnf 先取一份 metalink 文档，再从其中
列出的镜像下载。实测：`fedora-44` 的 metalink 返回的就是国内镜像（qlu、nyist、tuna、jlu、
ustc），且直连可达。

**为什么仍然值得管。** metalink 换来的两样东西都不是免费的：包数据到达之前多一次往返，以及
镜像列表里可能混进海外节点。第三方仓库的行为则各不相同：`dl.google.com` 直连（0.35 s）比
经代理（0.42 s）更快，PyCharm 那个 COPR 也是直连更快（2.2 s vs 经代理 5.8 s）。2026-11-21 重测
（每项取三次 `repomd.xml` 的中位数）：`dl.google.com` 直连 0.28 s、经代理 0.92 s；PyCharm COPR
直连 1.22 s、经代理 1.65 s。直连依旧更快，但 PyCharm 的差距是 1.35 倍而不是 2.6 倍 —— 上面的
数字只能当作一次采样。

**结论。** 把 `baseurl` 钉到国内镜像是一个合理但可选的改进，它不是 Mint 文档里 apt 那种
16 倍量级的收益。

### 4.6 四层 Shell 分层已于 2026-10-25 落到本机

Mint 与 WSL 两台机器共用一套四层 Shell 分层（`~/.zshenv`、`~/.shell_wslfn`、
`~/.shell_common`、`~/.zshrc` / `~/.bashrc`），以 `~/.shell_common` 作为环境变量的唯一真相
来源。本机此前一个都没有：只装了 bash，四个文件全部缺失。

**2026-10-25 起四个文件都在了**，是从仓库的 `shell/files/` 手工复制过来的，登录 shell 也换成了 zsh。
[`../../linux-bootstrap/`](../../linux-bootstrap/) 的第 7 阶段现在会自动完成同样的复制 —— 但与
手工部署不同，它也会替换 `~/.bashrc`（先备份），所以下表描述的是这台机器，而不是脚本会做的事。

| | 之前 | 之后 |
| :--- | :--- | :--- |
| shell | 只有 bash | zsh 5.9；`chsh` 切到 `/usr/bin/zsh`，并更新了会话快照 |
| `~/.zshenv` `~/.shell_wslfn` `~/.shell_common` `~/.zshrc` | 全部缺失 | 从仓库原件部署 |
| `~/.bashrc` | 本机原来那个 | **未改动**——bash 仍读自己的 rc 文件与自己的 `~/.bashrc.d` 钩子 |

部署过程里有三个细节，每一条都很容易做错：

1. **单靠 `chsh` 对已经在跑的桌面没有作用。** 它改的是 `/etc/passwd`，但从面板启动的终端
   继承的是会话环境，而那份快照是在改动之前取的。真正让已运行的会话用上新 shell 的，是
   `systemctl --user set-environment SHELL=/usr/bin/zsh` 与
   `dbus-update-activation-environment --systemd SHELL=...`——与 4.10 是同一套机制，同样是
   「看不见的来源赢了」。
2. **那份共享文件是给 X11 桌面写的，而问题并不在这两个变量上。** 它第 7 节无条件导出
   `GTK_IM_MODULE` 与 `QT_IM_MODULE`。部署副本按 Fcitx5 启动时的建议，在 Wayland 会话里
   去掉了它们，浏览器却并没有因此能打字。后来的两轮核实找到了真正的原因：Fcitx5 不是 KWin
   的输入法。把 Fcitx 5 选为虚拟键盘之后，Chrome 和 Firefox 设不设这两个变量都能打字 —— 见
   [`../wayland-fcitx5-rime.zh.md`](../wayland-fcitx5-rime.zh.md) 的根因四。会话快照也并没有被
   清理：`systemctl --user show-environment` 里仍然有这两个变量。仓库原件在所有会话类型上都
   继续导出它们。
3. **部署的 `~/.shell_common` 是仓库原件的一个草稿版本，外加一处本机改动。** 草稿版本会在
   Wayland 上去掉工具链输入法变量（第 2 条）。本机改动是给 `VISUAL="code --wait"` 包了一层
   `command -v code` 检查并带回落 —— 因为部署时（12:13）还没装 VS Code，而 `$VISUAL` 指向
   不存在的命令会让不带 `-m` 的 `git commit` 失败。VS Code 是 25 分钟后装上的（`rpm` 安装
   时间 12:38），所以这层包装现在解析出的就是 `code --wait`，什么也没改变。最终的仓库原件与
   部署副本的差别不止这一处：它保留输入法变量，并且在探测前清掉旧的代理变量（4.10）。

bash 那一半保留着自己的历史，也仍然是较弱的一半：

- **代理端口曾经是硬编码的。** `~/.bashrc` 里直接写死了 `<proxy-port>`。代理客户端没运行时，
  所有 CLI 请求都指向一个死端口并失败。共享的 `~/.shell_common` 是先用协议握手探测候选端口，
  没有端口应答就什么都不导出。**这一半现已修好**：探测脚本以 `~/.bashrc.d/50-proxy.sh` 部署
  （3.11），写死的导出已删除。
- **rc 文件被安装脚本污染过。** `~/.bashrc` 尾部仍带着 `pnpm setup` 与 nvm 各自追加的代码块
  ——与 Mint 文档 2.4 节症状相同。四层部署刻意没有动它。

注意 `~/.bashrc` 里已经有「若 `~/.bashrc.d` 存在则逐个 source」的钩子，那正是把共享环境层
移植成 bash 版的天然落点——而它仍然是那个落点，因为 bash 读的还是自己的 rc 文件，不是共享那份。

---

### 4.7 Fedora 上的 Ghostty 来自 COPR，不是官方仓库

**症状。** Mint 基线的结尾是「用 Ghostty」，而最直接的那一步查不到东西：
`dnf list --available ghostty` 没有结果，因为 Fedora 44 官方仓库不收录它。读得太快，
就会得出「Ghostty 在 Fedora 上装不了」。

**根因。** 包是有的，只是在第三方 COPR 里，而不在 Fedora 自家仓库：

```bash
dnf copr enable scottames/ghostty
dnf install ghostty
```

装上的是 `ghostty-1.3.1-4.fc44.x86_64`（vendor：`Fedora Copr - user scottames`）。

**两条值得记下的死路，因为它们都把人引向同一个错误方向。**

1. **Flathub 根本没收录 Ghostty——这和「被过滤掉」不是一回事。** 本机
   `flatpak search ghostty` 与 `flatpak update --appstream` 双双超时，Flathub API 对
   `com.mitchellh.ghostty` 返回 `{"detail":"App not found"}`。容易顺手推出的是：本机 flathub
   远端是 *filtered* 镜像（`flatpak remotes` → `flathub system,filtered`），所以它被挡住了。
   并没有：`/usr/share/flatpak/fedora-flathub.filter` 只有一行 `# Unfiltered`，这个远端
   什么都没过滤。真正的原因更简单——Ghostty 从来没有发布到 Flathub 上。Flathub 的 appstream
   里根本不存在 `com.mitchellh.ghostty` 这个 component，API 那句 "App not found" 说的就是
   这件事。
2. **上游的发布资产里没有 Linux 二进制。** v1.3.1 的资产是 macOS zip、源码 tarball 与 wasm
   产物；按常见命名探测（`ghostty-1.3.1.linux-x86_64.tar.xz` 之类）全部 404。上游只发布
   macOS 二进制，其余平台一律由打包者负责——上面那个 COPR 就是其中之一。

**还有第三条路。** 上游仓库里带着 Flatpak manifest（`flatpak/com.mitchellh.ghostty.yml`），
所以 `flatpak-builder` 可以从源码构建。注意仓库已迁到 `ghostty-org` 组织：`mitchellh/ghostty`
的路径现在全部 404，manifest 也不例外。

**顺带一条值得记住的发现。** 排查过程中 GitHub API 表现异常：`/releases/latest` 返回 404，
`/releases?per_page=30` 只返回一个 `tip` 预发布，而**发布 Atom feed** 里却列出了真实
tag（`v1.3.1`、`v1.3.0`、`v1.2.3`……）。当「最新版本」API 看起来不对时，先去查 feed，
再下「这个项目没有发布」的结论。

**结论。** 本机已装 Ghostty 1.3.1，它是与 Konsole 并存的第二个可用终端。Mint 那条笔记真正的
重点——严格的 1:2 终端字体——对它同样成立，但前提是显式指定字体：Ghostty 通过 fontconfig
解析 `monospace`，落到的是 **Noto Sans Mono**，而不是 Sarasa。因此
[`../files/ghostty/config`](../files/ghostty/config) 这个原件需要补一行 `font-family`，
才能拿到与 Konsole profile 同等的保证（3.6）。

**Mint 的安装命令在这里不适用。** `linux-desktop/README.md` 第 2.x 节用
`mkasberg/ghostty-ubuntu` 的 `install.sh` 装 Ghostty，而它取的是 **.deb**——那是 Ubuntu/Mint
专用路径。在 Fedora 上适用的是上面那条 COPR。

**另外，Nemo Action 在本机已有现成的 Dolphin 对应物。** Mint 基线的
`files/nemo/actions/*.nemo_action` 是 Nemo 专用的，拷到 Dolphin 下不起作用；但 COPR 包自带
一份 Dolphin 服务菜单，在 `/usr/share/kio/servicemenus/com.mitchellh.ghostty.desktop`
——「Open Ghostty Here」，执行 `ghostty --working-directory=%F`。不必再拷贝那些 Nemo 文件。

### 4.8 KDE 的自定义快捷键不能靠盲写

**症状。** Mint 笔记把 `Ctrl+Shift+Esc` 绑到 `gnome-system-monitor`。KDE 上的二进制是
`plasma-systemmonitor`（PATH 里没有 `systemmonitor`），而手工往 `~/.config/kglobalshortcutrc`
里写绑定并不生效。

**根因。** 这个版本里 `kglobalshortcutrc` 的自定义动作布局无法从命令行推导出来：

- 试了三种候选组布局——`[KDE Action for <cmd>]`、`[<cmd>]`、以及带索引键的 `[<cmd>]`——
  没有一种能在 kglobalaccel daemon 里注册出组件（`/component/plasma-systemmonitor` 始终
  「not a valid object path」，连 `systemctl --user restart plasma-kglobalaccel.service`
  之后也一样）；
- 该版本 daemon 的 `org.kde.kglobalaccel.Component` 接口没有 `registerShortcut` 方法，
  所以也没法用 DBus 注册；
- 老版本 KDE 用的组前缀字符串 `KDE Action for`，在已安装的 KDE 6.7 各库里**根本不存在**——
  也就是说那个旧布局不是这个版本写出来的。

**结论。** 快捷键得走图形界面：**系统设置 → 键盘 → 快捷键 → 自定义快捷键 → 添加**，
命令填 `plasma-systemmonitor`，名称填 "System Monitor"，快捷键 `Ctrl+Shift+Escape`。在
这之前，[`files/desktop/system-monitor.desktop`](files/desktop/system-monitor.desktop)
提供桌面上一键启动。

通用教训：**一个只有 daemon 读、却没有公开 API 可写的配置文件，不该盲写**。格式必须来自
写它的那个程序；而如果写它的是 GUI，那 GUI 就是工具。

### 4.9 Fedora 的 `uv` 在你明说之前不下载 Python

**症状。** `uv run --python 3.12 ...` 报：

```text
error: No interpreter found for Python 3.12 in virtual environments, search path, or managed installations
hint: A managed Python download is available for Python 3.12, but Python downloads are set to
      'manual', use `uv python install 3.12` to install the required version
```

**根因。** RPM 打包的 `uv` 自带 `/etc/uv/uv.toml`，其中 `python-downloads = "manual"`、
`python-preference = "system"`。前者挡掉隐式下载；后者让 uv 在没有钉版本时优先用系统解释器。

**结论。** 显式跑一次 `uv python install 3.12`（「manual」允许的正是这个），并把版本钉进
`~/.config/uv/.python-version`——钉子压过 `python-preference`，于是即便系统 Python 更新，
`uv run` 用的仍是 3.12.15。见 3.5。

### 4.10 客户端停了之后，会话环境里还留着代理变量

**症状。** 终端又没网了——尽管 rc 文件里已经不写死端口——而且 `curl` 报的是

```text
curl: (7) Failed to connect to <host> port 443 via 127.0.0.1 after 0 ms: Could not connect to server
```

也就是它正在用一个根本没人在监听的代理。

**根因。** 桌面会话自己留了一份环境快照。`systemctl --user show-environment` 里列着客户端运行
时注入的代理变量；从面板启动的终端会继承这份快照。于是即便 rc 文件自己从没设过变量，shell 里
也有；而客户端停下之后这份快照**不会刷新**，变量继续指向已经关闭的端口。

本机实测：会话环境里八个变量齐全，用的还是**旧的** `socks5://` 方案（rc 文件里是
`socks5h://`），客户端停掉之后它们仍然在。

**结论。** 同一批变量有两个来源，而看不见的那个赢了——因为它是 rc 文件运行**之前**就被继承
进来的。只改 rc 文件不够，变量必须在进入进程的地方就被清掉。

**做法。** 已部署的脚本在探测前先把它们清掉（3.11）。共享的 `shell/files/shell_common`
—— 四层分层部署之后 zsh 登录 shell 加载的就是它（4.6）—— 以前不清：在一个没有任何监听的
`unshare -rn` 网络命名空间里，旧的 `HTTPS_PROXY` / `ALL_PROXY` 在 bash 和 zsh 下都原样保留。
它的第 5 节现在也用同样的方式清掉。会话快照可以一次性清干净：

```bash
systemctl --user unset-environment HTTP_PROXY HTTPS_PROXY ALL_PROXY \
    http_proxy https_proxy all_proxy NO_PROXY no_proxy
```

---

## 五、可部署原件

| 文件 | 部署到 | 备注 |
| :--- | :--- | :--- |
| [`files/npmrc`](files/npmrc) | `~/.npmrc` | 只有 registry —— 见 4.2，**不要**把别的塞进来 |
| [`files/sudoers/proxy`](files/sudoers/proxy) | `/etc/sudoers.d/proxy` | 权限 `0440`；用 `sudo visudo -cf` 校验 |
| [`files/ff-proxy-test.sh`](files/ff-proxy-test.sh) | 探测脚本，不部署 | headless Firefox 加载探测，剥离代理环境变量 |
| [`files/chrome-proxy-test.sh`](files/chrome-proxy-test.sh) | 探测脚本，不部署 | headless Chromium 出口 IP 探测，剥离代理环境变量；PROXIED / DIRECT / BROKEN 三态 |
| [`files/fontconfig/64-default-cjk-sc-fedora.conf`](files/fontconfig/64-default-cjk-sc-fedora.conf) | `/etc/fonts/conf.d/64-default-cjk-sc-fedora.conf` | Fedora 没有 `/etc/fonts/conf.avail`；权限 `0644`，之后 `fc-cache -f` |
| [`files/konsole/Sarasa.profile`](files/konsole/Sarasa.profile) | `~/.local/share/konsole/Sarasa.profile` | 终端字体 profile；在 `~/.config/konsolerc` 里用 `DefaultProfile=Sarasa.profile` 设为默认。它固定了 `Command=/usr/bin/zsh`，所以新开的 Konsole 不管 `$SHELL` 是什么都会启动 zsh |
| [`files/bashrc.d/50-proxy.sh`](files/bashrc.d/50-proxy.sh) | `~/.bashrc.d/50-proxy.sh` | CLI 代理变量，探测而非写死；探测逻辑取自 `shell/files/shell_common` 第 5 节 —— 见 3.11 |
| [`files/desktop/system-monitor.desktop`](files/desktop/system-monitor.desktop) | `~/Desktop/system-monitor.desktop` | 桌面一键启动系统监视器 |

pnpm 配置与 Mint 机器共用，在 [`../files/pnpm/config.yaml`](../files/pnpm/config.yaml)。
四层 shell 文件同样与 Mint、WSL 机器共用，在 [`../../shell/files/`](../../shell/files/)；
本机部署了其中哪几个、部署版有何差别，记在 4.6。

---

## 六、本发行版的软件包可得性

用 `dnf list --available` 查过：

| 软件包 | Fedora 仓库里有 | 备注 |
| :--- | :--- | :--- |
| `btop` | 有 | TUI 系统监视器 |
| `copyq` | 有 | 带 `Meta+V` 热键的剪贴板历史 |
| `fd-find` | 有 | 提供 `fd` 命令 |
| `zsh` | 有 | 本机的登录 shell；四层分层已部署——见 4.6 |
| `uv` | 有 | Python 旁路管理 |
| `fsearch` | **无** | Everything 替代品；用 `plocate` + Dolphin 索引 |
| Ghostty | **无** | 不在 Fedora 仓库，Flatpak 与上游 Linux 二进制也都没有——见 4.7 |

本机已从上述列表装好：`btop`、`copyq`、`fd-find`、`zsh`、`uv`。

