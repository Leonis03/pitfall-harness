# Fedora 44 / KDE Plasma desktop (native Linux, Wayland)

The sibling directory [`../README.md`](../README.md) documents a **Linux Mint 22 / Cinnamon /
X11** machine. This one documents a **Fedora 44 / KDE Plasma 6 / Wayland** machine, and the
difference is bigger than a distro name swap: the package manager, the file manager, the
terminal, the clipboard backend, the display protocol and the desktop's own proxy settings are
all different components.

Most pitfalls in the Mint document still hold at the level of **cause** -- the actor changes.
This directory records what was measured on the Fedora machine, what is configured and
verified, and which Mint pitfalls need a different spelling here.

> Scope note: the Chinese input method is configured on this machine by a separate session and
> is deliberately **not** covered here. Fcitx5 / Rime belong to
> [`../gui-and-ime.md`](../gui-and-ime.md).
>
> **Status (2026-11-22).** Fedora was tried on this desktop and abandoned in 2026-11, so this
> directory is a point-in-time record and will not be re-measured. A verification on the machine
> before it was given up confirmed 4.1-4.4 and 4.7-4.10; 4.5's timings did not reproduce in
> magnitude (see there). For the Wayland input method see
> [`../wayland-fcitx5-rime.md`](../wayland-fcitx5-rime.md) -- the browsers typed once Fcitx 5 was
> KWin's virtual keyboard (its root cause 4). What the session could not do for the clipboard and
> automation is in [`../wayland-clipboard-automation.md`](../wayland-clipboard-automation.md), and
> the disk and boot layout of this desktop in
> [`../../os-install/triple-boot-layout.md`](../../os-install/triple-boot-layout.md).

---

## 1. The environment, as measured

Everything in this table was read off the running machine, not assumed from the distribution
name.

| Item | Value | How it was checked |
| :--- | :--- | :--- |
| Distribution | Fedora Linux 44, KDE Plasma Desktop Edition | `/etc/os-release` |
| Session | **Wayland** (`XDG_SESSION_TYPE=wayland`), `LANG=en_US.UTF-8` | `env` |
| Package manager | `dnf5` 5.4.6, all repos via official **metalink** | `dnf --version`, `/etc/yum.repos.d/` |
| File manager | Dolphin 26.08 | `rpm -qa` |
| Terminal | Konsole 26.08; **Ghostty 1.3.1** from the `scottames/ghostty` COPR | `command -v`, `rpm -q ghostty` |
| Shells | **zsh 5.9** is the login shell (bash is still installed); the four-layer split is deployed -- see 4.6 | `getent passwd`, `ls ~` |
| Node | v24.22.1 through nvm (`nvm alias default` = 24) | `node -v`, `~/.nvm/alias/default` |
| pnpm | 12.15.0, standalone binary under `~/.local/share/pnpm` | `pnpm -v` |
| Python | system `python3` 3.14.8 (**no `pip` module**); `uv` 0.12.24 with managed CPython 3.12.15 | `python3 -V`, `uv python list` |
| Clipboard backend | **wl-clipboard** 2.2.1 present; `xclip` / `xsel` **absent** | `command -v`, `rpm -qf` |
| Proxy client | FlClash 0.9.1, mixed port `<proxy-port>`, bound to `127.0.0.1` only | `ss -tlnp`, `~/.local/share/com.follow.clash/config.yaml` |
| Desktop proxy config | three stores, four consumers -- see 4.3 | `~/.config/kioslaverc`, `gsettings`, `~/.bashrc.d/50-proxy.sh`, `systemctl --user show-environment` |
| CJK fonts | `Noto Sans/Serif/Mono CJK SC` present, `Droid Sans Fallback` present, **no Sarasa** | `fc-list :lang=zh-cn` |
| System monitor | `plasma-systemmonitor` (the binary is **not** named `systemmonitor`) | `rpm -ql plasma-systemmonitor` |
| Terminal font | `Sarasa Term SC` (terminal) and `Sarasa Mono SC` (editor), installed to `~/.local/share/fonts/sarasa/` | `fc-list | grep -c Sarasa` |
| Clipboard manager | CopyQ 17.0.0, hotkey `Meta+V` | `copyq --version`, `~/.config/copyq/copyq.conf` |
| Search CLI | `bx` 1.7.0 plus the proxy wrapper, two API plans | `bx --version` |
| SSH | one ed25519 key, three hosts in `~/.ssh/config` | `ssh-keygen -lf ~/.ssh/id_ed25519.pub` |

---

## 2. How the Mint baseline maps onto this machine

