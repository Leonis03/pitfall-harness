# WSL 存储与磁盘

## 指南（照着做）

| 文件 | 内容 |
| :--- | :--- |
| [`wsl-distro-move-to-d-drive.md`](wsl-distro-move-to-d-drive.md) | 把发行版的 `ext4.vhdx` 从 C 盘迁到 D 盘：`wsl --manage --move` 优先，导出/导入兜底；**系统重装后复用已有 vhdx** 走同一篇的「复用已有的 ext4.vhdx」一节（`wsl --import-in-place` + 导入前的 ACL 归一化 + WSL 本体重装） |
| [`pnpm-npm-cleanup-20260920.md`](pnpm-npm-cleanup-20260920.md) | pnpm 12 / npm 双端空间清理，以及 pnpm 10+ 默认拦掉 postinstall 的坑 |

回收 vhdx 空间：**WSL 3.0 起**用 `wsl --manage <Name> --compact`（先 `fstrim`、再 `wsl --shutdown`），
不用再走 `Optimize-VHD -Mode Full`，见 [`../setup/README.md`](../setup/README.md) 的「维护：回收 vhdx 空间」。
旧版 WSL 仍用 skill [`../../agent/skills/compress-wsl-space/`](../../agent/skills/compress-wsl-space/)。

## 取证记录（只读，别照做）

[`forensics/`](forensics/) 是 2026-03-29/30 那次迁盘后 `E_ACCESSDENIED` 故障的原始材料：
icacls / auditpol / Procmon 输出、新旧 `/etc` 对比、从对话导出里摘的 PATH 白名单讨论。

| 文件 | 内容 |
| :--- | :--- |
| [`wsl-eaccessdenied-investigation-20260330.md`](forensics/wsl-eaccessdenied-investigation-20260330.md) | 故障的完整排查过程与结论 |
| [`wsl-admin-vs-standard-evidence-20260330.md`](forensics/wsl-admin-vs-standard-evidence-20260330.md) | 管理员与标准用户两种启动方式的对照证据 |
| [`wsl-ubuntu-acl-record-20260329.md`](forensics/wsl-ubuntu-acl-record-20260329.md) | VHDX 的 ACL 原始记录 |
| [`etc-diff-analysis-20260330.md`](forensics/etc-diff-analysis-20260330.md) | 旧系统 `/etc` 与全新安装基线的差异 |
| [`wsl-path-whitelist-conversations.md`](forensics/wsl-path-whitelist-conversations.md) | `appendWindowsPath=false` 决定的来源对话摘录 |

- 这些文件描述的是**当时那台机器**，路径、版本和结论不一定适用于现在；现行做法以 [`../setup/`](../setup/) 为准。
- 这里是整个仓库脱敏风险最高的地方：`privacy-gate.sh` 只认已知形态，**改动或新增后必须逐行人工读**。
- `<t-...>` 是**稳定**占位符：同一个 token 在哪出现都指同一时刻，所以取证块之间的时间列仍可比对。
