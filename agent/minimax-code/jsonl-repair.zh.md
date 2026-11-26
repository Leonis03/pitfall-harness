# minimax-code 会话 JSONL：历史是怎么存的，以及怎么手工修

minimax-code 把每个会话存成一个目录下的若干 JSONL 文件，而且从不盲信它们：每轮开始前都会
重新校验整条历史链，链对不上就直接拒绝启动。压缩会重写这条链——而压缩是由**工具输出体积**触发的，
跟上下文窗口快满了没关系——在这台机器上
（荣耀平板 Linux Lab，PRoot + f2fs），重写之后会留下一个校验器不认的文件——从此之后
**该会话里的每一个 prompt 都会在模型被调用之前就报错**。

本文是操作手册：这些文件是什么、校验器对它们提什么要求、故障的确切特征，以及实测有效的
修复步骤。

- 实测环境：Linux Lab（PRoot + f2fs），minimax-code 0.6.12（全局安装），会话目录日期 2026-10-23。
- 阅读的源码：<https://github.com/MiniMax-AI/minimax-code>（公开仓库检出的是 0.6.5；
  校验器代码在 0.6.12 的打包产物里逐字一致）。
- 本文刻意不出现 session id、用户名和宿主机绝对路径。

---

## 1. 一句话结论

| | |
| :--- | :--- |
| **症状** | 原本能跑的那一轮挂了，之后每个 prompt 也挂：`HistoryScannerError: Canonical history scan failed: unsafe-artifact`，`failure_stage: "Agent preflight failed."`，`setup_stage: "history_read"` |
| **真因** | 压缩产生的父快照是**硬链接**（用 `link()` 发布），而 PRoot 下 `readdir` 会把「一个 inode 多个名字」的文件的目录项类型报成 `DT_LNK`。校验器信了这个类型，就把它当成软链接 |
| **不是原因** | 消息内容、模型、网络、token 预算。历史内容是完好的，它的 revision 哈希也对得上 |
| **修复** | 把快照文件重建一次，让它只剩一个名字、拿到全新的目录项（`unlink` + 写回同样的字节）。**绝不要手改 `messages.jsonl`** |
| **防复发** | 改校验器：用 `lstat` 代替 `readdir` 的类型判断（见第 8 节） |

---

## 2. 会话状态放在哪

```text
$HOME/.minimax/v2/sessions/<YYYY>/<MM>/<DD>/<HH-MM-SS-mmm>-session_<base64url-id>/
```

日期段是 UTC；最后一段是 `session_` 加 session id 的 base64url（截断）。一个目录装下一个会话
的全部东西：

| 路径 | 是什么 |
| :--- | :--- |
| `messages.jsonl` | **当前历史**。一行一个 JSON 信封：`{"message_id", "turn_id", "message"}`，视情况还带 `"turn_config"` 和/或 `"history_artifact"` |
| `snapshots/g<12 位数字>--<compactionId>.jsonl` | **父快照**。每一代历史留一个文件，文件名里带代数和压缩 id |
| `history-catalog.json` | 历史链的索引缓存（代数、revision、字节数、消息数）。它是缓存，不是真相 |
| `user-message-locators.jsonl` | 每条外部送入的用户消息落在哪（行号、字节偏移），供血缘校验用 |
| `llm-call.json` | 最近一次模型调用的请求画像（模型、工具、系统提示词） |
| `reports/tool-outputs/` | 超出上下文的工具输出，被落盘成 artifact |
| `manifest.json` | 会话身份与预期路径 |

`history-catalog.json` 和 `user-message-locators.jsonl` 都是**派生文件**。它们过期或缺失时，
运行时靠扫描历史链重建——但前提是扫描能成功，所以坏掉的链无法靠它们自愈。

---

## 3. 历史模型：代数与父链

minimax-code 从不原地改写历史。一次压缩会产出**新的一代**：

