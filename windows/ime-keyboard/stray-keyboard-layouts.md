# Stray Keyboard Layouts in the Language Switcher

Symptom: languages were uninstalled, but their keyboards still appear in the Win+Space /
Alt+Shift switcher (seen: German, Greek, Russian), and the language bar offers no way to
remove them.

## Where the entries live

Settings only edits the user language list. The switcher also reads four registry keys, and
an uninstall can leave values behind in them:

| Key | Holds |
| :--- | :--- |
| `HKCU:\Keyboard Layout\Preload` | ordered layout IDs (`1 = 00000409`, ...) |
| `HKCU:\Keyboard Layout\Substitutes` | requested-ID -> actual-ID remaps |
| `HKU:\.DEFAULT\Keyboard Layout\Preload` | same, for the sign-in screen / new users |
| `HKU:\.DEFAULT\Keyboard Layout\Substitutes` | same |

Layout IDs to keep for English: `00000409` US, `00010409` US Dvorak, `00020409` US
International.

Trap: PowerShell has **no `HKU:` drive** by default. `Test-Path 'HKU:\.DEFAULT\...'` returns
`$false` even when the key exists, so a script reports "missing" and skips it. Create the
drive first: `New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS`. The first run of
the original script (2025-10-15) logged both `HKU:` keys as `<missing>` for this reason;
`fix-keyboard-layouts.ps1` now creates the drive.

## Fix, least invasive first

1. **Through Settings** (steps from the 2025-10-07 notes):
   `Settings -> Time & language -> Language & region -> Add a language`, add the ghost
   language (e.g. German); open its `Language options`, remove the keyboard; then remove the
   language itself. Repeat per language.
2. **Script:** `fix-keyboard-layouts.ps1` (this directory). It prints the four keys, resets
   the language list with `Set-WinUserLanguageList`, exports the keys to `.reg` backups,
   deletes Preload / Substitutes values outside the keep list, and warns about sync.
   `-Keep "ja-JP"` adds tags to the keep list (`en-US` is always kept). Restore a backup with
   `reg import <file>.reg`.
3. Reboot, then recheck the switcher.

## Cloud sync re-adds them

With `Settings -> Accounts -> Windows backup -> Remember my preferences -> Language
preferences` ON, layouts can come back from the account after you clean them. Turn it off
before cleaning (the script checks
`HKCU:\Software\Microsoft\Windows\CurrentVersion\SettingSync\Groups\Language` and warns).

## Evidence level

The script ran on one machine on 2025-10-15: it removed `zh-Hans-CN` from the language list
and exported `HKCU` backups; before the cleanup `HKCU` Preload held `00000804` three times
plus `00000409`.
The `lpksetup /u` step and the Substitutes cleanup were not observed to do anything there.
For the German / Greek / Russian ghosts (2025-10-07) only the manual steps in 1 were
written down; the notes do not record the final outcome.

## Related

- [`sogou-first-keystroke-latin.md`](sogou-first-keystroke-latin.md) -- another language-bar
  problem on the same machine.
