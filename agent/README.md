# AI 工具链

| 路径 | 内容 | 部署到 |
| :--- | :--- | :--- |
| [`claude-code/`](claude-code/) | `settings.json`、全局约定原件 `claude-global.md`、状态栏脚本 | `~/.claude/`（`cp`） |
| [`antigravity/`](antigravity/) | 全局约定原件 `agents-brave-uv.md`，`agy` CLI 用法与读图记录 | `~/.gemini/config/AGENTS.md`（`cp`） |
| [`minimax-code/`](minimax-code/) | 全局约定原件 `agents-windows.md`：Windows 侧约定，含实测的环境事实、幽灵命令表、编码三层与「先读再跑」路由 | `~/.minimax/AGENTS.md`（`cp`） |
| [`windows-agent/`](windows-agent/) | `agents-additional.md`——Windows 端 AGENTS.md 应该多写什么、每条的实测依据与取舍理由（`minimax-code/` 那份的设计说明）；`ghost-commands.md`——幽灵命令的排查与清除手册（为什么 0 字节不能判真假、哪些别名不能关、为什么硬链接优于 `.cmd` shim） | — |
| [`brave-search/`](brave-search/) | `bx` CLI 与 Brave Search MCP 的接入说明 | — |
| [`skills/`](skills/) | 全部 skill，两边共用 | `~/.claude/skills/`、`~/.gemini/config/skills/`、`~/.agents/skills/`（**只能**用 `tools/sync-skills.sh`，不能 `cp`） |

- 同一个工具可能出现在两处：`antigravity/` 是配置原件与使用记录，`skills/antigravity-cli/` 是给 agent 调用的 skill；
  `brave-search/` 与 `skills/bx/` 同理。改行为改 skill，改部署配置改前者。
- 全局约定原件故意不叫 `CLAUDE.md` / `AGENTS.md`：harness 会把子目录里这两个名字的文件当作指令自动加载。
- **不要用 `@路径` 转发**。根目录曾有一个 11 字节的 `CLAUDE.md`，内容只有 `@AGENTS.md`，
  靠 Claude Code 的 import 语法把根 `AGENTS.md` 引过来：换个 harness 就只剩一个空文件，
  在公开仓库里也是断链。已删除，让原件自身就是完整文件。
