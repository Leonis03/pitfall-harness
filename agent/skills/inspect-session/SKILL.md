---
name: inspect-session
description: Inspect, audit, and analyze coding agent conversation transcripts (Claude Code JSONL, Antigravity/Gemini, MiniMax Code, CodeBuddy CLI). Use when the user asks to check what files an agent modified, review Git commits and commands run in a past session, inspect conversation timelines, compare branched DAG forks, search past interactions, or export structured Markdown reports.
---

# Inspect Session

审查、诊断与结构化分析 AI 编程智能体（Claude Code、Antigravity / Gemini CLI、MiniMax Code、CodeBuddy CLI）的历史会话记录。

专为回答「**这个会话改了哪些文件？**」、「**对 Git 仓库执行了哪些操作？**」、「**会话分叉后两条路径各自做了什么？**」以及「**将会话导出为整洁的 Markdown 报告**」等场景设计。

---

## 快速使用 (Quick Start)

所有命令均使用系统规范的 Python 运行时执行：

> **路径**：下面的命令统一写 `~/.agents/skills/inspect-session/`。装在别处也能用，换成实际位置即可：`~/.claude/skills/inspect-session/`、`~/.gemini/config/skills/inspect-session/`，或相对本 SKILL.md 的路径，三处有一处存在就行。

```bash
# 1. 会话总览（统计、角色轮次、工具调用分布、分支拓扑）
PYTHONUNBUFFERED=1 uv run --python 3.12 python ~/.agents/skills/inspect-session/scripts/inspect.py <JSONL_PATH>

# 2. 文件变更与 Git 变更审计（核心：回答会话修改了什么）
PYTHONUNBUFFERED=1 uv run --python 3.12 python ~/.agents/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --changes

# 3. 详细 Git 操作审计（查看所有 git commit, push, diff, status）
PYTHONUNBUFFERED=1 uv run --python 3.12 python ~/.agents/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --git

# 4. 对话时间线流（按时间查看用户输入与模型回应）
PYTHONUNBUFFERED=1 uv run --python 3.12 python ~/.agents/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --timeline

# 5. 错误与失败审计（定位所有抛错工具与退出码）
PYTHONUNBUFFERED=1 uv run --python 3.12 python ~/.agents/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --errors

# 6. 会话内关键词搜索
PYTHONUNBUFFERED=1 uv run --python 3.12 python ~/.agents/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --search "关键词"

# 7. 导出结构化 Markdown 审计报告
PYTHONUNBUFFERED=1 uv run --python 3.12 python ~/.agents/skills/inspect-session/scripts/inspect.py <JSONL_PATH> --export-md /path/to/report.md
```

脚本只用标准库。机器上没有 `uv` 时，直接用现有的 Python 3 跑也行（`python -I .../inspect.py <JSONL_PATH>`；Windows 上用 3.13 实测过）。

**Windows 中文控制台**：输出被管道接走时 stdout 是 GBK，旧版脚本打到第一个 `✓` 就 `UnicodeEncodeError` 退出。
现在 GBK 等非 UTF 编码下，状态符号换成 ASCII（`✓` → `[ok]`，`❌` → `[X]`，emoji 角色标签去掉），
其他编不了的字符写成 `?`；`--json` 改用 `\uXXXX` 转义，内容不丢。`PYTHONIOENCODING` 救不了这个问题：
`python -I` 会忽略所有 `PYTHON*` 环境变量，所以修在脚本里。

### 怎么找到会话文件

| 智能体 | 目录 | 取哪个文件 |
| :--- | :--- | :--- |
| Claude Code | `~/.claude/projects/<项目路径转义>/` | 该目录下最新的 `*.jsonl` |
| Antigravity | `~/.gemini/antigravity-cli/brain/<session-id>/.system_generated/logs/` | `transcript.jsonl`（脚本自动合并 `transcript_full.jsonl` 的完整内容） |
| MiniMax Code | `~/.minimax/v2/sessions/<年>/<月>/<日>/` | 目录名以 `-session_` 结尾的那个，取其中的 `messages.jsonl` |
| CodeBuddy CLI | `~/.codebuddy/` 下（具体子目录未实测） | 文件名是 `<session-id>.jsonl`：`find ~/.codebuddy -name '<session-id>.jsonl'` |

