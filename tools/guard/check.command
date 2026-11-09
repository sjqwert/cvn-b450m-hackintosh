#!/bin/bash
# 只读：查看融合守护的安装状态、launchd 状态、日志、当前呈现参数与默认输出
echo "════════ 融合守护状态 ════════"
echo
echo "── 守护 plist ──"
ls -l /Library/LaunchDaemons/cn.laobamac.gpu-lab.plist 2>&1
echo
echo "── 旧守护（应已移除或持久禁用）──"
OLD_P=/Library/LaunchDaemons/cn.laobamac.nvpresent.plist
OLD_A="$HOME/Library/LaunchAgents/cn.laobamac.audio-output.plist"
if [ -f "$OLD_P" ]; then
  if launchctl print-disabled system 2>/dev/null | grep -q '"cn.laobamac.nvpresent" => disabled'; then
    echo "  ✅ 旧呈现 plist 仍在，但 label 已持久禁用（launchd 不会加载）"
  else
    echo "  ⚠️ 旧呈现 plist 存在且未禁用 —— 请重跑「安装融合守护.command」"
  fi
else
  echo "  ✅ 旧呈现 plist 已移除"
fi
if [ -f "$OLD_A" ]; then
  echo "  ⚠️ 旧音频 plist 仍存在 —— 请重跑「安装融合守护.command」"
else
  echo "  ✅ 旧音频 plist 已移除"
fi
echo
echo "── launchd（一次性守护：not running + last exit code = 0 = 已正常完成）──"
LP=$(launchctl print system/cn.laobamac.gpu-lab 2>/dev/null | grep -E 'state =|program =|last exit|pid =' | head -6)
if [ -n "$LP" ]; then echo "$LP"; else echo "  (本会话读不到；以状态文件和日志为准)"; fi
echo
echo "── 状态文件 /var/db/gpu-lab.state ──"
cat /var/db/gpu-lab.state 2>/dev/null || echo "  (尚无：守护可能还在等驱动/30 秒延迟)"
echo
echo "── 日志关键行 /var/log/gpu-lab.log ──"
KL=$(grep -E '\[present\]|\[audio\]|\[guard\]' /var/log/gpu-lab.log 2>/dev/null | tail -8)
if [ -n "$KL" ]; then echo "$KL"; else echo "  (无日志)"; fi
echo "  完整日志（含设备列表）：/var/log/gpu-lab.log"
echo
echo "── 当前呈现参数 ──"
sysctl debug.nvaccel_iop_flip debug.nvrmfb_flip_latch 2>&1
echo
echo "── 当前默认输出 ──"
if [ -x /usr/local/bin/setoutput ]; then
  /usr/local/bin/setoutput list | grep -E '默认输出|系统输出'
else
  "$(cd "$(dirname "$0")" && pwd)/../audio/setoutput" list 2>/dev/null | grep -E '默认输出|系统输出' || echo "  (setoutput 不可用)"
fi
echo
echo "按回车关闭..."
read -r _
