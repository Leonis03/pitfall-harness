# Archival pass catalog

The machine is being retired. The image will be exported, snapshotted, or handed over,
and the goal is that it takes as little space as possible **while still containing
everything that cannot be produced again**.

The rhythm is different from routine mode: group the candidates, report the size of
each group, get one decision per group. One blanket approval is how an irreplaceable
dataset gets deleted.

---

## The five classes

| Class | Reconstructible how | Action |
| :--- | :--- | :--- |
| **A. Cache** | Re-downloaded on demand | Delete, no question |
| **B. Re-installable software** | `apt install`, `npm i -g`, installer | Delete; list what needs reinstalling |
| **C. Re-downloadable artifacts** | Downloaded from a public source | Delete with the user's confirmation that a copy exists |
| **D. Session state** | Lost forever, but it is only conversation history | Delete; say which transcripts were in it |
| **E. Irreplaceable** | Not reconstructible at all | **Never delete. List it for the user.** |

---

## A. Cache

Everything in the routine catalog applies. On the measured machine this was
**1.45 GiB**: apt archives 426 MiB, apt lists 205 MiB, snap download cache 414 MiB,
journal 403 MiB, plus 182 MiB of retired snap revisions.

---

## B. Re-installable software

This is the class that distinguishes archival mode from routine mode. In routine mode
the user's IDE stays installed. In archival mode it goes.

| Item | Typical size | Reinstall by |
| :--- | :--- | :--- |
| `~/opt/<app>` | 700-800 MiB for a full IDE | Downloading the installer again |
| `~/.vscode-server/extensions` + `bin` | 2.5 GiB | The next remote connection |
| `~/.local/bin/<tool>` plus its `.old` sibling | 200 MiB each | The tool's own installer |
| `~/.nvm/` | 200 MiB | `nvm install` |
| `~/.local/share/uv/python/<other versions>` | 70-100 MiB each | `uv python install` |
| Language runtimes from the package manager | 100-250 MiB each | `apt install` |
| `~/.config/<app>/node_modules` | 50-70 MiB | `npm install` |

### Duplicated toolchains

Look for the same tool installed twice by different managers. On the measured machine
Go existed as **both** an apt package (`golang-1.22-src` 119 MiB + `golang-1.22-go`
98 MiB, plus `/usr/lib/go-1.22` and `/usr/share/go-1.22` on disk) **and** a snap
(2 revisions, 128 MiB). 345 MiB for one language. One of them is enough; which one
depends on how the user's projects invoke it, so check before choosing.

### The version manager is not redundancy

A version pinned by a project config, a `.python-version` file, or a `PATH` entry in
the shell rc is a **dependency**. Deleting it breaks the project silently -- the next
`uv run` just downloads a different interpreter. Keep the pinned version, delete the
others.

---

## C. Re-downloadable artifacts

### Model weights

Weights are the biggest thing in a machine-learning project and the least likely to
be under version control, because `.gitignore` excludes them.

```bash
find ~ -type f \( -name '*.pth' -o -name '*.pt' -o -name '*.ckpt' \
                -o -name '*.safetensors' -o -name '*.onnx' \) -size +10M \
  -printf '%s %p\n' | sort -rn
```

Three sub-kinds, three different answers:

1. **Public pretrained checkpoints** (a `torch.hub` backbone, a timm weight file) --
   re-downloadable by definition. Delete.
2. **Trained artifacts** (a fine-tuned adapter, a best checkpoint) -- only
   reconstructible by re-training, which costs hours or days. Delete **only** if the
   user confirms a copy exists elsewhere. Ask per family, not per file: "these eight
   are all one experiment, and I have them on two other machines" is a useful
   answer; eight separate questions are not.
3. **Datasets** -- never class C. See class E.

### Checkpoint integrity before deleting

A truncated checkpoint is a copy that never finished. A torch checkpoint is a zip, so
the entry count is a cheap integrity test:

```bash
python -c "import zipfile,sys; print(len(zipfile.ZipFile(sys.argv[1]).namelist()))" <ckpt.pth>
```

A `BadZipFile` means the file was cut short -- a partial copy, not a checkpoint. A
complete one has one `data.pkl` plus one entry per tensor, so roughly 221 entries for
a 220-tensor state dict. **Report the broken ones separately**: they are not a backup,
and treating them as one is how a user believes their work is archived when it is not.

### Repositories that can be re-cloned

A repository with a remote is a cache of something public:

```bash
for d in $(find ~ -maxdepth 5 -type d -name .git); do
  r=$(git -C "${d%/.git}" remote -v | head -1)
  echo "${d%/.git}  ${r:-!!no remote!!}"
done
```

Anything with a remote can be re-cloned. **Check the working tree first** --
`git -C <repo> status --porcelain` -- because uncommitted changes are local-only
content, and a re-clone loses them. A repository with a remote *and* uncommitted
changes is class E, not class C.

On the measured machine this was **1.27 GiB**: a set of vendored open-source
repositories cloned from public hosts, plus the unpacked contents of a few npm
packages whose tarballs sat in the same directory.

---

## D. Session state

Agent tools, editors, and shells all keep conversation history. It is unrecoverable
once deleted, and it is also usually worthless to anyone but the user. The
conversation is worth mentioning before deleting it, because transcripts sometimes
contain the only copy of an analysis.

- AI-tool conversation databases and their log files (see the routine catalog for
  the paths)
- Shell history -- archive it if the user wants it, with the redaction rules in
  SKILL.md
- Editor local history and workspace state
- Chat applications' local message databases

Before deleting, check whether any generated report is stored **only** inside the
session store. On the measured machine a handful of `.md` analysis reports lived
inside the agent's per-session "brain" directory, some of them under a
system-generated subdirectory. Deleting that subdirectory took the reports with it.

---

## E. Irreplaceable -- list it, never delete it

This is the list the user actually needs when the image is restored somewhere else.

Common members:

- SSH private keys and their `config` -- **losing these is permanent**
- Datasets, corpora, and annotated label files
- Trained weights whose training run cannot be repeated
- Notes, handover documents, and anything hand-written
- Source code with no remote, and no uncommitted state
- Shell and editor configuration the user wrote by hand
- Password databases, KeePass files, and anything similar
- Anything whose only copy is this machine

Check the mtime distribution before deciding a large data directory is a pure
extraction -- and then confirm with `md5`, because an extracted file can have been
written back afterwards:

```bash
find <dir> -type f -printf '%TY-%Tm-%Td\n' | sort | uniq -c | sort -rn | head
```

A single dominant date suggests an extraction. **Two or more clusters, or dates later
than the archive, mean it is original data.** Timestamps alone are not proof:
archives preserve the timestamps they contain, so "the files look old" proves nothing
about whether they were modified. `md5` is the only test that settles it.

If the source archive cannot be found, treat the directory as irreplaceable. "I could
not find the original" is a reason to keep, not a reason to delete.

---

## The archival report

Give the user all of these, in this order:

1. **The class table**, with the size of each class and the decision taken on it.
2. **The irreplaceable list**, itemised with its size -- this is the part they will
   need to restore the image elsewhere.
3. **What was deleted that they will want back**: the software to reinstall, the
   credentials to rotate, the checkpoints to re-derive.
4. **Before and after totals**, plus the platform step needed to give the space back
   (for WSL, compacting the image -- see SKILL.md).
5. **What you could not verify**, stated plainly. A directory whose origin could not
   be established, a checkpoint that turned out to be truncated, a remote you could
   not reach -- these are reported, not silently skipped.
