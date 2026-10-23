# Python 踩坑记录

本机环境约定（uv、`PYTHONUNBUFFERED`、不碰系统 `python3`）见 [`../../agent/claude-code/claude-global.md`](../../agent/claude-code/claude-global.md)。
本文只记**踩过的具体坑**，每条都在本机实测过，附验证方法。

---

## 1. `NO_PROXY` 里的通配符对 `urllib` 无效

### 症状

本机开着代理（Clash，`127.0.0.1:<proxy-port>`）时，Python 用 `urllib` 访问**本机服务**（如 `127.0.0.1:2026`）失败。若把 `no_proxy` 写成 `127.*` 这种省事的通配形式，请求会穿过代理出去，而不是直连。

更难判的是**错误长相**：本机端口没开时，代理返回一个 **HTTP 502 空体**。看起来像"请求失败"，实际是"根本没连到你以为的那个服务"。

### 实测（CPython 3.12.14，2026-09-19；3.12.15 上复测 2026-10-17，结论不变，见[第 5 节](#5-windows-上的-uv--python-312清华源只管-pypi管不了解释器)）

```python
from urllib.request import proxy_bypass_environment as pbe
```

| `no_proxy` 的值 | `pbe("127.0.0.1:2026")` | 结论 |
| :--- | :--- | :--- |
| `127.*` | **False** | ❌ 通配不生效，走代理 |
| `127.0.0.1` | True | ✅ |
| `localhost,127.0.0.1,::1,.local` | True | ✅ 本机现行配置 |
| `*` | True | ✅ 裸星号被特殊处理，确实绕过一切 |

注意最后两行的对比：**裸 `*` 是被特殊处理的，`127.*` 不是。** 所以"通配符不支持"这个说法要更准确一点——只有独立的 `*` 有效，带前缀的通配形式一律失效。

### 做法

**① shell 里把主机名写全，别图省事用通配。** 本机 [`../../shell/files/shell_common`](../../shell/files/shell_common) 第 5 节已经这么做了，并在那里留了注释。

**② 写访问本机服务的代码时，显式绕开代理，不依赖环境变量：**

```python
from urllib.request import build_opener, ProxyHandler

opener = build_opener(ProxyHandler({}))   # 空字典 = 不使用任何代理
resp = opener.open("http://127.0.0.1:2026/api")
```

用 `requests` 的话是 `requests.get(url, proxies={"http": None, "https": None})`。

### 自查

```bash
uv run --python 3.12 python -c '
import os
from urllib.request import proxy_bypass_environment as p
print("当前 no_proxy:", os.environ.get("no_proxy"))
print("本机请求是否绕过代理:", p("127.0.0.1:2026"))'
```

输出 `False` 就说明本机流量正在穿代理。本机现行配置实测为 `True`。

> 注意上面那个 `python -c` 不能省成 `uv run --python 3.12 -c`——`uv run` 会把 `-c`
> 当成自己的参数并报 `unexpected argument '-c' found`。要传给解释器的 flag，必须先写
> `python` 再跟 flag。

---

## 2. f-string 里的引号复用规则，按「字面量部分 / 表达式部分」分开看

中文输出场景特别容易撞上，因为中文标点和引号经常混排。

### 两个部分，规则不同

```python
f"每个{ x }的频道"
  └─字面量─┘└表达式┘└─字面量─┘
```

| 位置 | ≤ 3.11 | ≥ 3.12 (PEP 701) |
| :--- | :--- | :--- |
| **字面量**部分复用同类引号 | ❌ SyntaxError | ❌ **仍然 SyntaxError** |
| **表达式**部分复用同类引号 | ❌ SyntaxError | ✅ 允许 |
| 表达式部分用**不同**引号 | ✅ | ✅ |

**PEP 701 只放开了表达式部分。** 字面量部分永远不行——那个引号会直接把字符串终结掉，和版本无关。

### 实测对照（2026-09-19）

```
                                        3.10.21                      3.12.14
f"每个"从未见过"的频道"      SyntaxError: invalid syntax   SyntaxError: invalid syntax
f"{'zh':>9}"   外双内单      OK                            OK
f"{"zh":>9}"   外双内双      SyntaxError: expecting '}'    OK
f"{ {"a":1}["a"] }"          SyntaxError: unmatched '{'    OK
```

### 写法

```python
f"每个"从未见过"的频道"      # ✗ 任何版本都错
f"每个「从未见过」的频道"     # ✓ 中文引号，推荐
f"每个'从未见过'的频道"       # ✓ 换一种引号
f'每个"从未见过"的频道'       # ✓ 外单内双
```

**要跨版本跑的脚本**（例如本地 3.12、云端 3.10），表达式部分一律**外双内单**，不要依赖 3.12 的新特性。