1. 当前的 `messages.jsonl` 被复制到 `snapshots/g<gen>--<compactionId>.jsonl`。这个文件是新
   一代的**父**，之后不再改动。
2. `messages.jsonl` 被重写成裁剪后的内容，它的**第一条记录**带上指回父文件的标记：

```json
{
  "message_id": "msg-...",
  "turn_id": "turn-...",
  "message": { "role": "user", "...": "..." },
  "history_artifact": {
    "schemaVersion": 1,
    "generation": 1,
    "producedBy": "tool_archive",
    "parentSnapshot": {
      "generation": 0,
      "compactionId": "ctx_...",
      "revision": "sha256:e5cd0a34..."
    }
  }
}
```

`producedBy` 有三种：`tool_archive`（工具输出被移进 artifact）、`tool_trim`（工具输出被截短）、
`llm_checkpoint`（用模型写的摘要替换掉更早的轮次）。

**revision 是内容的指纹**：`sha256:` 加上一段十六进制 SHA-256，摘要对象是「记录数组按键递归排序
后的 JSON」。标记里存的是**父**的 revision；校验器会从父文件重算并比对。手改过父文件——哪怕
只差一个字节——整条链都会被判为无效。

校验器自下往上走：当前代（generation N）→ 父代（N-1）→ …… → generation 0。每一步都要找到
名为 `g<generation>--<compactionId>.jsonl` 的文件，其内容哈希要等于子代记录的 revision，且它
的第一条记录要么没有标记（generation 0），要么带有指向上一代的标记。

### 压缩是怎么触发的（跟上下文窗口无关）

新的一代由压缩产生，而能引发压缩的有三份互不相干的预算。前两份是**针对记录本身的字节预算**，
不是上下文窗口：

| 触发器 | 预算（默认值） | 做什么 |
| :--- | :--- | :--- |
| **ToolResult 压缩**（`tool_archive`） | `toolResultCompaction.watermarkKiB` = 累积工具结果文本 256 KiB；且必须能省下至少 `minSavingsKiB` = 256 KiB 才提交 | 把较早的工具结果挪进 `reports/tool-outputs/`，原位留一段收据 |
| **单条熔断** | `maxInlineKiB` = 单条工具结果 64 KiB | 超过体积的那条在进入历史之前就被归档 |
| **MCP detail 熔断** | `mcpDetailsMaxInlineKiB` = 单条 MCP 结果的原始 `details` 32 KiB | 只把 detail 块外置，可读正文仍留在原地 |
| **上下文压缩**（`llm_checkpoint`） | `contextManagement.compactionTriggerAt`，默认取模型上下文窗口的一个比例 | 让模型写一段摘要，替换掉更早的轮次 |

`keepRecentRounds`（5）会保护最近 5 个完整工具轮次，不参与累积压缩。

实测那一轮，上下文是 180037 token，模型窗口 512000——只用了 35%——压缩照样触发了，因为仅那一轮
就累积了 359767 字节的工具结果文本。预算在每个工具轮次都会重新评估一次，而且省不够就不提交。
那一轮一共尝试了 **11 次**：前 10 次被否，第 11 次才提交。

| # | outcome | 工具结果文本字节 | effective | 候选数 | 估算可省 | 实际可省 | 写出 artifact |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `below_minimum_savings` | 285214 | 285214 | 8 | 62523 | 0 | 0 |
| 2 | `below_minimum_savings` | 292254 | 292254 | 9 | 100502 | 0 | 0 |
| 3 | `below_minimum_savings` | 293504 | 293504 | 9 | 100502 | 0 | 0 |
| 4 | `below_minimum_savings` | 294759 | 294759 | 11 | 225800 | 0 | 0 |
| 5 | `below_minimum_savings` | 311951 | 311951 | 11 | 225800 | 0 | 0 |
| 6 | `below_minimum_savings` | 335195 | 335195 | 11 | 225800 | 0 | 0 |
| 7 | `below_minimum_savings` | 337878 | 337878 | 12 | 232328 | 0 | 0 |
| 8 | `below_minimum_savings` | 340240 | 340240 | 12 | 232328 | 0 | 0 |
| 9 | `below_minimum_savings` | 344837 | 344837 | 12 | 232328 | 0 | 0 |
| 10 | `below_minimum_savings` | 349398 | 349398 | 14 | 248496 | 0 | 0 |
| 11 | `candidate_ready` | 359767 | **87540** | 16 | 270716 | 272227 | 16 |