---

## 核心功能与使用场景

### 1. 变更审计 (`--changes` / `--git`)
当用户询问类似「*这个会话对我的项目改了什么？*」、「*刚才 Claude 提交代码了吗？*」时使用：
- **`--changes`**：自动归纳被创建或编辑的文件列表（包含操作行号、修改行数增减对比 `+X/-Y`、执行成功与否），并附带执行的 Git 命令汇总。
- **`--git`**：逐条列出所有 Git 操作（commit 信息、操作意图说明、原始命令、终端输出预览、退出状态）。

### 2. 分支深度感知与分支对比 (`--diff-branches` / `--branch`)
在 Claude Code 会话因 retry 或并发 resume 发生 DAG 分叉（多分支）时：
- **`--diff-branches 1 2`**：精准定位分叉点（Fork Point），并对比分支 1 和分支 2 在分叉之后：
  - 各自执行了哪些独特的工具调用与文件改动
  - 各自进行了哪些独特的用户对话
  - 辅助用户在运行 `trim-branch` 剪枝前，直观确认应该保留哪一条分支。
- **`--branch N`**：约束任何审计视图（`--summary`, `--changes`, `--timeline` 等），仅沿着第 N 条最深分支的血统链（Leaf -> Root）进行回溯分析。

### 3. 会话时间线 (`--timeline`)
按时间先后顺序展示会话演进：
- `--user-only`：只看用户的 Prompt 轨迹。
- `--tools-only`：只看工具执行流水。
- `--full`：展开完整消息文本（不进行 100 字符省略截断）。
- `--limit N`：限制展示条数。

### 4. 故障排查 (`--errors`)
快速过滤出会话中所有失败的操作：
- 失败的 Bash 命令（非零退出码）
- Hook 拦截警告（如 PreToolUse 守卫拦截）
- 文件编辑失败、权限拒绝或找不到目标内容错误

### 5. 格式兼容性
脚本原生自动识别四种格式，无需显式指定参数：

| 格式 | 会话文件位置 | 识别特征 |
| :--- | :--- | :--- |
| **Claude Code** | `~/.claude/projects/.../*.jsonl` | 顶层 `type`、`parentUuid` DAG、`ai-title`、`tool_use` / `tool_result` |
| **Antigravity / Gemini** | `~/.gemini/antigravity-cli/brain/<session>/.system_generated/logs/transcript.jsonl` | 顶层 `step_index`、`PLANNER_RESPONSE` / `GENERIC`、`run_command` |
| **MiniMax Code** | `~/.minimax/v2/sessions/<Y>/<M>/<D>/<session>/messages.jsonl` | 顶层 `message_id` / `turn_id`、`message.role` 为 `toolResult` / `custom` |
| **CodeBuddy CLI** | `~/.codebuddy/` 下的 `<session-id>.jsonl` | `session-meta.meta` 含 `codebuddy.ai/*` 键，`_meta.baggage` 含 `codebuddy.session_id`；顶层 `type` 为 `message` / `reasoning` / `function_call` / `function_call_result` |

CodeBuddy 也有顶层 `type` 和 `ai-title` 记录，旧版脚本把它误判成 Claude Code，报 0 个提问、0 次工具调用。
现在按 `codebuddy` 标记先认出来。

各格式的坑（脚本已处理，列在这里是为了让你读懂输出）：

- **Antigravity：调用记录与工具结果是交错的**。文件行序不等于因果序——一次发两个调用时，
  第一个结果可能写在调用记录**之前**。脚本按 `(created_at, 文件位置)` 排序后再配对，
  每个结果归还给最早那个还在等结果的调用。按文件顺序配对会让结果整体错位一格。
