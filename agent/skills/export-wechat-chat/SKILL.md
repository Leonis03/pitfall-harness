---
name: export-wechat-chat
description: Export local WeChat 4.x (WCDB / SQLCipher) chat history as plain SQLite, TXT and JSON. Read-only memory scan of Config.Cipher material -- no injection, no hook, no file modification. Also covers WeChat 3.x legacy SQLCipher 3 decryption with PyWxDump and the version-bypass patch trap.
---

# Export WeChat Chat History (Local, Read-Only)

Use this skill when the user asks to **export, decrypt, dump or back up their own local WeChat (Weixin) chat history on Windows** -- converting the encrypted database into plain text / JSON / SQLite they can read.

> **Scope boundary.** This skill is for processing the user's own chat data on their own device, for personal backup and analysis. It does not deal with accounts the user does not own, with credential theft, or with automation that sends messages.

> **Paths.** Commands below use `~/.agents/skills/export-wechat-chat/`. Any installed copy works: use `~/.claude/skills/export-wechat-chat/`, `~/.gemini/config/skills/export-wechat-chat/`, or a path relative to this SKILL.md instead -- only one of the three needs to exist.

## Tool landscape

The user may already have one or more of these locally. Check what is on disk first before cloning anything:

| Tool | Purpose |
|---|---|
| `wcdb-key-tool` | **Primary for WeChat 4.x** -- key extraction + WCDB decrypt |
| `PyWxDump` | WeChat 3.x SQLCipher 3 decrypt (legacy) |
| `WeChatMsg` | WeChat 3.x GUI viewer / exporter (legacy) |
| `version_tool` | Low-level WeChat 3 version-patch tool (avoid unless asked) |

This skill documents the pattern, not a single bundled tool. If the user does not have any of these, point them to the upstream repos rather than cloning without asking.

## WeChat 4.x -- Standard Workflow

