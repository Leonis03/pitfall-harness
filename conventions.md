# Conventions

*English · [中文](conventions.zh.md) · back to [README](README.md)*

- **Philosophy: The Agent as System Operator & Closed-Loop Distillation**:
  Treat the Agent as a real-world system operator. Humans specify objectives in natural language, prompting the Agent to conduct vibe-driven exploration in live OS and development environments. Once an empirical solution works reliably, the exploration outcomes are distilled into verifiable, reproducible, and deployable Markdown, configurations, automation scripts, and Agent Skills, ensuring future agents never have to re-explore from scratch.

  ```text
  Natural language goal → Agent directly operates live system & executes commands → Observe symptoms → Pinpoint & empirically prove root causes → Working config/procedure → Solidify into configs, scripts, READMEs, skills, & verification checklists → Future agents reproduce via deterministic knowledge.

  One-off Agent Exploration
              ↓
          Experience
              ↓
     Structured Conclusions
        ↙     ↓      ↘
    Config  README   Skill
        ↘     ↓      ↙
    Executable Specifications
              ↓
      Future Agent Reuse
  ```
- **These surfaces are pure ASCII only**: directory and file names; system and tool config
  files (**including their comments**, which are written in English); every skill's YAML
  frontmatter (especially `description`, which loads every session and participates in
  trigger matching). Non-ASCII in the wrong place fails **silently and far
  from its cause** -- across the WSL/Windows boundary, in archives, in shell and harness
  parsing.
- **Markdown filenames are lowercase kebab-case**: `wsl-gui-and-ime.md` -- no capitals,
  underscores or spaces. Forensic records and point-in-time snapshots get a `-YYYYMMDD`
  suffix (`etc-diff-analysis-20260330.md`, `pnpm-npm-cleanup-20260920.md`); process docs and
  evergreen docs do not. The only exceptions are **protocol filenames**: `README.md`,
  `README.zh.md`, `SKILL.md`, `SKILL.zh.md`, `AGENTS.md`, `CLAUDE.md`, `TROUBLESHOOTING.md` --
  tools and harnesses look these up literally, so renaming them breaks things.
- **`AGENTS.md` and `CLAUDE.md` exist only at the root.** Harnesses auto-load files with those
  names from subdirectories as instructions, so an *original* that deploys under one of those
  names gets a different name in the repo: `agent/claude-code/claude-global.md` ->
  `~/.claude/CLAUDE.md`, `agent/antigravity/agents-brave-uv.md` -> `~/.gemini/config/AGENTS.md`.
- **Every top-level directory except `tmp/` has a `README.md` index.** Where a directory has a `files/`
  subdirectory, `files/` holds deployable originals and everything else is documentation. An
  original used on more than one platform (the bash / zsh config) lives in a platform-neutral
  directory ([`shell/`](shell/)), not under one platform.
- **Markdown files are split into human-facing and agent-facing (English first, Chinese direct translation)**:
  - **For Agent reading & writing**: Written in the most comfortable, unambiguous, and context-efficient format for LLMs -- **English**.
  - **For Human reading**: Chinese versions serve as human reference, produced via **direct translation** sufficient for human comprehension.
  - **Eliminate the former "Chinese canonical first, then sync to English" requirement**: For all future edits and new documents, **always write the agent-facing English version first** (`x.md`), followed by a direct Chinese translation (`x.zh.md`). The deterministic specifications understood by agents form the core truth.
  - Root documents (`README`, `conventions`, `redaction`) and Skills are maintained as bilingual pairs: the English version is the primary execution baseline for agents, while the Chinese version provides human reference. Subdirectory notes are primarily for humans; skills serve both. Root [`AGENTS.md`](AGENTS.md) is strictly English and pure ASCII.
  - **When the layout, a deploy target, or a "must change together" pair changes, update `AGENTS.md` in the same commit** -- a stale map sends agents to the wrong files.
- **The README is a landing page and a router**: header, start here, layout, pitfall index,
  license. Anything substantial that is not needed on every read moves to its own file, with
  one row in the "Start here" table pointing at it -- the same split skills use between
  `SKILL.md` and `references/`. The pitfall index **deliberately stays** in the README: it is
  the most interesting thing here, and moving it out would leave a bare table of contents.
- **Python goes through `uv`, pinned to 3.12**. The system `/usr/bin/python3` is reserved for
  Ubuntu's apt packages; leave it alone.
- **Install skills with `cp`, never `ln -s`**. This tree gets moved between machines, file
  systems and operating systems, and symlinks do not survive that.
- **Sync skills with `bash tools/sync-skills.sh`, not a bare `cp` either.** The repo says
  `<your-home>`, `CourseName` and similar placeholders; the script expands them to real values
  when writing `~/.claude/skills/`, `~/.gemini/config/skills/` or `~/.agents/skills/`, and compares the
  **substituted** bytes when verifying -- so "the hashes match" means "repo == deployed copy,
  modulo redaction". Running it with no arguments is a read-only check. How to write a home
  directory depends on **whether a shell will expand it**: if it will, write `$HOME` (a
  runtime variable shipped as-is, not a placeholder); only where it will not do you write
  `<your-home>` -- just two lines of JSON left in the whole repo. See
  [`agent/skills/README.md`](agent/skills/README.md).
