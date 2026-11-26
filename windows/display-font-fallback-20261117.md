# 英文显示语言下的中文回退字体：三层机制与配置

*Windows 11 IoT Enterprise LTSC 26100；实测 2026-11-05 ~ 11-18。本文只记录「显示语言保持 `en-US`」前提下的修法——切到中文显示语言当然能正常显示中文，那不是本任务。*

> 相关：[`ime-keyboard/stray-keyboard-layouts.md`](ime-keyboard/stray-keyboard-layouts.md)（键盘布局清理脚本）、[`powershell/cjk-command-io.md`](powershell/cjk-command-io.md)（控制台编码 / 报错语言）、[`../README.md`](../README.md) pitfall index。

---

## 1. 先定位：不是缺字体，是回退表选错

实测这台机器上 `msyh.ttc`、`msyhbd/l`、`simsun.ttc`、`simhei`、`simkai`、`simfang`、`Deng*`、`msjh*.ttc`、`YuGoth*.ttc`、`malgun*.ttf`、`msgothic.ttc`、`NotoSansSC-VF.ttf`、`NotoSerifSC-VF.ttf` **全部存在且已在 `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` 注册**。所以「装中文字体」不是解法；要改的是**英文镜像自带的 CJK 回退顺序**。

| 层 | 谁在用 | 本机实测 | 落到哪 |
| :--- | :--- | :--- | :--- |
| GDI font linking | 经典 Win32 控件、属性页、部分 Shell UI | `HKLM\...\FontLink\SystemLink` 是 en-US 原装表：`Segoe UI` / `Tahoma` / `Microsoft Sans Serif` / `Segoe UI Variable*` 的 CJK 链首是 `MEIRYO.TTC,Meiryo UI`（文件不存在）→ `MSGOTHIC.TTC,MS UI Gothic`（存在）→ `MSJH.TTC,Microsoft JhengHei UI`（繁）→ `MSYH.TTC,Microsoft YaHei UI`（**排第 5 位以后**） | 第一个可用命中是 **日文黑体 `MS UI Gothic`** |
| Family fallback | GDI 字体映射器；也是「请求某个字体名但没装」时的重定向 | `HKLM\...\FontMapperFamilyFallback` 把 `Meiryo` / `MS Gothic` / `MS UI Gothic` / `MS Mincho` 全部映射到 `Yu Gothic UI`；`MingLiU` / `PMingLiU` 映射到 `Microsoft JhengHei UI`；**没有一条指向简体** | 日文 / 繁体名被锁死 |
| conhost | cmd / PowerShell 5.1（不是 Explorer，但同属系统组件） | `HKCU\Console` 根键 `FaceName = __DefaultTTFont__`、4 个子键 `Lucida Console`；`HKLM\...\Console\TrueTypeFont\0 = Lucida Console`、`936 = *新宋体` | 中文落到**宋体衬线** |

佐证这套表来自英文镜像：`FontLinkDefaultChar = 12539`（U+30FB 日文中点）、`InstallLanguage = 0409`、`Segoe UI Variable`（基础名）在 `SystemLink` 里**根本没有条目**（Win11 的 UI 字体，这族连链接数据都没有）。

浏览器是**另一层**，别混：Chrome 的 `intl.accept_languages` 里有 `zh-TW` 时，CJK 回退选中 `Microsoft JhengHei UI`，渲染成「简体的字、繁体的形」；在受控像素比对里，真实 profile 下 JhengHei 的匹配度是次优 `Noto Sans SC` 的 6 倍。这不是 Windows 层问题，修 Explorer 不会动它，删 `zh-TW` 也不会让 Explorer 变好。

---

## 2. 动手前

1. **备份**（管理员）：

   ```powershell
   $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
   $out = Join-Path $env:USERPROFILE "Desktop\fontfix-$stamp"
   New-Item -ItemType Directory -Force -Path $out | Out-Null
   reg export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink' "$out\FontLink.reg" /y
   reg export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontMapperFamilyFallback' "$out\FontMapperFamilyFallback.reg" /y
   reg export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' "$out\FontSubstitutes.reg" /y
   reg export 'HKCU\Console' "$out\Console-HKCU.reg" /y
   ```

