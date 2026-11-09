#!/bin/sh
# 以 root 运行：安装融合守护，并退役旧的两套守护（先备份，可回滚）
# 注意：/Library/LaunchDaemons -> 用户目录可能是跨卷 rename，mv 会 EACCES；
#       统一用 cp -p 备份 + rm -f 删除，备份主目录放在 root 可写的 /var/db。
exec > /tmp/gpu-lab-install.out 2>&1
set -u

SRC=$(cd "$(dirname "$0")" && pwd)
GPU_LAB_DIR=$(dirname "$SRC")
LAB=cn.laobamac.gpu-lab
PL=/Library/LaunchDaemons/$LAB.plist
OLD_D=/Library/LaunchDaemons/cn.laobamac.nvpresent.plist
OLD_A_LABEL=cn.laobamac.audio-output
BACKUP=/var/db/gpu-lab-legacy
USER_BACKUP="$SRC/legacy-backup"
STAMP=$(date +%Y%m%d-%H%M%S)

CU=$(stat -f %Su /dev/console 2>/dev/null)
[ -z "$CU" ] && CU=$(id -un)
UID_NUM=$(id -u "$CU" 2>/dev/null || echo 501)
UHOME=$(dscl . -read "/Users/$CU" NFSHomeDirectory 2>/dev/null | sed -E 's/^NFSHomeDirectory: *//')
[ -z "$UHOME" ] && UHOME="/Users/$CU"
OLD_A="$UHOME/Library/LaunchAgents/$OLD_A_LABEL.plist"

echo "════════ 安装融合守护 ${LAB} ════════"
echo "GUI 用户: ${CU} (uid=${UID_NUM})  home=${UHOME}"
echo

echo "── 1. 退役旧的两套守护（先备份，再删除 plist）──"
mkdir -p "$BACKUP" "$USER_BACKUP" 2>/dev/null
launchctl bootout "system/cn.laobamac.nvpresent" 2>/dev/null && echo "  ✅ 停止旧呈现守护" || echo "  (旧呈现守护未在运行)"
launchctl bootout "gui/$UID_NUM/$OLD_A_LABEL" 2>/dev/null && echo "  ✅ 停止旧音频守护" || echo "  (旧音频守护未在运行)"
launchctl unload "$OLD_D" 2>/dev/null
launchctl unload "$OLD_A" 2>/dev/null

if [ -f "$OLD_D" ]; then
    cp -p "$OLD_D" "$BACKUP/cn.laobamac.nvpresent.plist.$STAMP" 2>/dev/null
    cp -p "$OLD_D" "$USER_BACKUP/cn.laobamac.nvpresent.plist.$STAMP" 2>/dev/null
    /bin/rm -f "$OLD_D" 2>&1
else
    echo "  (无旧呈现 plist，跳过)"
fi
# 关键兜底：即使 plist 删不掉，也持久禁用 label，launchd 重启后绝不会加载它
/bin/launchctl disable system/cn.laobamac.nvpresent 2>/dev/null
if [ ! -f "$OLD_D" ]; then
    echo "  ✅ 旧呈现 plist 已移除，且 label 已持久禁用"
else
    echo "  ✅ 旧呈现 plist 保留但 label 已持久禁用（launchd 不会加载）"
fi

if [ -f "$OLD_A" ]; then
    cp -p "$OLD_A" "$BACKUP/cn.laobamac.audio-output.plist.$STAMP" 2>/dev/null
    cp -p "$OLD_A" "$USER_BACKUP/cn.laobamac.audio-output.plist.$STAMP" 2>/dev/null
    rm -f "$OLD_A" 2>/dev/null
    if [ ! -f "$OLD_A" ]; then
        echo "  ✅ 旧音频 plist 已备份并移除"
    else
        echo "  ❌ 旧音频 plist 删除失败，需手动处理：${OLD_A}"
    fi
else
    echo "  (无旧音频 plist，跳过)"
fi
echo

echo "── 2. 安装新文件 ──"
mkdir -p /usr/local/bin
install -m 755 -o root -g wheel "$SRC/gpu-lab-guard.sh" /usr/local/bin/gpu-lab-guard.sh || { echo "❌ 守护脚本安装失败"; exit 1; }
install -m 644 -o root -g wheel "$SRC/cn.laobamac.gpu-lab.plist" "$PL" || { echo "❌ plist 安装失败"; exit 1; }
echo "  ✅ /usr/local/bin/gpu-lab-guard.sh"
echo "  ✅ ${PL}"

AUDIOFIX="$SRC/../audio"
if [ -x "$AUDIOFIX/setoutput" ]; then
    install -m 755 -o root -g wheel "$AUDIOFIX/setoutput" /usr/local/bin/setoutput \
        && echo "  ✅ /usr/local/bin/setoutput（复用已编译二进制）"
elif [ -f "$AUDIOFIX/setoutput.m" ]; then
    clang -O2 -fobjc-arc -framework Foundation -framework CoreAudio \
        -o /usr/local/bin/setoutput "$AUDIOFIX/setoutput.m" \
        && echo "  ✅ /usr/local/bin/setoutput（现场编译）"
else
    echo "❌ 找不到 audio-fix/setoutput 或 setoutput.m"
    exit 1
fi
echo

echo "── 3. 加载守护 ──"
launchctl bootout "system/$LAB" 2>/dev/null
sleep 1
if launchctl bootstrap system "$PL" 2>&1; then
    echo "  ✅ bootstrap system 成功"
elif launchctl load -w "$PL" 2>&1; then
    echo "  ✅ legacy load 成功"
else
    echo "  ❌ 加载失败，检查上面的报错"
fi
launchctl print "system/$LAB" 2>/dev/null | grep -E 'state =|program =|last exit' | head -5
echo

echo "════════ 完成 ════════"
echo "日志: /var/log/gpu-lab.log   状态: /var/db/gpu-lab.state"
echo "守护启动后约 35-40 秒完成，双击「检查融合守护.command」查看结果。"
echo "旧守护备份: ${BACKUP} （工作区副本: ${USER_BACKUP} ）"
exit 0
