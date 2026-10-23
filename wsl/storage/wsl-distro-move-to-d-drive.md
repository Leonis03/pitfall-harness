# WSL Ubuntu 迁移到 D 盘

## 结论

当前机器优先使用：

```powershell
wsl --manage Ubuntu --move D:\WSL\Ubuntu
```

只有当本机 `wsl --help` 里没有 `--manage <Distro>` / `--move <Location>` 时，才使用“导出 -> 注销 -> 导入”的兼容方案。

## 当前情况

- 发行版名：`Ubuntu`
- 当前 WSL 版本：`2.6.3.0`
- 当前根盘文件：`C:\Users\<your-windows-user>\AppData\Local\wsl\{<distro-guid>}\ext4.vhdx`
- 当前目录占用：约 `19G`
- 当前默认用户：`<your-linux-user>`（系统内 `/etc/wsl.conf` 已配置）

## 目标

把 Ubuntu 的 WSL2 根盘从 `C:` 挪到 `D:`。

- 推荐目标目录：`D:\WSL\Ubuntu`
- 备份目录：`D:\WSL\backup`

说明：

- 对 `wsl --manage ... --move ...` 来说，目标是目录，不是具体的 `ext4.vhdx` 文件。
- 如果使用兼容方案，最终会得到 `D:\WSL\Ubuntu\ext4.vhdx` 这样的文件路径。

## 迁移前检查

以下命令在 Windows PowerShell 中执行，不是在 WSL 终端里执行。

```powershell
wsl --version
wsl --help
wsl -l -v
```

满足以下条件再继续：

- `wsl --help` 里能看到 `--manage <Distro>` 和 `--move <Location>`
- `wsl -l -v` 里能看到目标发行版名确实是 `Ubuntu`
- `D:` 至少预留 `25G+` 空间
- 关闭所有正在使用 WSL 的终端、IDE、Docker Desktop、后台服务

## 推荐方案：先备份，再直接 move

以下命令在 Windows PowerShell 中执行。

```powershell
$stamp = Get-Date -Format yyyyMMdd-HHmmss
$backup = "D:\WSL\backup\Ubuntu-pre-move-$stamp.vhdx"

New-Item -ItemType Directory -Force D:\WSL\backup | Out-Null
New-Item -ItemType Directory -Force D:\WSL\Ubuntu | Out-Null

# 先导出一份可回滚的备份
wsl --shutdown
wsl --export Ubuntu $backup --format vhd
Get-Item $backup

# 直接把现有发行版迁移到 D 盘
wsl --manage Ubuntu --move D:\WSL\Ubuntu
```

## 迁移后校验

### 基础校验

```powershell
wsl -l -v
wsl -d Ubuntu -- whoami
wsl -d Ubuntu -- sh -lc "df -h / && findmnt /"
Get-Item D:\WSL\Ubuntu\ext4.vhdx | Select-Object FullName,Length,LastWriteTime
```

预期结果：

- `wsl -l -v` 里仍能看到 `Ubuntu`，版本为 `2`
- `whoami` 返回 `<your-linux-user>`
- `/` 挂载正常，容量显示正常
- `D:\WSL\Ubuntu\ext4.vhdx` 存在

### 强校验

如果你想进一步证明“当前根盘确实正在写入 `D:\WSL\Ubuntu\ext4.vhdx`”，可以做一次探针写入：

```powershell
$before = (Get-Item D:\WSL\Ubuntu\ext4.vhdx).LastWriteTime
wsl -d Ubuntu -- sh -lc "dd if=/dev/zero of=~/wsl-move-probe.bin bs=1M count=16 status=none && sync"
$after = (Get-Item D:\WSL\Ubuntu\ext4.vhdx).LastWriteTime
"$before -> $after"
wsl -d Ubuntu -- rm ~/wsl-move-probe.bin
```

预期结果：

- `D:\WSL\Ubuntu\ext4.vhdx` 的 `LastWriteTime` 更新
- 说明刚才在 Linux 根文件系统里的写入，已经落到了 `D:` 盘这块 VHDX 上

## 如果默认用户不对

当前版本优先使用：

```powershell
wsl --manage Ubuntu --set-default-user <your-linux-user>
wsl --shutdown
wsl -d Ubuntu -- whoami
```

如果本机不支持 `--set-default-user`，再回到 `/etc/wsl.conf` 方案，确认其中包含：

```ini
[user]
default=<your-linux-user>
```

保存后执行：

```powershell
wsl --shutdown
wsl -d Ubuntu -- whoami
```

## 复用已有的 ext4.vhdx（Windows 重装后）

`--manage --move` 和下面那套导出/注销/导入，前提都是**发行版当前已注册**。Windows 重装后
注册表里的 `Lxss` 键整个没了（`wsl -l -v` 是空的），此时既没有可 move 的对象，也没有可
unregister 的对象——直接原地注册那块磁盘就够了：

```powershell
wsl --version                                # 必须是 Store 版 WSL 2.x/3.x，inbox 存根没这个动词
Get-Item D:\WSL\<distro>\ext4.vhdx           # 先确认文件还在、大小合理（把盘符换成实际的）
wsl --shutdown
wsl --import-in-place <Name> D:\WSL\<distro>\ext4.vhdx
```

