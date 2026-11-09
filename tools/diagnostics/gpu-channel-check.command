#!/bin/bash
# 显卡通道体检 v3 — NullMoth 2.6.6 / 2.7.2 通用
# 只读。默认弹一次管理员密码采集内核日志；NV_SKIP_LOG=1 可复用 /tmp/nvklog.txt 缓存。
# v3：把「BAR1 物理地址是否 ≥4GB」与「窗口大小是否 >256MB」拆成两把独立的锁分别判定。
# 不改任何设置：不动 config、不动刷新率、不动驱动参数。
cd "$(dirname "$0")" || exit 1

NEED=1
if [ "${NV_SKIP_LOG:-0}" = "1" ] && [ -r /tmp/nvklog.txt ]; then NEED=0; fi

if [ "$NEED" = "1" ]; then
  cat > /tmp/nvkbar-fetch.sh <<'FETCH'
#!/bin/sh
/usr/bin/log show --last 45m --info --debug --style compact --predicate 'process == "kernel"' > /tmp/nvklog.txt 2>/dev/null
touch /tmp/nvklog.done
FETCH
  chmod +x /tmp/nvkbar-fetch.sh
  rm -f /tmp/nvklog.done
  osascript -e 'do shell script "(/bin/sh /tmp/nvkbar-fetch.sh >/dev/null 2>&1 &) ; echo ok" with administrator privileges' >/dev/null 2>&1
  i=0; OK=0
  while [ $i -lt 75 ]; do
    if [ -f /tmp/nvklog.done ]; then OK=1; break; fi
    /bin/sleep 1; i=$((i+1))
  done
  [ "$OK" = "0" ] && echo "⚠️ 内核日志采集未完成（可能取消了密码框），以下结果可能基于旧日志"
fi

NV_LOG="$( { grep -iE 'bar1|resizable bar|64-bit window|_CRS|rebar|small firmware window|REFUSED|no larger size|host bridge' /tmp/nvklog.txt 2>/dev/null \
  | grep -viE 'nvAllocVram #[0-9]+: .*REAL VRAM' | sort -u | head -120; } 2>/dev/null )"
NV_IOREG="$(ioreg -l 2>/dev/null | grep -E '"(nvrm-bars|nvrm-gpu-profile)"' | head -4)"
NV_SYSCTL="$(sysctl -a 2>/dev/null | grep -E '^debug\.nvrmfb_vram_|^debug\.nvaccel_vm_refused|^debug\.nvaccel_surface_gpu_waits|^debug\.nvaccel_surface_gpu_wait_max_us' | head -20)"
NV_HW="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|VRAM \(Total\)|Device ID|UI Looks like' | head -6)"
NV_REFUSED="$(grep -cE 'REFUSED \(#[0-9]+\)' /tmp/nvklog.txt 2>/dev/null || echo 0)"
if [ "$NEED" = "0" ]; then export NV_LOG_CACHED=1; else export NV_LOG_CACHED=0; fi
export NV_LOG NV_IOREG NV_SYSCTL NV_HW NV_REFUSED

python3 - <<'PY'
import os, re

log = os.environ.get("NV_LOG", "")
ior = os.environ.get("NV_IOREG", "")
sc  = os.environ.get("NV_SYSCTL", "")
hw  = os.environ.get("NV_HW", "")

def g(pat, s, default=""):
    m = re.search(pat, s, re.I)
    return m.group(1) if m else default

print("════════ 显卡通道体检 v3 ════════")
print("\n1. 硬件")
for line in hw.splitlines():
    print("  " + line.strip())

pa_s = g(r'bar1@0x[0-9a-f]+:0x([0-9a-f]+)', ior)
sz_s = g(r'bar1@0x[0-9a-f]+:0x[0-9a-f]+\+0x([0-9a-f]+)', ior)
mb_s = g(r'"bar1-mb"=([0-9]+)', ior)
pa = int(pa_s, 16) if pa_s else None
sz = int(sz_s, 16) if sz_s else None
size_mb = sz / 1048576 if sz else (float(mb_s) if mb_s else None)
above = bool(pa is not None and pa >= 0x100000000)

print("\n2. BAR1 两把锁（IORegistry 实测，不依赖驱动日志）")
if size_mb is None:
    print("  (读不到 nvrm-bars，无法判定)")
else:
    if pa is not None:
        print(f"  🔒 主板侧窗口  BAR1 物理地址 0x{pa:x} = {pa/1024**3:.1f} GB")
        print("     " + ("✅ 落在 4GB 以上 → Above 4G / Re-Size BAR 生效，host bridge 提供了 64-bit MMIO" if above
                       else "❌ 仍在 4GB 以下 → 主板未给 64-bit MMIO 窗口"))
    print(f"  🔒 GPU 侧大小  窗口 {size_mb:.0f} MB")
    print("     " + ("✅ 大 BAR1 窗口" if size_mb >= 512
                   else "❌ 仍被 256MB 上限锁住（Turing VBIOS ReBAR mask）"))

