#!/bin/bash
# 登录后守护：等 NMXAudio 设备就绪，仅在默认输出被 NVIDIA HDMI 抢走时切回 ALC662
D="$(cd "$(dirname "$0")" && pwd)"
LOG=/tmp/cn.laobamac.audio-output.log
: > "$LOG"

if [ ! -x "$D/setoutput" ]; then
  clang -O2 -fobjc-arc -framework Foundation -framework CoreAudio -o "$D/setoutput" "$D/setoutput.m" || exit 1
fi

i=0
while [ $i -lt 30 ]; do
  if "$D/setoutput" guard >> "$LOG" 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') guard 完成" >> "$LOG"
    exit 0
  fi
  /bin/sleep 3
  i=$((i+1))
done

echo "$(date '+%Y-%m-%d %H:%M:%S') guard 超时：ALC662 未就绪或切换失败" >> "$LOG"
exit 1
