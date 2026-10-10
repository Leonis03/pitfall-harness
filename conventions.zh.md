# 约定

*[English](conventions.md) · 中文 · 回到 [README](README.zh.md)*

- **项目理念：Agent 作为系统操作员的闭环沉淀**：
  把 Agent 当成系统的真实操作员（System Operator），人类通过自然语言提出目标，驱动 Agent 在真实环境进行 vibe 式探索；一旦通过实证把方案跑通，就把探索结果沉淀为可验证、可复现、可部署的 Markdown、配置、脚本和 Skill，从而让下一次 Agent 不必重新探索。
  
  ```text
  自然语言提出目标 → Agent 直接操作真实系统并执行命令 → 观察症状 → 定位并实证根因 → 得到可工作的配置/操作方案 → 把方案固化成配置、脚本、README、Skill 和验证方法 → 下次由 Agent 按这些确定性知识复现。

  一次性的 Agent 探索
          ↓
         经验
          ↓
       结构化结论
      ↙    ↓    ↘
  Config README Skill
      ↘    ↓    ↙
       可执行规范
          ↓
    下一次 Agent 复用
  ```
- **这些地方只用纯 ASCII**：目录名与文件名、系统与工具的配置文件（**含其中的注释**，注释写英文）、
  每个 skill 的 YAML frontmatter（尤其 `description`，它每个会话都加载并参与触发匹配）。
  非 ASCII 跑到上面那几处，故障会**静默且远离原因**——跨 WSL/Windows 边界、打包、shell 与 harness 解析。
- **Markdown 文件名一律小写 kebab-case**：`wsl-gui-and-ime.md`，不用大写、下划线或空格。
  取证记录与时点快照在名字末尾加 `-YYYYMMDD`（`etc-diff-analysis-20260330.md`、
  `pnpm-npm-cleanup-20260920.md`），流程型与常青文档不加。
  唯一的例外是**协议性文件名**：`README.md`、`README.zh.md`、`SKILL.md`、`SKILL.zh.md`、
  `AGENTS.md`、`CLAUDE.md`、`TROUBLESHOOTING.md`——它们被工具或 harness 按字面查找，改了就失效。
- **`AGENTS.md` / `CLAUDE.md` 只在根目录出现**。harness 会把子目录里这两个名字的文件当作指令自动加载，
  所以要部署成这两个名字的**原件**在仓库里另起名字：`agent/claude-code/claude-global.md` →
  `~/.claude/CLAUDE.md`，`agent/antigravity/agents-brave-uv.md` → `~/.gemini/config/AGENTS.md`。
- **除 `tmp/` 外，每个顶层目录有一个 `README.md` 做索引**；目录里有 `files/` 的，`files/` 下是可直接部署的原件，
  其余是文档。原件若同时用于多个平台（如 bash / zsh 配置），放在平台无关的目录（[`shell/`](shell/)），
  不放在某个平台目录下。
- **Markdown 文件分为给人读的和给 Agent 读的（英文优先，中文直译）**：
  - **给 Agent 读写的**：用 Agent 最舒服、理解最精准、上下文最明确的方式——**英文（English）**。
  - **给人读的**：中文版作为人类参考对照，**使用直译**，人类能读懂即可。
  - **废除「先写中文正本再写 English」的旧要求**：以后编辑或新增文档，**统一先写给 Agent 读的英文版**（`x.md`），中文版（`x.zh.md`）通过直译生成。
  - 根目录文档双语配对（`README`、`conventions`、`redaction`），英文版是 Agent 执行的基准，中文版供人类理解。子目录常规取证与笔记主要供人类查阅；skill 则兼具两端，双语各有用处。根目录的 [`AGENTS.md`](AGENTS.md) 纯英文、纯 ASCII。
  - **目录结构、部署位或「必须一起改的文件」变了，同一个提交里更新 `AGENTS.md`**——它过期了，
    agent 就会按旧地图改错地方。
- **README 只做落地页与路由**：头部、从哪开始、目录、踩坑索引、许可证。
  成体系又不是每次都要读的内容拆成独立文件，在「从哪开始」那张表里留一行指过去——
  和 skill 用 `SKILL.md` + `references/` 分流是同一套做法。
  踩坑索引**故意留在 README**：它是这个仓库最值得看的东西，挪走会让落地页变成一张空目录。
- **Python 走 `uv`，固定 3.12**。系统 `/usr/bin/python3` 保留给 Ubuntu 的 apt 包，不动它。
- **装 skill 用 `cp`，不用 `ln -s`**。这棵树会在机器、文件系统和操作系统之间搬动，符号链接活不下来。
- **同步 skill 用 `bash tools/sync-skills.sh`，也不要裸 `cp`**。仓库里写的是 `<your-home>`、
  `CourseName` 这类占位符，脚本在写入 `~/.claude/skills/`、`~/.gemini/config/skills/` 或 `~/.agents/skills/`
  时展开成真值，核对时比对**渲染后**的字节——所以"哈希相同"的含义是「仓库 ≡ 部署位，模脱敏」。
  不带参数跑是只读核对。家目录的写法看**会不会被 shell 展开**：会展开就写 `$HOME`（原样发布的
  运行时变量，不是占位符），展不开才写 `<your-home>`——全仓库只剩 JSON 里的两行，
  详见 [`agent/skills/README.md`](agent/skills/README.md)。
