# 蓝牙

[← 返回 README](../README.md)

**状态：⚠️ 部分工作。** 芯片被识别，但未真正可用。

---

## 当前状态

```
Bluetooth Controller
    Address:            NULL
    State:              Off
    Chipset:            BCM_4350C2
    Firmware Version:   v0 c0
    Transport:          UART
    Vendor ID:          0x004C (Apple)
```

芯片型号识别正确，但 `Address: NULL` + `State: Off` + `Firmware v0 c0` 三个症状指向同一件事：**固件没有上传到芯片**。

BCM 系列蓝牙芯片分两类：

- **ROM 版** — 固件烧在芯片内部 flash，上电即可用
- **RAM 版** — 固件必须由主机每次上电时上传到芯片 RAM

`BCM_4350C2` 属于后者，需要 `BrcmPatchRAM3` 把固件推上去。`Firmware v0 c0` 说明这一步没成功。

---

## 本配置里的相关 kext

```
BlueToolFixup.kext          2.6.8   ← macOS 12+ 必需，修正 BlueTool 的检查
BrcmPatchRAM3.kext          2.6.8   ← 上传固件到 RAM
BrcmFirmwareData.kext       2.6.8   ← 固件数据（在 kext 内部）
RTLBluetoothFirmware.kext   1.2.0   ← Realtek 蓝牙固件（备用）
```

`BrcmPatchRAM3` 必须**在** `BrcmFirmwareData` **之前**加载 —— 前者是驱动，后者是数据源。顺序反了会上传失败。

---

## 排查顺序

### 1. 确认 USB 层面是否可见

```bash
system_profiler SPUSBDataType | grep -B2 -A8 -i bluetooth
ioreg -p IOUSB -l -w 0 | grep -i "IOUSBHostDevice" | head
```

如果 USB 层面**看不到**设备，问题在硬件连接（UART 排线、M.2 卡没插好、USB 内部线没接），不在软件。

### 2. 看 BrcmPatchRAM 的日志

```bash
log show --last 5m --predicate 'process == "kernel"' | grep -i "brcm\|bluetooth"
```

正常应该看到固件版本从 `v0` 变成实际版本号。如果一直停在 `v0`，说明上传被拒绝。

### 3. 确认 kext 顺序

```bash
python3 -c "
import plistlib
d = plistlib.load(open('EFI/OC/config.plist','rb'))
for k in d['Kernel']['Add']:
    if 'rcm' in k['BundlePath'] or 'lueTool' in k['BundlePath']:
        print(k['BundlePath'], k['Enabled'])
"
```

`BrcmPatchRAM3` 必须在 `BrcmFirmwareData` 前面。

### 4. 试关掉 BlueToolFixup

少数情况下 `BlueToolFixup` 会和 `BrcmPatchRAM3` 抢设备。临时禁用试一次：

```
Kernel → Add → BlueToolFixup → Enabled = false
```

能连上就是它的问题，再去找兼容的版本组合。

---

## 为什么不用 CSR8510

如果你手上是 CSR8510 A10 那类廉价 USB 蓝牙棒 —— **放弃**。

三条硬证据：

**1. 系统蓝牙守护进程的芯片表里没有 CSR**

`/usr/sbin/bluetoothd` 内建支持表共 25 款，全部是 `BCM_` 开头。CSR 一个都没有。

> 搜索 "CSR" 在这个文件里有 55 处命中，容易误判。逐条核对后全部是无关内容 —— `CSRK`（配对密钥）、`Channel Sounding`（CS 功能）、以及一条错误日志 `CSR chip not responding, bailing out`。没有一处是芯片支持。

**2. 内核里没有 USB 蓝牙的匹配入口**

`IOBluetoothFamily.kext` 的 `IOKitPersonalities` 只剩 3 条，没有一条匹配 USB 蓝牙设备：

| personality | 匹配条件 |
|---|---|
| Bluetooth Entitlement | `idVendor = 0x05AC`（Apple） |
| IOBluetoothHCIController | `IOProviderClass = IOResources` |
| MacPro6_1 BRCM20702B0 Hub | `idVendor = 0x0A5C:0x4500` |

你在系统里看到的那个"蓝牙控制器"是 `MacPro7,1` 机型凭空造出来的空壳，背后没有硬件。

**3. macOS 已经 9 年不支持 CSR**

从 10.12 左右开始，Apple 就不再为第三方 USB 蓝牙芯片提供驱动。任何软件手段（换 kext、改 NVRAM、注入 personality、刷固件）都无法凭空造出对一颗芯片的支持。

---

## 想要完整蓝牙功能，买什么

要同时满足「蓝牙 + Wi-Fi + AirDrop + 接力」，需要一张 **macOS 原生支持的 BCM 组合卡**：

| 型号 | 接口 | 原生支持 | 建议 |
|---|---|---|---|
| BCM94360CS2 | M.2 NGFF（需转接） | ✅ 免驱 | 最稳，老牌选择 |
| BCM943602CS | M.2 NGFF（需转接） | ✅ 免驱 | 3 天线，信号好 |
| BCM94360NG | M.2 NGFF 直插 | ✅ 免驱 | 免转接，价格高 |
| BCM94350ZAE | M.2 NGFF | ⚠️ 需 patch | 便宜但折腾 |
| BCM94352Z | M.2 NGFF | ⚠️ 需 patch | 同上 |

**买之前确认主板有 M.2 Key A/E 插槽，且不被显卡挡住。** B450M 板子上这个插槽通常在显卡下方，装了厚卡就插不进去。

台式机更省事的方案：**PCIe 转接卡 + BCM94360CS2**，插在远离显卡的 PCIe x1 槽上，天线走机箱后面。

价格参考：整套（转接卡 + 网卡 + 天线）约 ¥150–250。

---

## 如果不需要蓝牙

那就别管它。`BlueToolFixup` + `BrcmPatchRAM3` 这些 kext 留着无害，只是每次启动会多花几十毫秒尝试初始化。

真要清干净，把 `Kernel → Add` 里这四项的 `Enabled` 改成 `false`：

- `BlueToolFixup.kext`
- `BrcmPatchRAM3.kext`
- `BrcmFirmwareData.kext`
- `RTLBluetoothFirmware.kext`

同时清掉 NVRAM 里的两个变量（`config.plist → NVRAM → Delete` 已包含）：

```
bluetoothExternalDongleFailed
bluetoothInternalControllerInfo
```
