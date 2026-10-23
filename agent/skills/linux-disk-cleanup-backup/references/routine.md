# Routine housekeeping catalog

Everything here is **regenerable**. Deleting it costs the user nothing but a
re-download. The rhythm is measure, clean, report -- no per-item sign-off.

If an item is not on this list, it is not routine work. It belongs to the archival
catalog or to a conversation with the user.

---

## 1. System-level caches and logs

These live outside the home directory and are the most commonly missed. On a WSL
Ubuntu 24.04 that had been in daily use they measured:

| Path | Typical size | Command | Notes |
| :--- | :--- | :--- | :--- |
| `/var/cache/apt/archives` | 400-500 MiB | `sudo apt clean` | Downloaded `.deb` files. Nothing depends on them |
| `/var/lib/apt/lists` | 100-250 MiB | `sudo rm -rf /var/lib/apt/lists/*` | Package indexes; `apt update` rebuilds them. Do this only if `apt update` is known to work afterwards |
| `/var/lib/snapd/cache` | 200-450 MiB | `sudo sh -c 'rm -f /var/lib/snapd/cache/*'` | Downloaded `.snap` files. See the glob trap in rule 7 |
| `/var/log/journal` | 100-450 MiB | `sudo journalctl --vacuum-size=50M` | Systemd journal. Keep the current boot's entries if you are debugging |

`apt clean` and the journal vacuum are the two safest wins available and they are
worth running on every routine pass.

### The same cache exists in two places

Read this before concluding a cache is clean. On a Fedora 44 WSL host the dnf cache
measured **208 MiB at `/var/cache/libdnf5`** while `~/.cache/libdnf5` held a second
**217 MiB**. Clearing only the home-directory copy left half of it on disk, and the
surviving half looked like the whole story.

The home directory and the system directory hold *different* caches for most
managers, and on a machine whose home has just been cleaned the remaining half is
invisible in every `du ~` you would naturally run. Measure both:

```bash
du -sh ~/.cache/<manager> /var/cache/<manager> 2>/dev/null
```

### Non-apt package managers

`apt` is not the only one, and the table above is Debian-specific. Identify the
manager first (`command -v dnf apt-get zypper pacman apk`), then use **its own
cleanup command** rather than `rm -rf` -- `dnf clean all` also drops stale metadata in
a consistent state that a raw delete leaves behind:

| Manager | Path | Command | Notes |
| :--- | :--- | :--- | :--- |
| dnf / dnf5 | `/var/cache/libdnf5` | `sudo dnf clean all` | Fedora 41+. On a measured host: 208 MiB |
| dnf (dnf4) | `/var/cache/dnf` | `sudo dnf clean all` | Older Fedora. **208 MiB here, and `/var/cache/libdnf5` may not exist at all** |
| zypper | `/var/cache/zypp` | `sudo zypper clean --all` | openSUSE |
| pacman | `/var/cache/pacman/pkg` | `sudo paccache -rk2` | Keep the last 2 versions; `-r` with no number deletes all |
| apk | `/var/cache/apk` | `sudo apk cache clean` | Alpine |

**Fedora 44 measured, for reference:** `/var/cache/libdnf5` 208 MiB, journal 509 MiB,
887 installed packages, one kernel, no `/opt` applications and no `node_modules` --
an Archival pass on that host reclaimed 620 MiB from `/var` and nothing else. Compare
that with the Ubuntu host in the table above before assuming a package manager is the
biggest lever on the machine in front of you.

### Retired package-manager revisions

Every system that upgrades keeps the previous version of everything:

```bash
snap list --all | awk 'NR>1 && $6 ~ /^disabled/ {print $1, $3}'
sudo snap remove <name> --revision=<rev>
```

`snap list --all` prints `Name Version Rev Tracking Publisher Notes`, so the
revision is the **third** column. `$2` is the version string, and
`snap remove --revision=` rejects a version -- so `$2` there turns a working
cleanup into an error that names a revision that does not exist.

Three retired revisions on a measured machine were 67 + 64 + 51 = **182 MiB**.

**Hard links.** The snap download cache and the installed `.snap` file are the same
bytes with two names (`ls` shows link count 2). Removing the cache entry frees
nothing until the installed copy goes too. Re-measure with `du` after each step
instead of trusting the file listing.

---

## 2. Home-directory caches

| Path | What | Note |
| :--- | :--- | :--- |
| `~/.cache/uv` | uv's wheel and source cache | The largest single item on a Python-heavy machine -- 7 GB on the measured one |
| `~/.cache/pnpm` | pnpm's metadata cache | |
| `~/.local/share/pnpm/store` | pnpm's content-addressable store | **6.5 GB** on the measured machine. Regenerable; `pnpm install` re-fetches |
| `~/.cache/pip` | pip's wheel cache | |
| `~/.cache/node`, `~/.cache/node-gyp` | Node's own caches | |
| `~/.npm/_cacache` | npm's cache | |
| `~/.npm/_npx` | npx's per-package installs | **Check for running processes first** -- an MCP server launched through `npx` runs from here |
| `~/.cache/huggingface` | model hub cache | Regenerable, but the download is large; ask before clearing |
| `~/.go/pkg` | Go module cache | Read-only files, so `chmod -R u+w` first |

