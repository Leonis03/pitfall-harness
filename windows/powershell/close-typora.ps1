# Ask every open Typora window to close, the way the X button does.
#
# Why WM_CLOSE rather than Stop-Process: a window that receives WM_CLOSE runs
# Typora's normal close path, so a document with unsaved changes still gets the
# Save / Don't Save / Cancel prompt instead of being lost. Stop-Process skips it
# (that is what kill-typora.ps1 is for).
#
# Why enumerate windows by process id instead of Process.CloseMainWindow():
# Typora is Electron, so "Typora" is one process tree and several windows can be
# open. CloseMainWindow() only reaches the single main window of each process;
# EnumWindows reaches every visible top-level window owned by a Typora process.
#
# Double-click does not run a .ps1 (Explorer opens it in an editor). Make a
# shortcut with the target:
#   pwsh -NoProfile -WindowStyle Hidden -File "<path>\close-typora.ps1"
#
# Usage:  pwsh -NoProfile -File close-typora.ps1
Add-Type @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class TyporaCloser {
    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    const uint WM_CLOSE = 0x0010;

    public static int CloseAll() {
        var pids = new HashSet<uint>();
        foreach (var p in Process.GetProcessesByName("Typora")) pids.Add((uint)p.Id);
        int posted = 0;
        if (pids.Count == 0) return posted;
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pids.Contains(pid) && IsWindowVisible(hWnd)) {
                PostMessage(hWnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
                posted++;
            }
            return true;
        }, IntPtr.Zero);
        return posted;
    }
}
"@

$n = [TyporaCloser]::CloseAll()
Write-Host "Sent WM_CLOSE to $n Typora window(s)."