### 一条流传的错误说法

早先笔记里写「`f"{'中文':>9}"` 在 3.12 能跑、在 3.10 是 SyntaxError」——**这个例子是错的**。它外双内单，属于"不同引号"，实测在 3.10.21 上完全正常。

真正只有 3.12 才能跑的是 `f"{"中文":>9}"`（外双**内双**）。举错例子会让人以为所有格式化都得改，实际只需要盯住"同类引号复用"这一种情况。

同样地，笔记里说报错是 `Perhaps you forgot a comma?`——本机实测两个版本给的都是 `invalid syntax`。那条消息 CPython 确实会在别的上下文给出，但不是这里。

### 自查

```bash
for v in 3.10 3.12; do
  uv run --python $v python -c '
import sys
print(f"Python {sys.version.split()[0]}")
for src in ["f\"{\x27zh\x27:>9}\"", "f\"{\"zh\":>9}\""]:
    try: compile(src, "<t>", "eval"); print(f"  {src:22} OK")
    except SyntaxError as e: print(f"  {src:22} {e.msg}")'
done
```

实测输出：

```
Python 3.10.21
  f"{'zh':>9}"           OK
  f"{"zh":>9}"           f-string: expecting '}'
Python 3.12.14
  f"{'zh':>9}"           OK
  f"{"zh":>9}"           OK
```

---

## 3. CPU 密集的纯 Python 代码：换 Python 3.12 有用，换 numpy 2 没用

实测（2026-10-04，云端 24 核 CPU 实例；任务是逐分钟推进的报警状态机回放，numpy 只处理小数组）：

| 环境 | 串行 300 条序列 | 24 进程 2400 条序列 |
| :--- | ---: | ---: |
| Python 3.10.15 + numpy 1.26.4 | 2.47 s | 1.31 s |
| Python 3.12.15 + numpy 1.26.4 | 1.70 s | 0.95 s |
| Python 3.12.15 + numpy 2.5.3 | 1.68 s | 0.96 s |

- 提速（约 1.4 倍）全部来自解释器（3.11 起的 CPython 提速）；numpy 换大版本没有作用，因为热点不在 numpy 里。
- 三种组合的输出逐字节相同（对逐步结果数组做哈希比对）。另一个任务用 `default_rng` 生成随机位置、onnxruntime 从 1.23 换到 1.30，结果也完全一致。**换版本前先做这种比对**，不要假设。
- 如果代码还要在 3.10 / numpy 1 上跑（被老 torch 钉住的 GPU 环境、嵌入式板子），只给不需要那些依赖的 CPU 任务换新环境，代码保持两边兼容。

---

## 4. `uv run` 偶尔无声地卡住

**症状**：`uv run --with-requirements ... python ...` 没有输出、不报错，几分钟不结束；平时同一条命令几秒就完成。它卡在解析依赖时的联网检查上。

依赖都已在本地缓存里时加 `--offline`（或设 `UV_OFFLINE=1`）：

```bash
uv run --offline --with-requirements requirements.txt python script.py
```

另一面：看起来卡住的命令可能其实已经把活干完了，只是还没返回。杀掉之后**先看实际状态再重跑**（例如 `git diff`）——碰到过一次文本插入脚本被这样执行了两遍，留下重复内容。

---


## 5. 配了清华源，`uv pip` 走镜像、`uv add` 还是打 pypi.org

**症状**：`~/.config/uv/uv.toml` 里明明写的是清华源，`uv run --with requests` 也快，
但项目里的 `uv add` / `uv sync` 依然连 pypi.org；或者反过来，`uv pip install` 走了镜像，
而 `uv run` 慢得离谱。

**根因**：`[pip]` 和 uv 自己的解析器读的是**两张表**，互不相通：

| 写法 | 作用范围 |
| :--- | :--- |
| `[pip]` `index-url` | 只有 `uv pip install` 读 |
| `[[index]]` `url` + `default = true` | `uv add` / `uv sync` / `uv run --with` / `uv tool` 读 |

只配 `[pip]` 就等于只给一半的命令配了源。所以"我配过镜像了"和"所有命令都走镜像"是两件事。

**做法**：两个都写，别指望一个覆盖另一个。

```toml
# ~/.config/uv/uv.toml
link-mode = "copy"

[[index]]
url = "https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple"
default = true

[pip]
index-url = "https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple"
```

**自查**：加 `-v`，看它实际请求了哪个域名，别看配置文件猜。

```bash
uv run --python 3.12 --with idna -v python -c pass 2>&1 | grep -oE 'https://[^/]+/[^ ]*simple'
# 期望看到 mirrors.tuna.tsinghua.edu.cn，而不是 pypi.org
```