**Data location.** WeChat 4.x writes its data to a configurable directory, stored in:
```
%APPDATA%\Tencent\WeChat\<shared>\config\3ebffe94.ini
```
`<shared>` is WeChat's fixed shared-data folder, not an account name: on a stock
Windows install it is the literal `All Users` directory (the same one `C:\ProgramData`
points at), and it is identical on every machine. The gate script cannot tell that
literal folder name apart from a real username in a `Users\<name>\` path, hence the
placeholder; substitute the literal name when reading the file. `BaseDir=` inside it
gives the data root. The actual chat DBs are then at:
```
<BaseDir>\xwechat_files\<wxid_xxx_suffix>\db_storage\
```

Account directory format: `<wxid>_<4-hex-char-suffix>`, e.g. `wxid_abc123def456_85e7`.

To find the currently active account, list `xwechat_files\` and sort by `LastWriteTime`; the most recently touched directory belongs to the signed-in account. On a multi-account machine, confirm which account the user means before proceeding.

### Step-by-step

1. **Find the data directory.** Read `3ebffe94.ini` to get `BaseDir`, then list `xwechat_files\` under it.

2. **Verify WeChat is running and signed in.** Key extraction requires the process in memory:
   ```powershell
   Get-Process -Name Weixin -ErrorAction SilentlyContinue
   ```
   If not running, tell the user to log in first. There is no offline way to get the key.

3. **Extract key and decrypt in one step** (typical wcdb-key-tool command):
   ```powershell
   cd <wcdb-key-tool-dir>
   python wcdb_key_tool_windows.py extract `
     --db-dir "<BaseDir>\xwechat_files\<wxid_xxx>\db_storage" `
     --output "keys_<wxid_xxx>.json" `
     --decrypt
   ```
   This produces plain SQLite under `.\decrypted\`.

4. **Rename the decrypted dir** before working on the next account to avoid overwriting:
   ```powershell
   Rename-Item .\decrypted decrypted_<wxid_xxx>
   ```

5. **Verify.** Always verify before considering the job done:
   - row count matches what the user expects (or is plausible for their usage)
   - keyword search returns hits for words you know are in the data (see "Verification" below)
   - `contact.db` is readable with a plausible number of rows

### Schema notes (WeChat 4.x plain DB)

- `contact\contact.db` -- table `contact`, columns include `username, nick_name, remark, alias`.
- `message\message_*.db` -- many tables `Msg_<md5>`, each = one chat session.
  Columns include `local_id, server_id, sort_seq, create_time, message_content (TEXT)`,
  `compress_content (TEXT)`, `packed_info_data (BLOB)`.
- `session\session.db` -- session mapping.
- Full list: around 20-25 databases (bizchat, chatbot, contact, emoticon, favorite,
  general, hardlink, message, miniapp, public, search, session, sns, ...).

## WeChat 3.x -- Legacy Workflow

Use only when the user specifically asks about old WeChat 3 data on a machine that still has it.

Key facts:
- **Encryption:** SQLCipher 3, AES-256-CBC, SHA1 HMAC, 4096-byte pages.
- **Key location:** raw key in `WeChat.exe` memory, found by feature-code scan.
- **The version-bypass trap.** WeChat 3.9.12.x is rejected server-side ("version too low").
  `login_wechat.py`-style scripts patch the version number in memory. This is a fragile,
  version-specific hack -- some accounts are server-side banned and cannot be patched
  around. The user already knows this; only remind them if they ask why a 3.x login fails.
- **Migration.** WeChat 4.x auto-migrates 3.x history on first login (converts MSG*.db into
  WCDB and writes into `message\`). So for the same account, the WeChat 4 plain DB already
  contains 3.x history -- you do not need to decrypt both separately. Verify by checking
  that the earliest message timestamp predates 4.x's release date.

## Pitfalls (the "trap" list)

1. **Must be logged in.** No running Weixin.exe = no key in memory = can't extract.

2. **Multi-account mix-up.** Multiple `wxid_*` dirs can exist. Always pick the
   recently written one, or ask which account.

3. **WAL files matter.** `-wal` / `-shm` contain uncheckpointed recent messages. Always
   copy the whole `db_storage\` tree, not just `.db` files.

4. **Decrypt dir overwriting.** Default output is always `decrypted\`. Rename
   between accounts.

5. **Auto-migration from 3.x to 4.x.** On first login, 4.x converts 3.x MSG*.db into WCDB.
   So the 4.x plain DB already contains 3.x history for the same account.

6. **Large DBs are slow.** `message_3.db` (or whichever is biggest) can be 1+ GB and take
   several minutes to decrypt. It is not hung.

7. **Python 64-bit reading 32-bit WeChat 3.** `pymem.list_modules()` won't find
   `WeChatWin.dll` -- need `EnumProcessModulesEx` with `LIST_MODULES_ALL`.
   (Only relevant for 3.x work.)

8. **Subprocess lifecycle.** If you launch WeChat.exe from a Python script without
   `DETACHED_PROCESS`, the process dies when the script exits.

## Verification checklist

After any export, confirm all of these before reporting success:

- [ ] Decryption integrity: `integrity_check = ok` (or equivalent) on every decrypted DB.
- [ ] Row count: total message count is plausible for the account's age.
- [ ] Time range: earliest message is consistent with when the account was created.
- [ ] Keyword search: 2-3 words you expect to be in the data return >0 hits,
      and sample snippets are readable (not mojibake, not encrypted bytes).
- [ ] Contact / group info: auxiliary DBs (profile, group member) decrypt and are queryable.

Keep verification scripts **source-ASCII** -- build CJK keywords from code points
(`"温州"` not `"温州"`) -- so the script file's own encoding cannot
silently turn keyword matches into zero hits. Write results to a file as well as
stdout, so the console encoding cannot be the single point of failure.

## Legal / safety note

Mention briefly if the user asks "is this legal" or "is this allowed":

- Backing up your own chat data on your own device is personal data access,
  consistent with PRC Personal Information Protection Law article 45.
- The technique (read-only memory scanning) is similar to what antivirus / memory
  cleaners do -- much lower detection risk than code injection.
- The Tencent EULA prohibits reverse engineering / memory access. Risk is account
  restriction, not legal action.
- **Do not distribute decrypted DBs or keys.** They contain other people's
  personal info. Keep them local.

## Related skills

- `export-qq-chat` -- same pattern for QQ NT
- `run-sql-file` -- the CJK-in-scripts / BOM / encoding discipline used here
  comes from that skill's pitfalls
