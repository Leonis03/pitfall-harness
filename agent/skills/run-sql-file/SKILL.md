---
name: run-sql-file
description: Run a .sql script file against the local SQL Server instance with sqlcmd and return readable output, handling GBK/UTF-8/UTF-16 encoding correctly. Use when asked to run, execute, or get the output of a .sql file, SQL script, or query file on this machine. Covers both the Windows host (sqlcmd 11, console code page traps) and WSL/Linux clients (mssql-tools18 vs go-sqlcmd, the 127.0.0.1-not-localhost IPv6 pitfall, Chinese column-alias rendering). Chinese version -- SKILL.zh.md.
---

# Run a .sql File with sqlcmd

> **Paths.** The helper command below uses `~/.agents/skills/run-sql-file/`. Any installed copy works: use
> `~/.claude/skills/run-sql-file/`, `~/.gemini/config/skills/run-sql-file/`, or a path relative to this
> SKILL.md instead -- only one of the three needs to exist.

> This file is deliberately **pure ASCII**, including every example. Chinese test strings are
> written as code points, exactly as the "keep CJK literals out of scripts" rule below
> recommends. Three probe words recur; build them with `nchar()` when you need them live:
>
> | referred to as | code points | GBK bytes | UTF-8 bytes |
> |---|---|---|---|
> | PROBE-DEPT ("computer science", a `Dname` value) | U+8BA1 U+7B97 U+673A | `BC C6 CB E3 BB FA` | `E8 AE A1 E7 AE 97 E6 9C BA` |
> | PROBE-TITLE ("professor", a `Ttitle` value) | U+6559 U+6388 | `BD CC CA DA` | `E6 95 99 E6 8E 88` |
> | PROBE-ROUNDTRIP (3 chars used to test pipes) | U+7CFB U+7F16 U+7801 | `CF B5 B1 E0 C2 EB` | `E7 B3 BB E7 BC 96 E7 A0 81` |
>
> ```sql
> -- PROBE-DEPT as a literal, with no non-ASCII anywhere in the file
> select * from D where Dname = nchar(0x8BA1) + nchar(0x7B97) + nchar(0x673A);
> ```

## Usage -- one line, no conversion needed

**Run sqlcmd from the PowerShell tool, not the Bash tool.** sqlcmd picks its output encoding
from the console code page of whatever process hosts it. The PowerShell tool's console is
65001 and CJK arrives correct; the Bash tool's is **936** and every Chinese character arrives
as mojibake. This is the single most likely way to lose an afternoon here -- see **Trap 0**.

**UTF-8 with BOM (preferred for anything you create) -- no encoding flag at all:**

```powershell
sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i "D:\path\script.sql" -W -s"|" -w 400
```