**顺带一提**：`uv python install` 下载的解释器来自 python-build-standalone（GitHub），
**不走上面任何一个索引**。镜像配置对它是无效的，别把"解释器装得慢"归因到 pip 源。

## 6. Windows 上的 uv + Python 3.12：清华源只管 PyPI，管不了解释器

**实测（2026-10-17，Windows 11，uv 0.12.18 -> 0.13.1，Python 3.12.14 -> 3.12.15）**

### ⚠️ 装 uv / Python 之前，先查最新版本号，不要照抄文档里的

本节以及本文件其他地方出现的版本号（uv `0.12.18` / `0.13.1`、CPython `3.12.14` / `3.12.15`）
是**当时的实测快照，不是推荐版本**，过几个月就是过期的。按下面三条查当前值：

```powershell
# 1. uv 有没有更新（先查，别先装）
uv --version
curl.exe -s https://api.github.com/repos/astral-sh/uv/releases/latest | ConvertFrom-Json | Select-Object tag_name, published_at

# 2. 这个 uv 版本能看到哪些 Python（关键，见下方"新补丁版要先升 uv"）
uv python list --all-versions

# 3. python-build-standalone 出了哪些构建
curl.exe -s https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest | ConvertFrom-Json | Select-Object tag_name
```

装 uv 本身的命令（**官方安装器是唯一能原地升级的安装方式**，`uv self update` 只支持它，见下）：

```powershell
$env:UV_INSTALL_DIR = "$HOME\.local\bin"
irm https://astral.sh/uv/install.ps1 | iex   # 不带版本号 = 装最新版
```

**为什么必须先查**：uv 内置了一份 Python 下载清单（编译进二进制，不在运行时联网查），
**uv 版本决定了 `uv python install` 能装到哪些 Python 补丁版**。先装一个旧版 uv，再去装新发布的
CPython，会得到 `<download available>` 里根本没有那个版本的结果，而且**没有任何报错提示你原因**。
所以顺序是：**先查 uv 最新版 -> 装 uv -> `uv python list` 确认目标版本在列 -> 再 `uv python install`**。

装完在目标机器上**复测**一遍本文件里与版本相关的结论（本节已在 3.12.15 上复测，结论不变，见下）。

### 坑：清华源没有 `python-build-standalone`

> The general principle -- the interpreter comes from neither `[pip]` nor `[[index]]` --
> is stated in section 5. This subsection is the measured 404 evidence for it.

uv 装**包**走 PyPI，装**解释器**走 GitHub 上的 `astral-sh/python-build-standalone`。这是两个不同的下载源，
而清华 TUNA **只镜像前者**：

| 探测 URL | 结果 |
| :--- | :--- |
| `https://pypi.tuna.tsinghua.edu.cn/simple/` | **200** |
| `https://mirrors.tuna.tsinghua.edu.cn/github-release/astral-sh/python-build-standalone/` | **404** |
| `https://mirrors.tuna.tsinghua.edu.cn/github-release/` | 200，但整个 `astral-sh/` / `indygreg/` 子树都是 404 |

所以「把 uv 和 python 都设为清华源」这句话对解释器那半边**做不到**。别把 `python-install-mirror` 指向
TUNA——它是 404，不是慢，是直接没有。实测可用的替代（NJU / USTC / LZU / npmmirror 均 200，~200-300 ms）：

```
https://mirror.nju.edu.cn/github-release/astral-sh/python-build-standalone/releases/download
```

### 配置位置（Windows 与 Linux 不同）

| 用途 | Windows | Linux / macOS |
| :--- | :--- | :--- |
| uv | `%APPDATA%\uv\uv.toml` | `~/.config/uv/uv.toml` |
| pip | `%APPDATA%\pip\pip.ini` | `~/.config/pip/pip.conf` |

`%APPDATA%\pip\pip.ini` 写：

```ini
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
```

`uv.toml` 同时要写 `[pip]` 段和 `[[index]]` 段，两者管的是不同命令：

```toml
[pip]
index-url = "https://pypi.tuna.tsinghua.edu.cn/simple"

[[index]]
url = "https://pypi.tuna.tsinghua.edu.cn/simple"
default = true

python-install-mirror = "https://mirror.nju.edu.cn/github-release/astral-sh/python-build-standalone/releases/download"
```

> ⚠️ **`python-install-mirror` 在 uv 0.12.x / 0.13.x 是纯字符串**，写成 `[python-install-mirror]` 表会报
> `invalid type: map, expected a string`，且**整个 uv.toml 一起失效**（连 `[[index]]` 也不生效）。
> 用 `uv python list` 验证：报不报错 = TOML 有没有被接受，没有独立的 schema 校验子命令可查
> （`uv config` 子命令在这两个版本里已被移除，`uv config --help` 报 `unrecognized subcommand`）。