- **Do temporary things in `tmp/`**: backup copies taken before an edit, intermediate script
  output, snippets you want to try, raw command output. Not scattered across the repo root,
  and not in the system `/tmp` either (it is gone after a reboot, right when you want to look
  again tomorrow). The directory is gitignored, `git archive` will not export it, and
  `privacy-gate.sh` **skips** it -- so it can hold real paths and account names without
  turning the gate red every day. `tmp/.gitkeep` is tracked, so a fresh clone still has the
  directory.
- **Half-finished work and its to-do list go in `drafts/`, which is private-only.** It is
  tracked in the private repo (so it follows you between machines and is backed up) but
  **never exported**: `tools/publish.sh` deletes it from the export before the privacy gate
  runs and refuses to continue if it is still there, and `privacy-gate.sh` skips it like
  `tmp/`. Do not link to it from any other document: the link would dangle in the public
  repos. Credentials still never go in. To publish a draft, move it into the directory it
  belongs to, redact it (see [`redaction.md`](redaction.md)), and run the gate. `drafts/README.md`
  is the index and holds the to-do list.
- **Run `bash tools/privacy-gate.sh` before publishing.** It only covers known shapes; passing
  is not the same as safe -- `wsl/storage/forensics/` is raw forensic output and has to be read by hand.
  The account names are **not in the script** (putting them there would make the script itself
  the leak); they are read at run time from `tools/.privacy-names`, which is gitignored.
- **Publish with `bash tools/publish.sh`, never a hand-rolled `cp -r`.** This repo is a
  **private primary plus two public snapshots**:
  [`pitfall-harness`](https://github.com/Leonis03/pitfall-harness) gets the whole tree,
  [`pitfall-harness-skills`](https://github.com/Leonis03/pitfall-harness-skills) gets
  only the skills (`agent/skills/<name>/` -> `skills/<name>/`, without the third-party
  `find-skills`, plus a README the script generates from each skill's frontmatter). Each public
  repo has its own `.git`; keep a clone of each anywhere you like:

  ```bash
  bash tools/publish.sh <public clone> <skills clone>
  git -C <public clone> status        # read each diff, then add / commit / push in each
  ```

  What the script does -- the steps a manual sync must not skip:
  - **It exports `origin/main`, not `HEAD`.** The checkout here often sits on a feature branch,
    and `git archive HEAD` would publish that branch; `origin/main` is what has been merged.
  - **`git archive`, not `cp -r`**, so `tools/.privacy-names`, `tools/.sync-map` and `tmp/`
    cannot get in.
  - **It runs `privacy-gate.sh` on the export before writing anything**, and writes nothing if
    the gate fails. Rerun with `--skip-gate` only after reading every hit and confirming it is
    expected (say, an account name that is also the public author name).
  - **It wipes before unpacking**, because `tar -x` overwrites but never deletes: a file removed
    here would otherwise linger in public. The wipe spares `.git`.
  - **It does not commit.** Publishing is the one step that cannot be taken back, so commit and
    push stay with a person.

  - **Commits in the public repos carry no AI `Co-Authored-By` trailer** (Claude, Codex,
    Copilot, Gemini and the like): GitHub lists co-authors under the repo's Contributors.
    `publish.sh` uses the [`github-coauthor-scrub`](agent/skills/github-coauthor-scrub/) skill's
    script to install a commit-msg hook in both clones that rejects such a commit, and checks
    the existing history before exporting; if it finds one it stops and prints the rewrite
    (which drops only the AI lines and keeps human co-authors). The private repo and its PRs are
    not bound by this.

  The public repos keep **normal history** by default -- plain `commit` and `push`, never
  `--amend` plus a force push, which would break anyone who has cloned them. **Exception:
  rewriting and force-pushing is allowed** when a commit message carries an AI `Co-Authored-By`,
  when private data or a credential was published and has to leave the history, or in a
  comparable special case. The procedure is fixed: keep a local backup branch before rewriting,
  and push with `git push --force-with-lease=main:<SHA before the rewrite>`, so nobody else's
  new commit gets overwritten. **Then rename the default branch away and back**, or GitHub's
  cached Contributors box keeps the name. The whole sequence is the
  [`github-coauthor-scrub`](agent/skills/github-coauthor-scrub/) skill (`rewrite`, push,
  `refresh`, `verify`). (Precedent: on 2026-09-28 Claude's `Co-Authored-By` was removed
  from six commits; earlier, two amends added the licenses and reformatted a commit message.)
- **Credentials never enter version control.** Tokens that need to be environment variables go
  in `~/.shell_secrets` (`chmod 600`), loaded automatically at the end of `~/.shell_common`.

