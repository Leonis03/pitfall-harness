# minimax-code session JSONL: how the history is stored, and how to repair it by hand

minimax-code keeps every session in a directory of JSONL files and never trusts them blindly:
before each turn it re-validates the whole history chain and refuses to start when the chain
does not add up. A compaction rewrites that chain -- and it is triggered by tool-output
volume, not by the context window running low -- and on this machine (Honor tablet Linux Lab,
PRoot over f2fs) the rewrite leaves a file that the validator rejects. From then on **every
prompt in that session fails before the model is even called**.

This is the runbook: what the files are, what the validator demands of them, the exact
failure signature, and the repair procedure that was measured to work.

- Measured on: Linux Lab (PRoot over f2fs), minimax-code 0.6.12 (global install), session
  directory dated 2026-10-23.
- Source read: <https://github.com/MiniMax-AI/minimax-code> (public tree checked out at 0.6.5;
  the scanner code is byte-identical in the 0.6.12 bundle).
- No session id, no user name and no absolute host path appear in this document on purpose.

---

## 1. TL;DR

| | |
| :--- | :--- |
| **Symptom** | The turn that used to work dies, and so does every prompt after it: `HistoryScannerError: Canonical history scan failed: unsafe-artifact`, `failure_stage: "Agent preflight failed."`, `setup_stage: "history_read"` |
| **Real cause** | The compaction parent snapshot is a **hard link** (published with `link()`), and under PRoot `readdir` reports the directory entry type of a multi-named inode as `DT_LNK`. The validator trusts that type and calls the file a symlink |
| **Not the cause** | The message content, the model, the network, the token budget. The history content is intact and its revision hash matches |
| **Repair** | Re-create the snapshot file so it has exactly one name and a fresh directory entry (`unlink` + write the same bytes). Never edit `messages.jsonl` by hand |
| **Prevention** | Patch the validator to use `lstat` instead of the `readdir` type (section 8) |

---

## 2. Where the session state lives

```text
$HOME/.minimax/v2/sessions/<YYYY>/<MM>/<DD>/<HH-MM-SS-mmm>-session_<base64url-id>/
```

The date segments are UTC; the last component is `session_` plus the base64url of the session
id, truncated. One directory holds everything about one session:

| Path | What it is |
| :--- | :--- |
| `messages.jsonl` | **The active history.** One JSON envelope per line: `{"message_id", "turn_id", "message"}`, plus `"turn_config"` and/or `"history_artifact"` when applicable |
| `snapshots/g<12 digits>--<compactionId>.jsonl` | **Parent snapshots.** One file per past generation; the file name carries the generation and the compaction id |
| `history-catalog.json` | Cached index of the chain (generation, revision, byte length, message count). It is a cache, not the truth |
| `user-message-locators.jsonl` | Where each externally supplied user message sits (line number, byte offset), for lineage checks |
| `llm-call.json` | The request profile of the last model call (model, tools, system prompt) |
| `reports/tool-outputs/` | Tool outputs too large for the context, offloaded as artifacts |
| `manifest.json` | Session identity and the expected paths |

`history-catalog.json` and `user-message-locators.jsonl` are **derived** files. When they are
stale or missing the runtime rebuilds them by scanning the chain -- but only if the scan
succeeds, so a broken chain cannot heal itself through them.

---

## 3. The history model: generations and a parent chain

minimax-code never rewrites the history in place. A compaction produces a **new generation**:

1. The current `messages.jsonl` is copied to `snapshots/g<gen>--<compactionId>.jsonl`. That
   file is the *parent* of the new generation and is never touched again.
2. `messages.jsonl` is rewritten with the trimmed content. Its **first record** carries the
   marker that points back at the parent:

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

`producedBy` is `tool_archive` (tool outputs moved into artifacts), `tool_trim` (tool outputs
shortened) or `llm_checkpoint` (an LLM-written summary replaced older turns).

**The revision is the fingerprint of the content**: `sha256:` plus the hex SHA-256 over the
recursively key-sorted JSON of the record array. The marker stores the revision of the
*parent*; the validator recomputes it from the parent file and compares. If the parent file
was edited by hand, even by one byte, the chain is rejected.

