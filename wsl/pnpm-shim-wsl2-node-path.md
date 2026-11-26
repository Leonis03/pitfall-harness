# pnpm 全局 shim 在 WSL2 下把脚本交给了 Windows node

**一句话**：`pnpm add -g` 装进 WSL 的 CLI 可以装得完全正确、却起不来——pnpm 给它写的 shim
在**运行时**挑解释器，而 WSL2 上那条挑选路径优先要 `node.exe`，于是 Windows node 拿到一条
`\\wsl.localhost\...` 的 UNC 路径，而 Windows 读不了 pnpm store 里的 Linux 软链。

本文所有结论均为本机实测（Debian 13 / WSL 3.0.3.0 / nvm v0.40.8 / Node v24.22.1 /
pnpm 12.15.0），不是推测。

---

## 症状

```
$ mcode --version
Error: Cannot find module '\\wsl.localhost\<distro>\home\<user>\.local\share\pnpm\global\v11\<hash>\node_modules\@<scope>\<pkg>\cli.js'
    at Module._resolveFilename (node:internal/modules/cjs/loader:1564:15)
    ...
  code: 'MODULE_NOT_FOUND',
  requireStack: []
}
```

两个细节让它比看上去难查：

- **报错里的路径是存在的**。在 Linux 里 `ls` 它完全正常，模块就在那儿，是解释器够不着它。
- **Node 版本号不暴露是谁在跑**。实测机上 Windows 的 node 与 nvm 的 node 同为 24.22.1，
  报错尾部照样打 `Node.js v24.22.1`。看 banner 判断不出解释器是哪一个。

---

## 根因一：shim 的解释器挑选阶梯

pnpm 给每个 bin 写一个 shell shim。当包的 `bin` 指向**脚本**（`.js` 入口）时，shim 必须自己挑
一个解释器，而它是**运行时**挑的，顺序固定：

| # | 条件 | 解释器 | 交给它的路径 |
| :--- | :--- | :--- | :--- |
| 1 | `$basedir/node.exe` 存在 | 它 | Windows 路径（`wslpath -w`） |
| 2 | `$basedir/node` 存在 | 它 | Linux 路径 |
| 3 | MSYS/Cygwin 且 `node` 在 PATH | `node` | Windows 路径 |
| 4 | **`node` 在 PATH** | `node` | **Linux 路径** |
| 5 | **`node.exe` 在 PATH** | `node.exe` | **Windows 路径** |
| 6 | 都没有 | `node`（找不到） | Linux 路径 |

WSL2 分支不是用户选的：shim 跑 `uname -a`，内核版本串里就带 `WSL2`，于是它设 `exe=".exe"`
并预先算出一条 Windows 版基目录路径。**第 4 行才是想要的；第 5 行是"WSL 里没有 Linux `node`、
但 Windows PATH 被追加进来"时命中的那一条**——`node.exe` 收到的是
`\\wsl.localhost\<distro>\home\<user>\...`，走的是 WSL 的 UNC 文件提供程序。

---

## 根因二：Windows node 读不了那条路径

pnpm 的全局 store 满是软链。实测布局：

```
$PNPM_HOME/global/v11/<hash>                       -> 软链到 <hash>-<n>
$PNPM_HOME/global/v11/<hash>/node_modules/<pkg>    -> 软链到 ../.pnpm/<pkg>@<ver>/node_modules/<pkg>
```

用 Windows node（在 Windows 文件系统上的脚本里）对同一批路径做 `fs.existsSync`：

| 路径 | 结果 |
| :--- | :--- |
| `global\v11\<hash>\node_modules\<pkg>\cli.js`（两层软链） | `false`，`lstat` 报 ENOENT |
| `global\v11\<hash>-<n>\node_modules\<pkg>\cli.js`（一层软链） | `false`，`lstat` 报 ENOENT |
| `global\v11\<hash>-<n>\node_modules\.pnpm\<pkg>@<ver>\node_modules\<pkg>\cli.js`（无软链） | `true` |

也就是说，Windows node 只看得见**完全解析后**的路径，凡路径里含软链就够不着。shim 给的路径
含两层。**报成 "module not found" 而不是权限或路径错误**，是因为模块查找跑在了一条
Windows 文件系统提供程序无法解析的路径上。

推论：**没有任何 Windows 侧的 node 能运行装在 WSL 文件系统里的 pnpm JS CLI。** 这不是 pnpm 的
bug，是 WSL UNC 提供程序对 Linux 软链的处理方式。

---

## 四种组合，四种表现

