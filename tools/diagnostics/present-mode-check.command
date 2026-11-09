#!/bin/bash
# 检查呈现模式状态与健康度（只读，不需要密码）
LB=cn.laobamac.nvpresent
IOP=$(sysctl -n debug.nvaccel_iop_flip 2>/dev/null)
LAT=$(sysctl -n debug.nvrmfb_flip_latch 2>/dev/null)
echo "════════ 呈现模式 ════════"
case "$IOP/$LAT" in
  1/2) echo "✅ 零拷贝 + 低延迟（推荐，横条已消除）" ;;
  1/1) echo "⚠️ 零拷贝 + 锁存等待（每帧多等一个刷新周期，会有延迟感）" ;;
  0/*) echo "❌ 拷贝路径（出厂默认，横条来源）" ;;
  *)   echo "? iop_flip=$IOP latch=$LAT" ;;
esac
echo
echo "════════ 驱动计数器 ════════"
for k in debug.nvaccel_iop_flips debug.nvaccel_iop_flip_hit debug.nvaccel_iop_flip_miss \
         debug.nvaccel_iop_flip_refused debug.nvaccel_iop_flip_stale debug.nvaccel_iop_flip_unwritten \
         debug.nvaccel_iop_fail debug.nvrmfb_flip_latch_timeouts; do
  printf "  %-38s %s\n" "${k#debug.}" "$(sysctl -n $k 2>/dev/null || echo -)"
done
echo
echo "════════ 显存窗口(BAR1) ════════"
M=$(sysctl -n debug.nvrmfb_vram_mapped_bytes 2>/dev/null)
B=$(sysctl -n debug.nvrmfb_vram_budget_bytes 2>/dev/null)
D=$(sysctl -n debug.nvrmfb_vram_display_bytes 2>/dev/null)
if [ -n "$B" ] && [ "$B" != "0" ]; then
  P=$(echo "$M*100/$B" | bc 2>/dev/null)
  printf "  mapped  %.0fMB / budget %.0fMB = 占用 %s%%\n" "$(echo "$M/1048576"|bc)" "$(echo "$B/1048576"|bc)" "$P"
  printf "  display 常驻 %.0fMB   (BAR1 物理 256MB)\n" "$(echo "$D/1048576"|bc)"
  if [ "$P" -ge 85 ] 2>/dev/null; then
    echo "  ⚠️ 占用率贴顶(≥85%) → 视频播放易 Out of memory 卡顿"
    echo "     根因: B450 主板 BAR1 锁死 256MB，无法开 Re-Size BAR"
  else
    echo "  ✅ 占用率健康"
  fi
else
  echo "  (无法读取显存计数)"
fi
echo
echo "════════ 开机固化 ════════"
if launchctl print "system/$LB" >/dev/null 2>&1; then
  echo "  LaunchDaemon : 已加载 ($LB)"
else
  echo "  LaunchDaemon : 未加载"
fi
[ -f /var/db/nvpresent.disabled ] && echo "  ⚠️ 存在禁用标记 /var/db/nvpresent.disabled（连续快速重启触发保护）"
echo "  --- 最近日志 ---"
tail -5 /var/log/nv-present.log 2>/dev/null | sed 's/^/  /' || echo "  (无日志)"