2. **留一张 before 截图**：在 Explorer 里放一个文件名 `直骨每海令观调与体.txt`。这几个字的地区字形差异最明显，是判断「繁体感 / 日文感是否消失」的标尺。

3. **重新探测**：语言列表、区域、字体表在会话之间可能被别的进程或会话改过。本文所有数值都是某一时刻的快照，不是可以直接照抄的配置。

---

## 3. 配置：先做 3.3，每步 A/B

字体表在会话启动时加载，**每一步都要注销重登再看截图**，不要连着改完三张表才验证。

> **2026-11-18 实测结果（这台机器）**
>
> | 步骤 | 做了没有 | 注销重登后 |
> | :--- | :--- | :--- |
> | 3.1 家族重定向（18 个值改到 `Microsoft YaHei UI`） | 做了 | **桌面文件名与记事本都没有变化**，仍是横细竖粗的宋体感字形 |
> | 3.3 SystemLink 重排（23 个 face 雅黑提到链首 + 新建 `Segoe UI Variable`） | 在 3.1 之后做 | **Explorer 文件名恢复正常的简体雅黑** |
> | 3.2 字体名替换、3.4 conhost | 没做 | -- |
>
> 原因：Explorer 和经典 Win32 程序请求的是 `Segoe UI`，缺字时走的是 `SystemLink` 里的**文件链接链**
> （`MSGOTHIC.TTC,MS UI Gothic` 这类条目），根本不查 `FontMapperFamilyFallback`。所以真正起作用的是 3.3，
> 应当**先做 3.3**。3.1 没有回滚，所以「只做 3.3 是否就够」没有单独验证；记事本在 3.3 之后也没有复核。
> 3.2、3.4 仍是未实测的方案。

### 3.1 家族重定向（单独做无效，见上表）

```powershell
$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontMapperFamilyFallback'
(Get-ItemProperty $key).PSObject.Properties |
  Where-Object { $_.Name -notmatch '^PS' -and $_.Value -match 'Yu Gothic UI|Microsoft JhengHei UI' } |
  ForEach-Object { Set-ItemProperty -Path $key -Name $_.Name -Value 'Microsoft YaHei UI' }
```

按**现有值**筛选而不是硬编码键名：这样不会在命令里写 CJK 字面量，也顺带覆盖 `新細明體`、`メイリオ` 这类非 ASCII 键名。

代价：日文 / 繁体内容也会显示成简体字形。只用简体中文的话可接受。

### 3.2 字体名替换（`Microsoft JhengHei UI` 自己没有 3.1 的条目，补这层；**未实测**）

```powershell
$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
$map = @{
  'MS UI Gothic'          = 'Microsoft YaHei UI'
  'Yu Gothic UI'          = 'Microsoft YaHei UI'
  'Meiryo UI'             = 'Microsoft YaHei UI'
  'Microsoft JhengHei UI' = 'Microsoft YaHei UI'
  'Microsoft JhengHei'    = 'Microsoft YaHei'
  'PMingLiU'              = 'Microsoft YaHei UI'
  'MS Gothic'             = 'Microsoft YaHei'
}
foreach ($k in $map.Keys) {
  New-ItemProperty -Path $key -Name $k -Value $map[$k] -PropertyType String -Force | Out-Null
}
```

别动表里已有的 `FangSong_GB2312` / `KaiTi_GB2312` 和 `,charset` 别名。

### 3.3 SystemLink 重排（**实测有效**：Explorer 文件名恢复简体雅黑）