The validator walks upwards: active (generation N) -> parent (N-1) -> ... -> generation 0.
Each step must find a file whose name is `g<generation>--<compactionId>.jsonl`, whose content
hashes to the revision the child recorded, and whose first record either has no marker
(generation 0) or a marker for the next generation up.

### What triggers a compaction (it is not the context window)

A new generation is created by a compaction, and there are three unrelated budgets that can
cause one. The first two are **byte budgets on the transcript**, not on the context window:

| Trigger | Budget (defaults) | What it does |
| :--- | :--- | :--- |
| **ToolResult compaction** (`tool_archive`) | `toolResultCompaction.watermarkKiB` = 256 KiB of accumulated tool-result text, and it commits only if it can save at least `minSavingsKiB` = 256 KiB | Moves the older tool results into `reports/tool-outputs/` and leaves a short receipt in their place |
| **Per-result fuse** | `maxInlineKiB` = 64 KiB for one tool result | The oversized result is archived before it even enters the history |
| **MCP detail fuse** | `mcpDetailsMaxInlineKiB` = 32 KiB for the raw `details` of one MCP result | Only the detail blob is externalized; the readable text stays inline |
| **Context compaction** (`llm_checkpoint`) | `contextManagement.compactionTriggerAt`, by default a share of the model's context window | An LLM writes a summary and the older turns are replaced by it |

`keepRecentRounds` (5) protects the most recent complete tool rounds from the cumulative
compaction.

In the measured turn the context was 180037 of the model's 512000 tokens -- 35% -- and a
compaction fired anyway, because that turn alone had accumulated 359767 bytes of tool-result
text. The budget is re-evaluated at every tool round, and it refuses to commit unless it can
save enough. That turn made **11 attempts**: the first ten were rejected, the eleventh
committed.

| # | outcome | tool text bytes | effective | candidates | estimated savings | actual savings | artifacts |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |
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

Two things to read out of that table:

- **The threshold is a step, not a curve.** `estimated_savings_bytes` only moves when the
  candidate set changes -- 225800 three times in a row, then 232328 three times in a row --
  while the accumulated bytes climbed from 294759 to 340240. The candidates are whole tool
  results, so the estimate can only change when another one qualifies.
- **What shrinks is the tool-result text.** On the committed attempt
  `tool_result_text_bytes_effective` drops from 359767 to 87540: 16 results were replaced by
  receipts, and the context went from 180037 to 99253 tokens. The last attempt passed both the
  watermark (359767 > 262144) and the minimum (270716 > 262144).

**Why this matters for the failure**: a compaction is the only thing that advances the
generation chain, and therefore the only thing that creates a snapshot file. A tool-heavy turn
triggers it with the context window half empty, which is how this session ended up with a
snapshot to validate in the first place.

---

## 4. What the validator demands, and how it fails

`packages/local-runtime-v2/src/service/session-system/messages/history/mutation/canonical-history-scanner.ts`

| Error code | Meaning |
| :--- | :--- |
| `unsafe-artifact` | An artifact file is not a regular file, or the directory entry says it is a symlink |
| `parent-snapshot-missing` | The child names a parent file that does not exist |
| `parent-mismatch` | The child's `parentSnapshot.generation` is not `generation - 1` |
| `artifact-revision-mismatch` | The parent file's content does not hash to the revision the child recorded |
| `invalid-generation-marker` | The marker on the first record is missing, malformed, or its generation does not match |
| `malformed-jsonl` | A line is not valid JSON, or a record is not a valid envelope |
| `sequence-corruption` | A tool call has no result, or message ids repeat |
| `external-user-lineage-conflict` | The same externally supplied user message appears with a different fingerprint in two generations, or the generation jump is not by one |

Two of these deserve attention:

