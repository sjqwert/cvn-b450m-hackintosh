#!/bin/bash
# 显示呈现模式切换（双击运行，会弹一次管理员密码）
# 三种模式，改完 sysctl 立即生效；系重启后自动恢复默认，不会残留
cd "$(dirname "$0")" || exit 1
G=$(sysctl -n debug.nvaccel_iop_flip 2>/dev/null)
L=$(sysctl -n debug.nvrmfb_flip_latch 2>/dev/null)
CUR="当前：zero-copy=${G}  latch=${L}"

CHOICE=$(osascript <<EOF
set r to choose from list {"A 拷贝模式（出厂默认）", "B 零拷贝 + 低延迟（推荐）", "C 零拷贝 + 锁存等待（低撕裂）"} with title "显示呈现模式" with prompt "$CUR

选一个，然后播一段抖音对比：" default items {"B 零拷贝 + 低延迟（推荐）"}
if r is false then return "cancel"
return item 1 of r
EOF
)

case "$CHOICE" in
  A*) IOP=0; LAT=1; NAME="拷贝模式（默认）" ;;
  B*) IOP=1; LAT=2; NAME="零拷贝 + 低延迟" ;;
  C*) IOP=1; LAT=1; NAME="零拷贝 + 锁存等待" ;;
  *)  echo "已取消"; exit 0 ;;
esac

echo "→ 应用：$NAME  (iop_flip=$IOP latch=$LAT)"
osascript -e "do shell script \"/bin/sh '$PWD/nvapply.sh' $IOP $LAT > /dev/null 2>&1 &\" with administrator privileges" >/dev/null 2>&1
sleep 2

G2=$(sysctl -n debug.nvaccel_iop_flip 2>/dev/null)
L2=$(sysctl -n debug.nvrmfb_flip_latch 2>/dev/null)
echo "现在：zero-copy=${G2}  latch=${L2}"
if [ "$G2" = "$IOP" ] && [ "$L2" = "$LAT" ]; then
  echo "✅ 已生效。播一段视频看看；要测数据就跑 ./flipmeasure.sh 8"
else
  echo "⚠️ 可能没生效，重跑一次或检查密码是否输入"
fi
echo
if launchctl print system/cn.laobamac.nvpresent >/dev/null 2>&1; then
  echo "提示：已装开机固化（cn.laobamac.nvpresent），重启后约 1 分半会自动回到 B 模式。"
  echo "      想永久换成别的模式 → 改 /usr/local/bin/nv-present-mode.sh 里的 NV_IOP_FLIP / NV_FLIP_LATCH"
else
  echo "提示：未装开机固化，本次设置重启即失效。"
fi
sleep 1
