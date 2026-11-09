#!/bin/bash
# 驱动更新前后核对 — 更新 2.6.6 → 2.7.2 前后各跑一次，核对哪些设置被改动
# 用法: ./驱动更新前后核对.command before   （更新前，生成快照并备份 conf）
#       ./驱动更新前后核对.command after    （更新并重启后，对比 + 2.7.2 验收）
#       ./驱动更新前后核对.command verify   （随时单独跑验收清单）
# 只读（除 before 会把 conf 复制一份到 backups/），不改任何系统设置
set -u
cd "$(dirname "$0")" || exit 1
mkdir -p snapshots backups results
SNAP=snapshots/before-update.txt
MODE=${1:-auto}
CONF=/Library/GPUBundles/nvmtl/nvrm610.conf
# 双击（无参数）时自动判断：快照不存在 = 更新前；已存在 = 更新后对比
if [ "$MODE" = "auto" ]; then
  if [ -f "$SNAP" ]; then MODE=after; else MODE=before; fi
fi

one() { local v; v=$(printf '%s' "$2" | tr '\n' ' ' | sed 's/[[:space:]]*$//'); printf '%s=%s\n' "$1" "$v"; }

# 2.7.2 重启后验收：逐项判定驱动是否真正接管，不依赖「看起来能显示」
verdict() {
  local pass=0 fail=0 warn=0
  chk() {
    if [ "$2" = "1" ]; then printf '  ✅ %s\n' "$1"; pass=$((pass+1));
    else printf '  ❌ %s\n      → %s\n' "$1" "$3"; fail=$((fail+1)); fi
  }
  note() { printf '  ⚠️  %s\n      → %s\n' "$1" "$2"; warn=$((warn+1)); }

  echo "════════ 2.7.2 重启后验收 ════════"

  local v; v=$(cat /Library/NullMoth/driver-version 2>/dev/null | tr -d '[:space:]')
  chk "已安装驱动包 2.7.2（当前 ${v:-unknown}）" "$([ "$v" = "2.7.2" ] && echo 1 || echo 0)" \
      "更新未完成，回 1401 重新 Install"

  local k; k=$(kmutil showloaded 2>/dev/null | grep -Fc 'com.nullmoth.NVRM (2.7.2)')
  chk "内核已加载 NVRM 2.7.2" "$([ "${k:-0}" -ge 1 ] && echo 1 || echo 0)" \
      "kext 缓存没重建，再重启一次；若提示系统扩展被阻止，去「隐私与安全性」点 Allow"

  local ba; ba=$(sysctl -n kern.bootargs 2>/dev/null)
  chk "boot-args 无 -nvoff" "$(printf '%s' "$ba" | tr ' ' '\n' | grep -qx -- '-nvoff' && echo 0 || echo 1)" \
      "1401 只改磁盘上的 config；再重启一次让它生效"
  if printf '%s' "$ba" | tr ' ' '\n' | grep -qx -- '-wexoff'; then
    if sysctl -n debug.nvaccel_iop_flip >/dev/null 2>&1; then
      printf '  ℹ️  boot-args 带 -wexoff（NullMothSafe.efi 遗留标记），驱动已正常，无需处理\n'
    else
      note "boot-args 里仍有 -wexoff 且驱动仍停车" \
           "重启时别选「NullMoth: start once without the driver」/「1401: Remove NVIDIA driver」；持续存在可 sudo nvram -d boot-args 让 OpenCore 按 config 重写"
    fi
  fi

  chk "驱动 sysctl 树已注册" "$(sysctl -n debug.nvaccel_iop_flip >/dev/null 2>&1 && echo 1 || echo 0)" \
      "驱动仍处停车状态；再重启一次。仍不行可试 sudo sysctl -w debug.nvaccelfb=1（重启会失效）"

  local i l; i=$(sysctl -n debug.nvaccel_iop_flip 2>/dev/null); l=$(sysctl -n debug.nvrmfb_flip_latch 2>/dev/null)
  chk "呈现模式 iop_flip=1 / latch=2（当前 ${i:-空}/${l:-空}）" \
      "$([ "$i" = "1" ] && [ "$l" = "2" ] && echo 1 || echo 0)" \
      "开机后 LaunchDaemon 会等 30 秒再写；若开机不到 3 分钟请稍后重跑，持续为正则重跑「安装呈现固化.command」"

  local vr; vr=$(system_profiler SPDisplaysDataType 2>/dev/null | grep 'VRAM (Total)' | sed 's/.*: *//' | head -1)
  chk "Metal 设备已起：显存报告 GB 级（当前 ${vr:-unknown}）" \
      "$(printf '%s' "$vr" | grep -q 'GB' && echo 1 || echo 0)" \
      "22 MB = 只有 framebuffer、Metal 插件未加载；再重启一次，仍不行用 1401 的 Send logs"

  local cn; cn=$(system_profiler SPHardwareDataType 2>/dev/null | grep 'Processor Name' | sed 's/.*: *//')
  chk "「关于本机」CPU 名称保持 AMD" "$(printf '%s' "$cn" | grep -q AMD && echo 1 || echo 0)" \
      "检查 boot-args 里 revpatch=sbvmm,cpuname 是否被改"

  local ao; ao=$(system_profiler SPAudioDataType 2>/dev/null | grep -c 'Default Output Device: Yes')
  chk "内建输出仍是默认输出设备" "$([ "${ao:-0}" -ge 1 ] && echo 1 || echo 0)" \
      "2.7 自带 NMXAudio；到「系统设置 › 声音」重选「内建输出」，Logic/GarageBand 在自身设置里重选"

  echo
  printf '  结果: %d 项通过 / %d 项待处理 / %d 项提醒\n' "$pass" "$fail" "$warn"
  if [ "$fail" -eq 0 ]; then
    echo "  🎉 全绿 —— 2.7.2 已完整接管，可以开始 host512 试参和卡顿 A/B 采样"
  else
    echo "  ⚠️ 先按上面逐条处理，处理完再双击本工具复验（不会覆盖 before 快照）"
  fi
}

