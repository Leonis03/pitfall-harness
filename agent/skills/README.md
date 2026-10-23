# Skills

25 个 skill，同时供 Claude Code（`~/.claude/skills/`）与 Antigravity（`~/.gemini/config/skills/`）使用，也可以装在 `~/.agents/skills/`。
两边装的集合不同（见下表），但凡是两边都有的，内容保持一致。

## 部署与核对：不能直接 cp

**仓库是脱敏的**：这里写 `<your-home>`、`CourseName`，部署位写的是真实家目录、真实课程名。
两个方向的裸 `cp` 都是 bug——

- **仓库 → 部署**：`antigravity-cli` 的 `trustedWorkspaces` 是 JSON，占位符不会展开，
  照搬过去就是一个字面量 `<your-home>`，Antigravity 认不出这个工作区。
- **部署 → 仓库**：真实路径与账户名进公开仓库，`privacy-gate.sh` 事后才拦得住。

所以走渲染：

```bash
bash ../../tools/sync-skills.sh            # 核对：比对"渲染后"的字节
bash ../../tools/sync-skills.sh deploy     # 部署：展开占位符后写入两个部署位
bash ../../tools/sync-skills.sh deploy bx  # 只处理一个
```

### `deploy` 在原生 Windows 上会失败

2026-10-17 实测：Windows 的 Git Bash **不带 `rsync`**，`deploy` 走到写文件那步会报
`rsync: command not found` 然后停住——**核对模式不用 rsync，所以这个失败是半静默的**：
同一个脚本几分钟前还报告某个 skill 一切正常，下一刻部署却挂了。

WSL 的 Debian 里有 `rsync`（`/usr/bin/rsync`），在 WSL 里跑脚本是正常的——但那里 `$HOME`
是 WSL 的家目录，写进去的是 **WSL 部署位**，不是 Windows 的 `%USERPROFILE%`。

第二条出路是直接复制，**但只对纯占位符的 skill 成立**：既有 `<your-*>` 又有 `.sync-map`
键时，渲染是恒等变换，`cp` 与脚本逐字节一致。`distill-session` 2026-10-17 就是这样部署的，
之后 `sync-skills.sh` 核对报 `all match (modulo redaction)`。**带占位符的照旧必须走脚本**，
否则 `<your-home>` 会被原样写进部署位。

占位符 → 真值的映射在 `tools/.sync-map`（已 gitignore，理由同 `.privacy-names`：
值不写进脚本，脚本本身才能公开）。哈希相同的含义因此是**"仓库 ≡ 部署位，模脱敏"**。

### 家目录：默认写 `$HOME`，展不开才用 `<your-home>`

判据只有一条——**这串字符在使用时会不会被 shell 展开**：

| 情况 | 写什么 | 例子 |
| :--- | :--- | :--- |
| 会被 shell 展开（命令行、脚本、`uv run ...` 的参数、双引号里的 prompt） | `$HOME` | `uv run --python 3.12 python $HOME/.agents/skills/pdf-to-md/scripts/x.py` |
| 展不开，必须是字面路径（JSON、Python 字符串、配置文件的值） | `<your-home>` | `"trustedWorkspaces": ["<your-home>"]` |

所以 `$HOME` **不是**占位符，是原样发布的运行时变量；`<your-home>` 才是，全仓库只剩
`antigravity-cli/SKILL.md` 与 `SKILL.zh.md` 的 `trustedWorkspaces` 那两行（JSON 不做变量展开）。

这条判据的好处是部署出来的 skill 本身就跨机器可用。`deepln-setup/scripts/set-deepln.sh`
和 `gpu-cuda-checks/scripts/smoke-test.sh` 尤其依赖它——这两个脚本会在**租来的 GPU 机**上执行，
家目录根本不是本机的，把 `$HOME` 渲染成真值就等于把脚本钉死在这台机器上。

> 早先这两个记号混用同一个 `$HOME`，渲染时分不清哪个该替换。分开之后 `sync-skills.sh`
> 不需要任何按文件、按路径的例外规则。

### 更好的办法：让代码自己发现，就不必脱敏

占位符是退路，不是首选。**凡是程序能在运行时查出来的值，就不该出现在文本里**——
它既不用脱敏，也不会过期。

