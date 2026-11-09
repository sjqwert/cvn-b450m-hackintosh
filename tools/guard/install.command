#!/bin/bash
# 双击安装融合守护（需管理员密码），并退役旧的两套守护
D="$(cd "$(dirname "$0")" && pwd)"

echo "════════ 安装融合守护（需管理员密码）════════"
echo
osascript -e 'with timeout of 180 seconds' -e "do shell script \"/bin/sh '$D/install.sh'\" with administrator privileges" -e 'end timeout' >/dev/null 2>&1
rc=$?
cat /tmp/gpu-lab-install.out 2>/dev/null || echo "（无输出，可能取消了密码框）"
echo
if [ "$rc" -ne 0 ]; then echo "⚠️ 提权未成功或安装脚本报错（rc=$rc），以上方输出为准"; fi
echo
echo "按回车关闭..."
read -r _