snapshot() {
  local out="$1"
  : > "$out"
  one "driver_version" "$(defaults read /Library/Extensions/NVRM.kext/Contents/Info CFBundleVersion 2>/dev/null || echo unknown)" >> "$out"
  one "plugin_sha" "$(shasum -a 256 /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver 2>/dev/null | cut -c1-16)" >> "$out"
  one "conf_sha" "$(shasum -a 256 "$CONF" 2>/dev/null | cut -c1-16)" >> "$out"
  one "conf_has_my_block" "$(awk '/my settings, kept on update/{n++} END{print n+0}' "$CONF" 2>/dev/null)" >> "$out"
  one "bootargs" "$(sysctl -n kern.bootargs 2>/dev/null)" >> "$out"
  one "iop_flip" "$(sysctl -n debug.nvaccel_iop_flip 2>/dev/null)" >> "$out"
  one "flip_latch" "$(sysctl -n debug.nvrmfb_flip_latch 2>/dev/null)" >> "$out"
  one "nvpresent_daemon" "$([ -f /Library/LaunchDaemons/cn.laobamac.nvpresent.plist ] && echo present || echo missing)" >> "$out"
  one "driver_pkg_version" "$(cat /Library/NullMoth/driver-version 2>/dev/null | tr -d '[:space:]')" >> "$out"
  one "kext_versions" "$(kmutil showloaded 2>/dev/null | grep -oE 'com\.nullmoth\.[A-Za-z]+ \([0-9.]+\)' | sort -u | tr '\n' ';')" >> "$out"
  one "sysctl_tree_up" "$(sysctl -n debug.nvaccel_iop_flip >/dev/null 2>&1 && echo yes || echo no)" >> "$out"
  one "metal_vram" "$(system_profiler SPDisplaysDataType 2>/dev/null | grep 'VRAM (Total)' | sed 's/.*: *//' | head -1)" >> "$out"
  one "park_args" "$(sysctl -n kern.bootargs 2>/dev/null | tr ' ' '\n' | grep -E '^-nvoff$|^-wexoff$' | tr '\n' ';')" >> "$out"
  one "cpu_name" "$(system_profiler SPHardwareDataType 2>/dev/null | grep -E 'Processor Name|Processor Speed' | sed 's/.*: *//' | tr '\n' ';')" >> "$out"
  one "model_id" "$(system_profiler SPHardwareDataType 2>/dev/null | grep 'Model Identifier' | sed 's/.*: *//')" >> "$out"
  one "gpu" "$(system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|Device ID|VRAM' | tr '\n' ';' | sed 's/  */ /g')" >> "$out"
  one "audio_devices" "$(system_profiler SPAudioDataType 2>/dev/null | grep -E '^        [^ ].*:$' | sed 's/^ *//;s/:$//' | tr '\n' ';' )" >> "$out"
  one "default_output" "$(system_profiler SPAudioDataType 2>/dev/null | grep -B4 'Default Output Device: Yes' | grep -E ':$' | sed 's/^ *//;s/:$//' | tr '\n' ';')" >> "$out"
  one "bar1_mapped_mb" "$(sysctl -n debug.nvrmfb_vram_mapped_bytes 2>/dev/null | awk '{printf "%d", $1/1048576}')" >> "$out"
  one "bar1_budget_mb" "$(sysctl -n debug.nvrmfb_vram_budget_bytes 2>/dev/null | awk '{printf "%d", $1/1048576}')" >> "$out"
  one "bar1_mask_lock" "$(awk '/NVMTL_VRAM_HEADROOM_MB/{n++} END{print n+0}' "$CONF" 2>/dev/null)" >> "$out"
}

