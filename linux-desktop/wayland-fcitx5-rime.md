# Fcitx5 + Rime on a native Wayland desktop (KDE Plasma 6)

> **Environment**: Fedora 44, KDE Plasma 6.7, **Wayland** session (`XDG_SESSION_TYPE=wayland`),
> XWayland present for legacy X11 apps.
> **Scope**: installing Fcitx5 + Rime (雾凇拼音) and trying to make it work in **native Wayland
> clients** (Chromium/Chrome, Firefox) as well as in X11/D-Bus clients (Konsole, Dolphin, Plasma
> search).
>
> This is the Wayland-native counterpart to [`gui-and-ime.md`](gui-and-ime.md), which covers the
> X11 path (`im-config`, `~/.xinputrc`, `imsettings`). The two differ in **how Fcitx5 is
> started and which environment variables are set**, and getting that wrong breaks a *subset* of
> apps only -- which is what makes it hard to diagnose.
>
> Deployable originals for every config below live in
> [`files/fcitx5-wayland/`](files/fcitx5-wayland/): `environment`, `fcitx5-config`,
> `fcitx5-profile`, `default.custom.yaml`, `rime_ice.custom.yaml`.
>
> **Status (2026-11-22).** Two verification rounds followed on the same machine. The second found
> the cause behind the browsers: **Fcitx5 was not KWin's input method**
> ([root cause 4](#root-cause-4-fcitx5-is-not-kwins-input-method)). With Fcitx 5 selected as the
> Plasma virtual keyboard, Chrome and Firefox on native Wayland both type Chinese -- Chrome
> without any flags, Firefox with or without `GTK_IM_MODULE`. Root causes 1 and 3 and the XIM
> server name stand; root cause 2 was not the cause in either direction. Fedora was tried on this
> desktop and abandoned in 2026-11, so this document is a point-in-time record.

---

## The symptom that motivates this document

Chinese input works in the terminal, in the Plasma search bar, and in Dolphin -- but **not in
Chrome or Firefox**. Everything is installed; `fcitx5-remote` reports the daemon active and the
current IM is `rime`. Nothing errors.

That split is the fingerprint. `fcitx5-diagnose` labels each input context with the frontend that
created it:

```text
IC [..] program:org.kde.konsole frontend:dbus    cap:e001820832   <- works
IC [..] program:dolphin          frontend:dbus    cap:1e001800032   <- works
IC [..] program:google-chrome    frontend:wayland cap:1072         <- BROKEN
```

`frontend:dbus` means the app reached Fcitx5 through the **D-Bus** frontend (the
`im-fcitx5.so` GTK/Qt module path). `frontend:wayland` means the app used the **Wayland
input-method protocol** (`zwp_input_method_v2`, served by Fcitx5's `libwaylandim.so`).

So the working apps and the broken apps are not using the same code path. That is the whole
diagnosis: **the broken apps are the ones that go through the Wayland path**. Why that path
delivered nothing turned out to be root cause 4: KWin was not handing the input-method protocol to
Fcitx5. Root cause 2, the first explanation tried, was not it.

---

## Root cause 1: `XMODIFIERS=@im=none` for the whole session

**Symptom.** Fcitx5 is installed and starts, but nothing inherits a usable input method.
`fcitx5-diagnose` reports:

```text
**Environment variable XMODIFIERS is "@im=none" instead of "@im=fcitx".**
```

**Cause.** Fedora does not use `im-config`; it uses **imsettings**. The Plasma session runs
`/etc/xdg/plasma-workspace/env/xinput.sh` (a symlink to `/etc/X11/xinit/xinitrc.d/50-xinput.sh`),
which sources a per-user or system `xinputrc` to decide the IM. But that script contains a
**locale gate**:

```bash
_im_language_list="as bn gu hi ja kn ko mai ml mr ne or pa si ta te th ur vi zh"
for i in $_im_language_list; do
    if echo $tmplang | grep -q -E "^$i"; then source "$SYS_XINPUTRC"; ...; fi
done
if [ $_sourced_xinputrc -eq 0 ]; then
    source /etc/X11/xinit/xinput.d//none.conf      # XIM=none, GTK_IM_MODULE=gtk-im-context-simple
fi
```

With `LANG=en_US.UTF-8` the locale gate never matches, so the script falls through to
`none.conf` and the session starts with **no IM at all**. The system `xinputrc` already pointed at
`fcitx5.conf` (`/etc/alternatives/xinputrc` -> `/etc/X11/xinit/xinput.d/fcitx5.conf`), but the
locale gate means the *system* file is not read at all.

**Why it is invisible.** The desktop still starts, still has a terminal, still has a browser. Only
the IM is missing.

**Fix.** Give imsettings a **per-user** `xinputrc`. It is read *before* the locale-gated system
file, so it bypasses the gate:

```bash
ln -sfn /etc/X11/xinit/xinput.d/fcitx5.conf ~/.config/imsettings/xinputrc
```

Do not edit the system `xinputrc` and do not change the session locale to work around it.

On the machine the per-user file ended up as a regular 207-byte file, not this symlink, and it
also carries `IMSETTINGS_IGNORE_SESSION=*-wayland`, `GTK_IM_MODULE=fcitx` and
`QT_IM_MODULE=fcitx`. Those two lines are a plausible source of the toolkit variables that the
session environment still held at verification time (root cause 2) -- not verified.

---

## Root cause 2 (not confirmed): `GTK_IM_MODULE` / `QT_IM_MODULE` set globally

> **Not the cause, in either direction.** The text below is the original reading, kept as the
> record. Removing the variables did not make the browsers type, and the first verification's
> opposite reading ("the browser that types keeps `GTK_IM_MODULE=fcitx`") did not hold either:
> once Fcitx5 was KWin's input method, Firefox typed with and without the variable. The cause
> was [root cause 4](#root-cause-4-fcitx5-is-not-kwins-input-method). Do not deploy the
> `/etc/environment` change below as a browser fix.

**Symptom.** Root cause 1 is fixed, `XMODIFIERS` is now `@im=fcitx` -- and the terminal, Dolphin
and the Plasma search bar work, **but Chrome and Firefox still do not**.

**Cause.** On Wayland, a native client should talk to Fcitx5 over the Wayland input-method
protocol. Setting `GTK_IM_MODULE=fcitx` / `QT_IM_MODULE=fcitx` tells the *toolkit* to use Fcitx5's
X11-era module instead, which on a native Wayland client is the wrong path. Fcitx5 says so itself,
in a notification that appears at startup:

> **Wayland Diagnose** -- Detect `GTK_IM_MODULE` and `QT_IM_MODULE` being set and Wayland Input
> method frontend is working. It is recommended to use Wayland input method frontend.

Fcitx5's own `--verbose` log says the same thing:

```text
waylandmodule.cpp:702] Using Wayland native input method protocol: 1
waylandmodule.cpp:706] GTK_IM_MODULE=fcitx
waylandmodule.cpp:707] QT_IM_MODULE=fcitx
```

**Where the variables come from.** `fcitx5-autostart` ships `/etc/profile.d/fcitx5.sh`, which
exports them for every GUI login:

```bash
if [ ! "$XDG_SESSION_TYPE" = "tty" ]; then
    export INPUT_METHOD=fcitx
    export GTK_IM_MODULE=fcitx
    export QT_IM_MODULE=fcitx
    export XMODIFIERS=@im=fcitx
fi
```

That file is packaged and gets overwritten on upgrade, so **do not edit it**. The original fix
neutralised the variables for the session instead and kept only `XMODIFIERS` -- the verification
found it neither took full effect nor fixed the browsers:

```bash
# /etc/environment
XMODIFIERS=@im=fcitx
```

Verify what a fresh login would actually inherit -- `/etc/environment` is applied by PAM, but
`/etc/profile.d/*.sh` still runs afterwards for login shells:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin XDG_SESSION_TYPE=wayland \
  bash -c 'for f in /etc/profile.d/*.sh; do [ -r "$f" ] && . "$f"; done;
           echo "GTK_IM_MODULE=[$GTK_IM_MODULE] QT_IM_MODULE=[$QT_IM_MODULE] XMODIFIERS=[$XMODIFIERS]"'
```

At verification time that command still printed `GTK_IM_MODULE=[fcitx] QT_IM_MODULE=[fcitx]`:
the packaged `profile.d` file runs after `/etc/environment`, so login shells get both variables
back. `systemctl --user show-environment` still held both as well. Only the Fcitx5 daemon itself
started without them (its `/proc/<pid>/environ` had `XMODIFIERS` only, and the startup warning
was gone).

### First verification (2026-11-21) -- superseded by root cause 4

> This round ran while Fcitx5 was started by imsettings, not by KWin, and its reading -- "the
> variable is what makes the browser type" -- did not survive the second round. It is kept because
> it shows how a plausible reading of a real measurement can still be wrong.

Measured on the same machine -- Chrome 156.0.8078.47, Plasma 6.7, fcitx5 5.1.23 -- with a person
typing:

| Client | Started from | `GTK_IM_MODULE` in its environment | Input contexts in `fcitx5-diagnose` | Chinese input |
| :--- | :--- | :--- | :--- | :--- |
| Firefox, native Wayland | the panel | `fcitx` | `frontend:dbus` and `frontend:wayland` | **works** |
| Chrome, native Wayland | a shell that unsets the variable | absent | `frontend:wayland cap:1072` only | none |
| Chrome, native Wayland, `--enable-wayland-ime` | the same shell | absent | `frontend:wayland cap:1072` only | none |
| Chrome under XWayland: `GTK_IM_MODULE=fcitx google-chrome --ozone-platform=x11` | a shell, variable set for this process | `fcitx` | not recorded | **works** -- Rime candidates appear |

What this shows:

- The path that delivers text on this machine is the toolkit module over D-Bus, and it exists
  only while `GTK_IM_MODULE=fcitx` is in the client's environment. The `frontend:wayland`
  context appeared in both browsers; Chrome, which had nothing else, typed nothing.
- So root cause 2's conclusion -- remove the variables so the native Wayland path is used -- is
  backwards here. The original Chrome symptom (`frontend:wayland cap:1072 <- BROKEN`) was never
  fixed: it is the same line at verification time.
- The Chrome rows are not a clean comparison with the Firefox row: Chrome was started from a
  shell without the variable. The XWayland row is the one that isolates the variable.

This round left two questions open -- Firefox with the variables removed, and whether KWin
handed the input-method protocol to Fcitx5 at all. The second round answered both: see
[root cause 4](#root-cause-4-fcitx5-is-not-kwins-input-method).

The XWayland route measured here still works, and stays a fallback for a session where the
virtual-keyboard setting cannot be used:

```bash
GTK_IM_MODULE=fcitx google-chrome --ozone-platform=x11
```

---

## Root cause 3: a `default.custom.yaml` patch does not reach the active schema

**Symptom.** The Rime engine is loaded, the schema is `rime_ice`, but a patch to
`ascii_composer/switch_key` in `default.custom.yaml` has **no effect** -- Shift still commits the
first candidate instead of the raw pinyin.

**Cause.** `rime_ice.schema.yaml` has **no `extends:` line**, so it does not inherit
`default.yaml`. A patch in `default.custom.yaml` is applied to `default.yaml` only. Some keys still
appear to work (`menu/page_size`, `selector/linear/bindings`) because Rime merges `default.yaml`
as a base for *standard* sections -- but `ascii_composer` is not among them.

**Proof.** Put a unique marker in each file and rebuild:

```bash
# default.custom.yaml
patch:
  "menu/marker_in_menu": 111
# rime_ice.custom.yaml
patch:
  marker_only_in_schema: 67890

rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data \
              ~/.local/share/fcitx5/rime/build
grep -n 'marker' ~/.local/share/fcitx5/rime/build/rime_ice.schema.yaml
```

Result: `marker_in_menu` and `marker_only_in_schema` are both in the built schema;
a marker placed at the *top level* of `default.custom.yaml` is not.

**Fix.** Schema-level patches go in `~/.local/share/fcitx5/rime/rime_ice.custom.yaml`, named after
the **schema id**, not the schema file:

```yaml
# ~/.local/share/fcitx5/rime/rime_ice.custom.yaml
patch:
  "ascii_composer/switch_key":
    Caps_Lock: clear
    Shift_L: commit_code
    Shift_R: noop
    Control_L: noop
    Control_R: noop
```

The file name must be `<schema-id>.custom.yaml` (`rime_ice.custom.yaml`). Rime's build info
records the name it actually consumed:

```yaml
__build_info:
  timestamps:
    default.custom: 1792775136
    rime_ice.custom: 1792828172      <- non-zero means the file was read
    rime_ice.schema: 1792775133
```

A `rime_ice.custom: 0` timestamp means the file was ignored -- e.g. when it is wrongly named
`rime_ice.schema.custom.yaml`.

**Also verify the built file, not the source.** The compiled schema is what the engine loads:

```bash
grep -A 6 'switch_key' ~/.local/share/fcitx5/rime/build/rime_ice.schema.yaml
```

---

## Root cause 4: Fcitx5 is not KWin's input method

Found by the second verification (2026-11-22; Plasma 6.7.5, fcitx5 5.1.23, Chrome 156,
Firefox 158).

**Symptom.** Root causes 1 and 3 are fixed and `XMODIFIERS` is right, yet Chrome on native
Wayland types nothing: its only input context is `frontend:wayland`. Setting or removing
`GTK_IM_MODULE` does not change that.

**Cause.** On Plasma Wayland, KWin gives the input-method protocol only to the program selected
as the **virtual keyboard** (`[Wayland] InputMethod` in `kwinrc`). On this machine that key named
Plasma's own on-screen keyboard (`org.kde.plasma.keyboard.desktop`), and Fcitx5 was started by XDG
autostart under `systemd --user`. KWin never handed the protocol to it, so a client's
`frontend:wayland` context existed but delivered nothing.

**Fix.** System Settings -> Keyboard -> Virtual Keyboard -> **Fcitx 5**, Apply, then log out and
back in. Use the GUI rather than writing `kwinrc` by hand -- the same lesson as section 4.8 of
[`fedora/README.md`](fedora/README.md).

```bash
kreadconfig6 --file kwinrc --group Wayland --key InputMethod   # now names the Fcitx 5 entry
ps -o args= -p "$(ps -o ppid= -p "$(pgrep -x fcitx5)" | tr -d ' ')"   # kwin_wayland
```

The XDG autostart entry still fires after the change; its instance exits with `Unable to request
dbus name. Is there another fcitx already running?`, so only KWin's instance survives and the
autostart entry does not need to be removed.

**Measured after the change**, each client in a fresh profile with a text box focused:

| Client | Input context (`focus:1`) | Chinese | Shift toggles | Ctrl+C / Ctrl+V |
| :--- | :--- | :--- | :--- | :--- |
| Chrome, native Wayland, no flags | `frontend:wayland cap:80072` | yes | yes | yes |
| Chrome, `--enable-wayland-ime` | `frontend:wayland cap:80072` | yes | yes | yes |
| Chrome, `--enable-wayland-ime --wayland-text-input-version=3` | `frontend:wayland` | yes | yes | yes |
| Chrome under XWayland, `GTK_IM_MODULE=fcitx --ozone-platform=x11` | `frontend:dbus` | yes | yes | yes |
| Firefox, native Wayland, no toolkit variables | `frontend:wayland cap:72` | yes | yes | yes |
| Firefox, native Wayland, `GTK_IM_MODULE=fcitx` | `frontend:dbus` | yes | -- | -- |
| Konsole | `frontend:wayland cap:72` | yes | yes | n/a (Ctrl+C is SIGINT) |
| Dolphin, location bar and search field | `frontend:wayland` | yes | -- | -- |
| KRunner | `frontend:dbus` | yes | -- | -- |
| Kickoff (application launcher) search | -- | yes, typed by hand | -- | -- |

What follows from it:

- Chrome needs no flags on Plasma Wayland once Fcitx5 is KWin's input method. The XWayland route
  of the first round is a fallback, not the fix.
- `GTK_IM_MODULE=fcitx` does not matter to the browsers here: Firefox typed with it (over D-Bus)
  and without it (over Wayland). The repo's shared shell file keeps exporting it because X11
  sessions need it.
- Shift is Rime's `ascii_mode` toggle and is remembered per input context, so a Chinese/English
  switch made in one window does not carry over to the next.

**Testing this automatically.** `ydotool type` goes through uinput, the same path as a real
keyboard, and can drive these tests -- but only at human speed. At the default 20 ms per key, and
still at 110 ms, the client receives keys faster than the input method round-trips them: Firefox
drops keys, Chrome under text-input-v3 commits each letter on its own, and the Kickoff search field
lost the input method after the first key although it typed normally by hand. With a key delay of
130-140 ms every client above converted normally. `xdotool` cannot type on this desktop at all;
see [`wayland-clipboard-automation.md`](wayland-clipboard-automation.md).

---

## Installing the packages

Fedora names the packages differently from Debian/Ubuntu, and two of them are easy to miss:

```bash
sudo dnf install -y \
    fcitx5 fcitx5-autostart fcitx5-chinese-addons \
    fcitx5-gtk3 fcitx5-gtk4 fcitx5-qt5 fcitx5-qt6 \
    fcitx5-rime librime librime-tools brise \
    fcitx5-configtool kcm-fcitx5
```

| Debian/Ubuntu | Fedora | Note |
| :--- | :--- | :--- |
| `fcitx5-frontend-gtk3` | `fcitx5-gtk3` | |
| `fcitx5-frontend-gtk4` | `fcitx5-gtk4` | |
| `fcitx5-frontend-qt5` | `fcitx5-qt5` | |
| `fcitx5-frontend-qt6` | `fcitx5-qt6` | |
| `librime-bin` | `librime-tools` | holds `rime_deployer`, `rime_dict_manager`, `rime_patch` |
| `brise` | `brise` | the stock Rime dictionary package |
| `im-config` | *(absent)* | Fedora uses **imsettings** instead -- see root cause 1 |

`fcitx5-autostart` is what registers Fcitx5 with the session (autostart entry **and**
`/etc/profile.d/fcitx5.sh`). Without it, Fcitx5 must be started by hand and never comes back
after a reboot.

---

## Deploying Rime 雾凇拼音

`plum` installs into the **Fcitx5** Rime directory, which differs from the IBus one:

```bash
cd ~/plum
env rime_dir="$HOME/.local/share/fcitx5/rime" \
    ./rime-install iDvel/rime-ice:others/recipes/full
```

`rime_dir` must be set explicitly. Without it, `plum` guesses the **Ibus** path
(`~/.config/ibus/rime`) and Fcitx5 never sees the schema. The guess lives in `plum`'s
`scripts/frontend.sh`:

```bash
fcitx/fcitx-rime | fcitx5-rime)  export rime_dir="$HOME/.local/share/fcitx5/rime" ;;
rime/ibus-rime | ibus-rime)      export rime_dir="$HOME/.config/ibus/rime" ;;
```

Compile, then **verify the built schema** (root cause 3):

```bash
rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data \
              ~/.local/share/fcitx5/rime/build
```

---

## Verifying the whole chain

`fcitx5-diagnose` is the instrument that distinguishes the two client populations. On Plasma
Wayland, check who started Fcitx5 first (root cause 4), then read the rest:

```bash
kreadconfig6 --file kwinrc --group Wayland --key InputMethod
fcitx5-diagnose | grep -E 'Environment variable XMODIFIERS|Xim Server Name'
fcitx5-diagnose | grep -E 'IC \[' | grep -E 'dbus|wayland'
gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime \
    --method org.fcitx.Fcitx.Rime1.GetCurrentSchema
```

Expected on a healthy Wayland session:

```text
Environment variable XMODIFIERS is set to "@im=fcitx" correctly.
Xim Server Name from Environment variable is fcitx.
```

A browser's context may be `frontend:wayland` (native) or `frontend:dbus` (the toolkit module,
for example under XWayland); either types once root cause 4 is fixed. A native Wayland client that
has only `frontend:wayland` and types nothing points at root cause 4 first.

**The XIM server name is `fcitx`, not `fcitx5`.** Fcitx5 registers its XIM server under the name
`fcitx`; `XMODIFIERS=@im=fcitx5` is wrong and `fcitx5-diagnose` says so explicitly
(`Environment variable XMODIFIERS is "@im=fcitx5" instead of "@im=fcitx"`). The
`/etc/X11/xinit/xinput.d/fcitx5.conf` shipped by Fedora writes `XIM=fcitx5`, and the session
script derives `XMODIFIERS=@im=$XIM` from it -- so on a stock Fedora session `XMODIFIERS` ends up
wrong even though the IM is right. Verify the **live** value, not the file's intent.

---

## Why it is worth recording

Each of the causes looks like "the IME is installed but does nothing", and the symptom
(*only the browsers are broken*) points away from all of them. The thing that actually narrowed it
down was reading `fcitx5-diagnose`'s per-context **frontend** label: it splits the working apps
from the broken ones.

Two of the causes also mislead in a second way. Root cause 1 blames the IM package, but the
package is fine -- the *locale gate in a session script* skips it. Root cause 3 blames the patch
file, but the patch is applied -- to a file the schema does not read.

And the Fcitx5 notification that appears at startup reads like the answer:

> Detect `GTK_IM_MODULE` and `QT_IM_MODULE` being set and Wayland Input method frontend is
> working. It is recommended to use Wayland input method frontend.

It points in the right direction -- native clients should use the Wayland frontend -- but not at
the blocker. That frontend only works once KWin hands Fcitx5 the input-method protocol (root
cause 4), and that is a System Settings choice, not an environment variable. Two verification
rounds looked at the variables first, and the first even concluded the opposite of the
notification. A tool's recommendation is a hypothesis until the client that was broken actually
types.