这张表里要读出两件事：

- **门槛是台阶，不是曲线。** `estimated_savings_bytes` 只在候选集变化时才动——225800 连着三次、
  232328 又连着三次——而这期间累积字节从 294759 涨到 340240。候选是整条工具结果，所以只有又多
  一条够格时估算值才会变。
- **缩小的正是工具结果文本。** 提交的那一次 `tool_result_text_bytes_effective` 从 359767 掉到
  87540：16 条被换成收据，上下文从 180037 降到 99253 token。最后一次同时过了水位线
  （359767 > 262144）和下限（270716 > 262144）。

**这条为什么和本次故障有关**：压缩是唯一会推进代数链、也就是唯一会造出快照文件的动作。一个工具
输出很多的轮次，在窗口还空着一半的时候就能把它触发——这个会话正是这样才有了需要校验的快照。

---

## 4. 校验器要求什么、怎么失败

源码位置：`packages/local-runtime-v2/src/service/session-system/messages/history/mutation/canonical-history-scanner.ts`

| 错误码 | 含义 |
| :--- | :--- |
| `unsafe-artifact` | 某个 artifact 不是普通文件，或者目录项说它是软链接 |
| `parent-snapshot-missing` | 子代指名要的父文件不存在 |
| `parent-mismatch` | 子代记录的 `parentSnapshot.generation` 不是 `generation - 1` |
| `artifact-revision-mismatch` | 父文件的内容哈希不等于子代记录的 revision |
| `invalid-generation-marker` | 第一条记录上的标记缺失、格式错，或代数对不上 |
| `malformed-jsonl` | 某一行不是合法 JSON，或记录不是合法信封 |
| `sequence-corruption` | 有 toolCall 没有 toolResult，或 message id 重复 |
| `external-user-lineage-conflict` | 同一条外部送入的用户消息在两代里指纹不同，或代数跳级不是 +1 |

其中两条要特别注意：

- `unsafe-artifact` 是**按目录项类型**判定的，不是按 `stat`：

  ```ts
  // canonical-history-scanner.ts
  regular: entry.isFile() && !entry.isSymbolicLink(),   // 第 429 行，取自 readdir 的 dirent
  ...
  if (!snapshot.regular) throw new HistoryScannerError('unsafe-artifact');   // 第 235 行
  ```

  `readdir` 的 `withFileTypes` 报的是内核存在目录项里的类型，它不会回头再看 inode 一次。
  目录项说是「软链接」的文件，即使 `lstat` 说「普通文件」，照样被拒。

- `external-user-lineage-conflict` 是「不能手改历史」的原因：校验器会给每条外部送入的用户
  消息（`message_id` 以 `msg-user-v1-` 开头）算指纹，并要求它在父快照和当前文件里**逐字节相同**。
  工具结果在两代之间可以不同（压缩的意义就在于此），用户轮次不行。

---

## 5. 实测到的故障

触发它的是一次普通的 `tool_archive` 压缩，由工具输出的字节预算触发而不是上下文窗口（第 3 节）：
16 条超大的工具结果被挪进 `reports/tool-outputs/`，上下文从 180037 降到 99253 token——而窗口是
512000 token，也就是说根本不存在「空间不够要压缩」这回事。压缩本身是成功的，**紧接着跑的校验**
失败了：

