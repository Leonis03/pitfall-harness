# Force-kill every Typora process AND discard its session, so the next launch is one
# clean empty window instead of the windows and unsaved drafts that were open.
#
# Why the extra step: Typora records its open windows in %APPDATA%\Typora\backups\sum
# ({"innormalQuit":true,"windows":[...]}) and per-window recovery copies next to it.
# A normal quit rewrites sum to {"innormalQuit":false,"windows":[<one empty window>]};
# a kill cannot, so the next start sees innormalQuit=true and reopens everything
# ("recoverFromBackup" in typora.log). This script writes the same content a normal
# quit would, after the processes are gone. The recovery copies (backups\<n>,
# draftsRecover\) are left on disk but are no longer loaded.
#
# Unsaved edits are therefore NOT restored on the next launch. Files already saved to
# disk are untouched. Use close-typora.ps1 instead to keep the Save / Don't Save prompt.
#
# Typora is Electron: one main process plus renderer/GPU helpers, so kill the whole
# tree through taskkill /T.
#
# Double-click does not run a .ps1. Make a shortcut with the target:
#   pwsh -NoProfile -WindowStyle Hidden -File "<path>\kill-typora.ps1"
#
# Usage:  pwsh -NoProfile -File kill-typora.ps1
$procs = @(Get-Process -Name Typora -ErrorAction SilentlyContinue)
foreach ($p in $procs) {
    & taskkill.exe /F /T /PID $p.Id 2>&1 | Out-Null
}

# Wait until nothing is left; a still-running Typora would rewrite sum on exit.
$deadline = (Get-Date).AddSeconds(5)
while ((Get-Process -Name Typora -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
}
$left = @(Get-Process -Name Typora -ErrorAction SilentlyContinue).Count
if ($left -gt 0) {
    Write-Warning "$left Typora process(es) still running; session not reset."
    return
}

$sum = Join-Path $env:APPDATA 'Typora\backups\sum'
if (Test-Path $sum) {
    $clean = '{"innormalQuit":false,"windows":[{"path":"","id":0,"bound":{"fullscreen":false,"maximized":true}}]}'
    Set-Content -Path $sum -Value $clean -NoNewline -Encoding utf8
    Write-Host "Killed $($procs.Count) process(es); session reset, next start is a clean window."
} else {
    Write-Host "Killed $($procs.Count) process(es); no session file at $sum."
}