**GBK (the older scripts in `<your-sql-dir>\`) -- declare the input code page:**

```powershell
sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i "D:\path\script.sql" -f i:936 -W -s"|" -w 400
```

Output arrives as UTF-8 with Chinese intact. **No temp files, no UTF-16 round-trip.** Verified byte-identical under both PowerShell 5.1 and pwsh 7.

Four rules produce that result:

1. **Host it in PowerShell.** The console code page decides the output encoding, and only the PowerShell tool's is 65001 (Trap 0).
2. **Write new files as UTF-8 with BOM.** sqlcmd auto-detects the BOM, so `-f` disappears -- one less thing to get wrong, and Trap 1 becomes unreachable.
3. **If you do need `-f`, use `-f i:<cp>` and nothing else** -- the *input* code page only. Never the bare `-f 936`, never `-f o:<cp>` (see Trap 1).
4. **Let sqlcmd read the file itself (`-i`).** Never pipe script text into it (see Trap 2).

### When you can't control the shell, or you want the result saved

`-o <file> -u` writes **UTF-16LE with a BOM**, which is unambiguous and completely independent
of console state. This is the only invocation that gave identical output from every console
code page tested:

```powershell
sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i "D:\path\script.sql" -o "$env:TEMP\out.txt" -u -W -s"|" -w 400
[IO.File]::ReadAllText("$env:TEMP\out.txt", [Text.Encoding]::Unicode)
```

```bash
# from bash: -f UTF-16 (not UTF-16LE) so iconv consumes the BOM instead of emitting U+FEFF

sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i 'D:\path\script.sql' -o 'C:\Temp\out.txt' -u -W -s"|" -w 400
iconv -f UTF-16 -t UTF-8 < /c/Temp/out.txt
```

## Environment (verified 2026-09-15, console/encoding section re-verified 2026-09-22)

- **sqlcmd**: `C:\Program Files\Microsoft SQL Server\110\Tools\Binn\SQLCMD.EXE`, 11.0.2100.60 NT x64, on PATH
- **Instance**: `<your-host>\SQL2016` (only one; service `MSSQL$SQL2016`, virtual account `NT Service\MSSQL$SQL2016`)
- **Server**: SQL Server 2016 Enterprise 13.0.1601.5, server collation `Chinese_PRC_CI_AS`
- **Auth**: Windows integrated (`-E`) as `<your-host>\<your-windows-user>`, local admin. `LoginMode = 2`, so **SQL logins also work** -- relevant for WSL/Linux clients, which cannot use `-E`.
- **TCP**: enabled, but on a **dynamic port** (`TcpDynamicPorts` under `IPAll`, currently 8217 -- it changes on service restart). SQL Browser is running, so prefer resolving by instance name over hardcoding the port.
- **Console**: depends on the host process -- this is not one global fact (re-verified 2026-09-22):

  | host | `chcp` | `[Console]::OutputEncoding` | sqlcmd CJK output |
  |---|---|---|---|
  | Claude Code **PowerShell tool** (pwsh 7.6.5 Core, stdout redirected) | 65001 | 65001 | **correct** |
  | Claude Code **Bash tool** (Git Bash / MSYS) | **936** | n/a | **mojibake** |
  | a child `pwsh -Command` spawned from either | 65001 at start | 65001, but see Trap 1 | correct unless `-f` mutates it |

- **System non-Unicode ACP = 936** (`HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage\ACP`) even though `CurrentCulture.TextInfo.ANSICodePage` reports 1252 -- different settings, don't read the wrong one.
- Local `.sql` files here are **GBK (CP936), no BOM**.

## Trap 0: the Bash tool mangles every Chinese character

The Bash tool's console code page is **936**. sqlcmd writes its output in that code page, Git
Bash hands the bytes to a UTF-8 consumer, and PROBE-DEPT (GBK `BC C6 CB E3 BB FA`) arrives as
five or six U+FFFD replacement characters. The query ran fine; only the display is wrong.
Nothing in the error stream hints at it.

**Use the PowerShell tool.** If you genuinely must stay in bash, `-o <file> -u` (above) is the
only reliable fix. A `| iconv -f CP936 -t UTF-8` pipe also works *at that moment*, but it has
two problems:

- **It is not stable across invocations** -- see the `-f o:` off-by-one in Trap 1. The same
  command can need iconv on one run and be broken by it on the next.
- **A pipe destroys `-b`'s exit code.** `sqlcmd -b ... | iconv` reports the exit status of
  `iconv` (always 0). Use `${PIPESTATUS[0]}`, or don't pipe.

Four more bash-only hazards, all of which fail silently:

| you write | what actually happens |
|---|---|
| `-i "C:/Users/.../x.sql"` | sqlcmd 11 treats `/X` as an **option switch**, so `/Users` is parsed as `-U`, giving `Sqlcmd: The -E and the -U/-P options are mutually exclusive.` **Always backslashes.** |
| `"$D\\$f.sql"` | The `\\$` sequence eats the backslash *and* suppresses expansion -- you get a literal `...sqlprobe$f.sql`. Build Windows paths in single quotes. |
| `printf '...D:\\SQLData\\E3.sql...'` | GNU printf expands `\E` to ESC, so the path silently becomes `D:\SQLData<ESC>3.sql`. Use a quoted heredoc (`<<'EOF'`), never printf, for Windows paths. |
| `head`/`sed` in the pipeline | changes whether sqlcmd sees a console or a pipe, which changes the output encoding. Compare raw bytes with `od -An -tx1`, not rendered text. |

## Trap 1: `-f` mutates the console for the *next* process, not this one

The old version of this note blamed .NET caching in pwsh 7. The real mechanism is simpler and
worse: **`-f <cp>` and `-f o:<cp>` call `SetConsoleOutputCP` and never restore it, but sqlcmd's
own output is written in the code page it found at startup.** So the flag you pass takes effect
one run late.

Reproduced deterministically (Bash tool, console forced to 936 first):

| run | command | output |
|---|---|---|
| 1 | `-f o:65001 -Q "select Dname ..."` | **mojibake** (still 936) |
| 2 | *identical command* | **correct** (65001 left over from run 1) |
| -- | `chcp 936` to reset | |
| 3 | `-Q` with no `-f` | **mojibake** again |

Consequences:

- **The same command gives different answers on consecutive runs.** If output encoding seems to
  flap, this is why -- don't go looking for a bug in your SQL.
- **`chcp` does not reveal it.** It reported 936 for every row above, including the run that
  emitted UTF-8. Measuring `chcp` will actively mislead you.
- **Never use bare `-f <cp>` or `-f o:<cp>`.** `-f i:<cp>` only touches the input side and leaves
  no residue. This was already rule 3; the reason above is the real one.
- **Leaked state crosses processes.** A child `pwsh -Command` that runs `-f 936 -o file -u -i
  script.sql` ends with `[Console]::OutputEncoding` at 936 and prints plain string literals as
  GBK: PROBE-ROUNDTRIP comes out as U+03F5 followed by four U+FFFD, because GBK `CF B5` read as
  UTF-8 is U+03F5 (GREEK LUNATE EPSILON). Inside the Claude Code PowerShell tool the same command
  leaves it at 65001, because that host pins its encoding and has stdout redirected -- **so the
  harness hides this trap from you until it doesn't.** Don't rely on the immunity.

## Trap 2: never pipe CJK into a native exe

Broken in **both** shells, for different reasons -- verified by round-tripping PROBE-ROUNDTRIP:

| shell | `$OutputEncoding` | result |
|---|---|---|
| PS 5.1 | CP20127 (US-ASCII) | `FFFD,003F,003F,003F` -- encoded to `?` on the way out |
| pwsh 7 | CP65001 | `7EEF,8364,7D2A,942E,003F` -- UTF-8 bytes re-decoded as OEM by the exe |

Always hand the program a *path* and let it open the file.

## Why the input code page matters at all

Without `-f i:936`, sqlcmd reads these GBK scripts as UTF-8. Chinese identifiers and literals
become mojibake, so a predicate like `WHERE Ttitle = '<PROBE-TITLE>'` matches nothing -- the
query **succeeds and returns 0 rows** instead of erroring. Silent wrong answers, not a crash.

## Shell differences that bite (5.1 vs pwsh 7)

| behaviour | PS 5.1 (Desktop) | pwsh 7 (Core) |
|---|---|---|
| `Encoding::Default` | CP936 (system ACP) | always UTF-8 |
| `Get-Content` default on a GBK file | **decodes correctly** | **decodes wrong** |
| `Out-File` / `>` default | UTF-16LE + BOM | UTF-8, no BOM |
| `Set-Content -Encoding utf8` | UTF-8 **with** BOM | UTF-8 **no** BOM |
| `$OutputEncoding` | US-ASCII | UTF-8 |
| `.ps1` with CJK literals, no BOM | read as CP936 | read as UTF-8 |
| the `-f` console leak (Trap 1) | leaks, but 5.1 caches at startup so its *own* writes stay correct | leaks, and its own writes follow the leaked CP |

Practical consequences: a `.ps1` that must run under 5.1 and contains Chinese must be saved **UTF-8 with BOM**. Reading a GBK file in pwsh 7 always needs an explicit encoding. Safest of all: keep CJK literals out of scripts entirely (build them from code points, e.g. `[char]0x7CFB` in PowerShell or `nchar(0x7CFB)` in T-SQL) so the script file's own encoding stops mattering. This document follows its own advice.

## Running from WSL / Linux (verified 2026-09-22)

The whole Trap 0/1/2 family is a **Windows console** artifact. A Linux client speaks TDS over a
socket and has no console code page, so those traps do not exist there. Measured end to end:
the read-only half of a real script (13 queries) produced **byte-identical data rows** from
Windows sqlcmd 11 and from Linux sqlcmd 18 -- 54 normalised lines each, `diff` clean.

### Use `mssql-tools18`, not `go-sqlcmd`

| client | CP936 `varchar` -> UTF-8 | Chinese column-alias headers | verdict |
|---|---|---|---|
| **`mssql-tools18`** (`sqlcmd 18.7.0001.1`, ODBC) | correct | **correct, all lengths** | **use this** |
| `go-sqlcmd` (`v1.10.0`, go-mssqldb) | correct | **BROKEN -- see below** | only with `-h -1` |
| `pymssql` (FreeTDS) | correct | n/a -- you format the output yourself | good for scripted/CI use |
| `usql` | untested | untested | Ubuntu's build has no mssql driver compiled in |

```bash
export SQLCMDPASSWORD='...'          # never -P on the command line, never in a file
/opt/mssql-tools18/bin/sqlcmd -S '127.0.0.1\SQL2016' -U <login> -d study -C -b -W -s"|" -w 400 \
  -i /mnt/d/path/script.sql
```

- **`-S '127.0.0.1\SQL2016'`, never `localhost\SQL2016`.** `msodbcsql18` resolves `localhost`
  to IPv6 `::1` first; the instance does not listen on IPv6, so you get
  `TCP Provider: Error code 0x2749` / `Login timeout expired`. `go-sqlcmd` resolves to IPv4 and
  is *not* affected, which makes this look like a server problem when it is a resolver problem.
- **Instance name beats the port.** `\SQL2016` resolves through SQL Browser (UDP 1434) and
  survives restarts; the TCP port is dynamic. Note a TCP-only probe such as `/dev/tcp` cannot
  see SQL Browser at all -- it is UDP.
- **No `-E`.** Non-domain machine, so Windows integrated auth is unavailable from Linux. Needs a
  SQL login, which works here because `LoginMode = 2`. Give it `db_datareader` and nothing more
  unless writes are actually required.
- **UTF-8 + BOM `-i` files work.** Verified explicitly: the BOM is consumed, not sent to the
  server. Both BOM and BOM-less variants of the same script returned `exit=0` with identical
  output, so the Windows-side "always add a BOM" rule stays safe on Linux.

### go-sqlcmd v1.10.0 truncates Chinese column aliases

**The header is emitted as the first N *bytes* of the alias, where N is its *character* count**
(width sized by rune count, sliced by byte offset). Data rows are completely unaffected; only
the header line is wrong.

| alias chars | UTF-8 bytes | bytes actually emitted | what you see |
|---|---|---|---|
| 2 | 6 | `e5 a7` | **pure mojibake**, no whole character survives |
| 3 | 9 | `e5 b7 a5` | first character only -- **silent truncation, the dangerous case** |
| 4 | 12 | `e9 83 a8 e9` | one character plus a broken byte |
| 6 | 18 | `e5 a7 93 e5 90 8d` | first two characters only |

This matters here because the coursework scripts are built on Chinese aliases -- `E2.sql` has 50
uses (28 distinct), `E3.sql` 39 uses (16 distinct) -- and the most common case, a 2-character
alias, lands in the worst row. ASCII aliases are fine, and `-h -1` suppresses headers entirely,
but neither is available when the assignment itself requires Chinese column names.

`mssql-tools18` renders all of these correctly. Its one cosmetic flaw: the `---` underline is
one dash per *character*, so it reads short under a monospace font against double-width CJK.
That is alignment, not corruption -- do not "fix" it by changing collations or adding charset
flags.

## Flags that matter

| Flag | Why |
|---|---|
| `-S '<your-host>\SQL2016'` | Instance. **Single-quote in PowerShell** -- see the `$` gotcha below |
| `-d <db>` | Initial database; without it you land in `master` and unqualified tables fail |
| `-E` | Windows integrated auth |
| `-b` | **Exit code 1 on SQL error.** Without it failures look like success |
| `-i <file>` | Input script (repeatable). **Backslash paths only** -- `/` is an option prefix (Trap 0) |
| `-f i:936` | Input code page **only**. `i:65001` for UTF-8; omit for UTF-16/BOM files |
| ~~`-f 936`~~ ~~`-f o:65001`~~ | **Never.** Mutates the console for the next process and not this one (Trap 1) |
| `-W` | Trim trailing spaces |
| `-s"\|"` | Column separator -- makes output parseable into tables |
| `-w 400` | Line width; default 80 truncates |
| `-h-1` | Suppress headers |
| `-Q "..."` | One inline query, then exit |
| `-o <file>` `-u` | UTF-16LE + BOM to a file. `-u` requires `-o`. **The only console-independent output path** -- reach for it whenever encoding is in doubt |

## Detecting a file's encoding

```powershell
(([IO.File]::ReadAllBytes($p)[0..3]) | ForEach-Object { $_.ToString('X2') }) -join ' '
```

| First bytes | Encoding | Use |
|---|---|---|
| `EF BB BF ...` | UTF-8 with BOM | **omit `-f`** |
| `FF FE ...` | UTF-16 LE | omit `-f` |
| plain ASCII only | ASCII | anything works |
| high bytes, no BOM | **GBK** (the older files here) | `-f i:936` |
| high bytes, valid UTF-8 sequence, no BOM | UTF-8 without BOM | `-f i:65001` |

The last two are indistinguishable by inspection -- decide by attempting a **strict** UTF-8 decode (`UTF8Encoding($false, $true)`); if it throws, it's GBK. `Run-SqlFile.ps1` does exactly this.

### Verified behaviour matrix

A query whose predicate contains PROBE-DEPT (`where Dname = '<PROBE-DEPT>'`) returns 1 row when
decoded correctly, 0 rows when not:

| File encoding | without `-f` | with `-f i:<cp>` |
|---|---|---|
| **UTF-8 with BOM** | **1 row** | 1 row |
| UTF-8 without BOM | **0 rows** | 1 row (`i:65001`) |
| GBK | **0 rows** | 1 row (`i:936`) |

Two things this proves:

- **BOM removes the flag entirely.** sqlcmd 11.0 honours a UTF-8 BOM.
- **UTF-8 *without* BOM is the worst option on this machine** -- worse than GBK. sqlcmd defaults its input code page to the system ACP (**936**), not the console CP (65001), so a BOM-less UTF-8 file is read as GBK. GBK files at least open correctly in SSMS, which also falls back to the ACP.

Both failing cells fail **silently**: mojibake identifiers and literals match nothing, so the query succeeds with 0 rows. When a query returns 0 rows, rule out encoding before believing the data is empty.

Note that the mojibake can *also* surface as `Msg 102 ... Incorrect syntax`, not just 0 rows --
that happens when the mangled bytes land in an **identifier or alias** (`select Dname as <CJK>`)
rather than only in a string literal. Same root cause, louder symptom.

## Creating or editing a .sql file

The `Edit` and `Write` tools always emit UTF-8 **without** BOM. Two consequences:

- **Never point them at a GBK file** -- the whole file is rewritten as UTF-8 and every Chinese character is destroyed.
- **Using them on a UTF-8+BOM file strips the BOM**, silently downgrading a zero-flag file into one that needs `-f i:65001`.

**For a new file, don't hand-build the text in a here-string -- that is painful for anything
over ~20 lines and walks straight into the line-ending gotcha below. Write it with the `Write`
tool, then add the BOM in a second step:**

```powershell
$p = 'D:\path\script.sql'
$t = [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
(([IO.File]::ReadAllBytes($p)[0..2]) | ForEach-Object { $_.ToString('X2') }) -join ' '   # EF BB BF
```

The prohibition that still stands without exception: **never point `Edit` or `Write` at an
existing GBK file.** That rewrites the whole thing as UTF-8 and destroys every Chinese
character. Convert it first, or edit it through PowerShell:

```powershell
# create / rewrite as UTF-8 with BOM

[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($true)))

# read a GBK file

[Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
$text = [IO.File]::ReadAllText($path, [Text.Encoding]::GetEncoding(936))

# convert GBK to UTF-8 with BOM, in place

$t = [IO.File]::ReadAllText($p, [Text.Encoding]::GetEncoding(936))
[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
```

After converting, re-run the script and diff against the pre-conversion output -- a correct GBK to UTF-8+BOM conversion produces byte-identical results.

### Gotcha: line endings

A file written from a PowerShell here-string gets **LF**, not CRLF. A later string replace that assumes CRLF then matches nothing and **silently no-ops** -- the script still runs fine, so nothing looks broken; the edit just never happened. Detect the file's actual newline before replacing:

```powershell
$nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
```

Safer still: split on `"`r?`n"`, insert into the resulting array, and re-join with the detected newline.

## Running a script that contains DML, without committing it

When a script has `INSERT`/`UPDATE`/`DELETE`/`SELECT INTO` in it and you want to verify syntax,
constraints and affected-row counts *before* changing anything, wrap it in a transaction and
roll back. `:r` is sqlcmd's include directive; `go` inside the included file splits batches
normally, and the transaction persists across batches because it's one connection.

```sql
-- dryrun.sql  (pure ASCII, so its own encoding never matters)
set xact_abort on;
begin transaction;
go
:r D:\path\script.sql
rollback transaction;
go
print '--- ROLLED BACK ---';
go
```

```powershell
sqlcmd -S '<your-host>\SQL2016' -d study -E -b -i "D:\path\dryrun.sql" -W -s"|" -w 400
```

You get every `SELECT` result and every `(N rows affected)` line, with the database untouched.
Confirm with a row-count query afterwards. Notes:

- If a batch fails under `-b`, sqlcmd exits and the connection drops, so the server rolls back
  anyway -- you cannot leave a transaction dangling.
- `select ... into T` followed by `insert into T` inside the wrapper is fine; the rollback drops
  the table again.
- This verifies the statements **in order**. A script whose DML is order-dependent (a `+1000`
  raise before a `*1.05` raise) will not give the same numbers if you later run the statements
  individually.
- `:r` is a **sqlcmd** directive, not T-SQL. A dryrun wrapper cannot be pasted into SSMS as-is;
  paste the target script instead, wrapped in `begin tran` / `rollback tran` by hand.

## Optional helper -- capture to a file

`scripts\Run-SqlFile.ps1` auto-detects the encoding (strict UTF-8 decode distinguishes UTF-8-without-BOM from GBK), always uses the safe `-f i:<cp>` form, and converts the result to UTF-8. Use it when you want results **saved**, output is very large, or you want the exit code and server error text together. For simply reading results, the one-liner above is simpler.

```powershell
& "~/.agents/skills/run-sql-file/scripts/Run-SqlFile.ps1" -Path "D:\path\script.sql" -Database study
```

| Parameter | Default | Notes |
|---|---|---|
| `-Path` | *(required)* | The `.sql` file |
| `-Database` | `master` | Pass the real database, e.g. `study` |
| `-Server` | `<your-host>\SQL2016` | The only instance here |
| `-InputEncoding` | `auto` | Override: `936`, `65001`, `1252`, `utf16` |
| `-Separator` | `\|` | Column separator |
| `-Width` | `400` | Line width |
| `-NoHeaders` | off | Adds `-h-1` |
| `-OutDir` | `$env:TEMP` | Where the UTF-8 output lands |

On a SQL error it still returns (`ExitCode 1`) with the server message in the output file.

## Troubleshooting

**Output is mojibake** -- three different causes, check in this order:

1. **You are in the Bash tool.** Most likely by far. Its console is 936 (Trap 0). Re-run in the
   PowerShell tool, or use `-o <file> -u`.
2. **A previous sqlcmd run left the console code page changed** by a bare `-f <cp>` or `-f o:<cp>`
   (Trap 1). Symptom: the *same* command works on the second try. Use `-f i:<cp>` only.
3. **The input file's encoding was misdeclared**, so the mojibake is in the data you sent, not
   the data you got back. Check the file's first bytes.

`chcp` will not distinguish these -- it reports the same value in all three. Compare raw bytes
(`od -An -tx1`) against the probe table at the top of this file instead.

**Query returns 0 rows but the data is obviously there** -- missing `-f i:936`. See above.

**`Sqlcmd: The -E and the -U/-P options are mutually exclusive.`** -- you used a forward-slash path.
sqlcmd 11 reads `/U` inside `C:/Users/...` as the `-U` switch. Use backslashes.

**A `decimal` zero prints as `.00` instead of `0.00`** -- sqlcmd drops the leading zero when
rendering `decimal`. The value is correct and SSMS displays it normally. Not a calculation error,
and not worth re-verifying.

**`Msg 451 ... Cannot resolve collation conflict between "Latin1_General_CI_AS_KS_WS" and "Chinese_PRC_CI_AS"`** -- from concatenating `SERVERPROPERTY(...)` with catalog columns under this server's `Chinese_PRC_CI_AS`. Select the columns separately or add `COLLATE DATABASE_DEFAULT`.

**`FCB::Open failed ... OS error: 5(Access is denied)` when attaching a database** -- the service runs as virtual account `NT Service\MSSQL$SQL2016`, which is **not** covered by `Authenticated Users` or `Users` ACEs. Grant it explicitly:

```powershell
icacls "D:\folder" /grant 'NT SERVICE\MSSQL$SQL2016:(OI)(CI)(F)' /T
```

**PowerShell eats `$SQL2016`** -- inside double quotes it expands to an empty variable and the account name silently becomes wrong. Use **single quotes** for any argument containing `$`.

## Cross-tool encoding lessons (applies beyond sqlcmd)

The "keep CJK out of source files" and "be careful with BOM" rules are not
sqlcmd-specific. They come up every time a Python or Node script reads a JSON
config or data file that might contain Chinese. Two traps confirmed during
WeChat / QQ chat-export work:

### Trap A: BOM breaks `json.load()` when the file is UTF-8 + BOM

Python's `json.load(f)` with default `encoding="utf-8"` throws
`JSONDecodeError: Unexpected UTF-8 BOM` on a BOM-prefixed file.
`io.open(..., encoding="utf-8-sig")` works, but you can't change every tool.

**Rule of thumb:** if the tool reads JSON config with plain `utf-8` (qq-nt-export,
wcdb-key-tool, most Python CLI tools), **config files must be UTF-8 WITHOUT BOM**.
`[IO.File]::WriteAllText($path, $t, [Text.UTF8Encoding]($false))`.

This is the **opposite** of sqlcmd's rule, where BOM is preferred. So:

- `.sql` files for sqlcmd → UTF-8 **with** BOM (sqlcmd auto-detects it)
- `.json` config for Python tools → UTF-8 **without** BOM (json.load crashes on BOM)
- `.py` / `.ps1` source → pure ASCII inside (build CJK from code points)

### Trap B: `%` in SQL/Python strings + string formatting = silent wrong answers

In sqlcmd this is just `%%` in `-v` values. In Python scripts that build SQL
queries containing `LIKE '%pattern%'`, using `%`-formatting on the same string
consumes the `%` wildcards as format specifiers. The query runs but matches
nothing, returning 0 rows silently — same class of bug as mojibake giving 0 rows
in the GBK/UTF-8 mismatch case.

**Rule:** never `%`-format a string that also contains SQL `LIKE` wildcards.
Use parameterized queries, or concatenate the table name separately, or use
f-strings with `%%` doubling for the LIKE part.

### Trap C: verify with keyword search, not "it ran without error"

A database decrypt or export that exits 0 is not necessarily working. The
quickest sanity check is a keyword search for words you know are in the data
(place names, people, product names). If you get zero hits, something is wrong —
could be encoding (mojibake), could be wrong key, could be a wrong directory.
Count the rows first, then keyword-search, then check sample snippets for
readability.

This is the moral equivalent of the "if it returns 0 rows, rule out encoding
before believing the data is empty" rule from the sqlcmd section. Same shape of
bug, different surface.

## Notes

- Read the script before running it. These are usually read-only `SELECT`s, but check for `DROP`/`DELETE`/`UPDATE` and say so before executing.
- **Never use a real project script as throwaway test input.** When probing flags, encodings or
  paths it is tempting to reach for the `.sql` file already on disk -- but `-i` *executes* it, and
  a script with DML in it will commit, silently, with the interesting output scrolling past as
  "the test result". This has actually happened here: two encoding probes run against a homework
  script applied its `UPDATE`s twice (salaries ended up `+1000` twice and a `*1.05` compounded).
  Generate a disposable probe instead -- `select Dname from D where Dnum='D01'` is enough -- or
  wrap the run in the rollback harness above.
- Before *and* after any run that could write, snapshot the row counts
  (`select count(*) from T`, `sum(Tsalary)`, `object_id('S_1','U')`, and so on). A diff is the
  only thing that reliably catches an unintended commit; output that "looks right" does not.
- The real error text for a server-side failure is in the ERRORLOG, not always in the client message:
  `C:\Program Files\Microsoft SQL Server\MSSQL13.SQL2016\MSSQL\Log\ERRORLOG`
- Default data/log path: `C:\Program Files\Microsoft SQL Server\MSSQL13.SQL2016\MSSQL\DATA\` (already carries the service-account ACE).

---

- Chinese version: [SKILL.zh.md](SKILL.zh.md)
