# Clipboard and keystroke automation on a Plasma Wayland desktop

> **Environment**: Fedora 44, KDE Plasma 6.7.5, **Wayland** session, Fcitx 5 as KWin's input
> method (see [`wayland-fcitx5-rime.md`](wayland-fcitx5-rime.md), root cause 4), XWayland
> present. CopyQ 17.0.0, wl-clipboard 2.2.1, xclip 0.13, xdotool, ydotool.
> **Measured** 2026-11-22. Fedora was tried on this desktop and abandoned in 2026-11, so this is a
> point-in-time record.
>
> **Scope**: which of the X11 conveniences -- a clipboard manager that pastes for you, clipboard
> tools on the command line, typing on the user's behalf -- still work on Wayland, which need a
> workaround, and which do not work at all. It is the evidence for choosing between a Wayland and
> an X11 session.

---

## Summary

| What | Result |
| :--- | :--- |
| CopyQ records copies from native Wayland apps | works |
| CopyQ records copies from XWayland apps | works |
| CopyQ's own global shortcut (`Meta+V`) over a native Wayland window | works |
| Picking a CopyQ item puts it on the clipboard | works |
| Picking a CopyQ item **pastes it into the focused window** | **does not work** -- needs a real Ctrl+V |
| `wl-copy` -> `wl-paste` | works |
| X11 -> Wayland clipboard (`xclip` -> `wl-paste`) | works |
| Wayland -> X11 clipboard (`wl-copy` -> `xclip -o`) | failed in this test -- see below |
| Primary selection, X11 -> Wayland | works |
| Primary selection, Wayland -> X11 | failed in this test -- see below |
| `xdotool type` into any window, XWayland included | **does not work** |
| `ydotool type` into native Wayland, XWayland and X11 windows | works |

On an X11 session every row of this table works, which is the main reason to keep one.

---

## CopyQ: history yes, paste-for-you no

Clipboard monitoring works for both kinds of client: a copy in Chrome on native Wayland and a copy
in Chrome under XWayland (`--ozone-platform=x11`) both showed up as the newest item
(`copyq read 0`). CopyQ's own global shortcut, set in CopyQ's settings, opened its popup over a
focused native Wayland window, with the top item selected.

Activating an item (Enter) put it on the clipboard -- `wl-paste` returned it -- and returned focus
to the previous window. But CopyQ's "paste" step, the synthesized Ctrl+V that follows, never
reached the focused window, in a native Wayland window or in an XWayland one: the text box stayed
as it was. A real Ctrl+V sent right after, through `ydotool`, pasted the item.

So the chain breaks only at the last step. The workaround is a CopyQ command or a shortcut that
activates the item and then sends Ctrl+V through `ydotool`. The CopyQ documentation lists pasting
into other apps among the Wayland features that depend on the desktop.

---

## Clipboard and primary selection between Wayland and XWayland

Measured from a terminal on native Wayland:

| Direction | Command | Result |
| :--- | :--- | :--- |
| Wayland -> Wayland | `wl-copy` -> `wl-paste` | works |
| X11 -> Wayland | `xclip -selection clipboard` -> `wl-paste` | works |
| Wayland -> X11 | `wl-copy` -> `xclip -o -selection clipboard` | `There is no owner for the CLIPBOARD selection` |
| X11 -> Wayland, primary | `xclip` -> `wl-paste --primary` | works |
| Wayland -> X11, primary | `wl-copy --primary` -> `xclip -o -selection primary` | `There is no owner for the PRIMARY selection` |

Whatever is set on the X11 side is visible to Wayland clients; whatever is set on the Wayland side
was not visible to the X11 side. CopyQ itself saw both.

**Not settled:** the `xclip -o` reads ran from a native Wayland terminal, with no XWayland window
focused. A compositor may hand the Wayland clipboard to XWayland only when an X11 window takes
focus, which would make this direction a test artifact rather than a limit. To settle it, focus an
XWayland window (for example Chrome with `--ozone-platform=x11`) before reading with `xclip -o`.

---

## Typing for the user: `xdotool` does not work, `ydotool` does

| Target window | `xdotool type` | `ydotool type` |
| :--- | :--- | :--- |
| Chrome, native Wayland | nothing inserted | works |
| Chrome under XWayland | nothing inserted | works |
| Konsole forced to X11 (`QT_QPA_PLATFORM=xcb`) | nothing inserted | works |

`xdotool` failed even on X11 windows running under XWayland, while `xdotool getactivewindow`
still reported that window and its name -- it can see the X11 windows but cannot type into them.
`ydotool` writes to the kernel's uinput device, the same path as a physical keyboard, so the
compositor treats it as real input and it works everywhere; it needs its daemon running with access
to `/dev/uinput`.

**Automated typing must run at human speed** when an input method is involved. At `ydotool`'s
default 20 ms per key, and still at 110 ms, the client received keys faster than the input method
round-trips them: Firefox dropped keys, Chrome under text-input-v3 committed each letter on its
own, and the Plasma launcher's search field lost the input method after the first key -- while it
typed normally by hand. With a key delay of 130-140 ms every client converted normally. A test
that fails only under automation is not a finding until a person has typed the same thing.

---

## What this means when choosing a session

- The clipboard history itself is not the problem on Plasma Wayland; pasting for the user and
  typing for the user are. Both need `ydotool`, which runs as a root-level input device.
- Anything built on `xdotool` -- text expanders, macro tools, scripts that type -- has to be
  ported to `ydotool` or a compositor-specific tool, or stay on an X11 session.
- An X11 session (for example Debian 13 with KDE Plasma's X11 session, or Cinnamon) keeps all of
  the above working without workarounds.