```powershell
$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
$p = Get-ItemProperty $key
$faces = @($p.PSObject.Properties.Name | Where-Object {
  $_ -notmatch '^PS' -and $_ -match '^(Segoe UI|Tahoma|Microsoft Sans Serif|Lucida Sans Unicode)'
})
foreach ($f in $faces) {
  $v = @($p.$f)
  if ($v.Count -eq 0) { continue }
  $yh   = @($v | Where-Object { $_ -match 'MSYH|Microsoft YaHei' })
  $rest = @($v | Where-Object { $_ -notmatch 'MSYH|Microsoft YaHei' })
  if ($yh.Count -eq 0) { continue }
  Set-ItemProperty -Path $key -Name $f -Value ([string[]]($yh + $rest)) -Type MultiString
}
$disp = @((Get-ItemProperty $key).'Segoe UI Variable Display')
New-ItemProperty -Path $key -Name 'Segoe UI Variable' -Value ([string[]]$disp) -PropertyType MultiString -Force | Out-Null
```

`SystemLink` 下约 80 个 face，上面的正则只覆盖系统 UI 相关的族，不要全表乱改。值必须是 `REG_MULTI_SZ`（`-Type MultiString`），写错类型会让字体链接失效。

### 3.4 conhost（cmd / PowerShell 5.1，独立一层；**未实测**）

```powershell
$face = 'Sarasa Term SC'   # 必须等宽 + CJK；Microsoft YaHei 不是等宽，盒线会断
Get-ChildItem 'HKCU:\Console' | ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name FaceName -Value $face }
Set-ItemProperty -Path 'HKCU:\Console' -Name FaceName -Value $face
$tt = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Console\TrueTypeFont'
Set-ItemProperty -Path $tt -Name '0'   -Value $face
Set-ItemProperty -Path $tt -Name '936' -Value "*$face"
```

`932`（日文）那项别动。回归项：盒线字符（`│ ├ └`）不能断。

### 3.5 验证与回滚

- 注销重登；必要时重启 + 重启 `FontCache` 服务。
- 比对 2 里那张截图：`直 / 骨 / 每 / 海 / 令` 是否从繁体 / 日文字形变回简体雅黑。
- 回读类型：`reg query 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink' /v "Segoe UI"`，必须是 `REG_MULTI_SZ`。
- 回滚：`reg import "$out\FontLink.reg"` 等四份备份；改了哪个 hive 就恢复哪个。

如果 3.1–3.3 全做完 Explorer 仍不对，说明该控件走的是 DirectWrite **内置**系统回退表（按语言标签选字体），不吃 GDI 表。两条待验证备选：

1. 安装「中文(简体)补充字体」FOD，补齐 `MEIRYO.TTC` / `MINGLIU.TTC` / `GULIM.TTC` 等缺失文件。**必须先做 3.3 再装**：否则新装上的 `Meiryo` 会作为链首先命中。
2. `Set-WinUILanguageOverride -Language en-US` 先把显示语言钉成英文，再把 `zh-Hans-CN` 提到语言列表首位，让无语言标签的汉字按 `zh-Hans` 回退。UI 仍是英文，但 `Get-Culture` 会变，DWrite 是否跟随**没有实测过**——放最后，先备份语言列表。

---

## 4. 语言标签：搜狗会把 SG 改回 CN，且 `Set-WinUserLanguageList -Force` 会被它改回去

用户原始事实：本机原为「简体中文新加坡」，装搜狗后被安装程序强制改成「简体中文中国」。这不是错觉，而且**运行时也持续守护**。

实测：用标准 API 把第二语言写成 `zh-Hans-SG`（`New-WinUserLanguageList` + 复制全部 IME tips + `Set-WinUserLanguageList -LanguageList ... -Force`），同一进程 t0 回读是 `en-US, zh-Hans-SG`，**新进程 8 秒后读回 `en-US, zh-Hans-CN`**。`InputMethodTips` 是只读属性，`$zh.InputMethodTips = @(...)` 会报 `InvalidOperation`，只有末尾的 `Set-... -Force` 生效；那两条 `If the Windows Display Language has changed...` WARNING 是固定输出，显示语言并没变。

**有效的写法是直接写注册表，不触发设置广播**：

