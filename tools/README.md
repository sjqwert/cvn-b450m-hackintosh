# 工具

[← 返回 README](../README.md)

`tools/` 里的东西**不是必须的**。装上它们只是让体验完整一些 —— 开机自动恢复音频输出、快速看显卡状态、加个亮度条。

所有脚本都是纯 shell / Objective-C，没有二进制依赖（除了几个需要 `clang` 现场编译的）。

---

## 目录

```
tools/
├── guard/          开机自动恢复音频输出 + 呈现模式
├── audio/          手动切换音频输出
├── diagnostics/    只读诊断工具
└── extras/         亮度条、摄像头预览（源码）
```

---

## guard：开机守护

### 解决什么问题

macOS 会记住上次使用的音频输出设备。如果显示器带扬声器，它经常会在开机后被选中 —— 声音跑到显示器上去了。

这个守护进程在登录后自动把默认输出切回板载声卡（或你指定的设备），并固化显卡的呈现模式。

### 安装

双击 `tools/guard/install.command`，输管理员密码。

它会：

1. 退役旧的两套守护（`cn.laobamac.nvpresent`、`cn.laobamac.audio-output`），先备份再禁用
2. 安装 `/usr/local/bin/gpu-lab-guard.sh`
3. 安装 `/Library/LaunchDaemons/cn.laobamac.gpu-lab.plist`
4. 编译并安装 `setoutput`（音频切换工具）
5. 加载守护

启动后约 35–40 秒完成。

### 检查

双击 `tools/guard/check.command`（不需要密码）：

```
════════ 守护状态 ════════
  running
════════ 最近日志 ════════
  ...
════════ 当前呈现参数 ════════
  debug.nvaccel_iop_flip: 1
  debug.nvrmfb_flip_latch: 2
════════ 当前默认输出 ════════
  默认输出: Realtek ALC662 rev3
```

### 卸载

双击 `tools/guard/uninstall.command`。

它会移除守护并把旧的两套恢复回去（如果之前备份过）。

### 日志

```bash
tail -f /var/log/gpu-lab.log
```

状态文件：`/var/db/gpu-lab.state`

### 自定义输出设备

编辑 `/usr/local/bin/gpu-lab-guard.sh`，改目标设备名匹配串。

---

## audio：手动切换

### `setoutput`

```bash
# 列出所有输出设备
/usr/local/bin/setoutput list

# 切到指定设备（按名称模糊匹配）
/usr/local/bin/setoutput "ALC662"

# 切到系统默认
/usr/local/bin/setoutput default
```

源码在 `tools/audio/setoutput.m`，用 CoreAudio API 实现。

### 快捷脚本

| 文件 | 作用 |
|---|---|
| `switch-to-internal.command` | 切回板载声卡（双击即可） |
| `install-autoswitch.command` | 安装开机自动切换（**已并入 guard，一般不用**） |
| `uninstall-autoswitch.command` | 卸掉上面的 |

> `install-autoswitch` 和 `guard` 功能重叠。**装 guard 就够了**，不用两个都装。

---

## diagnostics：只读诊断

全部**不改任何设置**，可以放心跑。

### `gpu-channel-check.command` — 显卡通道体检

最有用的一個。检查：

- BAR1 物理地址是否 ≥ 4 GB
- 窗口大小是否 > 256 MB
- 帧缓冲预算与占用率
- 显存分配拒绝的实时速率

```
════════ 显卡通道体检 ════════

1. 硬件
   NVIDIA GeForce RTX 2080 Ti · 22 GB · 0x1e04

2. BAR 窗口
   BAR1 物理大小    256 MB    ⚠️ 未开启 Re-Size BAR
   帧缓冲预算      183.5 MB
   已映射          148.6 MB    占用 81%

3. 分配拒绝
   采样 45s   分配+15   拒绝+0   呈现+856
   拒绝率 0.0 次/分钟
```

会弹一次管理员密码（读内核日志）。设 `NV_SKIP_LOG=1` 可以复用上次的日志缓存：

```bash
NV_SKIP_LOG=1 ./gpu-channel-check.command
```

### `present-mode-check.command` — 呈现模式（不需要密码）

看当前显示更新走的是拷贝还是翻页：

```
════════ 呈现模式 ════════
✅ 零拷贝 + 低延迟（推荐，横条已消除）

════════ 驱动计数器 ════════
  nvaccel_iop_flips              54700
  nvaccel_iop_flip_hit           54700
  nvaccel_iop_flip_refused       143
```

`iop_flip = 0` 说明走拷贝路径 —— 这是拖窗口发涩的根源。见 [docs/05](../docs/05-nvidia.md)。

### `display-mode-switch.command` — 显示模式切换

快速在几个常用分辨率/刷新率之间切换。测试不同负载时用。

### `stutter-sampler.command` — 卡顿采样器

持续采样显存分配拒绝速率，用于定位"什么时候卡"。

```bash
./stutter-sampler.command 60     # 采样 60 秒
```

### `driver-diff.command` — 驱动更新前后核对

升级 NVIDIA 驱动前后各跑一次，对比关键指标是否变化。避免"升完发现变慢了但不知道哪里变了"。

---

## extras：附加组件

### BrightnessBar

菜单栏亮度条。对不支持 DDC 的显示器做软件调光。

```bash
cd tools/extras/BrightnessBar
swiftc -O main.swift -o BrightnessBar
./BrightnessBar
```

**注意**：软件调光是覆盖一层半透明黑，不是真的改背光。在 OLED 上会加速老化，在 HDR 内容上会失效。

### CamView

USB 摄像头预览工具。用来验证摄像头是否真的工作。

```bash
cd tools/extras/CamView
./build.sh
./CamView.bin
```

源码是单文件 Objective-C（`CamView.m`，16 KB），用 AVFoundation。

---

## 注意事项

### 都需要 macOS 26 的环境

这些脚本调用的 `sysctl` 键（`debug.nvaccel_*`、`debug.nvrmfb_*`）是 **NullMoth 驱动特有的**。没有装驱动的话大部分输出是空的。

### 不要复制到别的机器上跑

`guard` 和 `audio` 里的设备名是匹配这台机器的声卡（ALC662）。换机器要改。

### 权限

`.command` 文件双击执行，需要先：

```bash
chmod +x tools/*/*.command
```

（仓库里已经设好了，但 git clone 在某些平台会丢掉执行位。）

如果双击提示"无法打开，因为来自身份不明的开发者"：

```bash
xattr -d com.apple.quarantine tools/*/*.command
```

### 卸载干净

```bash
# guard
./tools/guard/uninstall.command

# 手动清残留
sudo rm -f /usr/local/bin/gpu-lab-guard.sh /usr/local/bin/setoutput
sudo rm -f /Library/LaunchDaemons/cn.laobamac.gpu-lab.plist
sudo rm -f /var/db/gpu-lab.state /var/db/gpu-lab.disabled
```