| 要拿什么 | 怎么拿 |
| :--- | :--- |
| Linux 家目录（Python） | `Path.home()`，或 `os.path.expanduser("~")`；两者都先看 `$HOME`，未设置时回落到 passwd 记录 |
| Linux 家目录（shell） | `$HOME`，原样写进文档即可 |
| **Windows 账户目录**（WSL 里） | WSL 中**没有** `%USERPROFILE%` 这个环境变量。用通配符：`glob.glob("/mnt/c/Users/*/AppData/Local/Microsoft/Windows/Fonts/*.ttf")`；需要确切的用户名时 `wslpath -u "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null \| tr -d '\r')"` |

`linux-cjk-font` 是这条规则的现成案例，也是个真实事故：它的 `scripts/cjk_font.py` 一直用
`glob.glob("/mnt/c/Users/*/...")` 做得很对，但 `SKILL.md` 里给 agent 照抄的代码片段却把账户名
写死成了另一台机器的值。那个目录在本机不存在，于是 matplotlib 静默回退 DejaVu Sans，出一版
豆腐块**且不抛异常**——正是这个 skill 自己写着要防的失败模式。两处现在都用通配符，
`<your-windows-user>` 这个占位符也就整个消失了。

所以顺序是：**能发现就发现 → 发现不了但 shell 能展开就用 `$HOME` → 都不行才用占位符**。

## 公开发布