```text
[19:06:41.944] INFO  ToolResult compaction  {"outcome":"candidate_ready","candidate_count":16,"artifact_write_count":16}
[19:06:41.992] INFO  beforeLlmCall replaced context messages {"replacement_id":"ctx_a84d10fa-...","tokens_before":180037,"tokens_after":99253}
[19:06:42.240] ERROR history delivery failed {"reason":"replaceMessages",
                 "error":"Canonical history scan failed: unsafe-artifact"}
[19:07:33.289] ERROR agent turn setup stage failed {"setup_stage":"history_read","error_type":"HistoryScannerError"}
[19:07:33.310] ERROR agent host turn failed {"failure_stage":"Agent preflight failed."}
```

后两行才是用户看到的：**下一个 prompt 根本没走到模型**，死在 `history_read` 这个准备阶段，
因为一轮对话在做任何事之前要先读已提交的历史。

链本身是好的，只有一样东西不对：

```console
$ node -e "const fs=require('fs');
  const e=fs.readdirSync('<session>/snapshots',{withFileTypes:true}).find(x=>x.name.startsWith('g0'));
  console.log('readdir:',e.isFile(),e.isSymbolicLink());
  const s=fs.lstatSync('<session>/snapshots/'+e.name);
  console.log('lstat  :',s.isFile(),s.isSymbolicLink());"

readdir: false true          <-- 目录项声称是「软链接」
lstat  : true false          <-- inode 其实是普通文件
```

### 两者为什么会不一致：PRoot 在模拟 `link()`

minimax-code 用一种原子的「不存在才发布」原语来发布文件
（`packages/local-runtime-v2/src/infra/file/jsonl.ts`）：先在目标旁边写一个暂存文件，然后
`link(staging, target)`。在 PRoot 下 `link()` 是被模拟的，模拟会在目标目录里留下两样东西：

```text
.l2s.<暂存文件名><NNNN>          指向下面那个的软链接
.l2s.<暂存文件名><NNNN>.000<M>    真正的数据，与目标文件共享同一个 inode
```

而且，**凡是共享这个 inode 的目录项，`readdir` 一律报成 `DT_LNK`**。在这台机器上用三行 Node
就能复现：

```console
$ node -e "const fs=require('fs');const d='<tmp>';
  fs.writeFileSync(d+'/a.txt','A');
  console.log(fs.readdirSync(d,{withFileTypes:true})[0].isFile());   // true
  fs.linkSync(d+'/a.txt', d+'/b.txt');
  for(const e of fs.readdirSync(d,{withFileTypes:true}))
    console.log(e.name, e.isFile(), e.isSymbolicLink(), fs.lstatSync(d+'/'+e.name).isFile());"

true
a.txt false true true
b.txt false true true
```

建立硬链接之前，`a.txt` 被报成普通文件；`link()` 之后，**两个名字**都被 `readdir` 报成软链接，
而 `lstat` 仍然说是普通文件。内核目录项里的类型是陈旧的，inode 本身没问题。

**这跟 minimax-code 一点关系都没有。** 在空目录里敲一条 `ln` 就能复现，连暂存对一起带出来：

```console
$ printf A > a.txt && ln a.txt b.txt && stat -c '%n  %F  inode=%i  links=%h' a.txt b.txt .l2s.a.txt0001 .l2s.a.txt0001.0002
a.txt  regular file  inode=3401171  links=2
b.txt  regular file  inode=3401171  links=2
.l2s.a.txt0001  symbolic link  inode=3386711  links=1
.l2s.a.txt0001.0002  regular file  inode=3401171  links=2

$ node -e 'const fs=require("fs");
for(const e of fs.readdirSync(".",{withFileTypes:true})){
  const l=fs.lstatSync(e.name);
  console.log(e.name.padEnd(20),"readdir.isFile="+e.isFile(),"isSymlink="+e.isSymbolicLink(),
    "| lstat.isFile="+l.isFile(),"ino="+l.ino,"nlink="+l.nlink);
}'
.l2s.a.txt0001       readdir.isFile=false isSymlink=true | lstat.isFile=false ino=3386711 nlink=1
.l2s.a.txt0001.0002  readdir.isFile=true isSymlink=false | lstat.isFile=true ino=3401171 nlink=2
a.txt                readdir.isFile=false isSymlink=true | lstat.isFile=true ino=3401171 nlink=2
b.txt                readdir.isFile=false isSymlink=true | lstat.isFile=true ino=3401171 nlink=2
```

