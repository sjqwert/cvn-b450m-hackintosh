#!/bin/bash
cd "$(dirname "$0")" || exit 1

echo "════════ 恢复声音：把默认输出切回 ALC662 ════════"
echo

if [ ! -x ./setoutput ] || [ setoutput.m -nt ./setoutput ]; then
  echo "首次运行，正在编译 CoreAudio 小工具…"
  clang -O2 -fobjc-arc -framework Foundation -framework CoreAudio -o setoutput setoutput.m
  if [ $? -ne 0 ]; then
    echo "❌ 编译失败，请把本窗口内容发给我"
    echo "按回车关闭..."; read -r _; exit 1
  fi
fi

echo "── 切换前 ──"
./setoutput list
echo
echo "── 执行切换 ──"
./setoutput auto
rc=$?
echo
echo "── 切换后 ──"
./setoutput list | grep -E '默认输出|系统输出|===|#' || true
echo

if [ "$rc" -eq 0 ]; then
  echo "✅ 默认输出已切回内置声卡"
  echo
  echo "如果还是没声音，按顺序试："
  echo "  1. 把正在放声音的 App 完全退出（Cmd+Q）再打开 —— 已建立的音频流不会自动迁移"
  echo "  2. 拔插一次耳机/音箱，确认插在主板后面板的绿色 3.5mm 口"
  echo "  3. 系统设置 › 声音 › 输出，手动选 Realtek ALC662 (Analog 2.0+HP/2.0)"
  echo "  4. 若下次重启又被抢，双击同目录的「安装开机自动切回.command」"
else
  echo "❌ 切换未生效，把本窗口内容发给我"
fi

echo
echo "按回车关闭..."
read -r _
