# 音频：macOS 26 没有 AppleHDA 怎么办

[← 返回 README](../README.md)

这是本平台**最反直觉**的一个坑，也是很多人卡住的地方。

---

## 现象

装好 macOS 26 (Tahoe) 后，`系统设置 → 声音` 里**一个输出设备都没有**。只有 USB 摄像头的麦克风。

`system_profiler SPAudioDataType` 输出只列输入设备，没有 Line Out、没有扬声器。

AppleALC 加载了，`kextstat` 能看到，`alcid` 也设了，就是没声音。

---

## 根因

**macOS 26 移除了 `AppleHDA.kext`。**

Tahoe 支持的 Mac 全部带 T2 芯片，音频由 T2 处理，Apple 认为不再需要这个驱动。

问题在于：**AppleALC 的工作原理是「给 AppleHDA 打补丁」**。它本身不是驱动，是一组 `IOKitPersonalities` 和二进制补丁，作用对象是 `AppleHDA`。

底层驱动没了，AppleALC 加载了也只是空转 —— 它找不到要 patch 的目标。

```bash
# 自己验证一下
ls /System/Library/Extensions/AppleHDA.kext
# ls: /System/Library/Extensions/AppleHDA.kext: No such file or directory
```

---

## 三条路

社区在 Tahoe 上摸索出三种方案：

| 方案 | 原理 | 代价 |
|---|---|---|
| **VoodooHDA** | 完全独立的通用声卡驱动，不依赖 AppleHDA | 音质差，要放宽 SIP，爆音 |
| **KDK 提取 AppleHDA** | 从 Kernel Debug Kit 里把旧版 AppleHDA 装回系统卷 | 要改系统卷、破坏 Sealed Volume、每次系统更新重做 |
| **SimpleHDA** | Lilu 插件，引导时把原生 AppleHDA 栈注入内核 | 几乎无代价，系统更新后仍有效 |

本配置用 **SimpleHDA**。

### 为什么不用前两个

**VoodooHDA** 的音质问题是结构性的。它是从 FreeBSD 的 `snd_hda` 移植来的，混音器和采样率转换都比 Apple 的实现粗糙。日常听个响可以，但这不是"能用"的标准。

**KDK 方案** 技术上可行，但它要求把系统卷挂载为可写、关掉 Sealed Volume、装完再重新封装。这意味着：

- 每次 macOS 更新，改动全部丢失，要重做一遍
- 系统卷完整性被破坏，某些系统功能（如快速启动）会退化
- 一旦出错，可能要重装系统

**SimpleHDA** 是引导期注入，不碰系统卷。这是决定性优势。

---

## 配置

### kext 加载顺序

顺序错了不生效。

```
Lilu.kext                  ← 必须第一个
...
AppleALC.kext              ← 提供 layout 定义
SimpleHDA.kext             ← 注入 AppleHDA 栈
```

在 `config.plist → Kernel → Add` 里，数组顺序就是加载顺序。

### SimpleHDA 的内核版本限制

```xml
<key>MinKernel</key><string>25.0.0</string>
<key>MaxKernel</key><string>25.99.99</string>
```

Darwin 25 对应 macOS 26。写死范围是为了避免它被错误加载到旧系统上 —— 旧系统自带 AppleHDA，再注入一份会冲突。

> 如果你要用于 macOS 27+，需要把 `MaxKernel` 调大，或者改成空字符串。

### layout-id

ALC662 rev3 用 layout **15**。

两个地方都要设，缺一不可：

**1. boot-args**
```
alcid=15
```

**2. DeviceProperties**

```
PciRoot(0x0)/Pci(0x8,0x1)
    layout-id      = <0f000000>      ← 小端 4 字节，即 0x0F = 15
    alc-layout-id  = <0f000000>
```

注意 `layout-id` 在 plist 里是 **data 类型**不是数字，值是 little-endian。写 `15`（integer）不会生效。

### 为什么 hda-gfx 不需要

板载声卡不参与 HDMI 音频路由，不需要 `hda-gfx` 属性。显卡的 HDMI 音频由 NVIDIA 驱动自己处理，走另一条路径。

---

## 验证

### 系统层面

```bash
# 应该能看到 Realtek ALC662
system_profiler SPAudioDataType | grep -A5 "ALC662"

# 检查 AppleHDA 栈是否被注入
kextstat | grep -iE "applehda|simplehda"
```

正常输出里应该有：

```
Realtek ALC662 rev3 (Analog 2.0+HP/2.0)
  Default Output Device: Yes
  Default System Output Device: Yes
  Output Channels: 2
  Current SampleRate: 48000
```

### 实际发声

```bash
afplay /System/Library/Sounds/Glass.aiff
```

没声音但设备存在 → 检查 `layout-id` 是否为 data 类型、是否为 little-endian。

---

## 常见问题

### 设备出现了但没声音

1. 检查系统设置里的输出是否选到了 ALC662
2. 换一个 layout-id 试（ALC662 可试 5、7、11、15）
3. 确认 `SimpleHDA` 的 `MinKernel` 覆盖当前内核版本：

```bash
uname -r    # 25.x.x 对应 macOS 26
```

### 系统更新后没声音

通常不用处理。SimpleHDA 是引导期注入，系统更新不影响。

如果真没了，检查 `config.plist` 是否被 OpenCore 的更新流程重置。

### 开机默认输出跑到了 HDMI

这是预期行为 —— macOS 会记住上次的输出设备。如果显示器有扬声器，它可能被优先选中。

用 `tools/guard/` 里的守护进程可以固定默认输出设备。见 [tools/README.md](../tools/README.md)。

### 有爆音 / 断音

采样率不匹配。在「音频 MIDI 设置」里把输出格式固定为 `48000 Hz / 2ch / 24-bit`。

---

## 关于 ALC662 本身

ALC662 是 2007 年的入门级 codec，板载实现通常只有：

- Line Out（绿色，接音箱/耳机）
- Line In（蓝色，多数板子省略）
- Mic In（粉色）

没有独立的前置耳机检测，没有光纤输出。别指望它推高阻耳机。

如果你在意音质，外接 USB DAC 是更好的选择 —— 免驱、绕过 codec、不受 macOS 音频栈变动影响。