| WSL 里有 Linux `node`？ | Windows PATH 被追加？ | 命中 | 你看到的 |
| :--- | :--- | :--- | :--- |
| 有 | 否 | 第 4 行 | 正常 |
| 有 | 是 | 第 4 行 | 正常 |
| **无** | **是** | 第 5 行 | `Cannot find module '\\wsl.localhost\...'` |
| 无 | 否 | 第 6 行 | `node: command not found` |

第 6 行是诚实的失败，第 5 行是糊涂的失败。`appendWindowsPath=false`（本仓库
`wsl/setup/files/wsl.conf` 的默认值）的作用就是：**不让"缺 Linux node"这件事退化成第 5 行。**

---

## 两个把机器推进"坏状态"的陷阱

### 陷阱一：让安装器别碰 rc 文件 = 把激活推给一个可能永远不会发生的步骤

nvm 的安装器默认往 rc 文件追加激活行，除非设 `PROFILE=/dev/null`。在本仓库里**关掉它是对的**
——PATH 归 `~/.shell_common` 管，而 `~/.shell_common` 自己 source `nvm.sh`
（见 `shell/files/shell_common` 第 4 节）。但它只在 **shell 层已部署之后**才成立。

坏掉的顺序是：先用 `PROFILE=/dev/null` 装工具链（步骤 5），shell 层（步骤 4）还没铺，
然后宣布这台机器"装好了"。于是 nvm 在盘上、`nvm alias default 24` 也设了，
**却没有任何人读它**——激活行所在的那个文件从来没被写过。

症状：新开的交互 shell 里 `command -v node` 是空的，而且**每一个** shell 里都空。

### 陷阱二：在手工拼出来的 PATH 里做验证，不算验证

一个开头是这样的脚本：

```bash
export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh" >/dev/null 2>&1
```

会**对任何 pnpm 装的东西都报成功**——因为它把安装器本该提供的环境又自己造了一遍。
于是交接表会长成这样：

```
| nvm   | v0.40.8 已装（PROFILE=/dev/null） |
| mcode | mcode --version -> 0.6.12       |
```

第二行**只在跑它的那个脚本里为真**。

能发现它的检查，要**用用户的调用方式**去跑：

```bash
env -i HOME="$HOME" TERM=xterm bash -ic 'command -v node && mcode --version'
```

`env -i` 不能省：继承自交互祖先的 PATH 同样会让检查为真（这正是步骤 5 里对 nvm 记的同一个坑）。

### 顺带：原生二进制和脚本入口的失败方式不一样

`bin` 指向**原生二进制**的包，shim 里**根本没有解释器阶梯**，直接用 Linux 路径 exec 二进制，
所以没有 `node` 也能跑；`bin` 指向 `.js` 的包才有阶梯、会炸。
**"一个 CLI 能跑、另一个不能" 不能作为"装好了"的证据。**

---

## 检查清单

1. `env -i HOME="$HOME" TERM=xterm bash -ic 'command -v node'` —— 必须打印一个 Linux 路径
2. `env -i HOME="$HOME" TERM=xterm bash -ic '<cli> --version'` —— 用用户实际会用的方式
3. `diff /etc/wsl.conf <仓库原件>` —— 现网文件必须带 `[interop] appendWindowsPath=false`；
   被 Windows 端安装器写出来的 `wsl.conf` 常常只有 `[boot] systemd=true`
4. `echo "$PATH" | tr ':' '\n' | grep -i 'nodejs\|node.exe'` —— Windows 的 node 目录在 PATH 上，
   第 5 行就是可达的
5. 改完 `/etc/wsl.conf` 之后：在 Windows 侧 `wsl --shutdown`（会停掉**所有**发行版）

---

## 给 WSL 侧 agent 的备注

- 报错里的 `\\wsl.localhost\...` 是 **Windows UNC 路径**，不是 Linux 路径。在 Linux 里 `ls` 它
  是好的——不要去找"丢失的文件"。
- 路径里那串 hash 是 pnpm 的 store id，既不是版本号也不是错误码。
- **这种状态下 `pnpm` 本身照常能用**：pnpm 是独立二进制，不是脚本，永远不走那条阶梯。
  所以"`pnpm -v` 正常"完全不能说明装出来的 CLI 能跑。
- 原生模块是另一根独立的轴：带 `better-sqlite3`（linux-x64 编译）的包即使路径解析成功，
  也不能交给 Windows node 跑。

---

## 相关文档

- [`setup/README.md`](setup/README.md) 步骤 1（`/etc/wsl.conf`）与步骤 5（工具链）
- [`../shell/README.md`](../shell/README.md) —— 四层分层，以及 PATH 为什么归 `~/.shell_common`
- [`../linux-desktop/README.md`](../linux-desktop/README.md) 2.13 / 2.16 / 2.17 —— pnpm 的 build
  审批门禁，以及 Node 大版本升级作废原生模块