case "$MODE" in
  before)
    [ -f "$SNAP" ] && cp "$SNAP" "$SNAP.prev"
    cp "$CONF" "backups/nvrm610.conf.pre-update-$(date +%Y%m%d-%H%M%S).bak" 2>/dev/null
    snapshot "$SNAP"
    echo "✅ 已生成更新前快照: $SNAP"
    echo "   conf 已额外备份到 backups/"
    echo
    cat "$SNAP"
    echo
    echo "现在可以去 1401 点 Update driver。重启后再运行本工具加 after 参数。"
    ;;
  after)
    [ -f "$SNAP" ] || { echo "❌ 没找到更新前快照 $SNAP，请先跑 before"; exit 1; }
    TMP=/tmp/nv-after-$$.txt
    snapshot "$TMP"
    echo "════════ 更新前后对比 ════════"
    python3 - "$SNAP" "$TMP" <<'PY'
import sys
def load(p):
    d={}
    for l in open(p,encoding="utf-8",errors="replace"):
        if '=' in l:
            k,v=l.rstrip('\n').split('=',1); d[k]=v.strip()
    return d
a,b=load(sys.argv[1]),load(sys.argv[2])
expect_changed={"driver_version","plugin_sha","conf_sha","gpu","audio_devices","default_output","bar1_mapped_mb","bar1_budget_mb","bar1_mask_lock","driver_pkg_version","kext_versions","metal_vram"}
for k in a:
    if k not in b: continue
    same = a[k]==b[k]
    if same:
        print(f"  ✅ {k:<22} 未变: {a[k][:70]}")
    else:
        mark = "🔄" if k in expect_changed else "⚠️ "
        print(f"  {mark} {k:<22} 变化")
        print(f"       前: {a[k][:100]}")
        print(f"       后: {b[k][:100]}")
print()
print("重点核查：")
if a.get("conf_has_my_block","0")!="0" and b.get("conf_has_my_block","0")=="0":
    print("  ⚠️ 你的 my settings 区块在更新后丢了！用「显存参数切换.command」重新写入")
elif a.get("conf_has_my_block","0")!="0":
    print("  ✅ conf 用户区块已保留")
else:
    print("  ✅ 未使用 conf 用户区块（更新前后一致，无需处理）")
if a.get("audio_devices")!=b.get("audio_devices") or a.get("default_output")!=b.get("default_output"):
    print("  ⚠️ 音频设备/默认输出变了 —— 2.7 在 Tahoe 上装自己的 HD Audio 驱动，请立即测声音；")
    print("     若无声，到「系统设置 › 声音」重选输出；Logic/GarageBand 需在自身设置里重选")
if a.get("cpu_name")!=b.get("cpu_name"):
    print("  ⚠️ 「关于本机」CPU 名称变了 —— 检查 revpatch=sbvmm,cpuname 是否还在 boot-args")
if a.get("iop_flip")!=b.get("iop_flip") or a.get("flip_latch")!=b.get("flip_latch"):
    print("  ⚠️ 呈现模式参数变了 —— 运行「检查呈现模式.command」确认 iop_flip=1 / latch=2")
if a.get("bootargs")!=b.get("bootargs"):
    print("  ⚠️ boot-args 被改动 —— 逐项核对 alcid=15 / revpatch / npci / nvfb 等")
if "22 MB" in b.get("gpu","") or "22 MB" in b.get("metal_vram",""):
    print("  ❌ 显存退化为 22 MB：Metal 设备没起来，这不是正常变化 —— 见下方验收清单")
PY
    echo
    verdict
    echo
    echo "提示: 更新后跑一次「显卡通道体检.command」确认双重硬件锁依旧（预期不变）"
    rm -f "$TMP"
    ;;
  verify)
    verdict
    ;;
  *) echo "用法: $0 before | after | verify"; exit 1 ;;
esac
echo
read -r -p "按回车关闭..." _
