---
name: distill-session
description: Turn what a session just discovered into content in this repo -- decide whether it earns a place, find the file it belongs in, prove the claim before writing it down, redact it, close the must-change-together pairs, and land it as a PR. TRIGGER when the user says record this, write this down, save this finding, distill this session, or points at a pitfall, a surprise, or a setup step that cost time and should not cost it again. Not for fixing code, and not when the finding is already documented.
---

# Distill one session into repo content

The repo's premise is that an agent is a system operator, and that a session
which ended in understanding should not end there. This is the closing step of
that loop: take the finding, put it where the next agent will look, and make it
verifiable.

> **Paths.** This file and its `scripts/` live under `~/.agents/skills/distill-session/`.
> Any installed copy works -- `~/.claude/skills/distill-session/`,
> `~/.gemini/config/skills/distill-session/`, or a path relative to this SKILL.md.
> Only one of the three needs to exist. Install it with
> `bash tools/sync-skills.sh deploy distill-session`, never `cp`.

## 0. Decide whether it earns a place

Most of what happens in a session is not worth recording. Write it down only when
**all three** hold:

1. **It cost time to find.** Something failed, failed quietly, or had to be
   measured before the answer was obvious.
2. **It will cost the same again.** The next agent, on the next machine, doing
   the same task.
3. **It is not already written.** Check first -- `grep` the area, read the
   directory README. A second copy is worse than none, because they drift apart
   and the reader cannot tell which is current.

Test 3 is the one that gets skipped. A finding you "remembered being absent" is
frequently present in a form you did not recognise.

**Not worth recording**: what a tool's own `--help` already says plainly; a
one-off typo; a finding already captured by a vendored upstream doc; anything you
have not verified.

## 1. Find the file

[`../../AGENTS.md`](../../../AGENTS.md) has a **Request -> files to edit** table.
That table is the router; use it rather than guessing. It maps intent to the
canonical file for each area.

If the finding is a **pitfall** rather than a change, the rule is narrower: it goes
in the doc of the area it belongs to, and it gets **one row in the root README
pitfall index**, mirrored into `README.zh.md`. The index deliberately stays in the
README because it is the most interesting thing here.

If nothing fits, it is a **new directory or a new skill** -- and both are layout
changes, which carry extra obligations (step 5).

If the work is genuinely unfinished, put it in [`../../drafts/`](../../../drafts/),
not next to the finished docs. `drafts/` is private-only and must not be linked
from any other document, because the link would dangle in the public repos.

## 2. Prove the claim before writing it

The repo does not store inferences. It stores measurements.

- **Run it.** A claim about a tool's behaviour is a claim about *this* machine.
- **Measure the thing that failed, not the thing that succeeded.** The useful
  number is usually the failure mode's fingerprint -- an exit code, a byte
  pattern, a substring -- because that is what you will match against next time.
- **Record the negative result too.** "X does not apply here, and that is why"
  is what stops the next agent from re-deriving it.
- **Do not generalise from one host.** If a count, a path or a config value came
  from a single machine, either scope it to that machine or verify it elsewhere
  first. A "five directories" that is two on the next box is a false rule.

**Date every environment fact.** Toolchains drift: in one session `uv`, `bx`,
`jq` and a WSL distribution all appeared between checks hours apart, and Node.js
arrived via an installer no package manager knew about. A remembered baseline is
wrong *silently*, because the tool still resolves. See
`agent/minimax-code/agents-windows.md` for what that looks like in practice.

## 3. Write the entry

- **Name the failure mode, not the fix.** "Editing CRLF file with the string
  replace tool keeps it CRLF forever" beats "use write to rewrite the file".
- **Say how it presents, or say that it does not.** The most expensive bugs in
  this repo's history are the ones with no symptom. If yours is silent, that is
  the first sentence.
- **Put the reproducible command in.** A claim without a command cannot be
  re-checked, and an uncheckable claim decays into folklore.
- **Write the English version first**; the Chinese one is a direct translation
  of it, not an independent draft.
- Config originals and deployable files stay **pure ASCII, comments in English**.

## 4. Redact

[`../../redaction.md`](../../../redaction.md) is the authority; the short version is
to classify each value by **whether a shell will expand it** at the destination:

1. it will -> write `$HOME`
2. it will not, but the target machine can detect it -> ship detection code
3. neither -> write a placeholder

The trap that recurs: an **illustrative** path that happens to look like a real
one. A `C:/Users/<anything>/...` example in a doc trips the privacy gate's
Windows-user-path rule, which cannot tell a placeholder from an account name --
exactly the trap that hit this very file once, and that the WeChat fix
(`b1cdccf`) was about. Reach for a path that is clearly generic instead, such as
`D:/data/x.sql`.

## 5. Close the pairs

Landing half a change is worse than not landing it. From
[`../../AGENTS.md`](../../../AGENTS.md), a new change usually obliges you to update,
**in the same commit**:

| The change | Also update |
| :--- | :--- |
| any doc under a bilingual pair | `README.md` <-> `README.zh.md`, `conventions*`, `redaction*` |
| a new skill | both tables in [`README.md`](../README.md) -- the platform table and the per-machine install matrix |
| a new directory, deploy target, or pair | `AGENTS.md` |
| a moved or renamed path | `git grep` the old path and fix every link, plus both root READMEs |
| a deployable original | decide explicitly whether this change deploys |

That last one is a decision, not a default: **editing a repo original does not
deploy it.** Deploy only when the user asks, and back up the live file into
`tmp/` first.

If you add a skill, the unquoted `description` must not contain `: ` or ` #` --
strict parsers drop the skill **without an error**.

## 6. Verify

`scripts/verify-change.sh` runs the mechanical part: the privacy gate, relative
links, pure-ASCII on the surfaces that require it, and line endings.

```bash
bash scripts/verify-change.sh          # against the working tree
bash scripts/verify-change.sh main     # against a ref
```

It does not judge whether the finding is true, only whether the tree is
shippable. Reading the diff is still your job, and `privacy-gate.sh` passing is
necessary, not sufficient.

## 7. Land it

- `git fetch` first. If the working tree moves under you, use
  `git worktree add tmp/<name>` rather than switching branches.
- Branch, commit, PR against `main`. Never force-push `main`.
- Write the commit body as **why**, with the measurement in it. A commit that
  only says what changed is a diff someone will misread later.
- Publishing to the public repos is a separate step (`tools/publish.sh`) and the
  user does the commits there.

## Failure modes actually observed

Each of these happened while building this skill's sibling entries.

**Merging silently loses content.** A PR reported `MERGED` and still never
reached `main`, because it was stacked -- its base was another PR's branch, not
`main`. **Check that the branch's content is an ancestor of `main`** rather than
trusting the PR's state field:

```bash
git merge-base --is-ancestor <pr-branch> origin/main && echo reached
```

A second one: git merged two files cleanly and **dropped one side's section**
without reporting a conflict. After merging, check that what each branch added
is still present -- grep for a distinctive string from each side.

**Auto-resolution is not verification.** Two stale claims about `python3`
survived into a document and were wrong by the end of the same day. Re-run the
checks against the live machine, not against yesterday's notes.

**"It exited 0" is not the question.** Most valuable entries here document a
command that *succeeded* and still produced wrong output. When you write such an
entry, name the observable difference between right and wrong, so the next agent
can tell which one it has.
