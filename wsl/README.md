# WSL2

Windows 11 + WSL2 这台机器的 Linux 侧。bash / zsh 的四层配置与原生 Linux 桌面共用，不在这里，在 [`../shell/`](../shell/)。

| 路径 | 内容 |
| :--- | :--- |
| [`setup/`](setup/) | **环境复刻指南**（可整份发给 agent 执行）。`files/` 下是 WSL 专属原件：`wsl.conf`、`.wslconfig`、`fstab`、binfmt / `/mnt/wsl` 守护 unit、`wslview` |
| [`distro-differences.md`](distro-differences.md) | Ubuntu 24.04 与 Fedora 44 的差异：哪些可避免、哪些是发行版决定的 |
| [`gui-ime/`](gui-ime/) | WSLg 图形应用与 fcitx5 中文输入法；`wayland-ime-smoke.sh` 是冒烟测试 |
| [`uninstall-cleanup.md`](uninstall-cleanup.md) | 卸载 WSL：单个发行版、整个 WSL、残留清理、验证与重装（英文） |
| [`storage/`](storage/) | 迁盘、磁盘清理，以及一次 `E_ACCESSDENIED` 故障的原始取证记录 |

核心思路是 **`appendWindowsPath=false` + 显式函数桥接**：不注入 Windows 的几百个 PATH 条目，
只把真正需要的几个 `.exe` 包成 shell 函数（见 [`../shell/files/shell_wslfn`](../shell/files/shell_wslfn)）。

从 WSL 调 Windows 命令、跨发行版操作的排查，在 skill [`../agent/skills/wsl-windows-command/`](../agent/skills/wsl-windows-command/)。
