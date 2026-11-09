# 七彩虹 CVN B450M GAMING · Ryzen 5 3500X · RTX 2080 Ti — Hackintosh EFI

> macOS 26.7.2 Tahoe (25G332) 在 AMD B450 + NVIDIA Turing 上的可用配置
> 已连续运行验证，音频 / 显卡加速 / 有线网络 / 睡眠 均可工作

**Language**：[中文](#) · [硬件配置](#硬件配置) · [快速开始](#快速开始) · [已知限制](#已知限制)

---

## 这是什么

一套在 **AMD Ryzen 平台 + NVIDIA RTX 20 系显卡** 上运行 macOS 26 (Tahoe) 的 OpenCore 配置。

大多数人认为这条路走不通：macOS 从 10.14 Mojave 起就不再支持 NVIDIA 显卡。这套配置能跑起来，靠的是三点：

1. **AMD 内核补丁**（algrey / Shaneee / CaseySJ 等社区多年积累的 `cpuid` 与 `mtrr` 补丁）
2. **第三方 NVIDIA 驱动**（NullMoth，Non-Apple 移植，见 [docs/05-nvidia.md](docs/05-nvidia.md)）
3. **macOS 26 移除 AppleHDA 后的音频替代方案**（SimpleHDA，见 [docs/03-audio.md](docs/03-audio.md)）

它能满足日常使用和轻度图形工作，但**不是一台 Mac**。硬件层面的限制（尤其是 256 MB 的 BAR1 窗口）无法通过配置解决，详见 [已知限制](#已知限制)。

---

## 硬件配置

| 部件 | 型号 | 状态 |
|---|---|---|
| CPU | AMD Ryzen 5 3500X（Zen 2，6C/6T） | ✅ 需内核补丁 |
| 主板 | 七彩虹 CVN B450M GAMING V14（B450，mATX） | ✅ |
| 内存 | 16 GB DDR4-2667 双通道 | ✅ |
| 显卡 | NVIDIA RTX 2080 Ti 22 GB（TU102，`0x1e04`） | ⚠️ 第三方驱动 |
| 声卡 | Realtek ALC662 rev3 | ✅ layout-id 15 |
| 有线网卡 | Realtek RTL8111 | ✅ |
| 蓝牙 | Broadcom BCM4350C2（UART） | ⚠️ 见 [docs/04](docs/04-bluetooth.md) |
| 存储 | NVMe SSD | ✅ NVMeFix |
| 引导 | OpenCore（Dortania 构建 2026-10-30） | ✅ |
| 系统 | macOS 26.7.2 Tahoe · Build 25G332 | ✅ |

> 机型伪装为 **MacPro7,1**。这个机型没有核显、没有 T2，是 AMD 平台最省事的选择。

### 功能状态

| 功能 | 状态 | 说明 |
|---|---|---|
| 开机 / 关机 / 重启 | ✅ | |
| 显卡硬件加速（Metal 3） | ✅ | 依赖 NullMoth 驱动 |
| HDMI / DP 音频输出 | ✅ | 显卡自带，4 路 |
| 板载声卡 ALC662 | ✅ | SimpleHDA + `alcid=15` |
| 有线网络 | ✅ | AppleVTD 兼容 |
| 睡眠 / 唤醒 | ✅ | |
| USB 端口映射 | ✅ | USBToolBox + UTBDefault |
| 蓝牙 | ⚠️ | 芯片识别为 BCM_4350C2，功能待完善 |
| AirDrop / 隔空投送 | ❌ | 需要支持的 Wi-Fi + 蓝牙组合卡 |
| iMessage / FaceTime | ⚠️ | 需自行生成三码，见 [docs/08](docs/08-smbios.md) |
| 硬件视频编解码 | ⚠️ | 首次查询返回 NO，见 [docs/05](docs/05-nvidia.md) |

---

## 快速开始

### 前提

- 一块 **≥ 512 MB 的 U 盘**（FAT32）
- 已在另一台电脑上准备好 macOS 安装盘（本仓库只含引导，不含系统）
- 会改 BIOS 设置，能接受"刷坏了要拆机"的风险

### 第 1 步：BIOS 设置

开机按 `Del` 进 BIOS，按下面逐项设置。**这一步做错，后面全部白费。**

```
Advanced Mode → Advanced → ACPI Settings
    ACPI Auto Configuration ............ Disabled

Advanced Mode → AMD CBS → NBIO Common Options
    4G以上 MMIO 资源分配 (Above 4G Decoding) ... Enabled     ← 必须
    Re-Size BAR Support .................... Enabled        ← 必须

Advanced Mode → 主板芯片组 → PCH 设置
    SATA Mode .............................. AHCI

Boot
    Fast Boot .............................. Disabled
    CSM Support ............................ Disabled
    Secure Boot ............................ Disabled
    Boot Mode .............................. UEFI only

    BIOS Write Protect ..................... Disabled       （如有此项）
```

> **Above 4G Decoding 与 Re-Size BAR 是显卡能驱动的必要条件。**
> 关掉任意一项，开机会黑屏。这一点在本平台上反复验证过。

### 第 2 步：把 EFI 拷到 U 盘

U 盘格式化为 **FAT32**、分区表 **GPT**，把本仓库的 `EFI/` 整个目录拷到根目录：

```
/EFI
  /BOOT
    BOOTx64.efi
  /OC
    OpenCore.efi
    config.plist
    ACPI/ Drivers/ Kexts/ Resources/ Tools/
```

### 第 3 步：生成你自己的三码

**不要直接用仓库里的 `config.plist` 开 iMessage。** 里面的序列号是占位符。

用 [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) 生成 MacPro7,1 的 `SystemSerialNumber` / `MLB` / `SystemUUID`，再用 [MACSerial](https://github.com/acidanthera/OpenCorePkg) 或直接取网卡 MAC 填 `ROM`。

详见 [docs/08-smbios.md](docs/08-smbios.md)。

### 第 4 步：启动

1. U 盘插上，开机按 `F11`（或 `F8`）调出启动菜单，选 U 盘
2. OpenCore 菜单里选 `Install macOS` 或已装好的系统盘
3. 首次启动会走 `-v` 详细模式，看滚动日志

能进桌面后，把 `EFI/` 拷到系统盘的 ESP 分区，让机器脱离 U 盘独立启动。

### 第 5 步（可选）：安装系统侧补丁

`tools/` 里是几个让体验完整的辅助脚本，**不是必须的**：

| 工具 | 作用 |
|---|---|
| `tools/guard/` | 开机自动恢复音频输出设备 + 呈现模式 |
| `tools/diagnostics/` | 显卡通道体检、呈现模式检查、显存占用采样 |
| `tools/extras/` | 亮度条、摄像头预览（源码） |

用法见 [tools/README.md](tools/README.md)。

---

## 目录结构

```
.
├── EFI/                        OpenCore 引导（整体拷入 ESP 根目录）
│   ├── BOOT/BOOTx64.efi
│   └── OC/
│       ├── config.plist        ← 三码已脱敏，需自行生成
│       ├── ACPI/               4 个 SSDT
│       ├── Drivers/            OpenRuntime / HfsPlus / apfs_aligned / ResetNvramEntry
│       ├── Kexts/              17 个内核扩展
│       ├── Resources/          OpenCanopy 图标与字体
│       └── Tools/NullMothSafe.efi   黑屏急救工具
├── docs/                       分专题文档
│   ├── 01-hardware.md          硬件与兼容性分析
│   ├── 02-bios.md              BIOS 逐项设置与原理
│   ├── 03-audio.md             ALC662 + SimpleHDA（macOS 26 无 AppleHDA 的解法）
│   ├── 04-bluetooth.md         蓝牙现状与换卡建议
│   ├── 05-nvidia.md            NVIDIA 驱动、boot-args、性能实测
│   ├── 06-known-issues.md      已知限制与根因
│   ├── 07-troubleshooting.md   黑屏 / 卡代码 / 启动项丢失的救法
│   ├── 08-smbios.md            三码生成
│   └── 09-kexts.md             组件清单与加载顺序
├── tools/                      系统侧脚本
└── scripts/                    辅助脚本（挂载 ESP 等）
```

---

## 关键配置说明

### boot-args

```
-v keepsyms=1 debug=0x100
alcid=15
nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth gfxrst=4
nvrmsettle=10000 nvfbhidpi=1 -nvrmnobootscreen
amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0 -amfipassbeta
revpatch=sbvmm,cpuname
npci=0x2000
```

| 参数 | 作用 |
|---|---|
| `-v keepsyms=1 debug=0x100` | 详细模式 + 保留符号 + 禁用看门狗。**调好之后可以去掉** |
| `alcid=15` | AppleALC 的 ALC662 layout-id |
| `nvfb=1` `nvaccel=1` | 启用 NVIDIA 帧缓冲与硬件加速 |
| `nvfbheads=4` | 显示头数量（驱动默认值，实测改成 2 无任何效果） |
| `-nvkmsnosmooth` | 关闭驱动的逐帧平滑，降低卡顿感 |
| `gfxrst=4` | 显卡复位策略 |
| `nvrmsettle=10000` | 驱动初始化等待 10 秒，避免开机时序竞争 |
| `nvfbhidpi=1` | 允许 HiDPI 分辨率 |
| `-nvrmnobootscreen` | **关键**。不把 UEFI 开机画面快照进 BAR1，省出约 15 MB |
| `amfi_get_out_of_my_way=0x1` `amfi=0x80` | 放行未签名 kext（AMFIPass 配套） |
| `ipc_control_port_options=0` | 修正 AMD 平台的 IPC 端口 |
| `revpatch=sbvmm,cpuname` | RestrictEvents：上报真实内存大小 + 自定义 CPU 名称 |
| `npci=0x2000` | 修正 PCI 配置空间扫描 |

`-nvrmnobootscreen` 值得单独说明：那张开机画面快照是 `2560×1440×4 = 14,745,600` 字节，正好等于一帧。BAR1 预算本来就被占满，关掉它才腾得出一帧给 WindowServer 做零拷贝翻页。详见 [docs/05](docs/05-nvidia.md)。

### 安全设置

```
SecureBootModel       = Disabled
Vault                 = Optional
csr-active-config     = 0x0A43
```

`0x0A43` 展开：

| 位 | 含义 | 值 |
|---|---|---|
| `1<<9` | 允许未批准 kext | 开 |
| `1<<11` | 允许未认证根卷 | 开 |
| `1<<1` | 关闭文件系统保护 | 开 |
| `1<<6` | 允许无限制 NVRAM | 开 |
| `1<<3` | 内核调试器 | 关 |
| `1<<5` | DTrace 限制 | 关（保留限制） |

SIP 处于这种半开状态是必要的：NVIDIA 驱动是未签名 kext，必须放行。**代价是系统完整性保护不完整**，这也是本配置不适合当生产机的另一个原因。

### 内核补丁

`Kernel → Patch` 里有 27 条，全部来自 AMD OSX 社区。删不得：

- `_cpuid_set_info` · GenuineIntel → AuthenticAMD
- `_cpuid_set_cpufamily` · 强制 `CPUFAMILY_INTEL_PENRYN`
- `_cpuid_set_cache_info` / `_cpuid_set_generic_info` · 绕开 Intel 专有 MSR
- `_commpage_populate` / `_i386_init` · 移除 `rdmsr`
- `_mtrr_update_action` · 修正 PAT（内存类型，显卡稳定性的关键）
- `IOPCIFamily` · 关闭 10-bit tag（Tahoe 上必须）
- `thread_quantum_expire` 等 · 调度器时序修正

### Quirks 要点

| 位置 | 项 | 值 | 为什么 |
|---|---|---|---|
| Booter | `ResizeAppleGpuBars` | `-1` | **不要设 0**。设 0 会把 BAR1 压回 64 MB，NVIDIA 驱动需要 ≥ 256 MB，直接黑屏 |
| Booter | `RebuildAppleMemoryMap` | 开 | AMD 平台必需 |
| Booter | `SyncRuntimePermissions` | 开 | 同上 |
| Kernel | `ProvideCurrentCpuInfo` | 开 | 让系统读到正确的 CPU 拓扑 |
| Kernel | `CustomSMBIOSGuid` | 开 | 配合 `UpdateSMBIOSMode = Custom` |
| UEFI | `ResizeGpuBars` | `-1` | 固件侧同理，让固件决定 BAR 大小 |
| UEFI | `RequestBootVarRouting` | 开 | 保护 `Boot####` 变量不被系统改写 |
| UEFI | `ReleaseUsbOwnership` | 开 | 交接 USB 控制器 |

---

## 已知限制

这些**不是配置错误**，是硬件或系统层面的死结。详细推导见 [docs/06-known-issues.md](docs/06-known-issues.md)。

### 1. BAR1 只有 256 MB

这块卡的 BAR1 窗口是 256 MB，而 macOS 的 `IOFramebuffer` 要求扫描输出缓冲必须落在 CPU 可映射的 BAR1 里。

```
256 MB = 扫描缓冲 56.5 MB + 加速器预算 183.5 MB + 守卫 16 MB
```

账刚好平，一个字节不剩。后果：

- 所有显示更新走「拷贝」而非「翻页」（`nvaccel_iop_flip` 恒为 0）
- 每秒约 145 次整帧显存申请失败
- 拖动窗口、滚动列表发涩

**尝试过的解法**：改 VBIOS 扩 ReBAR 能力位（Turing VBIOS 只声明 64/128/256 MB 三档，能力位掩码 `0x1c0`）、刷修改版 BIOS（被 AMI Secure Flash 签名校验拦住，零写入）。

**真正的出路**只有两条：

- **A.** 改 VBIOS 扩 ReBAR 能力位（需 Windows + `nvflash`，有变砖风险）
- **B.** 加一张 macOS 原生支持的 AMD 卡做显示输出，RTX 只做计算

### 2. 硬件视频编解码首次查询返回 NO

每个进程第一次查询硬件解码能力总是返回 `NO`，导致剪辑/渲染软件误判为"无硬解"，退回 CPU 软解。这是驱动的能力位上报缺陷，用户侧无法修复。

### 3. 着色器冷编译慢

每个 kernel 编译耗时 5–9 ms，大型工程首次打开累计可达数十秒。可开启驱动侧 SASS 缓存缓解。

### 4. 蓝牙

BCM4350C2 被识别为 `BCM_4350C2`，但 `State: Off`。完整讨论见 [docs/04-bluetooth.md](docs/04-bluetooth.md)。

### 5. Secure Boot 被完全关闭

未签名 kext 与 Secure Boot 不可共存。这台机器上 Secure Boot 永远是关的。

---

## 免责声明

**这是一个实验性配置，不是产品。**

- 刷 BIOS、改 EFI 有**变砖**风险。本仓库作者不对任何数据丢失、硬件损坏负责。
- `config.plist` 里的三码是占位符。**填入他人序列号可能导致 Apple ID 被封**。
- 本仓库**不分发** NVIDIA 驱动本身（NullMoth 为闭源第三方组件），只提供配置参数。
- macOS 的使用需遵守 Apple 的最终用户许可协议。黑苹果在多数司法辖区处于法律灰色地带，请自行判断。
- 不提供 Apple 服务（iMessage、iCloud、App Store）的可用性保证。

**如果你在找一台稳定工作的 Mac，请买一台 Mac。**

---

## 致谢

这套配置站在很多人的肩膀上：

| 项目 | 作者 | 用途 |
|---|---|---|
| [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg) | Acidanthera | 引导器 |
| [Lilu](https://github.com/acidanthera/Lilu) / [WhateverGreen](https://github.com/acidanthera/WhateverGreen) / [VirtualSMC](https://github.com/acidanthera/VirtualSMC) | Acidanthera | 内核补丁框架 |
| [AppleALC](https://github.com/acidanthera/AppleALC) | Acidanthera | 声卡 |
| [RestrictEvents](https://github.com/acidanthera/RestrictEvents) | Acidanthera | CPU 名称与内存上报 |
| [NVMeFix](https://github.com/acidanthera/NVMeFix) | Acidanthera | NVMe 电源管理 |
| [RealtekRTL8111](https://github.com/Mieze/RTL8111_driver_for_OS_X) | Mieze | 有线网卡 |
| [USBToolBox](https://github.com/USBToolBox/tool) | USBToolBox | USB 映射 |
| [AMFIPass](https://github.com/dhinakg/AMFIPass) | dhinakg | AMFI 放行 |
| [CtlnaAHCIPort](https://github.com/outtaym/CtlnaAHCIPort) | outtaym | AHCI 端口 |
| AMD 内核补丁 | algrey / Shaneee / CaseySJ / XLNC / Visual / Zormeister | `cpuid`、`mtrr`、`IOPCIFamily` |
| [AMD OSX](https://amd-osx.com/) | 社区 | 全部 AMD 平台知识的来源 |
| NullMoth / SimpleHDA | laobamac | NVIDIA 驱动、macOS 26 音频栈 |

本仓库自身的配置、文档与脚本以 MIT 协议发布，第三方组件遵循各自协议。

---

## 相关文档

- [硬件与兼容性](docs/01-hardware.md)
- [BIOS 设置](docs/02-bios.md)
- [音频：macOS 26 没有 AppleHDA 怎么办](docs/03-audio.md)
- [蓝牙](docs/04-bluetooth.md)
- [NVIDIA 显卡：驱动、参数与实测性能](docs/05-nvidia.md)
- [已知限制与根因](docs/06-known-issues.md)
- [故障排查](docs/07-troubleshooting.md)
- [三码生成](docs/08-smbios.md)
- [组件清单](docs/09-kexts.md)
- [工具说明](tools/README.md)
