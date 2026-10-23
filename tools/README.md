# tools

这里放两类东西，别混：

## 维护本仓库的脚本

| 文件 | 作用 |
| :--- | :--- |
| [`privacy-gate.sh`](privacy-gate.sh) | 提交 / 发布前的脱敏门禁。`bash tools/privacy-gate.sh`，退出码 0 = 已知形态都没命中（不等于安全） |
| [`sync-skills.sh`](sync-skills.sh) | skill 的渲染式部署与核对。不带参数 = 只读核对；`deploy [name]` = 展开占位符后写入 `~/.claude/skills/`、`~/.gemini/config/skills/`、`~/.agents/skills/` 里已装的 skill |
| [`publish.sh`](publish.sh) | 把 `origin/main` 导出到两个公开仓库的本地 clone（整棵树、只含 skill 的那份），写入前先跑门禁；给 clone 装 commit-msg 钩子拒收 AI 的 `Co-Authored-By`，已有历史里有就停下；不提交、不推送 |

两个脚本各读一个**不进版本库**的本机文件，每台机器单独准备：

- `tools/.privacy-names`：门禁要扫的真实账户名，一行一个
- `tools/.sync-map`：占位符 → 真值，`<your-home>=/home/...` 这种格式

规则与原理见 [`../conventions.zh.md`](../conventions.zh.md) 与 [`../redaction.zh.md`](../redaction.zh.md)。

### 这两个文件缺失时，脚本不会大声失败

新机器上最常见的情况是直接 clone 仓库然后干活，这两个文件并不存在。后果**不是报错退出**，
而是两个脚本各自**降级成更弱的保证**，而且都还返回成功：

| 缺哪个 | 实际发生什么 | 退出码 |
| :--- | :--- | :--- |
| `tools/.sync-map` | `sync-skills.sh` 直接 `exit 2`，打印一句 `error: ... not found`，**skill 的核对与部署能力整体失效** | 2 |
| `tools/.privacy-names` | `privacy-gate.sh` 明说 `the literal-name check was skipped`，**只扫已知形态**；除此之外照常运行，最后仍然打印 `RESULT: no known pattern matched` | 0 |

所以：

- 跑 `sync-skills.sh` 看到 `exit 2` 和 `.sync-map not found`，先建文件再排查别的，
  不要误以为是 skill 装坏了；
- `privacy-gate.sh` 退出 0 **不代表脱敏检查真的做了**，先确认 `.privacy-names` 在。
  它自己会把这句 warning 打出来，不要划过去。

最省事的初始化（`<your-home>` 是 `sync-skills.sh` 唯一需要的占位符）：

```bash
printf '%s\n' '<your-home>='"$HOME" > tools/.sync-map
```

`privacy-gate.sh` 需要你自己填账户名，它没有默认值，也**不该有**——这个文件不进版本库，
正是为了让脚本本身可以被公开。

## 工具笔记

| 路径 | 内容 |
| :--- | :--- |
| [`python/`](python/) | `no_proxy` 通配符失效、f-string 引号规则 |
| [`remote-ssh.md`](remote-ssh.md) | 远程执行：`pkill -f` 杀掉自己、BLAS 线程数设太晚、后台任务挂住 ssh |
| [`docker/`](docker/) | 零基础 Docker 入门：概念、镜像与容器 |
| [`latex/`](latex/) | VS Code LaTeX Workshop 工具链（`settings.json` 原件），以及中文文档为什么要关 ChkTeX |
