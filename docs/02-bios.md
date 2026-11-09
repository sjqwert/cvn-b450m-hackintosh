# BIOS 设置

[← 返回 README](../README.md)

七彩虹 CVN B450M GAMING V14，AMI UEFI，最新版本 **1012**。

开机按 `Del` 进入，按 `F7` 切到 **Advanced Mode**（高级模式）。

---

## 必改项

这两项不做，显卡驱动起不来，开机黑屏。

```
Advanced Mode → AMD CBS → NBIO Common Options
    Above 4G Decoding（4G以上MMIO资源分配） ......... Enabled
    Re-Size BAR Support ............................ Enabled
```

### 为什么必须开

macOS 的 `IOFramebuffer` 要求扫描输出缓冲区落在 CPU 可映射的 PCI BAR 里。

- `Above 4G Decoding` **关** → BAR 被分配到 4 GB 以下，空间不足，显卡驱动初始化失败
- `Re-Size BAR Support` **关** → BAR1 退回更小的窗口，加速器预算归零

实测这两项任一关闭，结果都是开机后黑屏（有背光无画面）。

> 注意：这里的 `Re-Size BAR Support` 是**主板给 PCIe 设备的能力声明**，和"显卡是否支持大 BAR"是两件事。Turing 显卡的 VBIOS 只声明 64/128/256 MB 三档，所以即使主板开了，实际窗口还是 256 MB。见 [06-known-issues.md](06-known-issues.md)。

---

## 建议设置

### ACPI

```
Advanced Mode → Advanced → ACPI Settings
    ACPI Auto Configuration ........................ Disabled
```

让 OpenCore 接管 ACPI 表，避免固件塞进多余的 SSDT。

### 存储

```
Advanced Mode → 主板芯片组 → SATA 设置
    SATA Mode ...................................... AHCI
```

`RAID` 模式下 macOS 看不到硬盘。

### 启动

```
Boot
    Boot Mode ...................................... UEFI only
    CSM Support .................................... Disabled
    Fast Boot ...................................... Disabled
    Secure Boot .................................... Disabled
    Boot Option Filter ............................. UEFI only
```

- **CSM 必须关** — 开启后 `BOOTx64.efi` 可能走 legacy 路径，OpenCore 起不来
- **Fast Boot 必须关** — 快速启动会跳过 USB 枚举，OpenCore 菜单可能不出现
- **Secure Boot 必须关** — 未签名 kext 与 Secure Boot 不共存

### 安全

```
Advanced Mode → Security
    Secure Boot .................................... Disabled
    BIOS Write Protect ............................. Disabled（如有此项）
```

如果固件里存在「BIOS 写保护」，关掉它能让后续的软件刷写（`flashrom` / AFU）少一层阻力。本主板固件里未见此项。

### 内置设备

```
Advanced Mode → 内置设备
    板载音频 ....................................... Enabled
    板载网卡 ....................................... Enabled
    串口 (Serial Port) ............................. Disabled
```

串口在 macOS 上没用，关掉能少一个 ACPI 设备、少一份干扰。

### 电源

```
Advanced Mode → APM Configuration
    Restore on AC Power Loss ....................... Power Off
    ErP Ready ...................................... Disabled
```

`ErP` 开着会切断 USB 待机供电，导致某些 USB 设备唤醒失败。

---

## 不要改的项

| 项 | 保持 | 原因 |
|---|---|---|
| 内存频率 / XMP | 默认或稳定档 | 内存不稳会导致随机 panic，很难查 |
| CPU 超频 / PBO | Auto | 同上 |
| `Above 4G` 以下的 MMIO 分配策略 | Auto | 手改容易让 PCIe 设备拿不到资源 |
| 风扇曲线 | 随意 | 与 macOS 无关 |

---

## 保存与验证

改完按 `F10` 保存退出。

验证 BIOS 设置是否生效的办法：

```bash
# 看 BAR 大小与 4G 解码是否生效
ioreg -l | grep -E "nvrm-bars|bar1"

# 或看内核日志
log show --last 5m --predicate 'process == "kernel"' | grep -i "bar1\|64-bit window"
```

如果看到 `small firmware window` 或 `REFUSED to map` 之类的字段，说明 BIOS 设置有项没生效，回去复查。

---

## 刷新 BIOS 的风险提示

这块板子**没有双 BIOS、没有 FlashBack**。刷坏了只能：

1. 拆机，用 CH341A 夹住 SPI 芯片重新写入
2. 或者用 U 盘 + AFU 尝试恢复（前提是能 POST）

在本平台上尝试刷入修改版 BIOS（为了扩 ReBAR 能力位）已被 **AMI Secure Flash** 的签名校验拦住，实测三种策略（默认 / `/CAPSULE` / `/RECOVERY`）全部返回 `18 - Error: Secure Flash Rom Verify fail`，且失败点在正式编程之前，**零写入**，不会变砖。

但这不代表以后不会。**刷 BIOS 前一定先把原厂镜像 dump 一份存好。**