- **Antigravity：工具输出会被截断**。同目录另有一份 `transcript_full.jsonl`；
  脚本检测到 `truncated_fields` 时自动把完整内容合并回来（截断点在 2 KB，
  不合并就搜不到后半段正文）。
- **Antigravity：`chunks/transcript/` 下是按字节切片的副本**，记录会跨切片边界，
  单个 chunk 不是合法会话。脚本检测到这个路径会把整组 chunk 重新拼回去，
  所以指向任意一个 chunk 都能得到与 `transcript.jsonl` 一致的结果。
- **Antigravity：失败有两种**。命令非零退出（`exited with code N`）和步骤执行失败
  （`Encountered error in step execution:`）。只看退出码会漏掉后者。
- **Antigravity：API 层错误是独立记录**（`ERROR_MESSAGE`），不属于任何工具调用，
  单独列为 `api_error`。
- **MiniMax：大输出被外置成 artifact**。`toolResult` 里只剩一段「请去读 artifact」的提示，
  真内容在会话目录的 `reports/tool-outputs/` 下。脚本把路径记进 `externalized_artifact`，
  `--errors` 会打印出来。
- **MiniMax / CodeBuddy：时间戳是 epoch 毫秒**（Claude Code / Antigravity 是 ISO 字符串），
  脚本统一格式化成本地时间（`--export-md` 里也是）。
- **CodeBuddy：一次模型回复拆成好几条记录**。`reasoning`、每个工具一条 `function_call`、
  一条 assistant `message`，共用 `providerData.messageId`。脚本按它合回一个 assistant 轮次；
  `reasoning` 是思维链，不进正文。模型名取 `providerData.model`，总览里显示。
- **CodeBuddy：不少 "user" 记录是工具链写的**。`command-caveat` 提示直接丢掉；
  `<command-name>`、`<local-command-stdout>`（斜杠命令及其输出）、`<task-notification>`
  （后台任务结束通知）和其他 `isMeta` / `skipRun` 记录显示为 SYSTEM，不算用户提问。
- **CodeBuddy：退出码在结果文本末尾**（`Exit Code: N`，同时在 `providerData.toolResult.rawResponse.exitCode`）。
  非零退出码、`status` 不是 `completed`，都算失败。
- **CodeBuddy：后台命令当场只回 `Status: Running in background`**，退出码要等后来的
  `<task-notification>`（`completed with exit code N`）。脚本按 `<tool-use-id>` 把它交还给原调用，
  后台命令失败也会进 `--errors`。
- **CodeBuddy：没有结果的 `function_call`** 是被打断或会话先结束了，算失败并列进 `--errors`。
  用户打断（assistant 记录 `Interrupted by user`）显示为 SYSTEM 事件，次数记在总览的 notes 里；
  其他 API 错误（`providerData.error`）和 Antigravity 一样列为 `api_error`。

**`--git` 也收 `gh`**：Bash 命令里的 `gh pr` / `gh api` / `gh issue` 等 GitHub CLI 操作和 git 命令一起列出，
各格式通用。

**只有 Claude Code 有分叉**：`--branch N` 和 `--diff-branches A B` 依赖 `parentUuid` 构成的 DAG，
其余三种格式是线性流，用 `--timeline` 看全程。CodeBuddy 的 `id` / `parentId` 也成链，但按文件顺序展示；
链上真有分叉时总览的 notes 会写出来。其余视图（`--summary` / `--changes` / `--git` /
`--timeline` / `--errors` / `--search` / `--export-md`）四种格式通用。

---

## 与其他会话技能的分工与联动

- **`inspect-session`**（本技能）：**单会话行为审计与内容解析器**。在已知会话文件路径的前提下，完成零依赖的单会话透视（Git 操作账单、文件修改记录、分支差异对比、导出 Markdown）。
- **`trim-branch`**：会话分支裁剪：切除 DAG 拓扑分叉，安全抽取单个分支，并覆写原文件。
- **`cass`**：**全局跨会话搜索引擎**。跨 23+ 种 Agent 检索全局历史、关键词找过去的解决方案。