### Language-manager runtimes

| Path | What | Note |
| :--- | :--- | :--- |
| `~/.local/share/uv/python/*` | uv-managed interpreters | **Keep the version the project pins.** A pinned version is a dependency, not redundancy |
| `~/.nvm/versions/*` | Node versions | Check `.zshrc` / `.bashrc` for the `nvm` sourcing line first |
| `~/.pyenv/versions/*` | Python versions | Same |

Deleting the *other* versions is usually right. Deleting the pinned one breaks the
project and, if the agent is currently running under it, breaks the session.

---

## 3. Build artifacts and virtual environments

```bash
find ~ -maxdepth 6 -type d -name '.venv' -exec du -sh {} \;
find ~ -maxdepth 6 -type d -name '__pycache__' | wc -l
```

Both are unconditionally regenerable. `.venv` in particular is often gigabytes and is
always reproducible from a lockfile -- but check that a lockfile exists before
deleting the environment that produced it.

Other routine items:

- `~/.cache/ms-playwright` -- downloaded browser binaries; re-downloadable
- `~/.cache/ms-playwright-go` -- same
- `target/` inside Rust projects -- `cargo clean`
- `node_modules/` inside projects -- `npm ci`; check for a lockfile first
- `__pycache__`, `*.pyc`, `*.pyo` -- always safe

---

## 4. Stale application state

| Path | What | Note |
| :--- | :--- | :--- |
| `~/.vscode-server/extensions` | Remote-server extensions | Re-downloaded on the next remote connection. **1.9 GB** on the measured machine |
| `~/.vscode-server/data/logs` | Server logs | |
| `~/.vscode-server/data/agent-host/sdk-cache` | Agent host cache | |
| `~/.oh-my-zsh` | Shell framework | **Check `.zshrc` first.** It usually contains `source $ZSH/oh-my-zsh.sh`; deleting the directory while the line stays breaks every new shell |
| `~/.ipython`, `~/.jupyter` | History and kernels | |
| `~/.dotnet`, `~/.conda` | Toolchain residue | |

### Extensions and plugins

`~/.vscode-server/extensions` and similar directories re-download on the next
connection, so they are routine. The extension's *configuration* and workspace state
are not -- keep `settings.json` and the `globalStorage` directory.

---

## 5. AI-tool session state

Agent tools accumulate conversation databases and logs faster than anything else on
a machine, and they are pure session garbage.

| Path | What | Note |
| :--- | :--- | :--- |
| `~/.codex/logs_*.sqlite` | Codex log database | 150 MiB on the measured machine |
| `~/.codex/sessions/` | Codex rollout JSONL | 125 MiB |
| `~/.codex/thread_history_*.sqlite` | Thread history | |
| `~/.codex/cache/` | Model and file cache | |
| `~/.openclaw/npm/` | OpenClaw's project dependency trees | 336 MiB on the measured machine; regenerable by reinstalling |
| `~/.openclaw/cache/` | Asset cache | |
| `~/.codebuddy/plugins/marketplaces/` | Plugin marketplace clones | Re-clonable from their own remotes |
| `~/.codebuddy/traces/`, `~/.codebuddy/logs/` | Traces and logs | |

**Keep** the configuration, credentials, skills, and plugins a user installed. Only
the logs, the session databases, and the re-clonable caches go.

**Do not touch `~/.claude/projects/`, `~/.claude/skills/`, `~/.claude/plugins/`, or
the `memory/` directory** -- that is the user's own work product, and in some setups it
is the only copy.

### Antigravity and Gemini CLI

```bash
du -sh ~/.gemini/*                       # look at the layers, not the total
du -sh ~/.gemini/antigravity-cli/*
```

Inside `antigravity-cli/`:

- `conversations/*.db` -- SQLite conversation stores. **The recorded media can be
  embedded as blobs in the database**, so the video exists in the database and not
  only in `.tempmediaStorage`. On the measured machine the largest `.db` was 75 MiB
  while its matching `.tempmediaStorage` directory was empty -- the two are not
  always 1:1 duplicates. Deleting the `.db` therefore removes the only copy of the
  recording. Ask before deleting.
- `brain/<uuid>/*.md` -- generated reports. Small, and they are the written output
  of the sessions. **Keep them** unless the user says otherwise.
- `brain/<uuid>/.user_uploaded/` -- the user's own uploaded files. Keep.
- `brain/<uuid>/.tempmediaStorage/`, `.system_generated/`, `scratch/` -- recorded
  media and scratch state. Removable, but check the `.md` files first: some reports
  live inside `.system_generated` and go with it.
- `bin/`, `~/.gemini/bin/` -- the CLI binaries. Re-downloadable.
- `~/.gemini/tmp/` -- scratch. Removable.

---

## 6. What is never routine

Do not delete these in routine mode, even when they are large:

- SSH keys and their configuration -- losing them is unrecoverable
- `~/.config/` as a whole -- it is the user's application configuration
- Browser or editor profiles
- Any file the user has written and not pushed
- A virtual environment, interpreter, or toolchain **currently in use**
- Anything in a directory whose only copy is this machine

For these, the archival catalog and a question to the user are the answer.
