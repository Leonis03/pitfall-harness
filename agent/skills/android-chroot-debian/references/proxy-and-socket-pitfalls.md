# Android chroot 里的代理变量与跨会话 socket：两个静默故障

本文记录在 Termux root Debian chroot 上实测到的三个坑。共同点是：报错信息都指向别处，
而真正的根因都在一个 shell 配置文件里。

- [1. 代理变量指向会消失的端口](#1-代理变量指向会消失的端口)
- [2. 一个端口不能同时当 HTTP 和 SOCKS](#2-一个端口不能同时当-http-和-socks)
- [3. 写死的 socket 路径让会话互相挤掉](#3-写死的-socket-路径让会话互相挤掉)

---

## 1. 代理变量指向会消失的端口

### 症状

不开代理软件时，Claude Code 发 prompt 直接 `connection refused`：

```text
--messaging-socket-path points to a live socket: ...
```

```text
Error: connect ECONNREFUSED 127.0.0.1:<proxy-port>
```

而开着代理软件时一切正常。直连也能通——同一个 API 端点绕开代理直接访问，返回的是正常的
HTTP 状态码（401/404 表示"请求到达了服务器"，不是"连不上"）。

### 根因 `[实测]`

`~/.shell_common` 第 5 节无条件导出代理变量：

```sh
export HTTP_PROXY="http://${host_ip}:${proxy_port}"
export HTTPS_PROXY="http://${host_ip}:${proxy_port}"
export http_proxy="http://${host_ip}:${proxy_port}"
export https_proxy="http://${host_ip}:${proxy_port}"
export ALL_PROXY="socks5h://${host_ip}:${proxy_port}"
export all_proxy="socks5h://${host_ip}:${proxy_port}"
```

在这个 chroot 里，代理软件是**宿主 Android 上的一个应用**，不是 chroot 内部的东西。
chroot 与宿主共享 network namespace（`readlink /proc/self/ns/net` 与 `/proc/1/ns/net` 相同），
所以宿主的监听端口在 chroot 里就是 `127.0.0.1:<port>`。

问题在于"应用"这个性质：**它随时可以被用户关掉**。代理关掉后，那个端口就没有任何进程
监听，而变量还在环境里，于是每一个走代理的请求瞬间被拒。直连本来是通的，代理却把它堵死了。

这和 WSL 的情况是同一类病，但成因不同，所以照抄 WSL 的解法也没用：
[WSL 下 `host_ip=127.0.0.1` 只有在 mirrored 模式下才对](../../../../wsl/setup/README.md)，
而这里 `127.0.0.1` 永远正确（共享 netns），跟 networking mode 无关。

### 实证方法

先问"端口有没有人监听"，再问"请求能不能通"：

```bash
# 1. 端口到底有没有人监听
timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/<proxy-port>' && echo OPEN || echo refused

# 2. 带代理 vs 清代理，同一条命令
curl -s -o /dev/null -w '%{http_code}\n' -m 8 -x http://127.0.0.1:<proxy-port> <url>
env -u http_proxy -u https_proxy -u all_proxy \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    curl -s -o /dev/null -w '%{http_code}\n' -m 8 <url>
```

第 2 条是关键：两个都返回非 `000` 说明两条路都通，那代理变量就是纯负担；
只有带代理的那条是 `000` 而清代理的是正常状态码，说明代理这条路本身坏了。

> `/dev/tcp` 是 bash 特性，zsh 没有。用 `bash -c` 显式调用，别直接写在 zsh 里。

### 处置

注释掉第 5 节的 `export`，保留 `NO_PROXY` / `no_proxy`：

```sh
# export HTTP_PROXY="http://${host_ip}:${proxy_http_port}"
# export HTTPS_PROXY="http://${host_ip}:${proxy_http_port}"
# ...
export NO_PROXY="localhost,127.0.0.1,::1,.local"
export no_proxy="localhost,127.0.0.1,::1,.local"
```

`NO_PROXY` 必须留着：没有代理时它完全惰性；将来重新启用代理时，正是靠它做 bypass。
**已经开着的终端要重开或 `source`**——进程在启动那一刻就把环境快照下来了，之后改
`.shell_common` 不会回灌。

> 这条与 [`honor-linuxlab/`](../../../../honor-linuxlab/README.md) 2.1 节是同一个坑的
> 不同环境版本：那里是"容器里根本没有代理软件"，这里是"代理软件在宿主上，但会被关掉"。
> 两边都必须靠探测端口来判断，不能想当然。

### 端口探测在 TUN 模式下会说谎 `[实测]`

上面第 1 条探测有个前提：端口开着 = 代理在跑。**在本机上这个前提不成立**，所以它会把
"代理正常"误报成"代理没开"。

实测（本机跑在 TUN 模式）：

```text
$ ps aux | grep clash
<uid> <pid> ... clash                                          <- 代理活着

$ timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/<http-port>'
refused                                                      <- 但端口没人监听
$ timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/<socks-port>'
refused
```

代理进程在跑、流量也通（直连经 TUN 出网），但 HTTP/SOCKS 入口端口一个都不开——因为
TUN 模式**根本不需要它们**：它在网络层接管流量，应用连不连本地代理端口都一样。

于是同一个 `refused` 有三种截然不同的含义：

| 观察 | 真实含义 |
| :--- | :--- |
| 进程不在，端口 refused | 代理关了 |
| 进程在，端口 refused，直连通 | **TUN 模式：代理开着，只是不用端口** |
| 进程在，端口 OPEN，直连不通 | 代理开着，但必须走它 |

**所以判断顺序是"先看请求通不通，再看端口"**，反过来会把一个正在工作的代理判成死的——
比不清变量更危险，因为你会去"修"一个没坏的东西。第 2 条探测（带代理 vs 清代理的对照）
才是决定性的：清代理后请求正常，说明这台机根本不需要代理变量，TUN 已经接管了。

---

## 2. 一个端口不能同时当 HTTP 和 SOCKS

### 症状

代理软件开着，HTTP 请求正常，但任何走 `ALL_PROXY` 的工具（curl、git、部分 Node 程序）
失败：

```text
curl: (56) Recv failure: Connection reset by peer
```

### 根因 `[实测]`

`ALL_PROXY` 和 `HTTP_PROXY` 原本指向同一个端口：

```sh
export HTTP_PROXY="http://${host_ip}:${proxy_port}"
export ALL_PROXY="socks5h://${host_ip}:${proxy_port}"
```

这在 WSL 的原配置里成立，因为 Clash Verge Rev 用的是**混合端口**（mixed port），
同一个口既说 HTTP 也说 SOCKS。但本机这个代理软件不是混合端口，**HTTP 和 SOCKS 是两个
不同的端口**。

> 本节记录的是**非 TUN 模式**下的实测。切到 TUN 模式后两个端口都不监听
> （见第 1 节末尾），此时代理变量本来就不该设。

实测证据——直接读内核的 socket 表（`/proc/net/tcp` 里地址是十六进制）：

| 监听地址 | 十进制 | 协议（实测） |
| :--- | :--- | :--- |
| `0100007F:1F90` | 127.0.0.1:<http-port> | HTTP（`CONNECT` 返回 `HTTP/1.1 200 Connection established`） |
| `0100007F:0438` | 127.0.0.1:<socks-port> | SOCKS5（握手回应 `05 00`，即"无需认证"） |

交叉验证：

```bash
curl -x http://127.0.0.1:<http-port>     <url>   # 正常返回状态码
curl -x socks5h://127.0.0.1:<http-port>  <url>   # 000，失败
curl -x socks5h://127.0.0.1:<socks-port> <url>   # 正常返回状态码
curl -x http://127.0.0.1:<socks-port>    <url>   # 000，失败
```

所以 `socks5h://` 打在 HTTP 端口上必然失败：那个口只认 HTTP 的 CONNECT 请求，
收到 SOCKS 握手包只会直接断开。

### 处置

两个端口分开写，别共用一个变量：

```sh
export proxy_http_port="<http-port>"
export proxy_socks_port="<socks-port>"

export HTTP_PROXY="http://${host_ip}:${proxy_http_port}"
export HTTPS_PROXY="http://${host_ip}:${proxy_http_port}"
export http_proxy="http://${host_ip}:${proxy_http_port}"
export https_proxy="http://${host_ip}:${proxy_http_port}"

export ALL_PROXY="socks5h://${host_ip}:${proxy_socks_port}"
export all_proxy="socks5h://${host_ip}:${proxy_socks_port}"
```

**一个端口一个变量**是硬规则。混合端口的软件上两者相同，也要分开写——哪天换成非混合
端口的软件，改一个变量就行，不用再改六行。

---

## 3. 写死的 socket 路径让会话互相挤掉

### 症状

两个现象，同一个根因：

1. 已经在跑一个 Claude Code，再开第二个直接失败：
   ```text
   --messaging-socket-path points to a live socket: <path>. Another process is
   listening there. Remove it or choose a different path.
   ```
2. 切到别的 Termux session 后，那个 session 被当前会话的消息刷屏。

### 根因 `[实测]`

wrapper 把 socket 路径写死成一个固定文件名：

```sh
SOCKET_PATH="$SOCKET_DIR/cc.sock"
exec "$REAL_CLAUDE" --messaging-socket-path "$SOCKET_PATH" "$@"
```

**为什么 wrapper 必须显式传这个路径**：CLI 会校验 socket 目录——逐级检查路径上的每个
组件，要求属主是 root 或本人、且不是 group/other 可写。在本 chroot 里 `/` 的属主是
Termux 应用的 uid（`stat -c '%u' /`），而它位于模拟存储上，`chown` 会被静默忽略，
所以 CLI 自动推导的 socket 目录一律被拒，跨会话消息功能直接关闭。显式传路径可以跳过
这个校验。

**为什么写死路径是错的**：CLI 自己的约定是**每个会话一个 socket 文件**，放在一个
`cc-socks` 目录里，文件名是 32 位十六进制（从二进制里能读到它的目录模式：
`^\/tmp\/cc-socks(?:-(0|[1-9]\d*))?$`、`^\/run\/user\/(0|[1-9]\d*)\/cc-socks$`，
以及文件名 `^[0-9a-f]{1,16}\.sock$`）。peer 的发现靠**扫描 socket 目录**，不是靠某个
固定名字。

写死一个路径的后果：

- 第二个实例 bind 失败（症状 1）。
- 所有会话挤在同一个 socket 上，`notify_when_idle` 的 peer 通知会送到"当前持有这个路径的
  那个会话"，也就是你正在看的那个；另一个 session 反而收到本该属于当前会话的消息流
  （症状 2）。

### 实证方法

```bash
# 谁占着这个 socket
grep cc.sock /proc/net/unix
ls -la /proc/*/fd 2>/dev/null | grep -l cc.sock   # 或 ps 看哪个 claude 进程带着 --messaging-socket-path

# 换个路径，第二个实例就能并存
claude --messaging-socket-path <dir>/cc-2.sock -p "ok"
```

### 处置

按会话分配唯一路径，并且沿用 CLI 的目录约定：

```sh
SOCKET_DIR="$HOME/.claude/run/cc-socks"
mkdir -p "$SOCKET_DIR"; chmod 700 "$SOCKET_DIR"

SOCKET_PATH="$SOCKET_DIR/$(printf '%08x' "$$")$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n').sock"

# 外层已经指定了就用外层的
if [ -n "${CLAUDE_CODE_MESSAGING_SOCKET:-}" ]; then
    SOCKET_PATH="$CLAUDE_CODE_MESSAGING_SOCKET"
fi

exec "$REAL_CLAUDE" --messaging-socket-path "$SOCKET_PATH" "$@"
```

文件名必须**只有十六进制**：CLI 的匹配模式是 `^[0-9a-f]{1,16}\.sock$`。写成
`$$-<随机>.sock` 会因为那个连字符落选——而 peer 的发现靠扫目录，于是又回到
"会话互相挤掉"那个症状，只是换了个原因。上面的写法把 PID 补齐成 8 位十六进制
再接 3 个随机字节，共 14 个十六进制字符，在长度上限之内。

`$$` 加随机后缀：并发启动的两个会话不会撞名，随机后缀避免同一秒内启动的两次撞上。

> **注意 `CLAUDE_CODE_MESSAGING_SOCKET` 环境变量的优先级高于命令行参数**。在 agent
> 沙箱里实测：这个变量已经存在时，即便命令行传了另一个路径，CLI 仍然报旧路径被占用。
> 所以 wrapper 里要显式处理它，而不是指望命令行参数一定赢。

---

## 4. 附带一条：PATH 重排把 pnpm 整个目录删掉了

不算代理或 socket 问题，但在同一个文件上撞见的，一并记下。

### 症状

改完 `~/.shell_common` 后，`mcode` 命令不见了，`pnpm` / `pnpx` 也不见了。

### 根因 `[实测]`

为了把 `~/.local/bin` 提到 pnpm bin 目录前面，live 文件里写的是：

```sh
case ":$PATH:" in
  *":$HOME/.local/bin:"*) PATH="$HOME/.local/bin:${PATH#*:$HOME/.local/bin:}" ;;
esac
```

`${PATH#...}` 是**最短前缀匹配**。此时 PATH 是：

```text
/root/.local/share/pnpm/bin:/root/.local/bin:/usr/local/sbin:...
```

`pnpm/bin` 排在前面，所以 `:$HOME/.local/bin:` 之前的所有内容被一起砍掉——**包括
`pnpm/bin` 自己**。实测：

```text
after prepends: /root/.local/share/pnpm/bin:/root/.local/bin:/usr/local/sbin:...
after reorder  : /root/.local/bin:/usr/local/sbin:...
>>> pnpm/bin LOST <<<
```

`mcode` 和 `mcode-tools` 就装在 `$HOME/.local/share/pnpm/bin/` 下，于是消失。（上面两段
是本机实测输出，chroot 里 `HOME` 就是 `/root`。）

注释里写着"Reordering is idempotent"——它既不幂等，也丢东西。

### 处置

按段重建，不做字符串切割：

```sh
_path_reorder() {
  # $1 = dir that must come first, $2 = dir that must come right after it
  _keep=""
  for _d in $PATH; do
    [ "$_d" = "$1" ] || [ "$_d" = "$2" ] || _keep="${_keep:+$_keep:}$_d"
  done
  PATH="$1:$2${_keep:+:$_keep}"
}
_path_reorder "$HOME/.local/bin" "$PNPM_HOME/bin"
```

**通用教训**：`${VAR#pattern}` 和 `${VAR##pattern}` 是最短/最长前缀匹配，
拿它们做"移动某个目录到最前面"必然误伤。要移动就按段重建列表。

---

## 5. 验证清单

改完 `~/.shell_common` 之后，**开一个新终端**（旧终端不会回灌）逐条确认：

```bash
# 代理变量应该不存在（除非你确实要开代理）
env | grep -i proxy

# 工具应该都在
command -v mcode mcode-tools pnpm claude agy

# PATH 不该有重复项，也不该缺目录
printf '%s\n' "$PATH" | tr ':' '\n' | sort | uniq -d      # 无输出 = 无重复
printf '%s\n' "$PATH" | tr ':' '\n' | grep -c pnpm        # >= 1

# 直连应该通（401/403/404 都算通：请求到达了服务器）
env -u http_proxy -u https_proxy -u all_proxy \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    curl -s -o /dev/null -w '%{http_code}\n' -m 15 <url>

# 反证：带上那个死端口会失败。这是"修复前"的状态，不是要达成的状态
curl -s -o /dev/null -w '%{http_code}\n' -m 8 -x http://127.0.0.1:<http-port> <url>
```

最后一条不是要通过，而是**记下对照**：`000` = 连不上（死端口），非 `000` = 通。
如果两条都返回非 `000`，说明那个端口现在是活的，代理变量就不该清——先回到第 1 节末尾
那张三行表，判断 `refused` 到底意味着什么。

socket 那条要**同时开两个实例**才能验：第一个正常跑着，第二个用同样的 wrapper 启动，
不该再报 "points to a live socket"。