> ⚠️ `UV_INDEX_URL` 已被官方标为废弃，新变量是 `UV_DEFAULT_INDEX`。`pip config list` / `uv add -v`
> 是确认「到底走了哪个源」的可靠办法：`uv add -v` 会打印 `Sending fresh GET request for: https://pypi.tuna...`。
> 实测在 **3.12.15 + uv 0.13.1** 上，TUNA 索引在**元数据和 wheel 两个环节**都生效。

### 坑：`~/.local/bin` 不在 PATH，Python 明明装了却调不到

uv 装完会警告 `%USERPROFILE%\.local\bin is not on your PATH`。已开的终端不会因为
`[Environment]::SetEnvironmentVariable('Path', ...)` 刷新，必须自己拼一次：

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
```

### 坑：`uv self update` 在 Windows 上不可用

`uv self update` 只支持**独立安装脚本**装的 uv。本机这份是别的方式装进来的，直接报
`Self-update is only available for uv binaries installed via the standalone installation scripts`。
升级要重跑官方安装器（`irm https://astral.sh/uv/install.ps1 | iex`，先设 `$env:UV_INSTALL_DIR`）。
本机就是这样从 0.12.18 升到 0.13.1 的——安装器会覆盖 `uv.exe` / `uvx.exe` / `uvw.exe`，
**已装的 Python 解释器和 `~/.local/bin` 里的 `python3.12.exe` 都不受影响**（它们在
`%APPDATA%\uv\python\` 下）。

### 坑：`python3.12.exe` 是个不归 uv 管的旧 shim

装解释器时撞到：

```
warning: Failed to install executable for cpython-3.12.14-windows-x86_64-none
  cause: Executable already exists at `%USERPROFILE%\.local\bin\python3.12.exe`
         but is not managed by uv; use `--force` to replace it
```

（上面 `3.12.14` 是当时的目标版本，这个 warning 的文案会带上你正在装的那个版本号。）

表现是**旧版本**的 `python3.12.exe` 还在原地（`python3.12 --version` 报
`error: uv trampoline failed to spawn Python child process / entity not found`）。`uv python install 3.12 --force`
可解。**升级换小版本后同样要 `--force`**，否则 shim 还指着旧解释器——`uv python list --only-installed`
里若同时出现两个版本，说明有残留。

### 坑：新版 CPython 要先升 uv 才认得

CPython 3.12.15 于 2026-09-30 发布，但 **uv 0.12.18（2026-09-22 构建）的内置清单里最高只有 3.12.14**，
`uv python list --all-versions` 不会列出 3.12.15。uv 0.13.1（2026-10-13）才加上。
判断依据是 uv 仓库里的下载清单（0.12.x 在 `crates/uv-python/download-metadata.json`）——
**清单是编译进二进制的，不是运行时查的**，所以「GitHub 上已经 release 了」不等于「本机能装」，
而且 `uv python install` 不会报错，只是告诉你这版不存在。注意 0.13.x 挪了这个文件的位置，
按旧路径查文件会 404，**直接跑 `uv python list --all-versions` 比翻源码可靠**。

验证（本机最终状态，2026-10-17）：

```powershell
uv --version                       # 0.13.1
uv python list --all-versions      # 3.12.15 在列（0.12.18 下不在）
uv python install 3.12.15 --force  # Installed Python 3.12.15 in 19.52s
python3.12 --version               # Python 3.12.15
uv run --python 3.12 python -c "import sys; print(sys.version.split()[0])"   # 3.12.15
```

### 复测：第 1 节的 `no_proxy` 结论在 3.12.15 上不变

第 1 节那张表是 3.12.14 上测的，在 3.12.15 上复测**结论完全一致**，可直接沿用：

| `no_proxy` 的值 | `proxy_bypass_environment("127.0.0.1:2026")` |
| :--- | :--- |
| `127.*` | False（通配不生效） |
| `127.0.0.1` | True |
| `localhost,127.0.0.1,::1,.local` | True |
| `*` | True |

> 自查脚本要在**循环内改 `os.environ`**，否则每次调用的都是进程启动时的旧值，
> 会得到一整列 False 的假结果（这个坑本节记录时踩过一次）。


---

## 相关

- [`../../agent/claude-code/claude-global.md`](../../agent/claude-code/claude-global.md) —— uv 规范、`PYTHONUNBUFFERED` 与块缓冲
- [`../../wsl/setup/`](../../wsl/setup/) —— 代理环境变量在哪定义
- [`../skills/linux-cjk-font/`](../../agent/skills/linux-cjk-font/) —— matplotlib / Pillow 的中文字体渲染
- [`../../agent/brave-search/bx-cli.md`](../../agent/brave-search/bx-cli.md) —— 同机 `bx` CLI 的 Windows 部署
