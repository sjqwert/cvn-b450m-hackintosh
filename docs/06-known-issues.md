# 已知限制与根因

[← 返回 README](../README.md)

这一页记录**改配置解决不了**的问题，以及每个问题的证据。

写这一页的目的是让后来者少走弯路 —— 下面每一条都有人试过，都失败了。

---

## 1. BAR1 只有 256 MB

### 现象

- 拖动窗口、滚动列表发涩
- 多窗口同时出现时偶发显存分配失败
- `nvaccel_iop_flip` 恒为 0（显示更新走拷贝而非翻页）

### 根因

```
256 MB = 扫描缓冲 56.5 MB + 加速器预算 183.5 MB + 守卫 16 MB
```

macOS 的 `IOFramebuffer` 要求扫描输出缓冲必须落在 **CPU 可映射的 BAR1** 里。预算刚好平，一个字节不剩，WindowServer 拿不到一整帧做零拷贝翻页。

### 为什么改不动

| 尝试 | 结果 |
|---|---|
| BIOS 开 Re-Size BAR | BAR1 仍为 256 MB |
| 移除 `npci=0x2000` | 无变化 |
| `sysctl` 调 `nvrmfb_vram_budget_bytes` | `read only`，root 也不行 |
| 改 `ResizeAppleGpuBars` / `ResizeGpuBars` | 只能维持现状，不能扩大 |
| 固件注入 ReBAR 模块（NvStrapsReBar） | 被 AMI Secure Flash 签名校验拦住，零写入 |
| 刷修改版 BIOS | 同上，三种刷写策略全部 `18 - Error: Secure Flash Rom Verify fail` |

真正的限制在 **Turing VBIOS**：它的 ReBAR 能力位掩码只有 `0x1c0`，对应 64 / 128 / 256 MB 三档。NVIDIA 从未给 20 系发放支持大 BAR 的官方固件，官方 ReBAR 支持自 Ampere 起。

### Secure Flash 为什么绕不过

三家 BIOS 厂商（AMI / Phoenix / Insyde）的整包签名机制。修改版 BIOS 的签名必然不匹配，固件在 `Loading capsule to secure memory buffer` 之后、正式编程之前就拒绝。

实测三种刷写策略：

```
Afuamd.efi MOD.ROM /p /b /x /k /l          → 18 - Error: Secure Flash Rom Verify fail
Afuamd.efi MOD.ROM /CAPSULE                → 18 - Error: Secure Flash Rom Verify fail
Afuamd.efi MOD.ROM /RECOVERY               → 18 - Error: Secure Flash Rom Verify fail
```

**好消息：失败点在正式编程之前，零写入，不会变砖。**

### 出路

**A. 改 VBIOS 扩 ReBAR 能力位**

需要 Windows + `nvflash`，把能力位掩码从 `0x1c0` 扩到覆盖 1GB/2GB/8GB。

风险：VBIOS 刷坏 = 显卡变砖。双 BIOS 显卡可以救，单 BIOS 只能拆芯片。

**B. 加一张 AMD 卡做显示输出**

RX 6600 / 6800 / 6900 XT 都是 macOS 原生驱动。RTX 只做计算（如果驱动支持）。

这是唯一"确定能成"的方案。

---

## 2. 硬件视频解码能力查询缺陷

### 现象

每个进程**第一次**调用 `VTIsHardwareDecodeSupported()` 恒返回 `NO`。

### 证据

```
单独查询 HEVC（首次调用）    → NO
先查 H.264，再查 HEVC        → HEVC = YES
```

预热后真实能力：`H.264 = YES`、`HEVC = YES`、`ProRes = NO`、`VP9 = NO`、`AV1 = NO`。

### 影响

所有依赖这个 API 的软件（Chrome、Safari、QuickTime、DaVinci、Premiere）都会误判为"无硬解"，退回 CPU 软解。Ryzen 5 3500X 只有 6 核 6 线程，软解 4K 直接满载。

**这是"看视频卡"的第一原因**，比 BAR1 影响大。

### 能不能修

用户侧不能。bug 在驱动的解码器注册时机 —— 驱动包里有 `libnvdec_h264.dylib`，能力是存在的，只是查询接口在初始化完成前就返回了默认值。

绕法：素材转 HEVC，或用代理剪辑。

---

## 3. 着色器冷编译

每个 kernel 编译 5.9–8.8 ms。真实工程动辄数千个材质变体，首次打开冻结数十秒。

跨进程缓存有效（第二次快 115 倍），**所以绝对不要清 `~/.cache/mesa_shader_cache`**。

这不是 bug，是翻译层（Metal → SPIR-V → Vulkan → NVK → SASS）的固有开销。原生 Metal 驱动不需要这一层。

---

## 4. Secure Boot 必须关闭

未签名 kext（NVIDIA 驱动、SimpleHDA）与 Secure Boot 不可共存。

`SecureBootModel = Disabled`、`csr-active-config = 0x0A43`。

代价：系统完整性保护不完整。这台机器上不能用：

- 需要 Secure Boot 的软件（部分反作弊游戏、企业 VPN）
- macOS 的 Sealed Volume 完整性校验
- 系统更新可能损坏自定义 kext

---

## 5. 蓝牙

BCM4350C2 识别但未工作（`State: Off`、`Firmware v0 c0`）。见 [04-bluetooth.md](04-bluetooth.md)。

CSR8510 一类廉价 USB 蓝牙棒**永远不可能工作** —— macOS 内没有驱动它们的代码，已经 9 年没有。

---

## 6. 没有双 BIOS

七彩虹 CVN B450M GAMING V14 只有一颗 SPI flash，没有 FlashBack 按钮。

刷坏 BIOS 的救援方式：

1. **CH341A 编程器夹 SPI 芯片**（需拆机，芯片在显卡下方）
2. USB 恢复（前提是能 POST 到 UEFI Shell）

这就是为什么本配置的作者在尝试刷修改版 BIOS 之前，先用编程器 dump 了一份完整固件存档。

---

## 7. 内存 16 GB 偏小

`压缩页数` 已达 125,100。渲染软件会触发内存压缩换页，表现为"切后台再切回来要等"。

这是唯一还有明确收益的硬件升级 —— 加到 64 GB。

---

## 汇总表

| 限制 | 可修复 | 修复方式 |
|---|---|---|
| BAR1 256 MB | ❌ | 换 AMD 卡 / 改 VBIOS（高危） |
| 硬解查询 bug | ❌ | 素材用 HEVC |
| 着色器冷编译 | ⚠️ 部分 | 保留缓存 |
| Secure Boot | ❌ | 不可能 |
| 蓝牙 | ⚠️ | 换 BCM 组合卡 |
| 无双 BIOS | ❌ | 硬件事实 |
| 内存 16 GB | ✅ | 加内存 |

---

## 一句话

这台机器的天花板不在配置里，在硬件里。

**如果你需要一台可靠的生产力工具，买 Mac。** 如果你把这件事当成学习和折腾，那这台机器已经跑得比大多数人预期得好了。
