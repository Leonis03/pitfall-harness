# 两块盘、三个系统：后备系统的引导要放在它自己那块盘上

*中文 · [English](triple-boot-layout.md) · 返回 [os-install/](README.zh.md)*

> **适用环境**：一台台式机，UEFI，Secure Boot 关闭。NVMe 固态硬盘上是 Windows 11 和一个 Linux 发行版；
> 1 TB 机械硬盘上是作为**后备**的 Linux Mint 22，外加数据分区。
> **实测时间** 2026-11-22，在替换固态硬盘上的 Linux（Fedora 44，装过、已弃用）之前。
> **适用场景**：每个系统的引导放在哪，为什么后备系统扛不住它本该扛住的那块盘坏掉，以及重装固态硬盘上的
> Linux 时怎样不弄坏另外两个系统。三个系统之间的时钟约定见 [`dual-boot-time-sync.zh.md`](dual-boot-time-sync.zh.md)。

---

## 1. 实测的分区布局

| 磁盘 | 分区 | 大小 | 内容 |
| :--- | :--- | ---: | :--- |
| 固态 | ESP（vfat） | 500M | `EFI/BOOT`、`EFI/Microsoft`、`EFI/fedora`、`EFI/ubuntu` —— **三个系统的引导全在这里** |
| 固态 | Microsoft 保留分区、Windows `C:`、一个 NTFS 数据分区 | 16M、128G、32G | Windows |
| 固态 | ext4 | 1.9G | 一个旧的 Fedora `/boot`，已成孤儿（不在 `fstab` 里） |
| 固态 | ext4 + btrfs | 2G + 313G | Fedora 的 `/boot`、`/` 和 `/home` |
| 机械 | ESP（vfat，ESP 分区类型） | 487M | **空的** —— 连 `EFI/` 目录都没有 |
| 机械 | ext4 x3 | 61G、61G、100G | Mint 的 `/`、`/var`、`/home` |
| 机械 | NTFS x3 | 共 709G | 数据 |

固件启动顺序是 Fedora、Windows Boot Manager、Ubuntu（Mint）—— 三个启动项全都指向固态硬盘的 ESP。
没有任何分区的 `FSTYPE` 是 `BitLocker`。

读取方法，全部只读：

```bash
lsblk -o NAME,SIZE,ROTA,FSTYPE,PARTTYPENAME,MOUNTPOINTS   # ROTA 0 = 固态，1 = 机械
sudo efibootmgr -v                                       # 每个启动项指向哪个分区
findmnt /boot/efi
```

没挂载的 ESP 可以只读挂载后查看（`sudo mount -o ro /dev/<esp> <目录>`，再 `ls <目录>/EFI`）。

---

## 2. 坑：后备系统是从它本该扛住的那块盘上启动的

Mint 的根文件系统在机械硬盘上，但它的 GRUB 和固件启动项都在**固态硬盘** ESP 上的 `EFI/ubuntu` 里，
而机械硬盘自己的 ESP 是空的。固态硬盘一坏，机械硬盘上那个完整的 Mint 就没有任何东西能把它启动起来，
只能靠救援盘。这个后备系统，恰恰依赖着它本该顶替的那块盘。

安装程序把引导装进了它找到的那个 ESP —— Windows 在固态硬盘上建的那个 —— 而没有在机械硬盘上另建一个。
Mint 的安装程序有没有提供选择的办法，这次没有重新测；常见的绕法是安装时在固件里禁用或拔掉固态硬盘，
让安装程序能看到的唯一一个 ESP 就是机械硬盘上的那个。

**规则**：后备系统的引导要放在后备系统自己那块盘上，固件里也要有指向那里的启动项。

---

## 3. 把 Mint 的引导挪到机械硬盘上（尚未实测）

在 Mint 里执行。这是打算采用的步骤，还没在这台机器上做过：

```bash
findmnt /boot/efi                      # 目前：固态硬盘的 ESP
sudo umount /boot/efi
sudo mount /dev/<机械硬盘的ESP> /boot/efi    # 这台机器上是 sda1
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=mint-hdd
sudo update-grub
sudo efibootmgr -v                     # 多出一个指向机械硬盘的 "mint-hdd" 启动项
```

然后把 Mint 的 `/etc/fstab` 改成用机械硬盘的 ESP 作 `/boot/efi`（按 UUID），否则下一次 GRUB 更新又会装回
固态硬盘。固态硬盘上旧的 `EFI/ubuntu` 可以留着当第二条路，只是不会再更新。

验证只有一种算数的办法：在固件启动菜单里选机械硬盘那个启动项 —— 最好有一次是在固件里禁用了固态硬盘的
情况下 —— 看 Mint 能不能起来。

---

## 4. 重装固态硬盘上的 Linux，又不弄坏另外两个

- **复用固态硬盘的 ESP，不要格式化它。** Windows Boot Manager 在里面，在第 3 节做完之前 Mint 的引导也在里面。
  安装程序里把现有的 ESP 选作 EFI 系统分区，但不格式化。
- 只删除旧的 Linux 分区 —— 这台机器上是那个孤儿 `/boot`、当前的 `/boot` 和 btrfs 卷 —— 保留 Microsoft 保留
  分区、`C:` 和 NTFS 数据分区。
- 新系统能启动之后，再清理旧系统留下的东西：它在 ESP 里的目录（这里是 `EFI/fedora`）和它的固件启动项
  （`sudo efibootmgr -b <编号> -B`）。务必等新系统能自己启动之后再做。
- 如果新的 GRUB 菜单里没有 Windows 和 Mint，打开 os-prober（在 `/etc/default/grub` 里设
  `GRUB_DISABLE_OS_PROBER=false`，再 `sudo update-grub`）。
- **三个系统的 RTC 约定必须一致。** 两个 Linux 就是两个写方，各自有自己的 `LocalRTC`。见
  [`dual-boot-time-sync.zh.md`](dual-boot-time-sync.zh.md)。

---

## 5. 抹掉之前：只存在于那个系统里的东西

在 Fedora 被替换之前实测 —— 这些是任何软件包、任何仓库原件都找不回来的部分：

| 内容 | 位置 |
| :--- | :--- |
| Rime 学习词库 | `~/.local/share/fcitx5/rime/*.userdb/` |
| Rime 的自定义 | `~/.local/share/fcitx5/rime/*.custom.yaml`、`custom_phrase.txt` |
| Fcitx5 自己的设置 | `~/.config/fcitx5/` |
| CopyQ 的历史和命令 | `~/.local/share/copyq/`、`~/.config/copyq/` |
| 手动装的字体 | `~/.local/share/fonts/` |
| SSH 密钥 | `~/.ssh/` |
| 浏览器配置目录 | `~/.config/google-chrome/`、`~/.mozilla/` |
| 第三方软件源 | `dnf5 repo list --enabled` / `/etc/apt/sources.list.d/` |
| 手工改过的系统配置 | `sudo rpm -Va`（Fedora）或 `debsums -ce`（Debian） |

规划拷贝时，知道大小和名字就够了（`du -sh <目录>`）；判断这些东西要不要留，不需要读它们的内容。
