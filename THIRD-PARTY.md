# 第三方组件

[← 返回 README](README.md)

`EFI/OC/` 里的二进制不全是本仓库作者的作品。这里逐项列出归属。

**本仓库自身的配置文件、文档与脚本以 [MIT](LICENSE) 发布。下面这些遵循各自协议。**

---

## 引导器与运行时

| 组件 | 协议 | 作者 / 来源 |
|---|---|---|
| `OpenCore.efi` · `OpenRuntime.efi` · `BOOTx64.efi` · `ResetNvramEntry.efi` | BSD-3-Clause | [Acidanthera / OpenCorePkg](https://github.com/acidanthera/OpenCorePkg) |
| `HfsPlus.efi` | Apple 专有（可再分发） | Apple Inc. |
| `apfs_aligned.efi` | 社区修改版（源自 Apple APFS EFI 驱动） | 社区 |

## 内核扩展

| 组件 | 版本 | 协议 | 作者 / 来源 |
|---|---|---|---|
| `Lilu.kext` | 1.7.3 | BSD-3-Clause | [Acidanthera](https://github.com/acidanthera/Lilu) |
| `VirtualSMC.kext` | 1.3.9 | BSD-3-Clause | [Acidanthera](https://github.com/acidanthera/VirtualSMC) |
| `WhateverGreen.kext` | 1.7.2 | BSD-3-Clause | [Acidanthera](https://github.com/acidanthera/WhateverGreen) |
| `AppleALC.kext` | 1.9.8 | BSD-3-Clause | [Acidanthera](https://github.com/acidanthera/AppleALC) |
| `RestrictEvents.kext` | 1.1.7 | BSD-3-Clause | [Acidanthera](https://github.com/acidanthera/RestrictEvents) |
| `NVMeFix.kext` | 1.1.3 | BSD-3-Clause | [Acidanthera](https://github.com/acidanthera/NVMeFix) |
| `BrcmPatchRAM3.kext` · `BrcmFirmwareData.kext` · `BlueToolFixup.kext` | 2.6.8 | BSD-3-Clause | [Acidanthera](https://github.com/acidanthera/BrcmPatchRAM) |
| `RealtekRTL8111.kext` | 3.0.0 | GPL-2.0 | [Mieze](https://github.com/Mieze/RTL8111_driver_for_OS_X) |
| `USBToolBox.kext` · `UTBDefault.kext` | 1.2.0 / 1.0 | GPL-3.0 | [USBToolBox](https://github.com/USBToolBox) |
| `AMFIPass.kext` | 1.4.1 | BSD-3-Clause | [dhinakg](https://github.com/dhinakg/AMFIPass) |
| `CtlnaAHCIPort.kext` | 341.0.2 | 见上游 | outtaym |
| `AppleMCEReporterDisabler.kext` | 1.2 | 见上游 | XLNC |
| `SimpleHDA.kext` | 1.0.0 | 作者保留权利 | laobamac |
| `RTLBluetoothFirmware.kext` | 1.2.0 | 作者保留权利 | laobamac |
| `NullMothSafe.efi` | — | 作者保留权利 | laobamac |

## AMD 内核补丁

`config.plist → Kernel → Patch` 里的 27 条补丁来自 AMD OSX 社区：

**algrey** · **Shaneee** · **CaseySJ** · **XLNC** · **Visual** · **Zormeister** · **Goldfish64**

原始出处：[AMD OSX 论坛](https://amd-osx.com/)

## 未分发的组件

以下组件**不在本仓库中**，需自行获取：

| 组件 | 说明 |
|---|---|
| `NVRM.kext` · `NVRMFB.kext` · `NVRMAGDC.kext` · `NVAccel.kext` · `NMXAudio.kext` | NVIDIA 驱动（NullMoth，第三方；源码公开于 [nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver)，用 [1401](https://github.com/nullmoth/1401) 安装） |
| macOS 安装镜像 | 法律风险 |
| 三码（序列号 / MLB / UUID） | 每人必须自行生成 |

---

## 关于 SimpleHDA 与 NullMothSafe

`SimpleHDA.kext`、`RTLBluetoothFirmware.kext`、`NullMothSafe.efi` 是 laobamac 的作品，作者未声明开源协议。

它们被包含在此是为了让 EFI 具备**可用性** —— 没有 SimpleHDA，macOS 26 上就没有任何音频输出（详见 [docs/03-audio.md](docs/03-audio.md)）。

**权利仍归原作者。** 如果原作者认为此处分发不妥，提一个 issue，会立即移除。

---

## 如何移除第三方组件

如果你想得到一个只有开源组件的 EFI，删掉下面这些，并相应修改 `config.plist`：

```bash
# 1. 删除 kext 目录
rm -rf EFI/OC/Kexts/SimpleHDA.kext
rm -rf EFI/OC/Kexts/RTLBluetoothFirmware.kext
rm -f  EFI/OC/Tools/NullMothSafe.efi

# 2. 在 config.plist 里把对应条目 Enabled 改成 false
#    Kernel → Add          SimpleHDA / RTLBluetoothFirmware
#    Misc → Tools          NullMothSafe
```

代价：**没有音频输出**、蓝牙彻底不可用、黑屏时没有急救工具。

Linux 内核的 `GPL-2.0` 组件（RealtekRTL8111）与 macOS 内核链接的合法性问题，属于长期存在的争议，本仓库不持立场，仅如实标注。
