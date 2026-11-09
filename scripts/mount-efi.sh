#!/bin/bash
# mount-efi.sh — 挂载本机内置硬盘的 EFI 系统分区到 /tmp/esp
#
# 自动在所有 EFI 分区里挑位于内置磁盘上的那个（重启后 disk 编号会漂移）。
# 需要管理员密码。
#
# 用法：
#   ./scripts/mount-efi.sh          挂载
#   ./scripts/mount-efi.sh -u       卸载

set -u
MP="/tmp/esp"

if [ "${1:-}" = "-u" ]; then
    if mount | grep -q "$MP"; then
        sudo umount "$MP" && echo "已卸载 $MP"
    else
        echo "$MP 未挂载"
    fi
    exit 0
fi

find_internal_esp() {
    diskutil list 2>/dev/null | awk '/ EFI /{print $NF}' | while read -r dev; do
        [ -z "$dev" ] && continue
        loc=$(diskutil info "$dev" 2>/dev/null | awk -F': *' '/Device Location/{print $2}')
        if [ "$loc" = "Internal" ]; then
            echo "$dev"
            break
        fi
    done
}

DEV=$(find_internal_esp | head -1)
if [ -z "$DEV" ]; then
    echo "错误：未找到内置磁盘上的 EFI 分区" >&2
    exit 1
fi

echo "目标分区：$DEV"

# 已挂载则直接报告挂载点
if mount | grep -q "/dev/$DEV"; then
    P=$(mount | awk -v d="/dev/$DEV" '$1==d{print $3}')
    echo "已挂载于：$P"
    exit 0
fi

sudo mkdir -p "$MP"

# 方式一：diskutil
if sudo diskutil mount -mountPoint "$MP" "$DEV" >/dev/null 2>&1; then
    echo "挂载成功：$MP"
    ls "$MP"
    exit 0
fi

# 方式二：mount_msdos（绕过 DiskArbitration 对隐藏分区的拒绝）
if sudo mount -t msdos "/dev/$DEV" "$MP" 2>/dev/null; then
    echo "挂载成功（mount_msdos）：$MP"
    ls "$MP"
    exit 0
fi

echo "挂载失败：$DEV" >&2
echo "提示：若分区类型是 0x1B（隐藏），diskutil 会拒绝挂载，但 mount_msdos 通常可以。" >&2
exit 1
