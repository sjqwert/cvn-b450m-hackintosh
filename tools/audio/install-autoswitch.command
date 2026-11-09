#!/bin/bash
if [ -f /Library/LaunchDaemons/cn.laobamac.gpu-lab.plist ]; then
  echo "⚠️ 已启用融合守护，音频自愈由统一守护负责，本旧安装器已停用。"
  echo "   请用 unified/安装融合守护.command；卸载融合守护后本工具会自动恢复。"
  echo "按回车关闭..."; read -r _; exit 0
fi
D="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/cn.laobamac.audio-output.plist"

echo "════════ 安装：登录后自动把默认输出切回 ALC662 ════════"
echo

if [ ! -x "$D/setoutput" ]; then
  echo "编译 CoreAudio 小工具…"
  clang -O2 -fobjc-arc -framework Foundation -framework CoreAudio -o "$D/setoutput" "$D/setoutput.m" || {
    echo "❌ 编译失败"; echo "按回车关闭..."; read -r _; exit 1
  }
fi

chmod +x "$D/audio-guard.sh"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>cn.laobamac.audio-output</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$D/audio-guard.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/cn.laobamac.audio-output.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/cn.laobamac.audio-output.err</string>
</dict>
</plist>
EOF

echo "=== plist 语法校验 ==="
plutil -lint "$PLIST" || { echo "❌ plist 无效"; exit 1; }

UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/cn.laobamac.audio-output" 2>/dev/null
launchctl unload "$PLIST" 2>/dev/null
if ! launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>&1; then
  echo "  bootstrap 失败，回退 legacy load…"
  launchctl load -w "$PLIST" 2>&1
fi
echo
echo "=== 已加载 ==="
launchctl list 2>/dev/null | grep cn.laobamac.audio-output || echo "  (未出现在列表，检查上面的报错)"
echo
echo "=== 立即跑一次 ==="
/bin/bash "$D/audio-guard.sh" && echo "✅ 守护执行成功" || echo "⚠️ 守护超时，看 /tmp/cn.laobamac.audio-output.log"
tail -6 /tmp/cn.laobamac.audio-output.log 2>/dev/null
echo
echo "说明：只在「默认输出是 NVIDIA HDMI」时才切回；已选 ALC662 时什么都不做。"
echo "以后若想用显示器 HDMI 音频，先双击「卸载开机自动切回.command」。"
echo
echo "按回车关闭..."
read -r _