| Mint baseline | Fedora / KDE equivalent | Note |
| :--- | :--- | :--- |
| `apt` + Mint dual-track TUNA sources | `dnf5` + official **metalink** | The metalink already answers with CN mirrors; see 4.5 |
| `mintupdate` (GUI updater) | `dnf5` + `dnf5 update` | no `aptk` background daemon, so no dpkg-lock class of problem |
| `chsh` + `gnome-terminal-server` caching `SHELL` | not applicable | Konsole is not the same architecture; and there is no zsh to switch to yet |
| GNOME Terminal dropping OSC 52 | Konsole | separate implementation; verify before assuming |
| Nemo Action for "Open in Ghostty" | Dolphin service menu | the COPR package ships its own (`/usr/share/kio/servicemenus/`) |
| `xclip` / `xsel` for the clipboard | `wl-clipboard` | the session is Wayland, so `wl-paste` is the first hit in any probe chain |
| `gnome-system-monitor` | `plasma-systemmonitor` | different binary name |
| `fsearch` (Everything clone) | not packaged | use `plocate` plus Dolphin's own index |
| `im-config -n fcitx5` | out of scope here | separate session |

---

## 3. The configured baseline

Four items were configured and verified. Every "verified" line below is a command you can
re-run; nothing is asserted from "the file looks right".

### 3.1 npm registry -> npmmirror

`~/.npmrc`:

```ini
registry=https://registry.npmmirror.com/
```

Measured on this machine:

| Path | Throughput (5.8 MB tarball) |
| :--- | ---: |
| `registry.npmjs.org` via proxy | 271 kB/s |
| `registry.npmmirror.com` via proxy | 747 kB/s |
| `registry.npmmirror.com` direct | **2.9 MB/s** |

A full `npm install typescript@5.4.5` then completed in 1.5 s.

### 3.2 pnpm supply-chain keys

`~/.config/pnpm/config.yaml` (deployed from [`../files/pnpm/config.yaml`](../files/pnpm/config.yaml)):

```yaml
dangerouslyAllowAllBuilds: true
minimumReleaseAge: 0
```

This is the optional "personal dev box" posture described in the Mint document, section 2.16.
`pnpm config get` confirms both keys are live. **Do not also put them in `~/.npmrc`** -- see 4.2.

### 3.3 GNOME proxy schema

```bash
gsettings set org.gnome.system.proxy mode manual
gsettings set org.gnome.system.proxy.http enabled true
```

The host/port entries were already present. Note the schema shape: **only the `http` sub-schema
has an `enabled` key**; `org.gnome.system.proxy.https` and `...socks` do not have one at all.
Setting `org.gnome.system.proxy.https enabled true` fails with a usage error.

### 3.4 `sudo` keeps the proxy variables

`/etc/sudoers.d/proxy` (mode `0440`, `visudo -cf` parsed OK):

```
Defaults env_keep += "http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY"
```

Without it, `sudo`'s `env_reset` strips the proxy variables and `sudo dnf` / `sudo git` fall
back to a direct connection. Verified: `sudo env | grep -i proxy` lists all eight variables,
and `sudo curl https://github.com/` returns 200.

---

### 3.5 Python: uv, and the one Fedora-specific refusal

The system `python3` is 3.14.8 and has **no `pip` module at all**, so the PEP 668 rule from the
Mint document ("never `pip install` into the system Python") is satisfied by construction here.
The side-channel manager is `uv` 0.12.24 from the distribution.

Fedora's `uv` package ships a system config that changes one thing you have to know about:

```toml
# /etc/uv/uv.toml (shipped by the RPM)
python-downloads = "manual"
python-preference = "system"
```

So the obvious first attempt fails:

```text
$ uv run --python 3.12 python -V
error: No interpreter found for Python 3.12 in virtual environments, search path, or managed installations
hint: A managed Python download is available for Python 3.12, but Python downloads are set to
      'manual', use `uv python install 3.12` to install the required version
```

`uv python install 3.12` is still allowed (that is what "manual" means) and installs CPython
3.12.15 under `~/.local/share/uv/python`, linked as `~/.local/bin/python3.12`.

The mirrors, in the two places the shared tooling reads:

| File | Content |
| :--- | :--- |
| `~/.config/uv/uv.toml` | `[[index]] url = "https://pypi.tuna.tsinghua.edu.cn/simple"`, `default = true` |
| `~/.config/uv/.python-version` | `3.12` |
| `~/.config/pip/pip.conf` | `index-url = https://pypi.tuna.tsinghua.edu.cn/simple` |

The `[[index]]` block with `default = true` matters: it covers uv's **own** resolver as well
(`uv add`, `uv sync`, `uv run --with`), which `pip.conf`'s `index-url` does not reach.

Verified afterwards: `uv run python -V` prints `Python 3.12.15` -- the `.python-version` file
wins over `python-preference = "system"`, so the pinned version is what runs even though the
system Python is newer.

### 3.6 Terminal font: Sarasa Term SC, measured rather than assumed

Fedora has no `sarasa` package, so the fonts come from the upstream release archives
(`SarasaTermSC-TTF-*.7z` and `SarasaMonoSC-TTF-*.7z`): extract each archive into its own empty
directory, copy the `.ttf` files into `~/.local/share/fonts/sarasa/`, then `fc-cache -f`.

