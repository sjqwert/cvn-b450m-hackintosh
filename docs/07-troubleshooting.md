# 故障排查

[← 返回 README](../README.md)

下面每一条都是在本平台上真实遇到并解决的，不是从教程抄的。

---

## 启动项全丢了，进不去系统

### 症状

BIOS 里能看到硬盘，但"启动项"列表是空的。或者每次都靠固件回退到 `\EFI\BOOT\BOOTX64.EFI` 才能进系统。

OpenCore 报：

```
OCB: BootOrder/BootNext are not present or unsupported 0 0
```

### 原因

NVRAM 里的 `efi-boot-device` 与 `Boot####` 变量被清空了。

**最常见的原因是用了 AFU 的 `/n` 参数**（`/n` = Program NVRAM）。某些主板的 AFU 实现会在每次开机时重写 NVRAM，把启动项冲掉。

### 救法

用 UEFI Shell 重建启动项。把下面这段存成 `RESTORE.nsh`（**必须 CRLF 行尾**，见下一节）：

```
echo -off
map -r
fs0:
if exist \EFI\OC\OpenCore.efi then
  goto Found
endif
fs1:
if exist \EFI\OC\OpenCore.efi then
  goto Found
endif
fs2:
if exist \EFI\OC\OpenCore.efi then
  goto Found
endif
:Found
echo 找到 OpenCore，当前盘符：
pwd
pause
bcfg boot dump -v
bcfg boot add 0 \EFI\OC\OpenCore.efi "OpenCore"
bcfg boot dump -v
pause
```

执行后 `bcfg boot dump -v` 应该能看到新增的 `Boot0000`。

### 验证

```bash
# 在 macOS 里看
nvram -p | grep -i "efi-boot-device\|Boot"
```

正常的机器会有 `efi-boot-device` 和至少一个 `Boot####`。

### 永久修复

如果 BIOS 里没有 `LauncherOption` 相关项，可以在 `config.plist` 里设：

```xml
<key>Misc</key>
<dict>
  <key>Boot</key>
  <dict>
    <key>LauncherOption</key><string>Full</string>
  </dict>
</dict>
```

`Full` 会让 OpenCore 在每次启动时主动维护 `Boot####` 变量，即使被清空也会重建。

---

## UEFI Shell 脚本报 "echo: Unknown flag"

### 症状

```
Shell> fs0:\startup.nsh
echo: Unknown flag - '-off'
```

后面所有 `if exist` / `goto` 全部失效。

### 原因

**脚本是 LF 行尾。** UEFI Shell 只认 CRLF，LF-only 时换行符会被并入 token，`echo -off\r` 变成 `echo -off` 但解析器把 `-off` 当成未知 flag。

另外 `@echo -off` 的 `@` 前缀在 UEFI Shell 里也不认。

### 修复

```bash
# 检查
file startup.nsh
# 显示 "ASCII text" 就是 LF；"ASCII text, with CRLF line terminators" 才对

# 转换
python3 -c "
import sys
p = 'startup.nsh'
s = open(p, encoding='utf-8').read().replace('\r\n','\n').replace('\r','\n')
open(p, 'w', encoding='utf-8', newline='\r\n').write(s)
"

# 验证
hexdump -C startup.nsh | head -3
# 应该看到 0d 0a 结尾
```

同时去掉 `@` 前缀，`echo -off` 不要写成 `@echo -off`。

---

## macOS 里看不到 EFI 分区（File System: None）

### 症状

`diskutil list` 能看到 EFI 分区，但 `diskutil mount` 报：

```
Volume on diskXs1 failed to mount
```

Finder 里显示 `File System: None`。

### 原因

**macOS 的 DiskArbitration 拒绝挂载类型为 `0x1B` 的隐藏分区。** 这不代表分区坏了 —— 直接读扇区能看到完好的 FAT32 引导记录。

### 验证分区确实完好

```bash
sudo dd if=/dev/rdiskXs2 bs=512 count=1 2>/dev/null | hexdump -C | head -8
```

应该看到 `eb 58 90` 开头、`FAT32` 字样的 BPB。

### 绕过

```bash
sudo mkdir -p /tmp/esp
sudo mount -t msdos /dev/diskXs1 /tmp/esp
```

**注意用 `/dev/diskXs1` 而不是 `/dev/rdiskXs1`。** `rdisk` 是原始设备，`mount_msdos` 不认。

用完卸载：

```bash
sudo umount /tmp/esp
```

> `diskutil unmountDisk force` 对手动 `mount_msdos` 挂的卷无效，必须用 `umount`。

---

## 改了分区表后 UEFI Shell 报 Media Changed

### 症状

```
Shell: Cannot read from file - Media Changed
```

