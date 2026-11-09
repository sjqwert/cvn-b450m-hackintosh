#!/bin/bash
if [ -f /Library/LaunchDaemons/cn.laobamac.gpu-lab.plist ]; then
  echo "⚠️ 已启用融合守护，音频自愈由统一守护负责，本旧卸载器已停用。"
  echo "   请用 unified/卸载融合守护.command。"
  echo "按回车关闭..."; read -r _; exit 0
fi
PLIST="$HOME/Library/LaunchAgents/cn.laobamac.audio-output.plist"

echo "════════ 卸载：登录后自动切回输出 ════════"
echo

UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/cn.laobamac.audio-output" 2>/dev/null && echo "✅ 已停止守护" || echo "  (守护未在运行)"
launchctl unload "$PLIST" 2>/dev/null
rm -f "$PLIST" && echo "✅ 已删除 $PLIST"
echo
echo "默认输出不会再被自动改回 ALC662，可在系统设置里自由选 HDMI 输出。"
echo
echo "按回车关闭..."
read -r _
