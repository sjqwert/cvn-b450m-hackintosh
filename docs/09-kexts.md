# 组件清单

[← 返回 README](../README.md)

本仓库 `EFI/` 里到底装了什么，每个是干什么的。

---

## 内核扩展（17 个）

| # | Kext | 版本 | 作用 | 可禁用 |
|---|---|---|---|---|
| 1 | **Lilu** | 1.7.3 | 补丁框架，其它 kext 的地基 | ❌ |
| 2 | **VirtualSMC** | 1.3.9 | 伪装 SMC 芯片，没它不能开机 | ❌ |
| 3 | **WhateverGreen** | 1.7.2 | 显卡补丁。**当前是禁用状态** | ✅ 已禁用 |
| 4 | **AppleALC** | 1.9.8 | 声卡 layout 定义 | ❌ |
| 5 | **SimpleHDA** | 1.0.0 | macOS 26 缺失的 AppleHDA 栈 | ❌ |
| 6 | **AMFIPass** | 1.4.1 | 放行未签名 kext | ❌ |
| 7 | **RestrictEvents** | 1.1.7 | CPU 名称 / 内存上报 | ⚠️ |
| 8 | **RealtekRTL8111** | 3.0.0 | 有线网卡 | ❌ |
| 9 | **NVMeFix** | 1.1.3 | NVMe 电源管理 | ⚠️ |
| 10 | **CtlnaAHCIPort** | 341.0.2 | AHCI 端口定义 | ⚠️ |
| 11 | **AppleMCEReporterDisabler** | 1.2 | 禁用 MCE 报告（AMD 必需） | ❌ |
| 12 | **USBToolBox** | 1.2.0 | USB 映射引擎 | ❌ |
| 13 | **UTBDefault** | 1.0 | USB 端口表（通用版） | ❌ |
| 14 | **BlueToolFixup** | 2.6.8 | 修正 macOS 12+ 的蓝牙检查 | ⚠️ |
| 15 | **BrcmPatchRAM3** | 2.6.8 | BCM 蓝牙固件上传 | ⚠️ |
| 16 | **BrcmFirmwareData** | 2.6.8 | BCM 固件数据 | ⚠️ |
| 17 | **RTLBluetoothFirmware** | 1.2.0 | Realtek 蓝牙固件（备用） | ✅ |

✅ 可禁用 = 不影响开机
⚠️ = 能禁但有功能损失
❌ = 禁了开不了机

### 加载顺序（重要）

`config.plist → Kernel → Add` 里的**数组顺序就是加载顺序**。

```
Lilu                          ← 必须第一个，其它都依赖它
AMFIPass
AppleMCEReporterDisabler
CtlnaAHCIPort
RealtekRTL8111
RestrictEvents
USBToolBox
UTBDefault
VirtualSMC
WhateverGreen                 ← 已禁用
AppleALC
SimpleHDA                     ← 必须在 AppleALC 之后
NVMeFix
BlueToolFixup
BrcmPatchRAM3                 ← 必须在 BrcmFirmwareData 之前
BrcmFirmwareData
RTLBluetoothFirmware
```

**两条硬规则：**

1. `Lilu` 永远在第一位
2. `BrcmPatchRAM3` 在 `BrcmFirmwareData` 之前（前者是驱动，后者是数据源）

---

## ACPI（4 个 SSDT）

| 文件 | 作用 | 内容 |
|---|---|---|
| `SSDT-EC.aml` | 提供 `EC` 设备 | 让系统认为有嵌入式控制器 |
| `SSDT-PLUG.aml` | `plugin-type = 1` | 让 XNU 加载 `X86PlatformPlugin` |
| `SSDT-USB-Reset.aml` | USB 复位 | 修正设备唤醒 |
| `SSDT-USBX.aml` | USB 供电参数 | 定义 `UsbPowerDelivery` |

全部是自己编译的最小 SSDT，没有从别人的 EFI 里搬来的大杂烩。

---

## UEFI 驱动（4 个）

| 文件 | 作用 | 必需 |
|---|---|---|
| `OpenRuntime.efi` | OpenCore 运行时服务 | ❌ 必需 |
| `HfsPlus.efi` | 读 HFS+ 分区 | 必需（Recovery 用） |
| `apfs_aligned.efi` | APFS 驱动（对齐修正版） | 必需 |
| `ResetNvramEntry.efi` | 菜单里的 Reset NVRAM 项 | 可选 |

---

## 工具（1 个）

| 文件 | 作用 |
|---|---|
| `NullMothSafe.efi` | 急救：不带显卡驱动启动一次（追加 `-nvoff`） |

菜单里注册了两次，显示为两个不同名字，指向同一个文件：

```
NullMoth: start once without the driver     ← 选这个
1401: Remove NVIDIA driver
```

**黑屏时用第一条。**

---

## 值得替换的组件

### UTBDefault.kext → 定制的 UTBMap.kext

`UTBDefault` 是通用端口表，不是为这块主板生成的。

定制方法：用 [USBToolBox](https://github.com/USBToolBox/tool) 扫描本机所有 USB 端口，生成专属映射。收益是所有端口都能正常工作、USB 3.0 速度正确。

### WhateverGreen 为什么是禁用的

它与 NVIDIA 驱动在帧缓冲路径上有冲突。实测开启后 `nvfb` 初始化失败。

**AMD 显卡用户**需要把它打开。

### RealtekRTL8111 版本必须是 3.0.0+

2.4.2（2021 年）不认识 macOS 26 (Tahoe) 的 AppleVTD 内存模型，会随机断网。3.0.0 的更新日志第一条就是 "Added support for AppleVTD under Tahoe"。

---

## 不包含什么

本仓库**刻意不包含**：

| 组件 | 原因 |
|---|---|
| NVRM / NVRMFB / NVAccel / NVRMAGDC / NMXAudio | NVIDIA 驱动是第三方闭源组件，版权在作者手里 |
| macOS 安装镜像 | 法律风险 |
| 三码（序列号 / MLB / UUID） | 已脱敏为占位符，每人必须自己生成 |
| 你的 config 备份 | 那是你的隐私，不是用来分享的 |

---

## 如何更新组件

1. 从各自的上游仓库下载新版
2. 替换 `EFI/OC/Kexts/` 下对应目录
3. **检查 `MinKernel` / `MaxKernel`** —— 新版可能改了支持范围
4. 检查加载顺序没变
5. 保留旧版一份，出问题能回滚

推荐用 [OCAT (OpenCore Auxiliary Tools)](https://github.com/ic005k/OCAuxiliaryTools) 做批量更新 —— 它能读取 `OpenCore.efi` 的实际版本，并从 Acidanthera 官方源同步 kext。
