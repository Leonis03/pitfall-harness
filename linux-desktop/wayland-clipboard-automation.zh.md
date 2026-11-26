# Plasma Wayland 桌面上的剪贴板与按键自动化

> **适用环境**：Fedora 44、KDE Plasma 6.7.5、**Wayland** 会话，Fcitx 5 作为 KWin 的输入法（见
> [`wayland-fcitx5-rime.zh.md`](wayland-fcitx5-rime.zh.md) 的根因四），有 XWayland。CopyQ 17.0.0、
> wl-clipboard 2.2.1、xclip 0.13、xdotool、ydotool。
> **实测时间** 2026-11-22。这台台式机上的 Fedora 已于 2026-11 弃用，本文是一份时间点记录。
>
> **适用场景**：X11 下的那些便利 —— 会替你粘贴的剪贴板管理器、命令行剪贴板工具、替用户打字 ——
> 在 Wayland 上哪些还能用、哪些要绕、哪些根本做不到。它是在 Wayland 和 X11 会话之间做选择的依据。

---

## 总表

| 项目 | 结果 |
| :--- | :--- |
| CopyQ 记录原生 Wayland 程序里的复制 | 能用 |
| CopyQ 记录 XWayland 程序里的复制 | 能用 |
| CopyQ 自带的全局快捷键（`Meta+V`），焦点在原生 Wayland 窗口上 | 能用 |
| 在 CopyQ 里选中一条，放到剪贴板 | 能用 |
| 在 CopyQ 里选中一条，**直接粘贴进当前窗口** | **不行** —— 要再按一次真正的 Ctrl+V |
| `wl-copy` -> `wl-paste` | 能用 |
| X11 -> Wayland 剪贴板（`xclip` -> `wl-paste`） | 能用 |
| Wayland -> X11 剪贴板（`wl-copy` -> `xclip -o`） | 这次测试失败 —— 见下文 |
| 主选区（中键粘贴），X11 -> Wayland | 能用 |
| 主选区，Wayland -> X11 | 这次测试失败 —— 见下文 |
| `xdotool type` 往任何窗口打字，包括 XWayland 窗口 | **不行** |
| `ydotool type` 往原生 Wayland、XWayland、X11 窗口打字 | 能用 |

在 X11 会话里，这张表的每一行都能用 —— 这也是保留一个 X11 会话的主要理由。

---

## CopyQ：历史记录能用，替你粘贴不行

两类客户端的复制都能被记录：原生 Wayland 下的 Chrome 和 XWayland 下的 Chrome（`--ozone-platform=x11`）
里复制的内容，都成了最新一条（`copyq read 0`）。在 CopyQ 自己的设置里绑的全局快捷键，能在焦点位于原生
Wayland 窗口时弹出它的菜单，并选中第一条。

选中一条（回车）会把它放到剪贴板上 —— `wl-paste` 能读出来 —— 并把焦点还给之前的窗口。但 CopyQ 接下来的
"粘贴"那一步，也就是它模拟的 Ctrl+V，在原生 Wayland 窗口和 XWayland 窗口里都没有送达：文本框原样不变。
紧接着用 `ydotool` 发一个真正的 Ctrl+V，就能粘贴进去。

所以整条链只断在最后一步。变通办法是写一个 CopyQ 命令或快捷键：先激活这一条，再用 `ydotool` 发 Ctrl+V。
CopyQ 的文档也把"粘贴进其他程序"列为 Wayland 下要看桌面支持的功能。

---

## Wayland 与 XWayland 之间的剪贴板和主选区

在原生 Wayland 的终端里实测：

| 方向 | 命令 | 结果 |
| :--- | :--- | :--- |
| Wayland -> Wayland | `wl-copy` -> `wl-paste` | 能用 |
| X11 -> Wayland | `xclip -selection clipboard` -> `wl-paste` | 能用 |
| Wayland -> X11 | `wl-copy` -> `xclip -o -selection clipboard` | `There is no owner for the CLIPBOARD selection` |
| X11 -> Wayland，主选区 | `xclip` -> `wl-paste --primary` | 能用 |
| Wayland -> X11，主选区 | `wl-copy --primary` -> `xclip -o -selection primary` | `There is no owner for the PRIMARY selection` |

X11 那边设的内容，Wayland 客户端都看得见；Wayland 这边设的内容，X11 那边没看见。CopyQ 自己两边都看得见。

**尚未定论**：读 `xclip -o` 时是在原生 Wayland 终端里，没有任何 XWayland 窗口获得焦点。合成器可能只在
某个 X11 窗口拿到焦点时，才把 Wayland 剪贴板交给 XWayland —— 那样的话，这个方向的失败就是测法造成的，
而不是真的做不到。要定论，先让一个 XWayland 窗口获得焦点（比如带 `--ozone-platform=x11` 的 Chrome），
再用 `xclip -o` 读。

---

## 替用户打字：`xdotool` 不行，`ydotool` 行

| 目标窗口 | `xdotool type` | `ydotool type` |
| :--- | :--- | :--- |
| Chrome，原生 Wayland | 什么也没打进去 | 能用 |
| XWayland 下的 Chrome | 什么也没打进去 | 能用 |
| 强制走 X11 的 Konsole（`QT_QPA_PLATFORM=xcb`） | 什么也没打进去 | 能用 |

连跑在 XWayland 下的 X11 窗口，`xdotool` 都打不进去，而 `xdotool getactivewindow` 仍能报出这个窗口和它的名字
—— 它看得见 X11 窗口，却打不了字。`ydotool` 往内核的 uinput 设备写，和物理键盘是同一条路径，合成器把它当成
真实输入，所以到哪都能用；它需要后台进程在运行，并且能访问 `/dev/uinput`。

**涉及输入法时，自动打字必须用人手的速度。** `ydotool` 默认每键 20 ms，甚至 110 ms，客户端收键都比输入法
往返快：Firefox 会丢键，text-input-v3 下的 Chrome 会把每个字母单独上屏，Plasma 开始菜单的搜索框在第一个键
之后就丢了输入法 —— 而手敲时它完全正常。把按键间隔调到 130-140 ms，所有客户端都能正常转换。只在自动化下
才失败的测试，在有人亲手敲过一遍之前，都不算结论。

---

## 选会话时意味着什么

- 在 Plasma Wayland 上，剪贴板历史本身不是问题；替用户粘贴和替用户打字才是。这两件事都要靠 `ydotool`，
  而它是以 root 级输入设备的身份运行的。
- 任何建立在 `xdotool` 上的东西 —— 文本扩展、宏工具、会打字的脚本 —— 要么移植到 `ydotool` 或某个合成器专用的
  工具上，要么留在 X11 会话里。
- X11 会话（比如 Debian 13 上 KDE Plasma 的 X11 会话，或者 Cinnamon）不用任何变通，上面这些全都能用。
