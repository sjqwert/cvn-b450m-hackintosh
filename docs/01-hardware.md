# 硬件与兼容性

[← 返回 README](../README.md)

---

## 平台

| 项 | 值 |
|---|---|
| CPU | AMD Ryzen 5 3500X |
| 代号 | Matisse（Zen 2） |
| 核心/线程 | 6C / 6T |
| 基准/加速 | 3.6 / 4.1 GHz |
| L3 | 32 MB |
| 主板 | 七彩虹 CVN B450M GAMING V14 |
| 芯片组 | AMD B450 |
| 版型 | mATX，245 × 245 mm |
| UEFI | 128 Mbit（16 MB），最新 1012 |
| 双 BIOS | **无** |
| FlashBack | **无** |
| 内存 | 16 GB DDR4-2667 双通道 |
| 显卡 | NVIDIA RTX 2080 Ti 22 GB |
| GPU 核心 | TU102 |
| Device ID | `0x1e04` |
| 声卡 | Realtek ALC662 rev3 |
| 有线网卡 | Realtek RTL8111 |
| 蓝牙 | Broadcom BCM4350C2（UART） |

### 关键短板：没有双 BIOS，没有 FlashBack

这块板子刷坏 BIOS 只能靠 **CH341A 编程器夹 SPI 芯片**救。没有第二颗 BIOS，没有一键回刷按钮。

这一点决定了本平台上任何 BIOS 层面的实验（比如为了扩 ReBAR 而改固件）风险等级都是"需要拆机 + 有编程器"。见 [06-known-issues.md](06-known-issues.md)。

---

## 为什么伪装 MacPro7,1

AMD 平台可选机型不多：`iMacPro1,1`、`MacPro7,1`、`iMac20,x`。

选 `MacPro7,1` 的理由：

| 理由 | 说明 |
|---|---|
| 无核显 | MacPro7,1 本来就不带 iGPU，不需要处理 `framebuffer-patch-enable` 那套 |
| 无 T2 | 避开了 T2 相关的启动与安全策略 |
| AGDP 宽松 | 独显输出不需要 `board-id` 白名单补丁 |
| 内存上报简单 | 用 `RestrictEvents` 的 `revpatch=sbvmm` 直接上报真实容量，不会出现"内存警告" |

代价：`MacPro7,1` 的 PCI 拓扑和真实机器不符，某些依赖机型判断的软件（如部分 Adobe 组件）可能表现异常。

---

## 兼容性逐项

### CPU

AMD 需要 27 条内核补丁，全部在 `Kernel → Patch` 里，来源是 AMD OSX 社区。核心是三类：

1. **品牌伪造** — `_cpuid_set_info` 里 `GenuineIntel` → `AuthenticAMD`
2. **MSR 屏蔽** — AMD 没有 Intel 的 `MSR_IA32_PLATFORM_ID` 等寄存器，`rdmsr`/`wrmsr` 会 `#GP`，必须替换成 `xor eax,eax; ret`
3. **MTRR 修正** — 内存类型寄存器语义不同，不打补丁会导致显存区域被标成 uncached，显卡性能崩溃

`ProvideCurrentCpuInfo` 打开后，系统能读到正确的核心数与缓存层级。

### 显卡

见 [05-nvidia.md](05-nvidia.md)。简要：靠第三方驱动 + 一组 boot-args，能拿到 Metal 3 与硬件加速，但受 256 MB BAR1 限制。

### 声卡

ALC662 rev3，layout-id 15。macOS 26 移除了 `AppleHDA.kext`，需要 SimpleHDA 补回音频栈。见 [03-audio.md](03-audio.md)。

### 网卡

RTL8111，用 Mieze 的 `RealtekRTL8111.kext` 3.0.0。**必须 ≥ 3.0.0**，2.4.2 不认识 Tahoe 的 AppleVTD 内存模型，会随机断网。

### 蓝牙

BCM4350C2，UART 接口。当前识别但 `State: Off`。见 [04-bluetooth.md](04-bluetooth.md)。

### 存储

NVMe SSD + `NVMeFix.kext` 处理电源管理。SATA 需要 `CtlnaAHCIPort.kext` 补端口定义。

### USB

`USBToolBox.kext` + `UTBDefault.kext`。`UTBDefault` 是通用映射，**如果你要定制端口，需要用 USBToolBox 在自己机器上重新生成**。见 [07-troubleshooting.md](07-troubleshooting.md)。

### 电源管理

`SSDT-PLUG.aml` 提供 `plugin-type=1`，让 XNU 加载 `X86PlatformPlugin`。AMD 平台不需要 `SSDT-PM`。

### 睡眠

`PowerTimeoutKernelPanic` 打开，避免睡眠超时导致的 panic。实测睡眠/唤醒正常，但唤醒后约 3 秒内 UI 会有轻微卡顿。

---

## 与"能用"的差距

诚实地说，这套配置在以下场景**不够好**：

- **视频剪辑** — 硬件解码能力上报缺陷导致软解兜底，4K 时间线会卡
- **多显示器** — BAR1 预算被摊薄，第二块屏可能触发显存分配失败
- **大型 3D 场景** — 着色器冷编译 + 显存抖动，首次加载慢
- **任何需要 Secure Boot 的场景** — 不可能

够用的场景：日常办公、网页、终端开发、轻度图片处理、1080p 视频播放。

---

## 参考

- [AMD OSX 论坛](https://amd-osx.com/) — AMD 平台补丁的源头
- [Dortania OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/) — 通用流程
- [r/Hackintosh](https://www.reddit.com/r/hackintosh/) — 排障
