#!/bin/bash
# 卡顿采样器 — 只读 sysctl 计数器，量化一次播放期间 BAR1 / surface 压力
# 用法: ./卡顿采样器.command [秒数=60] [标签=run]
# 建议: 每次用同一段抖音视频、同一清晰度、同样窗口大小，采样时长一致
set -u
cd "$(dirname "$0")" || exit 1
DUR=${1:-60}
TAG=${2:-run}
mkdir -p results
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="results/${TAG}-${STAMP}.csv"

NAMES=(
  debug.nvaccel_vm_refused
  debug.nvaccel_vm_alloc
  debug.nvaccel_vm_dealloc
  debug.nvaccel_surface_gpu_waits
  debug.nvaccel_surface_gpu_wait_max_us
  debug.nvaccel_surface_gpu_timeouts
  debug.nvaccel_iop_late
  debug.nvaccel_iop_flip_novram
  debug.nvaccel_iop_flip_refused
  debug.nvaccel_iop_flips
  debug.nvrmfb_vram_mapped_bytes
  debug.nvrmfb_vram_budget_bytes
  debug.nvrmfb_vram_grants
  debug.nvrmfb_vram_releases
  debug.nvrmfb_agdc_refused
)

{
  printf 't,'
  ( IFS=,; printf '%s\n' "${NAMES[*]}" )
} > "$OUT"

echo "采样 ${DUR}s，每 0.5s 一次 → $OUT"
echo "现在开始播放视频（同一段、同一清晰度）…"
echo
N=$(( DUR * 2 ))
for ((i=0; i<=N; i++)); do
  VALS=$(sysctl -n "${NAMES[@]}" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  printf '%s,%s\n' "$(printf '%.1f' "$(echo "$i*0.5" | bc)")" "$VALS" >> "$OUT"
  if (( i % 10 == 0 )); then printf '\r  已采样 %s / %ss' "$(printf '%.0f' "$(echo "$i*0.5" | bc)")" "$DUR"; fi
  sleep 0.5
done
echo; echo

python3 - "$OUT" "$TAG" <<'PY'
import sys, csv, os
path, tag = sys.argv[1], sys.argv[2]
rows=list(csv.DictReader(open(path)))
if len(rows)<3: print("采样不足"); sys.exit(0)
keys=[k for k in rows[0] if k!='t']
first, last = rows[0], rows[-1]
def num(r,k):
    try: return int(r[k])
    except: return 0
print(f"════════ {tag} 采样报告  ({os.path.basename(path)}) ════════")
print(f"时长 {last['t']}s，{len(rows)} 个采样点\n")
print(f"{'指标':<42} {'起始':>14} {'结束':>14} {'增量':>12}")
print("-"*86)
for k in keys:
    a,b=num(first,k),num(last,k)
    print(f"{k:<42} {a:>14,} {b:>14,} {b-a:>+12,}")
mapped=[num(r,'debug.nvrmfb_vram_mapped_bytes') for r in rows]
budget=[num(r,'debug.nvrmfb_vram_budget_bytes') for r in rows]
waits=[num(r,'debug.nvaccel_surface_gpu_wait_max_us') for r in rows]
pct=[m*100/b for m,b in zip(mapped,budget) if b]
print()
print(f"BAR1 占用: 最低 {min(pct):.1f}%  平均 {sum(pct)/len(pct):.1f}%  峰值 {max(pct):.1f}%")
print(f"           mapped 峰值 {max(mapped)/1048576:.1f}MB / budget {max(budget)/1048576:.1f}MB")
print(f"surface 等待历史峰值: {max(waits)/1000:.1f} ms  (自开机累计最大值，不会回落，仅供参考)")
dw=num(last,'debug.nvaccel_surface_gpu_waits')-num(first,'debug.nvaccel_surface_gpu_waits')
d=num(last,'debug.nvaccel_vm_refused')-num(first,'debug.nvaccel_vm_refused')
secs=float(last['t'])
print(f"BAR1 映射拒绝  : {d:,} 次 / {secs:.0f}s = {d/secs:.1f} 次/秒   ← 主指标")
print(f"surface 等待   : {dw:,} 次 / {secs:.0f}s = {dw/secs:.1f} 次/秒")
print(f"iop_flip 次数  : {num(last,'debug.nvaccel_iop_flips')-num(first,'debug.nvaccel_iop_flips'):,}  (约等于实际帧数)")
print()
print("判读: 拒绝次数/秒 ↓、surface 等待次数/秒 ↓、BAR1 峰值占用 ↓ = 该组参数更有效")
print("      注意 vm_refused 是累计计数器，必须用「增量」比较；且空闲桌面本身就有基线拒绝率")
PY
echo
echo "结果已存: $OUT"
echo "对比不同预设时，用同一段视频跑同样时长，比较上面三个数字。"
read -r -p "按回车关闭..." _