- `unsafe-artifact` is decided from the **directory entry type**, not from `stat`:

  ```ts
  // canonical-history-scanner.ts
  regular: entry.isFile() && !entry.isSymbolicLink(),   // line 429, from readdir(dirent)
  ...
  if (!snapshot.regular) throw new HistoryScannerError('unsafe-artifact');   // line 235
  ```

  `readdir` with `withFileTypes` reports the type the kernel stored in the directory entry.
  It never re-checks the inode. A file whose entry type says "symlink" is rejected even when
  `lstat` says "regular file".

- `external-user-lineage-conflict` is the reason you must not hand-edit history: the validator
  fingerprints every externally supplied user message (`message_id` starting with
  `msg-user-v1-`) and requires the fingerprint to be **identical** in the parent snapshot and
  in the active file. The tool results may differ between generations (that is the point of a
  compaction); the user turns may not.

---

## 5. The failure, measured

The turn that triggered it was an ordinary `tool_archive` compaction, fired by the tool-output
byte budget rather than by the context window (section 3): 16 oversized tool results were
offloaded to `reports/tool-outputs/`, which cut the context from 180037 to 99253 tokens -- of a
512000-token window, so there was never any pressure to compact. The compaction itself
succeeded. The **validation that ran right after it** failed:

```text
[19:06:41.944] INFO  ToolResult compaction  {"outcome":"candidate_ready","candidate_count":16,"artifact_write_count":16}
[19:06:41.992] INFO  beforeLlmCall replaced context messages {"replacement_id":"ctx_a84d10fa-...","tokens_before":180037,"tokens_after":99253}
[19:06:42.240] ERROR history delivery failed {"reason":"replaceMessages",
                 "error":"Canonical history scan failed: unsafe-artifact"}
[19:07:33.289] ERROR agent turn setup stage failed {"setup_stage":"history_read","error_type":"HistoryScannerError"}
[19:07:33.310] ERROR agent host turn failed {"failure_stage":"Agent preflight failed."}
```

The second pair is the one users see: the **next prompt** never reaches the model. It dies in
the `history_read` setup stage, because the turn reads the committed history before it does
anything else.

The chain itself was fine. Only one thing was wrong:

```console
$ node -e "const fs=require('fs');
  const e=fs.readdirSync('<session>/snapshots',{withFileTypes:true}).find(x=>x.name.startsWith('g0'));
  console.log('readdir:',e.isFile(),e.isSymbolicLink());
  const s=fs.lstatSync('<session>/snapshots/'+e.name);
  console.log('lstat  :',s.isFile(),s.isSymbolicLink());"

readdir: false true          <-- the directory entry claims "symlink"
lstat  : true false          <-- the inode is a regular file
```

### Why the two disagree: PRoot emulates `link()`

minimax-code publishes files with an atomic "publish if absent" primitive
(`packages/local-runtime-v2/src/infra/file/jsonl.ts`): write a staging file next to the
target, then `link(staging, target)`. Under PRoot, `link()` is emulated, and the emulation
leaves two things behind in the target directory:

```text
.l2s.<staging-basename><NNNN>          a symlink to the entry below
.l2s.<staging-basename><NNNN>.000<M>    the actual data, sharing the inode with the target
```

and, crucially, **every directory entry that shares that inode comes back from `readdir` with
type `DT_LNK`**. Reproduced on this machine with three lines of Node:

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

Before the hard link, `a.txt` is reported as a regular file. After `link()`, **both** names
are reported as symlinks by `readdir`, while `lstat` still says regular file. The kernel
entry type is stale; the inode is fine.

**None of this is minimax-code's doing.** One `ln` in an empty directory reproduces it,
including the staging pair:

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

Three things to read out of that:

- `a.txt` was an ordinary file **before** the link; after one `ln` its `readdir.isFile` is
  false while `lstat.isFile` is still true. One name, two answers.
- `a.txt`, `b.txt` and `.l2s.a.txt0001.0002` share one inode. The numbers change from run to
  run; the point is that they are the same one.
- `.l2s.a.txt0001` is a real symlink -- `readlink` resolves it to the `.0002` entry -- and it
  is the staging area itself.

That is the whole bug: a file published with `link()` (every published minimax-code file --
snapshots, tool-output artifacts, the builtin agent prompts) has a directory entry that the
validator refuses to accept.

