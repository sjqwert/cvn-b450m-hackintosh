#!/bin/sh
# 以 root 运行：移除融合守护，并从备份恢复旧的两套守护
exec > /tmp/gpu-lab-uninstall.out 2>&1
set -u

SRC=$(cd "$(dirname "$0")" && pwd)
LAB=cn.laobamac.gpu-lab
PL=/Library/LaunchDaemons/$LAB.plist
BACKUP=/var/db/gpu-lab-legacy
USER_BACKUP="$SRC/legacy-backup"

CU=$(stat -f %Su /dev/console 2>/dev/null)
[ -z "$CU" ] && CU=$(id -un)
UID_NUM=$(id -u "$CU" 2>/dev/null || echo 501)
UHOME=$(dscl . -read "/Users/$CU" NFSHomeDirectory 2>/dev/null | sed -E 's/^NFSHomeDirectory: *//')
[ -z "$UHOME" ] && UHOME="/Users/$CU"

echo "════════ 卸载融合守护 ${LAB} ════════"
launchctl bootout "system/$LAB" 2>/dev/null && echo "  ✅ 已停止融合守护" || echo "  (融合守护未在运行)"
launchctl unload "$PL" 2>/dev/null
rm -f "$PL" /usr/local/bin/gpu-lab-guard.sh /var/db/gpu-lab.state /var/db/gpu-lab.disabled
echo "  ✅ 已移除 plist / 脚本 / 状态文件（呈现参数保持当前值，不主动改回去）"
echo

echo "── 从备份恢复旧守护 ──"
NV=$(ls -1t "$BACKUP"/cn.laobamac.nvpresent.plist.[0-9]* 2>/dev/null | head -1)
AO=$(ls -1t "$BACKUP"/cn.laobamac.audio-output.plist.[0-9]* 2>/dev/null | head -1)
[ -z "$NV" ] && NV=$(ls -1t "$USER_BACKUP"/cn.laobamac.nvpresent.plist.[0-9]* 2>/dev/null | head -1)
[ -z "$AO" ] && AO=$(ls -1t "$USER_BACKUP"/cn.laobamac.audio-output.plist.[0-9]* 2>/dev/null | head -1)

if [ -n "$NV" ] && [ -f "$NV" ]; then
    /bin/launchctl enable system/cn.laobamac.nvpresent 2>/dev/null
    cp -p "$NV" /Library/LaunchDaemons/cn.laobamac.nvpresent.plist
    chown root:wheel /Library/LaunchDaemons/cn.laobamac.nvpresent.plist
    if launchctl bootstrap system /Library/LaunchDaemons/cn.laobamac.nvpresent.plist 2>/dev/null \
        || launchctl load -w /Library/LaunchDaemons/cn.laobamac.nvpresent.plist 2>/dev/null; then
        echo "  ✅ 旧呈现守护已恢复 ($(basename "$NV"))"
    else
        echo "  ⚠️ 旧呈现 plist 已放回，但加载未成功（下次重启会自动加载）"
    fi
else
    echo "  (无旧呈现守护备份，跳过)"
fi

if [ -n "$AO" ] && [ -f "$AO" ]; then
    mkdir -p "$UHOME/Library/LaunchAgents"
    cp -p "$AO" "$UHOME/Library/LaunchAgents/cn.laobamac.audio-output.plist"
    chown "$CU" "$UHOME/Library/LaunchAgents/cn.laobamac.audio-output.plist"
    if launchctl bootstrap "gui/$UID_NUM" "$UHOME/Library/LaunchAgents/cn.laobamac.audio-output.plist" 2>/dev/null \
        || launchctl load -w "$UHOME/Library/LaunchAgents/cn.laobamac.audio-output.plist" 2>/dev/null; then
        echo "  ✅ 旧音频守护已恢复 ($(basename "$AO"))"
    else
        echo "  ⚠️ 旧音频 plist 已放回，但加载未成功（下次登录会自动加载）"
    fi
else
    echo "  (无旧音频守护备份，跳过)"
fi

echo
echo "════════ 完成 ════════"
echo "如需彻底回到出厂呈现路径：sudo sysctl -w debug.nvaccel_iop_flip=0 debug.nvrmfb_flip_latch=1"
exit 0