这里要读出三件事：

- `a.txt` 在 `ln` **之前**是普通文件；一次 `ln` 之后它的 `readdir.isFile` 变成 false，而
  `lstat.isFile` 仍然是 true。同一个名字，两套答案。
- `a.txt`、`b.txt`、`.l2s.a.txt0001.0002` 共享同一个 inode（数字每次运行都变，要点是它们是
  同一个）。
- `.l2s.a.txt0001` 是货真价实的软链接——`readlink` 能读出它指向 `.0002`——它就是暂存区本身。

这就是整件事：凡是 minimax-code 用 `link()` 发布过的文件（快照、工具输出 artifact、内置
agent 提示词，全都是），它的目录项都会被校验器拒绝。

三条推论值得记住：

- 症状不限于快照。实测会话里，`reports/tool-outputs/` 的 117 个条目中有 78 个、内置的
  `agents/.builtin/*/agent.md`，都是 `readdir` 报 `isSymbolicLink() === true` 而 `lstat` 说普通
  文件。哪些文件会中招，取决于它的目录项最后被哪一次发布刷新过——所以不是「全部」，但凡是信
  目录项类型的过滤都有暴露面。按路径读这些文件不受影响。
- **两种运行时对「目录项是什么」的理解不一致。** Node 的 `fs.Dirent.isFile()` 不跟随软链接，
  所以软链接永远不是文件；Python 的 `os.DirEntry.is_file()` 会跟随，所以指向普通文件的软链接
  就是文件。为一种运行时写的代码换到另一种未必成立，而 `pathlib.Path.glob()` 直接按名字匹配，
  根本绕开了这个问题。
- `.l2s.*` 是发布方的临时暂存区：发布出来的名字和暂存文件共享 inode，所以它们是同一份数据的
  另一个名字，发布落定后就会消失。发布出来的名字可能短暂是指向该暂存区的软链接——那正是目录项
  类型最不可信的瞬间，也正是这个名字**别的程序解析不了**的瞬间（第 6 节第 2 步）。

---

## 6. 修会话

原则：**修文件，不要修历史。** 链的内容靠哈希担保，而它是正确的；错的只是文件的目录项。

### 动手之前：先查一遍有没有会话处在风险里

会话处在风险中的标志是：快照的目录项和它的 inode 对不上了——也就是校验器会拒绝的那种状态。
这个检查只读，不动任何东西：

```bash
node -e 'const fs=require("fs"),path=require("path");
const root=process.env.HOME+"/.minimax/v2/sessions";
(function walk(d){let e;try{e=fs.readdirSync(d,{withFileTypes:true})}catch(x){return}
 for(const x of e){const p=path.join(d,x.name);
  if(x.isDirectory()){walk(p);continue}
  if(!/^g\d{12}--[A-Za-z0-9][A-Za-z0-9._-]*\.jsonl$/.test(x.name))continue;
  const l=fs.lstatSync(p);
  if(!(x.isFile()&&!x.isSymbolicLink())&&l.isFile())
    console.log("AT RISK  "+p+"  (readdir says symlink, lstat says regular file)");
 }})(root);'
```

只看符合快照命名模式的文件：`.l2s.*` 条目**本来就该是**软链接（它们是发布方的暂存区），扫它们
只会添噪声。