除第三方的 `find-skills`、`skill-creator` 外，全部 skill 还会由 [`../../tools/publish.sh`](../../tools/publish.sh) 导出到公开仓库
[pitfall-harness-skills](https://github.com/Leonis03/pitfall-harness-skills) 的 `skills/<name>/`，
那边的 README 按各 skill 的 frontmatter 自动生成——所以 `description` 的第一句要能单独读懂。
导出的是脱敏后的仓库原样，占位符不渲染。

## 能在哪用：if / only if

- **only if X**：离开 X 就用不了，别的平台不要装。
- **if X / Y**：在列出的平台上能用，不代表别处一定不行。**Windows 一栏没打勾**，是因为命令和脚本都按
  bash 写，没在原生 PowerShell 下验证过，不是确认过不能用。

「Windows」指原生 Windows（PowerShell）；「WSL」是 Windows 上的 WSL2 发行版；「Linux」是原生 Linux，
含租来的 GPU 机；「Android」指 root 后的 Termux，或荣耀平板的 Linux 实验室。

| skill | Windows | WSL | Linux | Android | 条件 | 依据 |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- |
| `wsl-windows-command` | | ✅ | | | **only if** WSL | 全靠 WSL interop：`/mnt/c`、`.exe`、`wsl.exe` |
| `compress-wsl-space` | ✅ | | | | **only if** Windows（装了 WSL2） | WSL 3.x 用 `wsl --manage <Name> --compact`（无需提权）；2.x 才退回管理员 PowerShell 里的 `Optimize-VHD -Mode Full` |
| `android-chroot-debian` | | | | ✅ | **only if** Android（root + Termux） | 在 Termux 的 root chroot 里运行，依赖 Android 的挂载点与 `unshare` |
| `termux-debian-external-drive` | | | | ✅ | **only if** Android（root + Termux） | vold、`/mnt/media_rw`、`nsenter -t 1` |
| `android-miui-settings` | | | | ✅ | **only if** Android（root + Termux） | 穿透 Android 宿主 Mount Namespace (`nsenter -t 1 -m`) 调取 `settings` 与 DoT 私人 DNS |
| `honor-linuxlab` | | ✅ | ✅ | ✅ | **only if** 手边有荣耀平板 | 目标是平板里的 PRoot 容器；命令从电脑端用 `adb shell` 注入 |
| `video-to-md` | ✅ | ✅ | ✅ | | **only if** Antigravity | 视频靠 agy 的 `view_file` 读；Claude Code 没有等价工具，所以只装 `.gemini` |
| `linux-cjk-font` | | ✅ | ✅ | | **if** WSL / Linux | WSL 先找 `/mnt/c/Users/*/.../Fonts`；Linux 退回 `/usr/share/fonts`，要装 `fonts-noto-cjk` 或文泉驿 |
| `linux-disk-cleanup-backup` | | ✅ | ✅ | | **if** WSL / Linux | 清理脚本是 bash + `du`/`find`/`dpkg-query`/`rpm`，只读且跨发行版；三种模式（日常维护 / 归档式清理 / 备份到移动硬盘）。备份实测的是 WSL → NTFS（drvfs 需 `metadata`），原生 Linux 那份还是骨架 |
| `antigravity-cli` | | ✅ | ✅ | | **if** WSL / Linux（需装 agy） | 包装脚本是 bash；在 WSL 上实测（agy 1.2.11），Linux 上 agy 是原生二进制 |
| `bx` | | ✅ | ✅ | | **if** WSL / Linux | 配方是 bash + `jq`，需要 `bx` CLI |
| `deepln-setup` | | ✅ | ✅ | | **if** WSL / Linux（本地端） | 本地改 `~/.ssh/config`、跑 bash 脚本；远端是租来的 Linux GPU / CPU 机 |
| `gpu-cuda-checks` | | ✅ | ✅ | | **if** WSL / Linux（本地端） | 经 ssh 在远端 Linux GPU 机上检查 |
| `hf-cn-download` | | ✅ | ✅ | | **if** WSL / Linux | 配方是 bash + `env -u` 剥代理；针对桌面代理开着时从 hf-mirror 这类境内可达镜像站下模型 |
| `docx-to-md` · `pdf-to-md` | | ✅ | ✅ | | **if** WSL / Linux | `uv run` 跑 Python 脚本 |
| `download-bilibili` | | ✅ | ✅ | | **if** WSL / Linux | BBDown + ffmpeg，命令按 bash 写 |
| `inspect-session` · `trim-branch` | | ✅ | ✅ | | **if** WSL / Linux | 读 `~/.claude/projects` 下的会话 JSONL，Python 脚本 |
| `shuorenhua` | ✅ | ✅ | ✅ | ✅ | 任意平台 | 纯文字编辑，不跑命令 |
| `find-skills` | ✅ | ✅ | ✅ | ✅ | 任意平台（需 Node） | 只调用 `npx skills` |
| `github-coauthor-scrub` | | ✅ | ✅ | | **if** WSL / Linux（需 git、perl、`gh`） | bash 脚本；`refresh`、`verify` 走 GitHub API，要 `gh` 已登录 |
| `export-wechat-chat` | ✅ | | | | **only if** Windows（微信 4.x） | 只读扫内存提 Config.Cipher，解密 WCDB/SQLCipher；也含微信 3.x 踩坑 |
| `export-qq-chat` | ✅ | | | | **only if** Windows（QQ NT / PCNT） | 只读扫内存提 SQLCipher 密钥，解密 nt_msg.db，导出 TXT/JSON |
| `run-sql-file` | ✅ | ✅ | | | **only if** 有 SQL Server 实例的机器 | Windows 侧 sqlcmd 11，WSL 侧换 `mssql-tools18`；`go-sqlcmd` 会把中文列别名按字节截断，不能用 |
| `distill-session` | ✅ | ✅ | ✅ | ✅ | 任意平台（需这个仓库的副本 + git） | 会改仓库的文件，所以先证伪再落笔；`scripts/verify-change.sh` 跑机械检查。它只改文件，不部署、不发布 |
| `skill-creator` | ✅ | ✅ | ✅ | | 任意平台（需 Python）；跑评测、优化描述 **only if** Claude Code | 起草、改写 skill 哪都能做；评测要派子 agent，描述优化要 `claude -p` |

## 装在哪

按机器记。一台机器装哪些 skill，先按上表排除用不了的，再按工具分工排除用不上的。

| skill | WSL 机 `.claude` | WSL 机 `.gemini` | Linux 桌面 `.claude` | Linux 桌面 `.gemini` |
| :--- | :---: | :---: | :---: | :---: |
| `antigravity-cli` · `bx` · `deepln-setup` · `distill-session` · `find-skills` · `gpu-cuda-checks` · `honor-linuxlab` · `inspect-session` · `shuorenhua` · `trim-branch` | ✅ | ✅ | ✅ | ✅ |
| `docx-to-md` · `download-bilibili` · `pdf-to-md` | — | ✅ | ✅ | ✅ |
| `video-to-md` | — | ✅ | — | ✅ |
| `android-chroot-debian` · `termux-debian-external-drive` · `android-miui-settings` · `wsl-windows-command` | ✅ | ✅ | — | — |
| `linux-cjk-font` | — | ✅ | — | — |
| `linux-disk-cleanup-backup` | — | — | — | — |
| `compress-wsl-space` | — | — | — | — |
| `github-coauthor-scrub` | — | — | ✅ | ✅ |
| `hf-cn-download` | — | — | — | — |
| `run-sql-file` | — | — | — | — |
| `skill-creator` | — | — | —（插件已提供） | ✅ |

- Windows 机是第三个部署目标，`.agents` / `.claude` / `.gemini` 三个目录都还没建，
  所以上表它在每一栏都是 `—`。`run-sql-file` 是这台机器上的第一个 skill，
  但它要 SQL Server 实例才用得上，本机没装，属于「已入库、未部署、暂不可用」。

- `linux-disk-cleanup-backup` 是新入库的，四栏都是 `—`：清理脚本只用发行版自带的 `du` / `find` /
  `dpkg-query` / `rpm`，WSL 与原生 Linux 都用得上，但装不装由各台机器自己决定——
  磁盘吃紧的机器才需要它，重装前要备份的机器则用它的备份那一半。
  `references/backup-linux-desktop.md` 还是骨架，WSL 那份（`backup-wsl-ntfs.md`）才实测过。
- `hf-cn-download` 同属「已入库、未部署」。它的前提是**这台机器真的开着本地代理**——
  Linux 桌面机开着 Clash Verge Rev，WSL 机则取决于当时是否转发；两边都没装的话，
  上层文档里的 `env -u` 配方无害但用不上。要装的话按下面的方式手动建目录再 deploy。

- Linux 桌面两栏是 2026-09-28 按上面的规则装的：Android、WSL 专属的都不装；`linux-cjk-font`（原名
  `wsl-cjk-font`）在原生 Linux 上也能用，但这台机器用不上，没装；`video-to-md` 不进 `.claude`，因为读视频靠的是 agy 的 `view_file`。
- WSL 机两栏是此前的记录，那台机器上的实际安装以它自己的 `sync-skills.sh` 核对结果为准。
- Linux 桌面两边还各有一个仓库里没有的 `local-torch-cuda`（本机 GPU 专用），`sync-skills.sh` 不管它。

`antigravity-cli` 在 Claude Code 侧不止是 skill 目录：它的 `scripts/agy-guard.sh` 挂在
`~/.claude/settings.json` 的 PreToolUse 钩子上（见 [`../claude-code/`](../claude-code/)），
负责拦下裸 `agy -p` 与 agent 自行 `grant`。只装 skill 不配钩子，同意闸门就只剩文档约束。

**新装一个 skill 是手动动作**（各台机器、两个 harness 的集合本就不同，脚本不会替你决定）：
先建空目录，再让脚本渲染写入。**不要直接 `cp`**，那会把 `<your-home>` 这类占位符原样拷过去。

```bash
mkdir ~/.claude/skills/<name>        # 或 ~/.gemini/config/skills/<name>、~/.agents/skills/<name>
bash ../../tools/sync-skills.sh deploy <name>
```

卸载就是删掉部署位里那个目录（先备份到 `tmp/`）。之后由 `sync-skills.sh` 维持一致。
不要 `ln -s`，见 [`../../conventions.zh.md`](../../conventions.zh.md)。

## 约定

- **frontmatter 纯 ASCII**，尤其 `description`：它每个会话都加载，并参与触发匹配。
  正文（frontmatter 以下）可以中文。
- **`description` 不加引号时，里面不能出现 `: ` 或 ` #`**，要用 ` -- ` 代替冒号，或者整体加引号 / 用 `>-` 折叠。
  这在 YAML 里不合法：Claude Code 的加载器能容忍，照样加载；但 `npx skills` 这类严格解析器会**不报错地跳过整个 skill**。
  `deepln-setup`、`gpu-cuda-checks` 就是这样在公开 skill 仓库里消失的。`tools/publish.sh` 导出前会检查这一条。
- 带 `SKILL.zh.md` 的 skill，中文版是对照副本，**不被 harness 加载**，以英文主版为准。
- **第三方 skill（`find-skills`、`skill-creator`）原样保留**，不套本仓库的规则（`~/.agents` 路径、「路径」说明等），
  更新时整个目录重新从上游拷贝；来源与许可证记在根目录 README 的「第三方内容」一节，`publish.sh` 不把它们发到公开 skill 仓库。
  `skill-creator` 在 Claude Code 里已经由官方插件 `skill-creator@claude-plugins-official` 提供，所以只装 `.gemini`，免得两份同名。
- **skill 里调用自身脚本的路径统一写 `~/.agents/skills/<name>/...`**，并在第一处用到的地方加一条「路径」说明：
  装在 `~/.claude/skills/`、`~/.gemini/config/skills/` 也行，用相对本 SKILL.md 的路径也行，三处有一处存在就能执行。
  不要写死某个 harness 的目录。以前 `docx-to-md`、`pdf-to-md` 写的是 `.gemini`，只装 `.claude` 的机器就找不到脚本。
  例外是 Claude Code 的钩子配置（`~/.claude/settings.json` 里的 `agy-guard.sh`）：它只在 Claude Code 下运行，
  照旧写 `~/.claude/skills/`；`agy-guard.sh` 提示用户运行的命令，按它自己所在的目录推算。
