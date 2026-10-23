# Backing up a WSL home directory to an NTFS drive

Measured on Fedora 44 WSL, kernel 5.18.54.1-microsoft-standard-WSL2, to a 1 TB NTFS
3.0 external drive over drvfs.

This covers the **backup half** of the skill. Run the routine or archival cleanup
first: the exclusion list below is derived from what that pass measured, and cleaning
first is what keeps the backup from carrying what could be re-downloaded.

---

## 1. Find the drive letter from Windows

`[automount] enabled = false` in `/etc/wsl.conf` means **nothing is mounted for
you** -- not even `C:`. That is deliberate (it lets Windows eject USB sticks), so
the drive has to be mounted by hand every time.

Ask Windows rather than guessing:

```bash
powershell.exe -NoProfile -Command \
  "Get-PSDrive -PSProvider FileSystem | Select-Object Name,Root,@{n='FreeGB';e={[math]::Round(\$_.Free/1GB,1)}} | Format-Table -AutoSize"
```

| Name | Root | FreeGB |
| :--- | :--- | ---: |
| C    | C:\  | 60.9 |
| J    | J:\  | 144.5 |

`wmic` returns nothing under WSL interop; `Get-PSDrive` works. Note that
`/mnt/` may still contain **empty mount-point directories** left over from earlier
attach attempts -- a directory under `/mnt` is not proof that the volume is mounted.
Check with `findmnt /mnt/<letter>`, not `ls /mnt`.

## 2. Mount it

```bash
sudo mkdir -p /mnt/j
sudo mount -t drvfs 'J:' /mnt/j -o metadata,uid=1000,gid=1000,umask=22
findmnt /mnt/j
```

- `metadata` makes drvfs synthesise Unix permissions on the NTFS side; without it
  every file comes out `0777` and a restore cannot set a private key to `0600`.
- `uid`/`gid`/`umask` are what let the copy run as the user instead of root.
- Verify with `findmnt`, which reports `aname=drvfs;path=J:` and the full option
  list. The fstype shows as `9p`, not `drvfs` -- `findmnt -t drvfs` finds nothing.

## 3. Decide what goes

Only class E. Everything regenerable is excluded, and the exclusions come from the
cleanup scan, not from guesswork:

```bash
du -sh ~/.nvm ~/.npm ~/.local ~/.cache ~/.vscode-server ~/.oh-my-zsh 2>/dev/null
```

Measured on the reference host:

| Path | Size | Why excluded |
| :--- | ---: | :--- |
| `~/.nvm` | 516 MiB | `nvm install` re-creates it |
| `~/.npm` | 128 MiB | npm re-downloads |
| `~/.local` | 28 KiB | re-installable |
| `~/.cache` | -- | on demand |
| **Copied** | **284 MiB** | 8,845 files |

## 4. Copy

Pipe `tar` rather than `cp -r`: it preserves modes, applies the exclusions in one
pass, and cannot leave a half-copied tree behind.

```bash
cd "$HOME"
DEST="/mnt/j/<path>/home"
mkdir -p "$DEST"
time tar -cf - \
      --exclude='./.nvm' --exclude='./.npm' --exclude='./.local' \
      --exclude='./.cache' --exclude='./.vscode-server' --exclude='./.oh-my-zsh' \
      . | (cd "$DEST" && tar -xf -)
```

**49 seconds** for 284 MiB over drvfs on that host. `cp -r` would not have preserved
the `-rw-------` on the private key.

## 5. Verify

A byte count is not a backup. Check the irreplaceable classes explicitly:

```bash
ls -la "$DEST/.ssh/"                                    # modes survived
md5sum "$HOME/.ssh/id_ed25519" "$DEST/.ssh/id_ed25519"  # private key
for r in <repos>; do
  a=$(git -C "$HOME/$r" rev-parse HEAD); b=$(git -C "$DEST/$r" rev-parse HEAD)
  [[ "$a" == "$b" ]] && echo "ok $r ${a:0:8}"
done
```

Also confirm the exclusions held -- a directory that regrew between the cleanup and
the copy is easy to miss:

```bash
for x in .nvm .npm .local; do
  [[ -e "$DEST/$x" ]] && echo "LEAKED $x" || echo "ok $x excluded"
done
```

**Compare file counts, not just sizes.** On the reference host the source and
destination differed by exactly the excluded entries -- that difference is the
check. A repository showing a different `HEAD` means the copy is not a snapshot of
what was there.

## 6. Eject

```bash
sudo umount /mnt/j
```

Only after this can Windows release the volume. Unmounting first is what allows
ejecting from the File Explorer without a `wsl --shutdown`. Skipping it leaves the
volume locked and the "safe to remove hardware" dialog never appears.

---

## Traps measured on this run

**A cleaned directory regrows on the next login.** After the archival pass deleted
`.nvm` and `.npm`, switching the login shell from zsh to bash brought back 516 MiB
and 128 MiB respectively -- the bash profile sources the version manager, which
installs on first use. A backup taken the next morning would have carried them again.
Check the sizes immediately before copying, and prefer excluding by pattern over
trusting a list written down hours earlier.

**`ls /mnt` lies.** It listed `g` as a directory while `Get-PSDrive` showed no such
volume -- a leftover mount point. `findmnt` is the authority.

**NTFS has no Unix permissions**, so a restore onto Linux will not reproduce modes
unless the copy was made with `metadata` or the tree is restored with `tar -p`.

**The drive is readable by whoever holds it.** The reference backup carried a 32-byte
gitee token file in plaintext. That token now exists in two places with different
blast radii, and rotating it is the user's decision -- but they have to be told:

```bash
grep -rlaE 'gh[pousr]_|AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,}|AKIA' "$DEST" 2>/dev/null
```

## Restoring

```bash
sudo mkdir -p "$HOME"
cd "$HOME" && tar -xf - -C "$HOME" <path>/home.tar   # or copy in place
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*             # if permissions came across wrong
```

Then re-verify: `git rev-parse HEAD` in each repository, `md5sum` on the key, and a
shell that starts clean.
