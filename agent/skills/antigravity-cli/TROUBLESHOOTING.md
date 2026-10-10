# Antigravity CLI (agy) — Troubleshooting

> Usage: see [SKILL.md](SKILL.md). This doc covers issues you may hit.

## agy-run.sh diagnostics

Every run ends with an `agy-run: exit=... log=...` line on stderr; the full `stream-json`
trace is at that `log=` path (`~/.local/state/agy-run/`, newest 50 kept).

| stderr | Meaning | Fix |
|---|---|---|
| `BLOCKED write_to_file(...) -- needs a write grant` | target is outside every `write_file(...)` rule | user decides: `! bash .../agy-run.sh grant write <dir>` |
| `BLOCKED ... -- a deny rule in ... blocks this` | a `deny` rule matched (e.g. `write_file(/tmp)`) | intended; write somewhere else |
| `BLOCKED run_command(...) -- command not allowlisted` | no `command(prefix)` rule matches | user decides: `grant command '<prefix>'` |
| `BLOCKED run_command(...) -- command is allowlisted but writes outside a granted dir` | the command word is allowed, its redirect target is not | grant write for the target dir, or change the command |
| `BLOCKED view_file(...) -- outside the workspace` | agy tried to read a file outside the workspace | pass it with `--image`, or pick a `--dir` that contains it |
| `sandbox: <cmd> -> Read-only file system` | the command wrote outside what the sandbox mounts writable | grant write for the workspace, or keep output in the workspace |
| `sandbox: <cmd> -> Could not resolve host` / `Failed to connect to 127.0.0.1` | the sandbox has no network, not even the local proxy | do network work outside agy |
| `agy/API error: RESOURCE_EXHAUSTED` (exit 3) | quota spent | `agy-run.sh quota`; switch pool with `--model` (Gemini vs Claude/GPT), or wait for the reset |
| `... is not valid JSON -- agy would silently deny every tool` (exit 1) | settings.json does not parse | fix the JSON (double backslashes, no trailing commas) |
| `empty response` / `may be incomplete` (exit 5) | agy returned nothing, or hit `--print-timeout` | retry once; raise `--timeout` |
| `killed after Ns (hard timeout)` (exit 5) | agy hung past `--timeout` + 120 s | check proxy and login (below) |

## Raw agy behavior the wrapper works around (agy 1.2.11)

- **A denial ends the turn silently**: a tool with no allow rule is soft-denied (headless
  cannot prompt), the turn stops, `agy -p` exits **0** with an empty response. Only
  `result.denied_actions` in `stream-json` and a `jetski: no output produced ...` stderr
  line show it.
- **A deny rule behaves differently**: the tool call fails with
  `Matches user-configured deny rule`, the model sees the error and keeps answering;
  `denied_actions` stays `null`. agy-run catches it from the tool step's `ERROR` state.
- **`command(...)` rules are token-prefix matches** (`command(ls)` allows `ls -la /etc`);
  without `--sandbox` an allowed `touch /anywhere` really writes there. Redirect targets
  (`> file`) are checked against `write_file` rules.
- **`--sandbox` does not auto-approve anything** in headless mode: the built-in list of
  sandbox-safe commands (`cat`, `ls`, `cp`, ...) still needs `command(...)` rules.
- **`"enableTerminalSandbox": true`** in settings.json is equivalent to `--sandbox` for every
  session, interactive ones included. `"sandboxAllowNetwork": true` has no effect.
- **`--print-timeout` defaults to 0** (wait until the turn ends); agy-run passes 10m.
- **Workspace = cwd**: agy reads its cwd without any `read_file` rule. The old template's
  `read_file(*)` is unnecessary and lets agy read anything.

## Network & proxy (WSL must go through the proxy)

- **Direct access to Google from WSL is blocked**: verified `dial tcp 172.217.118.4:443: i/o timeout`, flaky. agy must use the proxy.
- agy (Go) honors the `HTTPS_PROXY`/`HTTP_PROXY` env vars; setting them routes traffic over HTTP CONNECT. Already configured in `.bashrc`:
  ```bash
  export HTTPS_PROXY=http://127.0.0.1:<proxy-port>
  export HTTP_PROXY=http://127.0.0.1:<proxy-port>
  export ALL_PROXY=socks5h://127.0.0.1:<proxy-port>   # for curl/git and other tools that read ALL_PROXY
  ```
- **`ALL_PROXY` has no effect on agy**: Go only reads `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`; `ALL_PROXY` only applies to curl/git etc.
- **Use `socks5h://` for SOCKS5**: WSL's local DNS is poisoned for Google domains (`www.google.com` → fake address `2001::1`); `socks5://` (local DNS) fails against the fake address; `socks5h://` (remote DNS) resolves via Clash and works.
- **Don't wrap agy with antissh.sh's graftcp**: agy honors `HTTP_PROXY`, so just use the env vars — no graftcp needed.
- The proxy serves agy itself only. Shell commands inside the sandbox have no network at all.

## Authentication

| Symptom | Fix |
|---|---|
| `Please sign in to view available models` / stuck at auth / exit 3 `UNAUTHENTICATED` | Token expired or refresh failed. **The user runs an interactive `agy` once** to re-authenticate; headless calls work again afterwards |
| Long silence (no output, `i/o timeout`) | Not going through the proxy. Confirm `HTTPS_PROXY`/`HTTP_PROXY` are set |

Auth mechanism: token stored at `~/.gemini/antigravity-cli/antigravity-oauth-token`, auto-refreshed; once expired and headless can't refresh on its own, only an interactive `agy` can refresh it manually. The sandbox hides this directory from shell commands.

## Images