- **Terminal** -> `Sarasa Term SC` (the "Term" cut, built for terminals)
- **Editor / code** -> `Sarasa Mono SC`

The Mint document insists on a strict 1:2 half-to-full-width ratio. That is measurable rather
than a matter of taste, and it was measured here with `fontTools`:

```text
Sarasa Term SC     upem=1000 A=500 CJK=1000 fullwidth-comma=1000 CJK/A=2.0000
Sarasa Mono SC     upem=1000 A=500 CJK=1000 fullwidth-comma=1000 CJK/A=2.0000
```

A full-width comma is also 1000 units, so punctuation does not break the grid either.

**Konsole** (one of the two terminals on this machine) takes the font from a profile:

- `~/.local/share/konsole/Sarasa.profile` -- the profile itself
- `~/.config/konsolerc` -- one added group, `[Desktop Entry]` / `DefaultProfile=Sarasa.profile`
  (this file also holds Konsole's own settings, so merge the group, do not overwrite the file)

The `Font` property uses Konsole's QFont serialization:

```ini
Font=Sarasa Term SC,11,-1,5,50,0,0,0,0,0
```

which is `family,pointSize,pixelSize,styleHint,weight,style,underline,strikeOut,fixedPitch,rawMode`.

Verifying it took two steps, because Konsole exposes no font property over DBus:

1. **Is the profile in use?** Konsole's own DBus answers it:
   ```bash
   gdbus call --session --dest org.kde.konsole-<pid> --object-path /Sessions/1 \
     --method org.kde.konsole.Session.profile      # -> ('Sarasa',)
   ```
2. **Is the font in the profile actually applied?** A screenshot of the running session, zoomed
   in: the Latin glyphs are **Iosevka** (the `l` with a tail, the serifed `i`, the footed `1`),
   which is Sarasa's Latin face. Noto Sans Mono has none of those marks, so the profile's font
   really is in effect.

**Ghostty** (the other terminal here, 4.7) needs the family named explicitly, because it
resolves `monospace` through fontconfig -- which lands on **Noto Sans Mono**, not on Sarasa:

```bash
fc-match monospace              # -> Noto Sans Mono
fc-match "Sarasa Term SC"       # -> Sarasa Term SC
```

So the shared config original carries the line that makes the ratio hold there as well:

```ini
font-family = Sarasa Term SC
```

in [`../files/ghostty/config`](../files/ghostty/config).

### 3.7 Fontconfig: the Simplified Chinese rules that Fedora needs

The rule file is [`files/fontconfig/64-default-cjk-sc-fedora.conf`](files/fontconfig/64-default-cjk-sc-fedora.conf).
Fedora has no `/etc/fonts/conf.avail`, so the file goes straight into
`/etc/fonts/conf.d/64-default-cjk-sc-fedora.conf` (mode `0644`), then `fc-cache -f`.

The resolution matrix afterwards:

| Query | Result |
| :--- | :--- |
| `fc-match "sans-serif:lang=zh-Hans"` | `Noto Sans CJK SC` (was `Noto Sans`, Latin) |
| `fc-match "sans-serif:lang=zh-Hans-CN"` | `Noto Sans CJK SC` |
| `fc-match "sans-serif:lang=zh"` | `Noto Sans CJK SC` (was Latin) |
| `fc-match "sans-serif:lang=zh-SG"` / `zh-MY` | `Noto Sans CJK SC` |
| `fc-match "serif:lang=zh-Hans"` | `Noto Serif CJK SC` |
| `fc-match "monospace:lang=zh-Hans"` | `Noto Sans Mono CJK SC` |
| `fc-match "sans-serif:lang=zh-Hant"` / `zh-TW` | `Noto Sans CJK TC` |
| `fc-match "sans-serif:lang=zh-HK"` | `Noto Sans CJK HK` |
| `fc-match "sans-serif:lang=zh-JP"` | `Noto Sans CJK JP` |
| `fc-match "sans-serif"` / `serif` / `monospace` | unchanged (`Noto Sans` / `Noto Serif` / `Noto Sans Mono`) |

Traditional Chinese still reaches the Traditional faces, and the Latin defaults are untouched --
the rules only add the missing BCP-47 forms.

### 3.8 Clipboard history: CopyQ with a `Meta+V` hotkey

`dnf install copyq` provides CopyQ 17.0.0. Two settings, neither of which the `copyq config`
command covers:

| What | How |
| :--- | :--- |
| start with the session | `copyq config autostart true` -> writes `~/.config/autostart/com.github.hluk.copyq.desktop` |
| show the history on `Meta+V` | the `[Shortcuts]` group of `~/.config/copyq/copyq.conf` |

The shortcut's key is the **action name**, not a setting name:

```ini
[Shortcuts]
Show/hide main window=Meta+V
```

CopyQ re-serializes the key with KConfig's escaping when it next writes the file, which is how
you can tell the action name was recognized rather than stored as a dead key:

```ini
[Shortcuts]
Show\hide%20main%20window=Meta+V
```

Caveat: on Wayland a global shortcut needs the GlobalShortcuts portal. CopyQ 17 logs
`Failed to create portal global shortcuts session` when the portal is unavailable, so check
`~/.local/share/copyq/*.log` if the hotkey does not fire.

### 3.9 Brave Search CLI (`bx`)

Installed with the repository's own script, which handles the dnf branch, renames the real
binary to `bx-bin` and writes the proxy wrapper:

```bash
sh agent/brave-search/files/setup-bx-linux.sh --skip-key
```

The two key files are deployed separately, because they are **two different plans**:

| File | Plan | How to call it |
| :--- | :--- | :--- |
| `~/.config/brave-search/config.json` | Search (web / news / images / videos / places / context) | `bx web "..." --count 2` |
| `~/.config/brave-search/config-answers.json` | Answers (AI), a separate quota | `bx answers "..." --config ~/.config/brave-search/config-answers.json --no-stream` |

Directory mode `700`, files mode `600`. The wrapper's job is to clear `ALL_PROXY` for the `bx`
process only -- `ureq` cannot parse a SOCKS5 proxy URL and silently falls back to a direct
connection, which fails even though the proxy is up. Verified end to end:

```bash
bx web "Debian" --count 2 | jq -r '.web.results[]? | "[\(.title)] \(.url)"'
bx answers "What is 2+2?" --config ~/.config/brave-search/config-answers.json --no-stream \
  | jq -r '.choices[0].message.content'
```

Always pipe through `jq`; the raw JSON is tens of thousands of tokens per call.

### 3.10 SSH

The key material and the host config are deployed into `~/.ssh` with the usual modes: directory
`700`, `id_ed25519` and `config` `600`, `id_ed25519.pub` and `known_hosts` `644`.

`ssh -G <host>` resolves the config without touching the network, which is the cheap check:

```bash
ssh -G p4 | head          # user / port / hostname come from the config
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

At deploy time the three configured endpoints did not answer (connection timed out) -- the
instances were down. Deployment and reachability are separate questions; SSH is not HTTP and
does not go through `http_proxy`.

### 3.11 The CLI proxy variables are detected, not hardcoded

Deployed from [`files/bashrc.d/50-proxy.sh`](files/bashrc.d/50-proxy.sh) to
`~/.bashrc.d/50-proxy.sh`. The `~/.bashrc` on this machine already had the hook that sources
`~/.bashrc.d/*`, so nothing else had to change.

The probe is copied verbatim from [`../../shell/files/shell_common`](../../shell/files/shell_common)
section 5: the candidate ports are **handshaked** (SOCKS5 `05 01 00` -> `05 00`, HTTP `CONNECT`
-> `200 Connection established`) and only a port that answers as a proxy is exported. If nothing
answers, no proxy variable is exported and the direct connection is used.

This copy also clears the variables it inherits before probing -- see 4.10 for why that step is
not optional on this machine.

Verified in both states, with the client running and with the client stopped:

| State | Exported | Direct path |
| :--- | :--- | :--- |
| client running | `http_proxy`, `https_proxy`, `all_proxy` (+ upper case, `no_proxy`) | -- |
| client stopped | `no_proxy` only | `baidu` / `npm registry` / `github` all 200 |

`no_proxy` is `localhost,127.0.0.1,::1,.local` -- host names written out in full, because a
prefixed wildcard such as `127.*` or `*.local` is **not** special-cased by `urllib` and silently
sends local traffic through the proxy (`tools/python/` section 1).

---

## 4. Pitfalls specific to this machine

### 4.1 `org.gnome.system.proxy.http enabled` does not gate Firefox

**Symptom.** The desktop proxy is configured in three places (4.3) and one of them -- the
GNOME schema -- carries `http enabled = false`. The natural reading is "the HTTP proxy is
switched off, so Firefox goes direct". That reading is wrong.

**Root cause.** libxul reads the GNOME schema for the **mode** and the **host/port of each
scheme**, but it does not consult the `enabled` key. And the key only exists in the `http`
sub-schema anyway -- `https` and `socks` have no such key to read.

**Evidence.** A headless Firefox was pointed at a site that is blocked without a proxy, with
every proxy environment variable stripped, so the only remaining source was the GNOME schema:

| Run | GNOME schema | Result |
| :--- | :--- | :--- |
| A | `mode=manual`, `http enabled=false`, `https host/port` set | page rendered |
| B | `mode=manual`, `http enabled=true` | page rendered |
| C | `mode=none` | **no page**, load timed out |

**Consequence.** When a browser on this machine does not proxy, look at `mode`, `host` and
`port`. Do not chase `enabled`. Setting it to `true` anyway is harmless and keeps the
configuration self-consistent, but it is not a fix.

The probe lives in [`files/ff-proxy-test.sh`](files/ff-proxy-test.sh).

### 4.2 pnpm 12 ignores `~/.npmrc` for the supply-chain keys

**Symptom.** The Mint document, section 2.16, offers two methods: write the keys into
`~/.config/pnpm/config.yaml`, or mirror them into `~/.npmrc` "so npm-format toolchains see
them too". The mirrored version produces a warning on every npm command and does nothing.

**Root cause.** pnpm 12 reads `dangerouslyAllowAllBuilds` and `minimumReleaseAge` from
`~/.config/pnpm/config.yaml` only. Verified by removing that file: `pnpm config get` then
returns `undefined` for both keys even though `~/.npmrc` still contains them. npm 11, which
does read `~/.npmrc`, does not know either key and prints:

```
npm warn Unknown user config "dangerously-allow-all-builds". This will stop working in the
next major version of npm. See `npm help npmrc` for supported config options.
```

**Consequence.** Keep `~/.npmrc` to the registry line. Put the two keys in the pnpm config
file only.

### 4.3 KDE splits the desktop proxy settings in two

**Symptom.** "The terminal does not proxy", "the browser does not proxy", "it works only when
I turn TUN on" -- three different symptoms with one cause: on KDE the desktop proxy lives in
two unrelated stores, and neither one feeds the CLI.

| Consumer | Reads |
| :--- | :--- |
| Firefox | GNOME `org.gnome.system.proxy.*` (libxul has no KDE support) |
| Chromium | `~/.config/kioslaverc` (`ProxyType=1`) |
| Terminal / CLI | nothing -- only the environment variables |
| GUI apps launched by the session | `systemctl --user show-environment` |

FlClash's "system proxy" switch writes `~/.config/kioslaverc` on KDE and does not write the
GNOME schema at all. So the GNOME half has to be configured by hand, and the CLI half needs
`http_proxy` / `https_proxy` / `all_proxy` from a source that detects them (3.11).

**Resolution, and the asymmetry it explains.** The two halves have different owners, so the
split shows up as a *difference between browsers*: with the GNOME schema set and FlClash's
"system proxy" switch **off**, Firefox proxies and Chromium does not -- Chromium reads
`kioslaverc`, and the switch had written `ProxyType=0` there. Turn the switch **on** and let
the client own `kioslaverc`: it writes `ProxyType=1` while it runs and takes it back when it
stops, so Chromium is never pointed at a dead port. The GNOME half stays hand-configured.

Measured with [`files/chrome-proxy-test.sh`](files/chrome-proxy-test.sh), which loads an
exit-IP endpoint in headless Chromium with the proxy environment stripped: the browser's exit
IP is the proxy's while the switch is on, and the direct one while it is off.

TUN mode masks all of this: it takes over routing at the kernel level, so every application
proxies regardless of which store it consults. That is why "turning TUN on fixes it" is not a
diagnosis.

### 4.4 Fedora's Noto CJK families already carry the SC suffix

**Symptom.** The Mint document's fontconfig rule (section 2.14) is written for a system where
the family is the generic `Noto Sans CJK`, whose SC glyphs sit at TTC index 2. Fedora ships
the variable fonts with **separate families per region**: `Noto Sans CJK SC`,
`Noto Serif CJK SC`, `Noto Sans Mono CJK SC`. A rule that matches the string `Noto Sans CJK`
and rewrites it to `Noto Sans CJK SC` therefore has nothing to match, and the TTC-index
reasoning does not apply.

Measured on this machine:

| Query | Result |
| :--- | :--- |
| `fc-match "sans-serif:lang=zh-cn"` | `Noto Sans CJK SC` (correct) |
| `fc-match "serif:lang=zh-cn"` | `Noto Serif CJK SC` (correct) |
| `fc-match "sans-serif:lang=zh-Hans"` | **`Noto Sans` (Latin)** -- the BCP-47 form is not normalized |

So the Simplified-Chinese case is already fine, and the gap that remains is the modern web
form `zh-Hans` (and `zh`), which falls through to the Latin family. `Droid Sans Fallback` is
installed here as well, so the old-glyph risk from the Mint document is present too.

### 4.5 dnf5 and metalink

**What is actually happening.** The Fedora repos are configured with `metalink=`, so dnf
first fetches a metalink document and then downloads from a mirror listed in it. Measured: the
metalink for `fedora-44` answers with CN mirrors (qlu, nyist, tuna, jlu, ustc), and those are
reachable directly.

**Why it still matters.** Two things the metalink buys are not free: one extra round trip
before any package data arrives, and a mirror list that can contain an overseas node. The
third-party repos behave differently: `dl.google.com` was faster direct (0.35 s) than through
the proxy (0.42 s), while the PyCharm COPR was faster direct (2.2 s) than through the proxy
(5.8 s). A re-measurement on 2026-11-21 (median of three `repomd.xml` fetches each) gave
`dl.google.com` 0.28 s direct vs 0.92 s proxied and the PyCharm COPR 1.22 s direct vs 1.65 s
proxied: direct stays faster, but the PyCharm gap is 1.35x, not 2.6x -- treat the numbers above
as one sample.

**Consequence.** Pinning `baseurl` to a CN mirror is a reasonable but optional improvement.
It is not the 16x-class win the Mint document reports for its apt case.

### 4.6 The four-layer shell split arrived here on 2026-10-25

The Mint and WSL machines share a four-layer shell split (`~/.zshenv`, `~/.shell_wslfn`,
`~/.shell_common`, `~/.zshrc` / `~/.bashrc`) with `~/.shell_common` as the single source of
truth for the environment. This machine had none of it: bash was the only shell installed, and
the four files were absent.

**As of 2026-10-25 all four are here**, copied by hand from the repository's `shell/files/`, and
the login shell is zsh. [`../../linux-bootstrap/`](../../linux-bootstrap/) stage 7 now automates
the same copy -- but unlike the hand deployment it replaces `~/.bashrc` too (after a backup), so
the table below describes this machine, not what the script would do.

| | before | after |
| :--- | :--- | :--- |
| shells | bash only | zsh 5.9; `chsh` to `/usr/bin/zsh`, and the session snapshot updated |
| `~/.zshenv` `~/.shell_wslfn` `~/.shell_common` `~/.zshrc` | absent | deployed from the repo originals |
| `~/.bashrc` | the local one | **untouched** -- bash keeps its own rc file and its own `~/.bashrc.d` hook |

Three details of the deployment, each of them easy to get wrong:

1. **`chsh` alone changes nothing for a running desktop.** It rewrites `/etc/passwd`, but a
   terminal started from the panel inherits the session environment, and that snapshot was
   taken before the change. `systemctl --user set-environment SHELL=/usr/bin/zsh` and
   `dbus-update-activation-environment --systemd SHELL=...` are what make the already running
   session use the new shell -- the same mechanism as 4.10, with the same "the invisible
   source wins" failure.
2. **The shared file was written for an X11 desktop, and the variables were not the problem.**
   Its section 7 exports `GTK_IM_MODULE` and `QT_IM_MODULE` unconditionally. Following Fcitx5's
   startup advice, the deployed copy dropped them on a Wayland session; it did not make the
   browsers type. Two later verifications found the real cause: Fcitx5 was not KWin's input
   method. With Fcitx 5 selected as the virtual keyboard, Chrome and Firefox typed with or
   without the variables -- see [`../wayland-fcitx5-rime.md`](../wayland-fcitx5-rime.md), root
   cause 4. The session snapshot was not cleaned either: `systemctl --user show-environment`
   still held both variables. The repository original keeps exporting them on every session
   type.
3. **The deployed `~/.shell_common` was a draft of the repository original plus one local
   change.** The draft dropped the toolkit IM variables on Wayland (item 2). The local change
   wraps `VISUAL="code --wait"` in a `command -v code` check with a fallback, because VS Code
   was not installed at deploy time (12:13) and a `$VISUAL` that points at a missing command
   breaks `git commit` without `-m`. VS Code was installed 25 minutes later (`rpm` install time
   12:38), so the wrapper now resolves to `code --wait` and changes nothing. The final
   repository original differs from the deployed copy in more than that: it keeps the IM
   variables and clears stale proxy variables before its probe (4.10).

The bash side keeps its own history, and it is still the weaker half:

- **The proxy used to be hardcoded.** `~/.bashrc` exported `<proxy-port>` literally. If the
  proxy client is not running, every CLI request points at a dead port and fails. The shared
  `~/.shell_common` instead probes candidate ports with a protocol handshake and exports
  nothing when no port answers. **This half is fixed** on this machine: the probe was
  deployed as `~/.bashrc.d/50-proxy.sh` (3.11) and the hardcoded exports were removed.
- **The rc file was polluted by installers.** `~/.bashrc` still ends with the `pnpm setup`
  block and the nvm block appended by their installers -- the same symptom as the Mint
  document's section 2.4. It is untouched by the four-layer deployment on purpose.

Note that `~/.bashrc` already sources `~/.bashrc.d/*` if that directory exists, which is the
natural landing spot for a bash-only port of the shared environment layer -- and it stays
that, because bash still reads its own rc file rather than the shared one.

---

### 4.7 Ghostty on Fedora comes from a COPR, not from the official repos

**Symptom.** The Mint baseline ends with "use Ghostty", and the obvious check finds nothing:
`dnf list --available ghostty` returns no match, because the Fedora 44 repositories do not
carry it. Read too quickly, that looks like "Ghostty cannot be installed on Fedora".

**Root cause.** The package exists, but in a third-party COPR rather than in Fedora's own
repos:

```bash
dnf copr enable scottames/ghostty
dnf install ghostty
```

which lands `ghostty-1.3.1-4.fc44.x86_64` (vendor: `Fedora Copr - user scottames`).

**Two dead ends worth recording, because both mislead in the same direction.**

1. **Flathub does not carry Ghostty at all -- that is not the same as being filtered.**
   `flatpak search ghostty` and `flatpak update --appstream` time out on this machine, and the
   Flathub API answers `{"detail":"App not found"}` for `com.mitchellh.ghostty`. The tempting
   inference is that the *filtered* remote (`flatpak remotes` -> `flathub system,filtered`)
   is hiding it. It is not: `/usr/share/flatpak/fedora-flathub.filter` contains a single line,
   `# Unfiltered`, so the remote filters nothing. The real reason is simpler -- Ghostty has
   never been published on Flathub. The Flathub appstream carries no `com.mitchellh.ghostty`
   component at all, and the API's "App not found" is that absence, reported literally.
2. **Upstream ships no Linux binary in its releases.** The v1.3.1 assets are macOS zips, the
   source tarball and the wasm artifacts; probing `ghostty-1.3.1.linux-x86_64.tar.xz` and
   friends returns 404 for each. Upstream publishes only macOS binaries and leaves every
   other platform to its packagers -- the COPR above is one of them.

**A third route that does exist.** Upstream keeps a Flatpak manifest in its repository
(`flatpak/com.mitchellh.ghostty.yml`), so `flatpak-builder` can build it from source. Note the
repository moved to the `ghostty-org` organisation: the `mitchellh/ghostty` paths now 404,
including for the manifest.

**A side finding worth keeping.** While probing this, the GitHub API behaved oddly:
`/releases/latest` returned 404 and `/releases?per_page=30` returned a single `tip` prerelease,
while the **releases Atom feed** listed the real tags (`v1.3.1`, `v1.3.0`, `v1.2.3`, ...). When
an API for "the latest release" looks wrong, check the feed before concluding the project has
no releases.

**Consequence.** Ghostty 1.3.1 is installed on this machine and is a working second terminal
alongside Konsole. The Mint note's actual point -- the strict 1:2 terminal font -- holds for it
too, but only if the font is set explicitly: Ghostty resolves `monospace` through fontconfig,
which lands on **Noto Sans Mono**, not on Sarasa. The config original in
[`../files/ghostty/config`](../files/ghostty/config) therefore needs a `font-family` line to
carry the same guarantee the Konsole profile gives (3.6).

**The Mint install command does not apply here.** `linux-desktop/README.md` section 2.x installs
Ghostty with `mkasberg/ghostty-ubuntu`'s `install.sh`, which fetches a **.deb**; that path is
Ubuntu/Mint only. On Fedora the COPR route above is the one that applies.

**And the Nemo Action has a Dolphin equivalent already installed.** The Mint baseline's
`files/nemo/actions/*.nemo_action` files are Nemo-specific and do nothing under Dolphin, but
the COPR package ships its own Dolphin service menu at
`/usr/share/kio/servicemenus/com.mitchellh.ghostty.desktop` -- "Open Ghostty Here", running
`ghostty --working-directory=%F`. Copying the Nemo files over is unnecessary.

### 4.8 A KDE custom shortcut cannot be written blind

**Symptom.** The Mint note binds `Ctrl+Shift+Esc` to `gnome-system-monitor`. On KDE the
binary is `plasma-systemmonitor` (there is no `systemmonitor` on PATH), and binding it through
`~/.config/kglobalshortcutrc` by hand does not work.

**Root cause.** The custom-action layout of `kglobalshortcutrc` is not discoverable from the
command line in this build:

- three candidate group layouts were tried -- `[KDE Action for <cmd>]`, `[<cmd>]`, and
  `[<cmd>]` with indexed keys -- and none of them registered a component in the kglobalaccel
  daemon (`/component/plasma-systemmonitor` stays "not a valid object path", even after
  `systemctl --user restart plasma-kglobalaccel.service`);
- the daemon's `org.kde.kglobalaccel.Component` interface in KDE 6.7 has no `registerShortcut`
  method, so it cannot be done over DBus either;
- the string `KDE Action for`, which older KDE versions used as the group prefix, does not
  occur anywhere in the installed KDE 6.7 libraries -- so that older layout is not what this
  version writes.

**Consequence.** The hotkey has to be set through the GUI: **System Settings -> Keyboard ->
Shortcuts -> Custom Shortcuts -> Add**, with command `plasma-systemmonitor`, name "System
Monitor", shortcut `Ctrl+Shift+Escape`. Until then,
[`files/desktop/system-monitor.desktop`](files/desktop/system-monitor.desktop) gives one click
from the desktop.

The general lesson: a config file that a daemon reads but that has no public API to write is
not something to blind-write. The file format has to come from the writer, and if the writer is
a GUI, the GUI is the tool.

### 4.9 Fedora's `uv` refuses to download a Python until told to

**Symptom.** `uv run --python 3.12 ...` fails with

```text
error: No interpreter found for Python 3.12 in virtual environments, search path, or managed installations
hint: A managed Python download is available for Python 3.12, but Python downloads are set to
      'manual', use `uv python install 3.12` to install the required version
```

**Root cause.** The RPM-packaged `uv` ships `/etc/uv/uv.toml` with `python-downloads = "manual"`
and `python-preference = "system"`. The first setting blocks the implicit download; the second
makes uv prefer a system interpreter whenever no version is pinned.

**Consequence.** Run `uv python install 3.12` once (that is exactly what "manual" allows), and
pin the version in `~/.config/uv/.python-version` -- the pin wins over `python-preference`, so
`uv run` then uses 3.12.15 even though the system Python is newer. See 3.5.

### 4.10 The session environment keeps proxy variables after the client stops

**Symptom.** The terminal has no network *again*, even though the rc file no longer hardcodes
a port -- and `curl` says

```text
curl: (7) Failed to connect to <host> port 443 via 127.0.0.1 after 0 ms: Could not connect to server
```

i.e. it is trying to use a proxy that is not listening.

**Root cause.** The desktop session keeps its own snapshot of the environment.
`systemctl --user show-environment` lists the proxy variables the client injected while it was
running, and a terminal started from the panel inherits that snapshot. So a shell gets proxy
variables even when its own rc file never set them -- and when the client stops, the snapshot is
not refreshed, so the variables keep pointing at the port that is now closed.

Measured here: the session environment carried all eight variables with the **old**
`socks5://` scheme while the rc file used `socks5h://`, and they were still there after the
client was stopped.

**Consequence.** Two sources of the same variables, and the invisible one wins -- it is inherited
*before* the rc file runs. Fixing the rc file alone is not enough; the variables have to be
cleared where they enter the process.

**Fix.** The deployed script clears them before it probes (3.11). The shared
`shell/files/shell_common` -- what the zsh login shell sources once the four-layer split is
deployed (4.6) -- did not: in an `unshare -rn` namespace with nothing listening, stale
`HTTPS_PROXY` / `ALL_PROXY` survived it in bash and zsh alike. Its section 5 now clears them the
same way. The session snapshot can be cleaned once with:

```bash
systemctl --user unset-environment HTTP_PROXY HTTPS_PROXY ALL_PROXY \
    http_proxy https_proxy all_proxy NO_PROXY no_proxy
```

---

## 5. Deployable originals

| File | Deploy to | Notes |
| :--- | :--- | :--- |
| [`files/npmrc`](files/npmrc) | `~/.npmrc` | registry only -- see 4.2 for what must **not** go here |
| [`files/sudoers/proxy`](files/sudoers/proxy) | `/etc/sudoers.d/proxy` | mode `0440`; validate with `sudo visudo -cf` |
| [`files/ff-proxy-test.sh`](files/ff-proxy-test.sh) | probe, not deployed | headless Firefox load probe with the proxy environment stripped |
| [`files/chrome-proxy-test.sh`](files/chrome-proxy-test.sh) | probe, not deployed | headless Chromium exit-IP probe with the proxy environment stripped; PROXIED / DIRECT / BROKEN |
| [`files/fontconfig/64-default-cjk-sc-fedora.conf`](files/fontconfig/64-default-cjk-sc-fedora.conf) | `/etc/fonts/conf.d/64-default-cjk-sc-fedora.conf` | Fedora has no `/etc/fonts/conf.avail`; mode `0644`, then `fc-cache -f` |
| [`files/konsole/Sarasa.profile`](files/konsole/Sarasa.profile) | `~/.local/share/konsole/Sarasa.profile` | the terminal font profile; make it default with `DefaultProfile=Sarasa.profile` in `~/.config/konsolerc`. It pins `Command=/usr/bin/zsh`, so a new Konsole starts zsh whatever `$SHELL` says |
| [`files/bashrc.d/50-proxy.sh`](files/bashrc.d/50-proxy.sh) | `~/.bashrc.d/50-proxy.sh` | the CLI proxy variables, detected rather than hardcoded; the probe is copied from `shell/files/shell_common` section 5 -- see 3.11 |
| [`files/desktop/system-monitor.desktop`](files/desktop/system-monitor.desktop) | `~/Desktop/system-monitor.desktop` | one-click launch of the system monitor |

The pnpm config is shared with the Mint machine and lives at
[`../files/pnpm/config.yaml`](../files/pnpm/config.yaml). The four-layer shell files are shared
with the Mint and WSL machines as well, and live at
[`../../shell/files/`](../../shell/files/); 4.6 records which of them are deployed here and how
the deployed copy differs.

---

## 6. Package availability on this distribution

Checked with `dnf list --available`:

| Package | In the Fedora repos | Note |
| :--- | :--- | :--- |
| `btop` | yes | TUI system monitor |
| `copyq` | yes | clipboard history with a `Meta+V` hotkey |
| `fd-find` | yes | provides the `fd` command |
| `zsh` | yes | the login shell here; the four-layer split is deployed -- see 4.6 |
| `uv` | yes | Python side-channel manager |
| `fsearch` | **no** | Everything clone; use `plocate` + Dolphin's index |
| Ghostty | **no** | not in the Fedora repos, and no Flatpak or upstream Linux binary either -- see 4.7 |

Installed on this machine from the list above: `btop`, `copyq`, `fd-find`, `zsh`, `uv`.

