# NVIDIA RTX 2080 Ti：驱动、参数与实测

[← 返回 README](../README.md)

> 数据来源：本机实测（2026-11），驱动 NullMoth 2.6.6 / 2.7.2
> 部分结论基于对驱动二进制的字符串提取与交错 A/B 对照实验

---

## 一句话总结

**能跑，性能损失可接受，但 256 MB 的 BAR1 是物理天花板。**

真正拖慢体验的不是显卡算力，而是一个驱动 bug（硬解能力查询）和一块改不动的显存窗口。

---

## 依赖什么

NVIDIA 驱动**不在本仓库里**，需要自行获取安装。它是第三方组件（NullMoth），源码公开在 [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver)，但预编译包约 250 MB、版本迭代频繁，不随本仓库分发。

**别手工拷 kext。** 用官方的安装器 **1401**，它会连 OpenCore 配置一起改好。

### 1401：唯一推荐的安装方式

1401 是独立项目，Mac 与 Windows 双端都有：

| 项目 | 地址 | 内容 |
|---|---|---|
| **1401**（安装器） | [github.com/nullmoth/1401](https://github.com/nullmoth/1401) | 图形界面安装 / 卸载 / 诊断，Windows 端还能用来装 macOS |
| 驱动本体 | [github.com/nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver) | 内核模块 + Metal 插件 + 着色器翻译层，源码在仓库里 |

**下载哪个文件** —— 不用 clone，直接进 Releases：

- 下载页：[Releases](https://github.com/nullmoth/nvidia-macos-driver/releases)
- 拿 **`1401-Mac-<版本>.dmg`**（约 3 MB）。**驱动包已经内置在 dmg 里**，不需要另外去下那个 250 MB 的 tar.gz
- 只有想手工安装或审计源码时，才需要 `nullmoth-nvidia-<版本>.tar.gz`

本配置验证于 **2.7.2**。截稿时官方最新为 **2.8.1**（2026-11-08 发布）。升级前先备份 EFI，理由见文末「驱动版本说明」。

### 1401 具体做了什么

它不是「下一步 → 下一步」的傻瓜安装器，装驱动时会**动你的 OpenCore**：

- 自动找到**启动本机的那一份** OpenCore（`EFI/OC` 或 `EFI/BOOT`，在 EFI / FAT32 分区上）
- 改动前把 `config.plist` 备份一份，并把**每一处变更先列给你看**
- 写好 `boot-args`、`csr-active-config`、`SecureBootModel` 等必需项（就是下面「必需的 EFI 配置」那几节）
- 往 OpenCore 启动菜单加一条 **`1401: Remove NVIDIA driver`** —— 选它就会在下次启动时把驱动**连同 OpenCore 配置一起还原到安装前**，然后自动重启
- 顺带做 USB 端口映射

**一条硬前提：运行 1401 时，以及之后每一次重启，启动用的那块盘都要插着。**

它改的就是那块盘上的配置，**从不会把 OpenCore 复制进内置硬盘**。拔掉它，下次启动读到的是旧配置，驱动不会生效。

### 两个容易踩的点

**1. 启动菜单里两条名字很像的条目，选错就白折腾**

| 条目 | 实际行为 | 什么时候用 |
|---|---|---|
| `NullMoth: start once without the driver` | 这一次追加 `-nvoff` 启动，**不改任何配置** | 驱动把系统搞黑屏了，临时进桌面 |
| `1401: Remove NVIDIA driver` | **彻底卸载**驱动，并把 OpenCore 配置还原 | 决定不装了 |

黑屏救急选第一条。选第二条等于把刚装好的驱动删掉。

**2. 1401 会装两个登录项**

`~/Library/LaunchAgents/` 下会多出两个入口，每次登录各拉起一次 `/Applications/1401.app`（参数 `--reached-desktop` 和 `--tester-report`），用途是状态检查与崩溃诊断。

**它不会自动上传任何东西。** 上报要你在 app 里手动点「Send logs to NullMoth」，且上报前会去掉机器名、序列号和内存地址。不需要的话可以 unload 掉，不影响驱动工作。

### 装完之后

系统里会有这五个 kext：

```
/Library/Extensions/
    NVRM.kext          核心驱动（约 14 MB）
    NVRMFB.kext        帧缓冲
    NVRMAGDC.kext      显示控制器
    NVAccel.kext       加速器
    NMXAudio.kext      HDMI 音频
```

`kextstat` 里能看到 `com.nullmoth.NVRM (2.7.2)` 这类条目。

**本配置的作者不对该驱动的可用性、合法性、安全性做任何保证。** 它不属于本仓库。

---

## 必需的 EFI 配置

三处，缺一不可。

### 1. Booter → Quirks → ResizeAppleGpuBars = -1

```
ResizeAppleGpuBars = -1
```

**不要设成 0。** 设 0 会让 macOS 在启动时把 BAR1 压回 64 MB，驱动初始化直接失败，黑屏。

这是本平台最容易踩的坑之一 —— 很多教程建议 `0`，在 AMD + NVIDIA 组合上会直接起不来。

### 2. UEFI → Quirks → ResizeGpuBars = -1

```
ResizeGpuBars = -1
```

固件侧同理：不要主动缩小 BAR，让固件按自己的能力分配。

### 3. BIOS 开 Above 4G + Re-Size BAR

见 [02-bios.md](02-bios.md)。这两项关闭的结果同样是黑屏。

---

## boot-args 逐条

```
nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth gfxrst=4
nvrmsettle=10000 nvfbhidpi=1 -nvrmnobootscreen
```

| 参数 | 作用 | 调不调 |
|---|---|---|
| `nvfb=1` | 启用帧缓冲 | 必需 |
| `nvaccel=1` | 启用硬件加速 | 必需，否则无 Metal |
| `nvfbheads=4` | 显示头数量 | **别调**。实测 4→2 无效，`display_bytes` 一个字节没变 |
| `-nvkmsnosmooth` | 关闭逐帧平滑 | 建议保留，减少卡顿感 |
| `gfxrst=4` | 显卡复位策略 | 保留 |
| `nvrmsettle=10000` | 驱动初始化等待 10 秒 | 保留，避免开机时序竞争 |
| `nvfbhidpi=1` | 允许 HiDPI | 需要缩放分辨率时开 |
| `-nvrmnobootscreen` | **不把开机画面快照进 BAR1** | 关键，见下 |

### 为什么 -nvrmnobootscreen 重要

驱动默认会把 UEFI 控制台画面快照进显存，作为开机过渡画面。

那张快照 = `2560 × 1440 × 4` = **14,745,600 字节**，正好一整帧。

而 BAR1 预算情况是：

```
256 MB = 扫描缓冲 56.5 MB + 加速器预算 183.5 MB + 守卫 16 MB
```

账刚好平，一个字节不剩。WindowServer 要做零拷贝翻页，需要再拿一整帧 —— 拿不到。

关掉快照后腾出约 15 MB，刚好够那一帧。**这是「翻页能否启动」的临界点。**

副作用：开机接管瞬间会短暂黑屏（没有开机图可画），不影响系统。

---

## 实测性能

基线（NullMoth 2.6.6，2560×1440@120Hz）：

| 指标 | 实测 | 参考值 | 达成率 |
|---|---|---|---|
| 渲染填充率 | 832 fps（1.20 ms/帧） | — | 健康 |
| 2000 draw call | 866 fps（0.57 µs/call） | — | 健康 |
| 纹理上传 | 8.9 GB/s | PCIe 3.0 x16 ≈ 13 GB/s | 68% |
| 呈现（渲染 + 回读） | 400 fps（2.5 ms/帧） | 120 Hz 需 8.3 ms | 有余量 |
| 算力 fp32 | 10.5 TFLOPS | 公版 13.4 TFLOPS | 78% |
| 显存带宽 | 540 GB/s | 公版 616 GB/s | 88% |

**结论：翻译层的性能损失在可接受范围。** 这条链路很长：

```
Metal → SPIR-V → Vulkan → NVK → SASS
```

损失 22% 的峰值算力，换来一张能跑 macOS 的 NVIDIA 卡，这个交换比不算差。

### 调参是死路（重要负面结果）

从三个驱动二进制里提取出 **214 个**未公开调参键，扫描了 24 个关键项。

单次扫描最大增益看起来有 +8.1%（`NVK_BAR_VRAM=1`）。用交错 A/B（A-B-A-B-A，5 轮）验证后：

```
present fps   基线 400.10   组合 395.60   -1.1%
drawcalls     基线 875.84   组合 863.06   -1.5%
upload GB/s   基线 8.93     组合 9.03     +1.1%
```

**全部落在噪声内。** 有一个反例：`NVMTL_SASS_CACHE=1` 会让 compute 掉 26%，应该避免。

**不必再花时间调驱动参数，瓶颈不在那里。**

---

## 三个真实瓶颈

### 1. 硬解能力查询缺陷（最影响体验）

**现象**：同一进程内，`VTIsHardwareDecodeSupported()` 的**第一次调用恒返回 `NO`**，之后才返回真实值。

```
单独查询 HEVC（首次调用）    → NO
先查 H.264，再查 HEVC        → HEVC = YES
```

预热后的真实能力：

```
H.264   : YES      ← 驱动包里确有 libnvdec_h264.dylib
HEVC    : YES
ProRes  : NO       ← 确实不支持
VP9     : NO
AV1     : NO
```

**影响**：Chrome、Safari、QuickTime、DaVinci Resolve、Premiere 都用这个 API 决定是否走硬解。如果第一个查询正好是 H.264（最常见的素材格式），就会得到 `NO` 并按软解处理 —— 6 核 6 线程的 Ryzen 5 3500X 立刻跑满。

**这就是"看视频/剪视频卡"的真实原因**，不是性能不够。

**应对**：

- 用户侧无法修复（bug 在驱动的解码器注册时机）
- 素材优先用 **HEVC**，或用代理剪辑
- 值得向驱动作者提 issue

### 2. 着色器冷编译

```
200 个唯一 kernel 冷编译：1187 / 1711 / 1757 ms
单 kernel 平均：5.9 ~ 8.8 ms
```

真实渲染软件动辄数千个材质变体 → 首次打开工程冻结数十秒。

**好消息：跨进程缓存非常有效。**

```
第一次运行  969 ms    (4.85 ms/kernel)
第二次运行    8.4 ms  (0.04 ms/kernel)    ← 115× 加速
第三次运行    9.2 ms
```

**绝对不要清空 `~/.cache/mesa_shader_cache`。** 那 239 条缓存价值上百秒。

### 3. 256 MB 的 BAR1 窗口

```
nvrm-gpu-profile = { "bar1-mb"=256, "vram-mb"=22528, "chip"="TU102" }
帧缓冲显存预算   = 183.5 MB
已映射帧缓冲     = 148.6 MB
```

2560×1440 一帧 14.06 MB，183 MB 仅容纳约 13 帧。

> **注意区分**：183 MB 是**帧缓冲（显示合成）**的预算，不是应用可用显存上限。
> 实测应用侧能分配 **10 GB** 以上纹理，与"22 GB 显存不够用"无关。
> 这是最容易误读的地方。

#### 这 256 MB 为什么改不动

四条证据：

| # | 验证 | 结果 |
|---|---|---|
| 1 | Turing 的 VBIOS 是否声明大 BAR | **不声明**。NVIDIA 从未给 Turing 发过 ReBAR VBIOS，官方支持自 Ampere 起 |
| 2 | 主板开 ReBAR 后 2080 Ti 的 BAR1 | 仍为 256 MB。Turing VBIOS 的 ReBAR 能力位掩码只有 `0x1c0`（64/128/256 MB 三档） |
| 3 | `debug.nvrmfb_vram_budget_bytes` 能否运行时调大 | `read only`，root 也不行 |
| 4 | 改 VBIOS 扩能力位 | 理论上可行，但有变砖风险，需 Windows + `nvflash` |

另外尝试过给固件注入 ReBAR 模块（NvStrapsReBar 路线），被 AMI Secure Flash 的签名校验拦住，**零写入**。

**结论：BAR1 = 256 MB 是显卡固件层写死的。** 改 EFI、改 BIOS 设置、换 `npci` 参数都不会有变化。

#### 拒绝分配是突发式的

累计计数看起来很吓人：

```
debug.nvaccel_vm_refused = 14,043     （启动 52 分钟，含全部基准测试）
```

但空闲采样 45 秒：**0 次拒绝**，呈现 19 次/秒。

**所以闲时桌面本身是健康的。** 拒绝集中在应用启动、上下文创建、窗口批量出现时。影响的是**峰值**，不是常态。

---

## 真正有效的优化

按性价比排序：

| 措施 | 收益 | 成本 |
|---|---|---|
| 保留着色器缓存 | 二次启动快 115× | 0 |
| 素材用 HEVC | 绕开硬解查询 bug | 0 |
| 降刷新率 120 → 60 Hz | 减少合成器压力 | 0 |
| 关窗口毛玻璃 / 降低透明度 | 减少合成压力 | 0 |
| **内存加到 64 GB** | 16 GB 下压缩页数达 125,100，渲染软件会触发换页 | 硬件钱 |
| 换 AMD 显卡（RX 6600 / 6800） | 原生驱动，彻底解决 | 硬件钱 |

**不建议**：继续调驱动参数、期待 macOS 26 上有原生性能、为了 BAR 去刷 VBIOS。

---

## 黑屏了怎么救

`config.plist` 里带了一个急救工具：`EFI/OC/Tools/NullMothSafe.efi`。

```
开机看到 OpenCore 菜单时选：
    NullMoth: start once without the driver
```

它会追加 `-nvoff`，一次性不带驱动启动，不改任何配置，直接回到可用桌面。进系统后再改配置。

> 注意 `Misc → Tools` 里有两条同名条目（`NullMoth: start once without the driver` 和 `1401: Remove NVIDIA driver`），指向同一个 efi。**选第一条**。

---

## 驱动版本说明

- 本文性能数据基于 **2.6.6**
- 当前配置使用 **2.7.2**（`/Library/Extensions` 里五个 kext 均为 2.7.2）
- 官方验证平台是 **Sequoia 15.7**，macOS 26 支持自 2.0.0 起标注为"待验证"

升级驱动后**第一次运行必然慢**（着色器缓存失效），第二次开始恢复正常。这是预期行为，不是故障。