- agy reads an image only when its path is **in the prompt text**; a positional argument is silently dropped. `--image` does this for you.
- Use WSL paths; Windows paths (`C:\...`) cannot be read.
- The model opens the image with `view_file`; no shell command and no `read_file` rule are needed once the file is in the workspace.

## Misc

| Symptom | Fix |
|---|---|
| `Eligibility check failed: ... EOF` | Transient proxy/endpoint jitter — **just retry** |
| settings.json changed key order after a run | agy rewrites the file on start; content is kept |

## Bulk read-only review jobs (Windows host, agy 1.2.14, 2026-10-02)

Seen while having agy read 88 Markdown files and report which passages sound machine-written.

- **agy cannot find files for you without a `command` permission.** Listing, globbing and
  searching go through a shell command; headless soft-denies it and `agy -p` exits **0** with
  an empty reply and a `jetski: no output produced` line on stderr. Give it the file list in the
  prompt (absolute paths) and tell it to use only its file-reading tool (`view_file`, covered by
  `read_file`). Do not reach for `--dangerously-skip-permissions` on a read-only job.
- **Do not put 70+ files in one conversation.** After about 150 steps (73 files read) agy
  compacts its context; every later `agent_response` then had `output_tokens: 0`, each followed by
  an `error_message`, and it kept retrying without ever printing a reply. All findings from the
  reading phase were lost. Batches of 16-23 files finished normally.
- **`-p -` (prompt on stdin) was unreliable**: one run answered with a greeting as if the prompt
  were empty, another tried to run a command. `agy -p "$(cat prompt.md)"` worked (a 6 KB prompt
  is far below the Windows command-line limit of about 32 KB).
- **`error: Error: empty prompt`** means the prompt file was empty or missing. Check it before
  launching: `wc -c`, `head`, `tail`, and count the path lines.
- **Build Windows paths in code, not in shell text.** Backslashes in a quoted heredoc, `sed` or
  `awk` replacement got collapsed (`D:\SQLData\vibe-pitfalls-notes-private\x` came out as
  `D:SQLDataibe-pitfalls-notes-private\x`), so the agent was handed paths that do not exist.
  Write the prompt with a small script that joins the parts with `chr(92)` or `pathlib`, then
  verify that the first and last paths exist.
- **`--output-format stream-json` shows progress, not the reply, while the job runs.** The events
  carry the tool name, the path (`AbsolutePath`) and token usage. Count `view_file` steps in state
  `DONE` to see how many files were read. Redirect stdout to a file and read it with a short script
  while the job is still running.
- **A growing output file is not a finished one.** In text mode the file grew over several
  minutes (1.3 KB, 4.7 KB, 8.9 KB). Decide from the process (`tasklist`) and the exit status, not
  from the size. Once a report contained the same answer three times, each a little different:
  use the last one.
- **Trust the quotes, not the line numbers.** Quoted text was found verbatim in the files every
  time (46 of 46 checked with `grep -F`), but several `path:line` references pointed at the wrong
  line. Re-locate with the quote.
- **Parallel runs work.** Two `agy -p` processes started side by side without interfering.
- **Killing the parent loop does not stop agy.** `taskkill` on the `sh` running a batch loop
  leaves the current `agy.exe` running; useful for letting one batch finish while taking over the
  rest by hand.

- **`INTERNAL (code 500)` with exit 3 can be tied to the input.** One 14-file batch failed twice
  with `retryable: false`; splitting it in halves found one half that always failed and one that
  succeeded, and a further split narrowed it to two ordinary Markdown files (no odd bytes, longest
  line about 1,000 characters). The cause was never found, so do not assume it is size or content:
  bisect the batch, skip the file, and review it by hand.
- **If even `hi` hangs on `Loading...` in both the IDE and the CLI, suspect the service.** Later in
  the same session every request stalled, interactive ones included; nothing on the machine had changed.
  Stop launching jobs and retry later.
- **Driving the interactive UI from Windows works through WSL's tmux.** `tmux new-session -d -s agy
  -c <dir> agy`, `tmux send-keys -t agy -l "<one-line prompt>"` then `Enter`, and
  `tmux capture-pane -p` returned the trust prompt, the main screen and the working spinner. Each new
  workspace first shows "Do you trust the contents of this project?"; Enter accepts it, so decide
  before sending. `tmux kill-session` ended with "server exited unexpectedly" once; harmless.

## Appendix: verified facts on this machine (2026-09-26)

- `agy` at `$HOME/.local/bin/agy`, v1.2.11, native Linux ELF.
- Models (`agy models`): `gemini-3.8-flash-high/medium/low` (default `-high`), `gemini-3.7-flash-*`, `gemini-3.6-flash-*`, `gemini-3.1-pro-high/low`, `claude-sonnet-4-6`, `claude-opus-4-6-thinking`, `gpt-oss-120b-medium`.
- Quota (`agy-run.sh quota`): weekly and five-hour limits, separately for Gemini models and for Claude/GPT models.
- Sandbox mounts, from `/proc/self/mountinfo` inside a command: `/` is an empty read-only tmpfs; `/usr`, `/etc`, `/var`, `~/.config`, `~/.gitconfig` read-only; the workspace writable only with a write grant; `~/.cache`, `~/.npm`, `~/.nvm`, agy's scratch dir `brain/<id>` and a private `/tmp` writable; the rest of the workspace's parent, `~/.ssh`, `~/.gemini/antigravity-cli` and `~/.gemini/config` covered by empty `deny` mounts. seccomp filter, no capabilities, `NoNewPrivs=1`, own PID namespace, network namespace without DNS.

中文版见 [TROUBLESHOOTING.zh.md](TROUBLESHOOTING.zh.md)。