```powershell
Set-ItemProperty -Path 'HKCU:\Control Panel\International\User Profile' `
  -Name 'Languages' -Value ([string[]]@('en-US','zh-Hans-SG')) -Type MultiString
```

验证：t0、t+10 秒、跨进程等 30 秒，`Get-WinUserLanguageList` 与注册表都稳定为 `en-US, zh-Hans-SG`，3 个 `0804` IME tips 完整，`Get-UICulture` 仍 `en-US`。**未验证注销 / 重启后是否保持**（搜狗登录时初始化可能再次改回）；若被重置，再做登录脚本 / 计划任务的持久化，不要擅自杀输入法进程或删除 `User Profile\zh-Hans-CN` 子键。

注意：SG 与 CN 同属 `zh-Hans` 父类，这一步**不修字体**。

---

## 5. 历史会话考证：两个容易记反的结论

### 5.1 「幽灵键盘布局」是 Agent 的误判，不是机器症状

一次 PR 审核会话里，agent 在 **thinking** 中看到 `Preload 1=00000804, 2=00000409, 3=00000804`，就写下「this is a **stray state** … which IS the stray pattern」，套用了仓库文档里「卸载语言后残留布局」的模板。随后用户指出「本机当前是装了 Microsoft 自带的拼音输入法，和搜狗输入法，有两个中文输入法。是不是这个原因？」

继续核对后，agent 自己推翻：

- 「这状态其实是健康的」「这是正常编码，**不是幽灵布局**」；
- 文档说的残留是**代码不在允许集合里**的那些（如遗留的 `0000040c`），「这台机器一个都没有」；
- 「我之前的判断错了」「**你对，搜狗确实是那两个中文输入法之一。我把 GUID 认错了**」。

真正的规则：两个中文 IME 共用布局码 `0804`，Windows 为每个文本服务写一条 Preload 项 → `0804` 出现两次是**正常投影**。`Set-WinUserLanguageList -Force` 重新应用同一份列表就会让 Windows 自己归一掉重复项；`fix-keyboard-layouts.ps1` 的 `Clean-PreloadKey` 只删不在允许集合里的编码，对 `0804` 无能为力。文档里「德语 / 希腊语 / 俄语幽灵」来自另一次记录，且文档自承没有记下最终结果——**先问用户有没有这个症状，别从注册表快照反推**。

### 5.2 真正删掉中文语言的是脚本，不是搜狗

另一会话的 transcript 记录：清理脚本在 `23:26:01` 运行（**用户自己按文档里的用法命令触发的**），把 `zh-Hans-SG` 连同搜狗 + 微软拼音两个 IME tips 一起删掉，`Preload` 只剩 `00000409`。脚本的 keep list 硬编码 `@('en-US')`，这是它的设计目标，不是 bug。仓库文档里「dropped `zh-Hans-SG`」「keep en-US only costs」那段是**事后补写**的证据记录，不是当时的动机讨论。

搜狗的角色是**强改** `zh-Hans-SG` → `zh-Hans-CN`（并塞入第二个 `0804` tip，这才造成上面那个被误读的重复），**强删** `zh-Hans-SG` 的是脚本。两件事别合并。

---

## 6. 不要做

- 不改 Windows 显示语言（本任务前提）、不改 `Get-WinSystemLocale`（已是 `zh-SG` / ACP 936，与字体无关）。
- 不动 `HKCU\Control Panel\Desktop\WindowMetrics` 的 `lfCharSet`：现在是 `DEFAULT_CHARSET(1)`，改成 `134` 会让所有 UI 字体走 `SimSun` 映射，副作用大于收益。
- 不再跑 `fix-keyboard-layouts.ps1` 的默认参数：keep list 只有 `en-US`，会把中文语言再删一次；即使传 `-Keep`，脚本也把 `en-US` 放第一。
- 不把 Chrome 的 `zh-TW` 当成 Explorer 的解法；两层分开。
- `$PROFILE` 把 `CurrentUICulture` 钉成 `en-US` 让 PowerShell 报错保持英文，这是既有偏好，与字体无关，别误判成「没生效」。