Three corollaries worth knowing:

- The symptom is not limited to snapshots. In the measured session, 78 of the 117 entries in
  `reports/tool-outputs/` and the builtin `agents/.builtin/*/agent.md` report
  `isSymbolicLink() === true` from `readdir` while `lstat` says regular file. Which files are
  affected depends on which publish step last refreshed their directory entry, so the count is
  not "all of them" -- but any filter that trusts the entry type is exposed. Reading those
  files by path is unaffected.
- **The two runtimes disagree about what a directory entry means.** Node's
  `fs.Dirent.isFile()` does not follow symlinks, so a symlink is never a file; Python's
  `os.DirEntry.is_file()` does follow, so a symlink to a regular file is a file. Code written
  for one is not automatically correct for the other, and `pathlib.Path.glob()` sidesteps the
  question entirely by matching on the name.
- The `.l2s.*` entries are the publisher's transient staging area: the published name shares
  the staging file's inode, so they are the same data under a second name, and they disappear
  once the publish settles. A published name can briefly be a symlink into that staging area,
  which is the moment the entry type is at its least trustworthy -- and the moment the name
  stops being resolvable by another program (section 6, step 2).

---

## 6. Repairing the session

The rule: **repair the file, never the history.** The content of the chain is verified by
hash and is correct; only the file's directory entry is wrong.

### Before anything: check whether a session is at risk

A session is at risk when a snapshot's directory entry no longer matches its inode -- the
condition the validator will reject. The check is read-only and touches nothing:

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