2026-10-17 实测（Debian 13，WSL 3.0.1.0）：注册后 `BasePath` 写作 `\\?\D:\WSL\<distro>`，
`DefaultUid` 写成 `0`——**但默认用户照样生效**，因为 `/etc/wsl.conf` 的 `[user] default=`
在磁盘里，优先级更高。跟「如果默认用户不对」那一节是同一套逻辑，不用额外处理。

### 导入前先做两件事

**一、把所有权归一化。** 磁盘是重装前留下的，文件上的显式用户 ACE 可能已经没了，只剩继承来的
`Authenticated Users:(M)`；attach 时 HCS 盖不上 VM 专属 ACE，就会报
`MountDisk/HCS/E_ACCESSDENIED`（完整排查见 [`forensics/`](forensics/)，修复段是这四行）：

```powershell
wsl --shutdown
icacls D:\WSL /setowner <your-windows-user> /T /C
icacls D:\WSL /grant "<your-windows-user>:(OI)(CI)F" /T /C
Restart-Service WSLService
```

健康态的判据是 `icacls <vhdx>` 里有一行 `<your-windows-user>\:(I)(F)`。

**二、复制一份备份。** `--unregister` 会连同 `ext4.vhdx` 一起删掉（见
[`../setup/README.md`](../setup/README.md) 的「重装的三个层级」和
[`../uninstall-cleanup.md`](../uninstall-cleanup.md) 第 0 节），而 `--import-in-place`
注册的就是**你这个文件本体**。重装前的数据在这块盘上是唯一副本，磁盘比备份小得多，
先 `Copy-Item` 再导入。

### 重装后 WSL 本体也得重装

两个可选特性是随重装清掉的，`wsl.exe` 退回 inbox 存根，此时 `--import-in-place`
这个动词**根本不存在**，导入必然失败：

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
winget install --id 9P9TQF7MRM4R --source msstore --accept-source-agreements
# 必须重启。HypervisorPresent 变 True 之前，wsl --status 会说 WSL2 不可用
```

两个坑：

- inbox 存根的 `wsl --install --no-distribution` 在 26100 上**不工作**——它只是个转发器，
  只会回一句让你去 `wsl.exe --install`。走 winget 的 msstore 源装 Store 版才有效。
- 别用 `dism` 之外的手段去确认特性状态。`Get-WindowsOptionalFeature` 会显示
  `Enabled` 而 `HypervisorPresent` 仍是 `False`，因为虚拟机平台要重启才真正加载。

## 兼容旧版 WSL 的回退方案

只有在本机没有 `wsl --manage ... --move ...` 时，再使用下面这套。

```powershell
wsl --shutdown
New-Item -ItemType Directory -Force D:\WSL\Ubuntu | Out-Null

# 导出当前 Ubuntu 为 VHDX
wsl --export Ubuntu D:\WSL\Ubuntu\ext4.vhdx --format vhd
Get-Item D:\WSL\Ubuntu\ext4.vhdx

# 只有在已经保留了额外备份，且确认要走兼容方案时，再继续
wsl --unregister Ubuntu
wsl --import-in-place Ubuntu D:\WSL\Ubuntu\ext4.vhdx
```

完成后，重复执行上面的“迁移后校验”。

## 注意事项

- `wsl --manage Ubuntu --move D:\WSL\Ubuntu` 的目标是目录，不是文件路径。
- 推荐先做一次导出备份，再做 `--move`。这样即使迁移失败，也有单独的回滚文件。
- 兼容方案里的 `wsl --unregister Ubuntu` 是破坏性操作，只能在确认备份可用后执行。
- `/mnt/c`、`/mnt/d` 这类挂载的 Windows 文件不会跟着一起“搬迁”。
- 建议把 WSL 放在本机固定磁盘上，不建议放到容易断开的外置盘。
- 如果迁移后旧路径还残留文件，不要立刻手动删，先确认新路径稳定使用几天。
- WSL 3.0 起回收空间用 `wsl --manage <Name> --compact`（先 `fstrim`、再 `wsl --shutdown`），
  不用再走 `Optimize-VHD`。实测回收比例远小于「宿主文件大小 − `df` 已用」的差值，
  详见 [`../setup/README.md`](../setup/README.md) 的「维护：回收 vhdx 空间」。
- `--import-in-place` 注册的就是你指定的那**一个文件**，没有中间层。误 `--unregister`
  的后果比注册过的发行版更直接：磁盘本身没了。

## 以后新装时避免再落到 C 盘

如果以后新安装发行版，可以直接指定位置：

```powershell
wsl --install Ubuntu --location D:\WSL\Ubuntu
```

这只影响新安装，不会迁移已经存在的发行版。

## 参考

- Microsoft Learn: https://learn.microsoft.com/en-us/windows/wsl/basic-commands
- Microsoft Learn: https://learn.microsoft.com/en-us/windows/wsl/wsl-config
- Microsoft Learn: https://learn.microsoft.com/en-us/windows/wsl/disk-space