判定条件与校验器完全一致：目录项不是普通文件的产物，一律被拒。反过来的不一致——目录项说是普通
文件、inode 说是软链接——是更安静也更值得警惕的一种，因为校验器会**放行**它。把
`!(x.isFile()&&!x.isSymbolicLink())&&l.isFile()` 换成 `x.isFile()&&!l.isFile()` 就能查那一种。

在这台机器上，修复之后这个检查不输出任何东西：没有会话处在风险中。

### 第 1 步 —— 确认内容是完好的

重算父快照的 revision，和子代记录的 revision 比对。revision 是「记录数组按键递归排序后的
JSON」的 SHA-256：

```bash
python3 - <<'PY'
import json, hashlib
def sort_json(v):
    if isinstance(v, dict):  return {k: sort_json(v[k]) for k in sorted(v)}
    if isinstance(v, list):  return [sort_json(x) for x in v]
    return v
def revision(path):
    h = hashlib.sha256(); h.update(b'[')
    first = True
    for line in open(path):
        line = line.strip()
        if not line: continue
        if not first: h.update(b',')
        h.update(json.dumps(sort_json(json.loads(line)), separators=(',', ':'), ensure_ascii=False).encode())
        first = False
    h.update(b']')
    return 'sha256:' + h.hexdigest()

snap = '<session>/snapshots/g000000000000--ctx_....jsonl'
print('snapshot   ', revision(snap))
print('marker wants sha256:e5cd0a34...   # history_artifact.parentSnapshot.revision')
PY```

两者必须一致。如果不一致，说明文件被改过：这时应该从备份恢复，而不是去改标记——标记是子代对
父代的陈述。

同时要比对用户轮次：每个 `msg-user-v1-*` 记录的信封在快照和当前文件里必须完全一致，否则
下一次校验会报 `external-user-lineage-conflict`。

### 第 2 步 —— 给文件换一个全新的目录项

文件最后必须只剩一个名字，并且目录项要明确说「普通文件」。**不要试图用 rename 覆盖旧名。**
在这个文件系统上，发布出来的名字是指向发布方 `.l2s.*` 暂存区的软链接，而**只要链路里有一节
以 `.l2s.` 命名的路径分量，别的程序就解析不了它**——`mv -f` 在自己的前置 `stat` 上就失败了，
根本没走到 `rename(2)`：

```console
$ mv -f .fixstage.tmp g000000000000--ctx_....jsonl
mv: cannot stat 'g000000000000--ctx_....jsonl': Operation not permitted
```

本机实测矩阵（`mv -f <源> <目标>`）：

| 目标 | 结果 |
| :--- | :--- |
| 普通文件 | ok |
| 名字以 `.l2s.` 开头的**普通文件** | ok |
| 链路里没有 `.l2s.` 分量的软链接 | ok |
| 链路里含 `.l2s.` 命名分量的软链接 | **前置 stat 就 EPERM** |

`unlink` 不解析链路，所以能用。先把字节拷走，再删旧名，再写回：

```bash
cd "$SESSION/snapshots"
SNAP='g000000000000--ctx_....jsonl'
cp "$SNAP" "$HOME/<备份目录>/$SNAP"          # 先留一份
rm "$SNAP"                                 # 坏掉的是旧目录项
cp "$备份目录/$SNAP" "$SNAP"                 # 新目录项，字节完全相同
```

把字节原样拷回去就够了：哈希覆盖的是内容，副本的内容一模一样。

### 第 3 步 —— 验证

```bash
node -e "const fs=require('fs');const d='$SESSION/snapshots';
  for(const e of fs.readdirSync(d,{withFileTypes:true}))
    console.log(e.name, 'readdir.isFile='+e.isFile(), 'lstat.isFile='+fs.lstatSync(d+'/'+e.name).isFile());"
```