- **临时的事情一律在 `tmp/` 里做**：要改之前先备份的副本、脚本的中间产物、想跑一下看看的片段、
  原始命令输出——都放这儿，不要散在仓库根目录，也不要丢进系统 `/tmp`（重启即失，第二天想复看时已经没了）。
  这个目录已 gitignore，`git archive` 导不出去，`privacy-gate.sh` 也**跳过**它，
  所以里面可以放带真实路径和账户名的东西，不会把门禁搞成天天红。
  `tmp/.gitkeep` 是被跟踪的，新 clone 下来目录就在。
- **没做完的内容和它的待办清单放在 `drafts/`，该目录只在私有仓库里。** 它在私有仓库中被跟踪
  （跨机器同步、有备份），但**永不导出**：`tools/publish.sh` 在跑隐私门禁之前就把它从导出里删掉，
  删不掉就拒绝继续；`privacy-gate.sh` 也像对 `tmp/` 一样跳过它。不要在其他文档里链接它，
  链接到了公开仓库里会失效。凭据照样不能放进去。要发布某篇草稿，就把它移到该去的目录、
  按 [`redaction.zh.md`](redaction.zh.md) 脱敏、再跑门禁。`drafts/README.md` 是索引，也是待办清单。
- **发布前跑 `bash tools/privacy-gate.sh`**。它只覆盖已知形态，跑通不等于安全——`wsl/storage/forensics/` 是原始取证输出，必须人工读。
  账户名**不写在脚本里**（写进去，这个脚本自己就成了泄露源），运行时从 `tools/.privacy-names`（已 gitignore）读取。
- **发布到公开仓库用 `bash tools/publish.sh`，不要手工 `cp -r`**。本仓库是**私有主仓 + 两个公开快照**：
  [`pitfall-harness`](https://github.com/Leonis03/pitfall-harness) 是整棵树，
  [`pitfall-harness-skills`](https://github.com/Leonis03/pitfall-harness-skills) 只有 skill
  （`agent/skills/<name>/` → `skills/<name>/`，不含第三方的 `find-skills`，README 由脚本按各 skill 的
  frontmatter 生成）。两个公开仓各自有 `.git`，本机各 clone 一份，目录名随意：

  ```bash
  bash tools/publish.sh <公开仓 clone> <skills 仓 clone>
  git -C <公开仓 clone> status        # 逐个看 diff，再各自 add / commit / push
  ```

  脚本做的事，也就是手工同步时不能省的步骤：
  - **导出的是 `origin/main`，不是 `HEAD`**。本机 checkout 常停在功能分支上，`git archive HEAD`
    会把那个分支发出去；`origin/main` 才是合并过、审过的内容。
  - **用 `git archive` 而不是 `cp -r`**，`tools/.privacy-names`、`tools/.sync-map`、`tmp/` 天然进不去。
  - **写入前先对导出内容跑 `privacy-gate.sh`**，没过就什么都不写。每条命中都读过、确认是预期的
    （比如账户名恰好等于公开作者名），才加 `--skip-gate` 重跑。
  - **先清空再解包**，否则私有仓里删掉的文件会残留在公开仓——`tar -x` 只覆盖不删除；清空时保留 `.git`。
  - **不自动提交**。发布是唯一撤不回的一步，所以 commit 与 push 留给人。

  - **公开仓的提交信息里不能带 AI 的 `Co-Authored-By`**（Claude、Codex、Copilot、Gemini 等）。GitHub
    会把共同作者列进仓库的 Contributors。`publish.sh` 借 [`github-coauthor-scrub`](agent/skills/github-coauthor-scrub/)
    skill 的脚本给两个 clone 装 commit-msg 钩子拒收这种提交，导出前也检查已有历史，发现就停下并给出清理步骤。
    私有仓库和它的 PR 不受这条限制。

  公开仓默认走**正常历史**，普通 `commit` + `push`，不要 `--amend` 强推——任何人 clone 过就会被打乱。
  **例外：以下情况允许改写历史并强推**——提交信息带了 AI 的 `Co-Authored-By`；把隐私、凭据等不该公开的
  内容发了出去，需要从历史里清掉；其他同等性质的特殊情况。做法固定：改写前先留一个本地备份分支，推送用
  `git push --force-with-lease=main:<改写前的 SHA>`，确认远端没有别人的新提交才覆盖；**推完再把默认分支改名
  再改回来**，否则 GitHub 缓存的 Contributors 里还挂着那个名字。整套步骤见
  [`github-coauthor-scrub`](agent/skills/github-coauthor-scrub/)（`rewrite` → 推送 → `refresh` → `verify`）。
  （先例：2026-09-28 去掉了 6 个提交里 Claude 的 `Co-Authored-By`；更早有两次 amend，一次补许可证、
  一次改提交消息格式。）
- **凭据不进版本库**。需要环境变量形式的 token 时放 `~/.shell_secrets`（`chmod 600`），由 `~/.shell_common` 末尾自动加载。

