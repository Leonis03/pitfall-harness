# Closing Typora From a Script (and Discarding Its Session)

Two scripts in this directory, for when you want Typora gone without clicking through it:

| Script | Does | Unsaved edits | Next launch |
| :--- | :--- | :--- | :--- |
| `close-typora.ps1` | posts `WM_CLOSE` to every visible Typora window | Typora asks Save / Don't Save / Cancel | one empty window |
| `kill-typora.ps1` | `taskkill /F /T` on every Typora process, then resets the session file | **discarded**, no prompt | one empty window |

Tested on Typora 1.14.9 (Windows 11): both end with one empty `Typora` window on the next start.

## Why a plain kill is not enough

Typora keeps its session in `%APPDATA%\Typora\backups\sum`:

```json
{"innormalQuit":true,"windows":[{"id":2,"path":"<file>","mountFolder":"<dir>","bound":{...}}]}
```

- While running, `innormalQuit` is `true` and `windows` lists every open window.
- A normal quit rewrites it to
  `{"innormalQuit":false,"windows":[{"path":"","id":0,"bound":{"fullscreen":false,"maximized":true}}]}`.
- A kill cannot rewrite it, so the next start sees `true`, logs `recoverFromBackup` in
  `%APPDATA%\Typora\typora.log`, and reopens every window with its unsaved content from
  `backups\<n>` and `draftsRecover\`.

`kill-typora.ps1` writes the "normal quit" content after the processes are gone. It must wait
for them to exit first: a still-running Typora rewrites `sum` on its way out. The recovery
copies stay on disk (dig through `draftsRecover\` to rescue something); they are just no
longer loaded.

## Why enumerate windows in `close-typora.ps1`

Typora is Electron: one main process plus renderer and GPU helpers, and several document
windows can be open. `Process.CloseMainWindow()` reaches one window per process.
`EnumWindows` filtered by Typora process ids reaches all of them.

## Running it by double-click

Explorer opens a `.ps1` in an editor on double-click. Make a shortcut instead; target:

```text
pwsh -NoProfile -WindowStyle Hidden -File "<path>\close-typora.ps1"
```

(`powershell.exe` works too; the scripts use nothing PowerShell 7 specific.)

## Caveats

- `sum` is an internal Typora file, not a documented interface; the format above was read from
  1.14.9. If a future version changes it, the kill script falls back to a plain kill plus a
  restored session. Check `typora.log` for `recoverFromBackup` after an update.
- Files already saved to disk are never touched by either script.