### 原因

`EFI_MEDIA_CHANGED`。改了分区表之后，固件里缓存的块设备句柄失效了。

### 修复

```
map -r
```

重新扫描。不行就重启。

---

## 开机黑屏（有背光无画面）

### 检查顺序

**1. BIOS 的 Above 4G / Re-Size BAR 是否都开了**

见 [02-bios.md](02-bios.md)。这是最常见原因。

**2. `Booter → Quirks → ResizeAppleGpuBars` 是不是被改成了 `0`**

必须是 `-1`。设 `0` 会把 BAR1 压到 64 MB，驱动初始化失败。

**3. 用急救工具启动一次**

OpenCore 菜单里选：

```
NullMoth: start once without the driver
```

它会追加 `-nvoff`，不带驱动启动。能进桌面说明是驱动问题，不是硬件问题。

**4. 进系统后看日志**

```bash
log show --last 5m --predicate 'process == "kernel"' | grep -i "nvrm\|bar1\|window"
```

看到 `small firmware window` 或 `REFUSED` 就是 BAR 不够。

---

## 卡在启动代码

macOS 启动时的进度代码含义：

| 代码 | 含义 | 排查方向 |
|---|---|---|
| `+++++++` | 内存初始化 | 内存条松动、频率不稳 |
| `EB` | `EXITBS` 前 | 通常是 `RebuildAppleMemoryMap` 或 `SyncRuntimePermissions` |
| `EXITBS` 后黑屏 | 引导完成，显卡没接手 | 显卡驱动、BAR 设置 |
| `still waiting for root device` | 找不到系统盘 | AHCI 模式没开、`CtlnaAHCIPort` 版本不对 |
| `AMFI: ... denied` | AMFI 拦了未签名 kext | 检查 `amfi=0x80`、AMFIPass |

`-v` 要保留着。调好了再去掉。

---

## 系统盘 ESP 里没有引导文件

### 症状

拔掉 U 盘就进不去系统。

### 检查

```bash
./scripts/mount-efi.sh
ls /tmp/esp/EFI/OC/OpenCore.efi
```

不存在就是没有。

### 修复

把 U 盘上的 `EFI/` 整个拷过去：

```bash
./scripts/mount-efi.sh
ditto --noextattr --norsrc ./EFI /tmp/esp/EFI
```

**必须用 `ditto --noextattr --norsrc`**，普通 `cp` 会在 FAT32 上生成 `._` 开头的垃圾文件，某些固件会因此卡住。

---

## USB 端口不对（部分口不能用）

`UTBDefault.kext` 是通用映射，不是为这台机器定制的。

要定制：

1. 在 Windows 或 macOS 里用 [USBToolBox](https://github.com/USBToolBox/tool) 扫描所有端口
2. 逐个插拔设备，标记每个物理口
3. 生成 `UTBMap.kext`，替换 `UTBDefault.kext`

不做的后果：某些端口可能不供电、或者 USB 3.0 设备只能跑 2.0。

---

## 音频没声音

见 [03-audio.md](03-audio.md)。最常见的两个原因：

1. `layout-id` 写成了 integer 而不是 data
2. `SimpleHDA.kext` 的 `MinKernel` 没覆盖当前内核

```bash
uname -r     # 25.x.x 对应 macOS 26
```

---

## 系统更新后进不去

1. 先看 `-v` 卡在哪
2. 用急救工具 `NullMoth: start once without the driver` 进系统
3. 检查 NVIDIA 驱动是否兼容新系统版本
4. 记着：**驱动升级后第一次启动必然慢**（着色器缓存失效），别当成故障

---

## 通用排查手段

### 打开详细日志

`config.plist`：

```xml
<key>Misc</key>
<dict>
  <key>Debug</key>
  <dict>
    <key>Target</key><integer>67</integer>       <!-- 输出到文件 + 屏幕 -->
    <key>DisplayLevel</key><integer>2147483650</integer>
  </dict>
</dict>
```

日志文件在 ESP 根目录的 `opencore-YYYY-MM-DD-HHMMSS.txt`。

### 对比配置差异

```bash
plutil -convert xml1 -o - config.plist | diff -u - old.plist
```

### 验证 config.plist 语法

```bash
plutil -lint config.plist
```

### 检查 kext 是否加载

```bash
kextstat | grep -v com.apple
```

---

## 最后手段：从别的机器修

拆下硬盘（或 U 盘），插到另一台电脑：

1. 挂载 EFI 分区
2. 把 `config.plist` 改名成 `config.plist.broken`
3. 复制一份已知可用的备份为 `config.plist`
4. 推出，插回本机

**养成习惯：每次改 `config.plist` 前先备份一份。**
