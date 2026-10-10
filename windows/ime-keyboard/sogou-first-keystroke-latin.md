# First Pinyin Keystroke Commits as Latin (Sogou / Third-Party IMEs)

Symptom: on Windows 11, right after a paste (or a window switch), the first letter of a
Pinyin string goes into the document as plain Latin while the rest enters the IME pre-edit.
Example: type `zimu` after Ctrl+V; the app shows `z`, the candidate line shows `imu`.

**Status: hypothesis, not a proven root cause.** Nothing on record shows that the symptom
stopped after the changes below. Treat this as a checklist of suspects, not a verdict.

## Suspects

The symptom correlates with the touch-keyboard / text-input stack rather than with the IME.

| Suspect | Where | Value that avoids it |
| :--- | :--- | :--- |
| Touch keyboard auto-invoke with a physical keyboard attached | `HKCU:\Software\Microsoft\TabletTip\1.7\EnableDesktopModeAutoInvoke` (DWORD) | `0` |
| Touch keyboard tap invoke | same key, `TouchKeyboardTapInvoke` (DWORD) | `0` |
| Text input service not running | service `TextInputManagementService` (Windows 11); `TabletInputService` is absent on 25H2 | Running |
| Undocumented per-user flags (community reports only) | `HKCU:\Software\Microsoft\InputMethod\Settings\Common`: `TouchKeyboardHasEverShown`, `InputPanelPageLastOpenTime` | `0` and a far-future Unix time (`2051193600`) |

Settings equivalent of the first row: `Time & language -> Typing -> Touch keyboard`.
The last row is undocumented and may change between builds; change it only after the rest
failed, and export the key first (`reg export`).

## Observed state on the affected machine (Windows 11 25H2, build 26200)

A diagnostic run on 2025-10-21, after remediation, read: `EnableDesktopModeAutoInvoke=0`,
`TouchKeyboardTapInvoke=0`, `TouchKeyboardHasEverShown=0`, `InputPanelPageLastOpenTime=2051193600`,
`TextInputManagementService` Running with start type **Auto**, physical keyboard present.
The check script itself is not kept in this repo.

## Check and try, in order

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\TabletTip\1.7' |
  Select-Object EnableDesktopModeAutoInvoke, TouchKeyboardTapInvoke
Get-Service TextInputManagementService | Select-Object Status, StartType
Set-ItemProperty 'HKCU:\Software\Microsoft\TabletTip\1.7' EnableDesktopModeAutoInvoke 0
Restart-Service TextInputManagementService     # needs an elevated shell
```

Reproduce after each step: Notepad, copy some text, Ctrl+V, type `zimu`.
If the first letter still leaks, switch IME (the Microsoft Pinyin IME is the control) to
separate an IME bug from a text-input-stack bug.

## Related

- [`stray-keyboard-layouts.md`](stray-keyboard-layouts.md)