print("\n3. 驱动判定（内核日志）")
if os.environ.get("NV_LOG_CACHED") == "1":
    print("  ℹ️ 复用缓存日志（可能是上一次启动），仅作参考；直接双击本工具可重新采集")
mask = g(r'sizes supported mask (0x[0-9a-f]+)', log)
if mask:
    v = int(mask, 16)
    names = ["1MB","2MB","4MB","8MB","16MB","32MB","64MB","128MB","256MB",
             "512MB","1GB","2GB","4GB","8GB","16GB","32GB"]
    sup = [names[i] for i in range(16) if v >> i & 1]
    print(f"  ReBAR capability mask {mask} → 支持档位: {' '.join(sup)}")
    print("  " + ("✅ GPU 支持 >256MB" if (v >> 9) & 1 else "❌ GPU 侧最大 256MB（VBIOS 限制）"))
else:
    print("  2.7.2 本次未打印 ReBAR capability（该日志只在 resize 探测路径输出），")
    print("  不能据此认定 mask 已改变；以第 2 节 IORegistry 实测为准。")
if "no 64-bit window" in log:
    print("  ℹ️ 旧日志里有 host bridge 无 64-bit 窗口 —— 若第 2 节显示 4GB 以上，此为历史记录")
if "no larger size" in log:
    print("  🔒 GPU 侧：card offers no larger size")
if "small firmware window" in log or "BAR1 not placed" in log:
    print("  ⚠️ 日志含 small firmware window / BAR1 not placed（请确认是否为本次启动）")
n_ref = int(os.environ.get("NV_REFUSED", "0") or 0)
if n_ref:
    print(f"  ⚠️ 日志出现 {n_ref} 次 BAR1 REFUSED（resizable-BAR ceiling）")

print("\n4. 实时占用")
d = {}
for line in sc.splitlines():
    m = re.match(r'([^:]+):\s*(-?\d+)', line)
    if m:
        d[m.group(1).strip()] = int(m.group(2))
budget = d.get("debug.nvrmfb_vram_budget_bytes", 0)
mapped = d.get("debug.nvrmfb_vram_mapped_bytes", 0)
disp   = d.get("debug.nvrmfb_vram_display_bytes", 0)
if budget:
    print(f"  mapped {mapped/1048576:.1f}MB / budget {budget/1048576:.1f}MB = {mapped*100/budget:.1f}%"
          f"   display 常驻 {disp/1048576:.1f}MB")
print(f"  累计 BAR1 拒绝 {d.get('debug.nvaccel_vm_refused', 0)} 次"
      f"   surface 等待 {d.get('debug.nvaccel_surface_gpu_waits', 0)} 次")

print("\n5. 结论与下一步")
if size_mb is not None and size_mb >= 512:
    print("  ✅ BAR1 已放大：两把锁都解开，显存窗口瓶颈消除")
elif above:
    print("  ◐ 半通：主板侧那把锁已经解开了")
    print("     BAR1 已搬到 4GB 以上，说明 BIOS 的 Above 4G / Re-Size BAR 确实生效；")
    print("     但窗口仍是 256MB，卡在 GPU VBIOS 的 ReBAR mask（TU102 只报 64/128/256MB）。")
    print("     → 继续开 BIOS 选项不会让 BAR1 变大，别再折腾固件。")
    print("     → 想复核 mask：Windows 下用 GPU-Z 看 Resizable BAR 状态；")
    print("       根治需刷 GPU VBIOS（高风险）或换 Ampere+ 显卡。")
    print("     → 软件层：2.7.2 的显存复用已大幅降低 BAR1 拒绝，卡顿以体感为准。")
    print("  ⚠️ 开 4G 后 NMXAudio 会枚举出 NVIDIA HDMI 输出并抢走默认输出；")
    print("     若没声音，双击 audio-fix/恢复声音-切回内置输出.command")
else:
    print("  ❌ 主板侧窗口也没打开：BAR1 仍在 4GB 以下")
    print("  回 BIOS 逐项确认（缺一项都可能是这个结果）：")
    print("    ① Above 4G Decoding = Enabled")
    print("    ② Re-Size BAR Support = Enabled ← 独立选项，最容易漏")
    print("    ③ CSM = Disabled，纯 UEFI 启动")
    print("    ④ 驱动侧：npci=0x2000 会让 macOS 忽略 ACPI _CRS，开 Above 4G 后常需移除")
    print("  安全边界：不要改 ResizeGpuBars=13（官方警告会在进 picker 前卡死）；")
    print("            动 config 前先备份 EFI，一次只改一项，别动刷新率。")
print("\n  本工具只读。真实卡顿请用「卡顿采样器.command」在播放同一段视频时采样 60 秒。")
PY

echo
read -r -p "按回车关闭..." _