Only files matching the snapshot name pattern are looked at: the `.l2s.*` entries are
*expected* to be symlinks (they are the publisher's staging area) and would only add noise.

The condition mirrors the validator exactly: it rejects an artifact whose directory entry is
not a plain file. The opposite mismatch -- the entry says regular file, the inode says
symlink -- is a quieter and more interesting case, because the validator would *accept* it.
Change `!(x.isFile()&&!x.isSymbolicLink())&&l.isFile()` to `x.isFile()&&!l.isFile()` to look
for that one instead.

On this machine, after the repair, the check prints nothing: no session is at risk.

### Step 1 -- confirm the content is intact

Recompute the revision of the parent snapshot and compare it with the revision the child
recorded. The revision is SHA-256 over the recursively key-sorted JSON of the record array:

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
PY
```

The two must match. If they do not, the file was edited: restore it from a backup instead of
patching the marker, because the marker is the child's statement about the parent.

Also compare the user turns: the envelopes of every `msg-user-v1-*` record must be identical
in the snapshot and in the active file, otherwise the next validator run reports
`external-user-lineage-conflict` instead.

### Step 2 -- give the file a fresh directory entry

The file must end up with exactly one name and a directory entry that says "regular file".
**Do not try to rename over the old name.** On this filesystem the published name is a
symlink into the publisher's `.l2s.*` staging area, and a chain that contains a
`.l2s.`-named component cannot be resolved by another program -- `mv -f` fails at its
pre-stat, before it ever calls `rename(2)`:

```console
$ mv -f .fixstage.tmp g000000000000--ctx_....jsonl
mv: cannot stat 'g000000000000--ctx_....jsonl': Operation not permitted
```

Measured on this machine (`mv -f <source> <target>`):

| Target | Result |
| :--- | :--- |
| regular file | ok |
| regular file whose *name* starts with `.l2s.` | ok |
| symlink whose chain has no `.l2s.` component | ok |
| symlink whose chain contains a `.l2s.`-named component | **EPERM at the pre-stat** |

`unlink` does not resolve the chain, so it works. Copy the bytes back afterwards:

```bash
cd "$SESSION/snapshots"
SNAP='g000000000000--ctx_....jsonl'
cp "$SNAP" "$HOME/<backup>/$SNAP"          # keep a copy first
rm "$SNAP"                                 # the old entry is the broken one
cp "$BACKUP/$SNAP" "$SNAP"                 # fresh entry, identical bytes
```

Copying the bytes back is enough; the content is what the hash covers, and a copy has the
same bytes.

### Step 3 -- verify

```bash
node -e "const fs=require('fs');const d='$SESSION/snapshots';
  for(const e of fs.readdirSync(d,{withFileTypes:true}))
    console.log(e.name, 'readdir.isFile='+e.isFile(), 'lstat.isFile='+fs.lstatSync(d+'/'+e.name).isFile());"
```

`readdir.isFile=true` for the snapshot means the validator will accept it. The next prompt
then starts normally; the runtime rebuilds `history-catalog.json` and
`user-message-locators.jsonl` from the chain.

### Step 4 -- know what you have not fixed

The publisher will produce the same shape again at the next compaction in this session, and
the same symptom will return. The data repair buys one session back; the patch in section 8
is what stops it.

---

## 7. Rules for touching this state by hand

- **Never edit `messages.jsonl`.** Its content is hashed into the parent marker and into the
  next generation's parent revision. Edit it and the chain is broken for good.
- **Never edit a snapshot to "fix" a hash mismatch.** The hash is the contract; the file is
  the evidence.
- **Never delete a snapshot to "start over".** The validator needs the whole chain; a missing
  parent is `parent-snapshot-missing`, which is just as fatal.
- **Leave the `.l2s.*` staging entries alone.** They are the publisher's transient staging
  area -- the same bytes under a second name -- and they disappear once the publish settles.
  Removing one by hand can leave a published name pointing at nothing.
- **A session that fails at `history_read` is not a model problem.** Look at the runtime log
  (`$HOME/.minimax/v2/observability/logs/runtime-*.log`) for the failing turn and find the
  `HistoryScannerError` code; it names the broken link.

---

## 8. The durable fix (source)

One line in the scanner decides whether a snapshot is acceptable. It should ask the
filesystem about the inode, not the directory entry:

```ts
// packages/local-runtime-v2/src/service/session-system/messages/history/mutation/canonical-history-scanner.ts
-      regular: entry.isFile() && !entry.isSymbolicLink(),
+      regular: await isRegularFile(snapshotPath),   // lstat: isFile() && !isSymbolicLink()
```

`readArtifact()` in the same file already does exactly this check on the same path
(`lstat` plus `isSymbolicLink()`, lines 376-377), so the lstat-based rule is the code's own
definition of "safe artifact" -- the dirent shortcut is the odd one out, and it is the one
that fails on a filesystem whose directory entry types are not authoritative.

The same pattern, and the same exposure, exists in:

| File | Line | What it filters |
| :--- | :--- | :--- |
| `packages/agent-modules/session-report/src/llm-call-report-store.ts` | 88, 188 | Report snapshots |
| `packages/local-runtime-v2/src/infra/db/backup.ts` | 143 | Files included in a database backup |
| `packages/local-runtime-v2/src/service/session-system/messages/history/session-history-location.ts` | 207 | Session directories |

Reporting a file as a symlink when it is not is the safe direction for a *read* filter; for
the canonical history it is fatal, because the chain has to be provable. Any of these checks
that decides "this file is a symlink, refuse it" should be based on `lstat`.

---

## 9. Reading the runtime log

`$HOME/.minimax/v2/observability/logs/runtime-<YYYYMMDDHH>.log` is one file per hour. The
lines that matter for this class of failure:

```text
ERROR agent turn setup stage failed {"setup_stage":"history_read","error_type":"HistoryScannerError"}
ERROR agent host turn failed   {"failure_stage":"Agent preflight failed.","errors":[{"name":"HistoryScannerError","message":"Canonical history scan failed: unsafe-artifact"}]}
```

`setup_stage: history_read` means the turn never started; `failure_stage: Agent preflight
failed` with an `HistoryScannerError` code names the broken link directly. The same code
also appears as `chain-corrupt` in the user-facing session error, which is the same problem
wearing a different label.

---

## 10. Related

- [`agents-windows.md`](agents-windows.md) -- the Windows-side global rules for the same tool
- [`../windows-agent/agents-additional.md`](../windows-agent/agents-additional.md) -- why those
  rules exist, one measured basis per rule
