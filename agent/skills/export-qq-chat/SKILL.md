---
name: export-qq-chat
description: Export local QQ NT (PCNT / QQ 9.x) chat history from encrypted nt_msg.db to plain SQLite, TXT and JSON. Read-only memory scan of QQ.exe process extracts SQLCipher key -- no injection, no hook, no file modification.
---

# Export QQ NT Chat History (Local, Read-Only)

Use this skill when the user asks to **export, decrypt, dump or back up their own local QQ NT (PCNT / QQ 9.x) chat history on Windows** -- converting the encrypted `nt_msg.db` into plain text / JSON / SQLite they can read.

> **Scope boundary.** For the user's own QQ account on their own device, personal backup only. Not for other people's accounts, not for automated message sending, not for data scraping.

> **Paths.** Commands below use `~/.agents/skills/export-qq-chat/`. Any installed copy works: use `~/.claude/skills/export-qq-chat/`, `~/.gemini/config/skills/export-qq-chat/`, or a path relative to this SKILL.md instead -- only one of the three needs to exist.

## Tool

The upstream tool is [q957506633/qq-nt-export](https://github.com/q957506633/qq-nt-export).
If it is already on disk (check common locations like a `backup` or `tools` directory),
use that instead of cloning a fresh copy.

## Finding the data directory

QQ NT does not store its data in `Documents\Tencent Files` (the old PCQQ location),
and the registry key `HKCU\Software\Tencent\QQNT` only has the version number.

Most reliable method: locate `nt_msg.db` on the drive(s), then check which file has a
recently written `-wal` (that account is currently logged in).

On a machine with multiple QQ accounts, there will be one directory per account under
the QQ data root (often named `<QQ号>\nt_qq\nt_db\`).

Account directory structure:
```
<qq-data-root>\<QQ号>\nt_qq\nt_db\
  nt_msg.db           -- main message DB (encrypted, + 1024 byte custom header)
  nt_msg.db-wal       -- WAL (recent messages, must copy together with db)
  nt_msg.db-shm       -- SHM
  group_info.db       -- group metadata and members
  profile_info.db     -- friend / contact profiles
  ...
```

## Standard workflow (one account)

```powershell
cd <qq-nt-export-dir>

# 0. Copy config.example.json to config.json and set db_path / work_dir / output_dir.
#    (config.json must be UTF-8 WITHOUT BOM -- tool reads with plain utf-8.)

# 1. Key scan (QQ must be running and signed in)
uv run --python 3.12 --with sqlcipher3-wheels --with pycryptodome --with zstandard `
  python scripts/ntqq_key_scan.py
# Writes key+salt back to config.json, also saves ntqq_key_scan.json to work_dir.

# 2. Decrypt main message DB
uv run --python 3.12 --with sqlcipher3-wheels --with pycryptodome --with zstandard `
  python scripts/ntqq_decrypt.py
# Produces: work_dir\nt_msg_plain.db  (standard plain SQLite, integrity_check=ok)

# 3. Decrypt aux DBs (group info + profile info, for nickname backfill)
#    (Aux script expects ntqq_db_key.json with all_nt_db_keys array,
#     but key_scan writes ntqq_key_scan.json with all_hits array. Convert.)
#    Convert with:
$j = Get-Content work_<qq>\ntqq_key_scan.json -Raw -Encoding UTF8 | ConvertFrom-Json
$uniq = $j.all_hits | Sort-Object salt_hex, key_hex -Unique |
  ForEach-Object { [PSCustomObject]@{kind=$_.kind; key_hex=$_.key_hex; salt_hex=$_.salt_hex; pid=$_.pid} }
@{ all_nt_db_keys = $uniq } | ConvertTo-Json -Depth 4 |
  Out-File work_<qq>\ntqq_db_key.json -Encoding utf8NoBOM

uv run --python 3.12 --with sqlcipher3-wheels --with pycryptodome --with zstandard `
  python scripts/ntqq_aux_decrypt.py --keys-json work_<qq>\ntqq_db_key.json

# 4. Export
uv run --python 3.12 --with sqlcipher3-wheels --with pycryptodome --with zstandard `
  python scripts/ntqq_export.py
# Outputs: output_dir\txt\*.txt, output_dir\json\*.json, sessions_index.json

# 5. Verify
uv run --python 3.12 --with sqlcipher3-wheels --with pycryptodome --with zstandard `
  python scripts/ntqq_verify.py
# Checks: every JSON file valid, message count matches index, no parse errors.
```

## Multi-account: switch config.json

Each account needs its own `work_dir` / `output_dir`. Before switching accounts,
update `db_path`, `work_dir`, `output_dir`, and `self_qq` in `config.json`,
then re-run steps 1-5.

## Technical facts

- **Encryption:** 1024-byte custom header + SQLCipher
  (`cipher_page_size=4096`, `kdf_iter=4000`, PBKDF2-HMAC-SHA512,
  `cipher_hmac_algorithm = HMAC_SHA1`).
- **Key extraction:** read-only scan of `QQ.exe` main process memory, regex-match
  credential feature strings, cross-verify with the DB file header's 16-byte salt.
  The key is 32 raw bytes as hex, concatenated with the salt.
- **Message tables:** `c2c_msg_table` (single chat) and `group_msg_table` (group chat).
  Column names are numeric strings: `40001`=msg_id, `40050`=timestamp,
  `40800`=message body (protobuf wire format).
- **Protobuf:** a minimal wire-format decoder is built in -- no protobuf library needed.
  Supports text, image, video, file, reply, forward merge, card, call record,
  rich text. Unknown types degrade gracefully.

## Key provenance and what happens after reinstall

Empirically confirmed: QQ NT keys are **account-stable**. An account whose local DB
has not been written to for many months can be decrypted with a freshly-extracted
key after signing in again. So:

- **Reinstall OS -> re-login -> export works** (as long as the same QQ account
  still works and the DB file is preserved).
- **Old encrypted DB file + fresh login key = works**.
- **But if the account is banned and you cannot log in, you cannot get the key.**
  No offline brute-force or key recovery method exists for Windows QQ NT.

## Pitfalls

1. **config.json must have no BOM.** The tool reads with `encoding="utf-8"`
   (not `utf-8-sig`) and will throw a `JSONDecodeError` on `﻿`. When writing
   config from PowerShell, use `[IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]($false))`.
   (This is the *opposite* of sqlcmd's convention, where BOM is preferred --
   don't mix them up.)

2. **Aux decrypt key file name mismatch.** `ntqq_key_scan.py` writes
   `ntqq_key_scan.json` (with `all_hits` array); `ntqq_aux_decrypt.py` expects
   `ntqq_db_key.json` (with `all_nt_db_keys` array). Convert before step 3.

3. **QQ spawns many processes (10-15).** Only the main process (no `--type=`)
   has the credentials in memory. The scanner tries all PIDs and reports which
   ones matched -- just check that `confirmed >= 1`.

4. **WAL matters.** If `-wal` is not copied along with the DB, the most recent
   messages (up to several hours / days) are missing. The tool handles this
   automatically (it copies both), but if you manually copy files, grab the whole
   `nt_db\` directory.

5. **Cloud sync may still be pulling in history.** Right after first login on a
   fresh install, `nt_msg.db` grows for minutes/hours as cloud messages sync.
   The tool backs up before decrypting, so a fresh run after sync completes
   gets the full history.

6. **Nickname backfill coverage ~90%.** Roughly 8-12% of messages end up with
   a bare uid as the sender name -- mostly because the sender is not in the
   contact list (e.g. strangers in big groups). The data is still there; it is
   just a display-name issue.

7. **Keyword verification: build CJK from code points.** Keep verification scripts
   ASCII-source. If you write the keyword as a literal inside the .py file and
   the file's encoding is misread, you get 0 hits silently -- same shape of bug
   as the sqlcmd "0 rows because mojibake" trap.

## Legal / safety note

Same pattern as the WeChat export skill:

- Personal backup of your own data on your own device = personal data access.
- Read-only memory scan, no code modification, low detection risk compared to
  injection / patching.
- Do not share decrypted DBs or key files -- they contain other people's info.

## Related skills

- `export-wechat-chat` -- same pattern for WeChat 4.x
- `run-sql-file` -- CJK-in-scripts discipline, BOM rules (not directly applicable
  here but the mindset is the same)