快照的 `readdir.isFile=true` 意味着校验器会接受它。下一个 prompt 就能正常开始；运行时会在
扫描历史链后重建 `history-catalog.json` 和 `user-message-locators.jsonl`。

### 第 4 步 —— 明白哪些还没解决

发布会在这段会话的下一次压缩时再产出同样的形状，同样的症状会再回来。数据修复只救回这一次
会话；第 8 节的补丁才是根治。

---

## 7. 手工碰这些状态时的规矩

- **绝不要改 `messages.jsonl`。** 它的内容被哈希进父标记，也被哈希进下一代要记录的父 revision。
  改了就永久性地把链搞坏。
- **绝不要为了「对上哈希」去改快照。** 哈希是契约，文件是证据。
- **绝不要为了「重来」去删快照。** 校验器需要完整的链；少一个父代就是 `parent-snapshot-missing`，
  同样致命。
- **别动 `.l2s.*` 暂存条目。** 它们是发布方的临时暂存区——同一份数据的另一个名字——发布落定后
  就会消失。手工删掉一个，可能让某个已发布的文件名指向虚空。
- **死在 `history_read` 的会话不是模型的问题。** 去运行时日志
  （`$HOME/.minimax/v2/observability/logs/runtime-*.log`）里找到那一轮，看 `HistoryScannerError`
  的错误码——它会直接点名断的是哪一环。

---

## 8. 根治（改源码）

校验器里有一行代码决定快照是否可以接受。它应该问文件系统「这个 inode 是什么」，而不是问
目录项：

```ts
// packages/local-runtime-v2/src/service/session-system/messages/history/mutation/canonical-history-scanner.ts
-      regular: entry.isFile() && !entry.isSymbolicLink(),
+      regular: await isRegularFile(snapshotPath),   // lstat: isFile() && !isSymbolicLink()
```

同一个文件的 `readArtifact()` 对同一条路径本来就是这么查的（`lstat` 加 `isSymbolicLink()`，
第 376-377 行），也就是说「安全 artifact」的定义早就是 lstat 版本——用目录项类型是那个
异类，而它恰好在「目录项类型不可信」的文件系统上失效。

同样的写法、同样的暴露面还出现在：

| 文件 | 行 | 过滤对象 |
| :--- | :--- | :--- |
| `packages/agent-modules/session-report/src/llm-call-report-store.ts` | 88, 188 | 报告快照 |
| `packages/local-runtime-v2/src/infra/db/backup.ts` | 143 | 进数据库备份的文件 |
| `packages/local-runtime-v2/src/service/session-system/messages/history/session-history-location.ts` | 207 | 会话目录 |

对**读**过滤器来说，把文件误报成软链接是安全方向；但对 canonical history 是致命的，因为链
必须可证。凡是「判断这是不是软链接，是就拒绝」的检查，都应该建立在 `lstat` 上。

---

## 9. 看运行时日志

`$HOME/.minimax/v2/observability/logs/runtime-<YYYYMMDDHH>.log`，一小时一个文件。这类故障
要看的就是这几行：

```text
ERROR agent turn setup stage failed {"setup_stage":"history_read","error_type":"HistoryScannerError"}
ERROR agent host turn failed   {"failure_stage":"Agent preflight failed.","errors":[{"name":"HistoryScannerError","message":"Canonical history scan failed: unsafe-artifact"}]}
```

`setup_stage: history_read` 说明这一轮根本没开始；`failure_stage: Agent preflight failed`
配上 `HistoryScannerError` 的错误码，直接点名断掉的那一环。同一个错误码在面向用户的会话
错误里会显示成 `chain-corrupt`，是同一个问题的另一个名字。

---

## 10. 相关

- [`agents-windows.md`](agents-windows.md) —— 同一个工具的 Windows 侧全局约定
- [`../windows-agent/agents-additional.md`](../windows-agent/agents-additional.md) —— 这些约定
  为什么这么写，每条规则的实测依据
