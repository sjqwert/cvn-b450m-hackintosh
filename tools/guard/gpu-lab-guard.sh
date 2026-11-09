#!/bin/sh
# /usr/local/bin/gpu-lab-guard.sh
# 融合守护：一次启动完成「呈现参数固化」+「默认输出切回 ALC662」
# 以 root 运行（LaunchDaemon）；用户态 CoreAudio 动作经 launchctl asuser 下发。
# 环境变量：GPU_LAB_IOP / GPU_LAB_LATCH / GPU_LAB_DELAY / GPU_LAB_DRY / GPU_LAB_SETOUTPUT

IOP=${GPU_LAB_IOP:-1}
LATCH=${GPU_LAB_LATCH:-2}
DELAY=${GPU_LAB_DELAY:-30}
DRY=${GPU_LAB_DRY:-0}
SETOUTPUT=${GPU_LAB_SETOUTPUT:-/usr/local/bin/setoutput}

STATE=/var/db/gpu-lab.state
DISABLE=/var/db/gpu-lab.disabled
LOG=/var/log/gpu-lab.log

if [ "$DRY" = "1" ]; then
    STATE=/tmp/gpu-lab-dry.state
    DISABLE=/tmp/gpu-lab-dry.disabled
    LOG=/tmp/gpu-lab-dry.log
    : > "$LOG"
fi

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

if [ -f "$DISABLE" ]; then
    log "[guard] 存在禁用标记 ${DISABLE} ，跳过"
    exit 0
fi

# 必须锚定开头的 sec，贪婪 .*sec 会误匹配到 usec = 取到微秒值
BOOT=$(sysctl -n kern.boottime 2>/dev/null | sed -nE 's/^\{ sec = ([0-9]+),.*/\1/p')
[ -z "$BOOT" ] && BOOT=0
APPLIED=0
RAPID=0
[ -f "$STATE" ] && . "$STATE"

# 180 秒内连续快速重启 = 异常，自动停手（沿用旧 nvpresent 的保护逻辑）
if [ "${APPLIED:-0}" -gt 0 ] && [ "$BOOT" -gt "${APPLIED}" ] && [ $((BOOT - APPLIED)) -lt 180 ]; then
    RAPID=$(( ${RAPID:-0} + 1 ))
fi
if [ "${RAPID:-0}" -ge 2 ]; then
    printf 'rapid=1 %s\n' "$(date)" > "$DISABLE"
    log "[guard] 连续两次快速重启，自动禁用（删除 ${DISABLE} 可恢复）"
    exit 0
fi

# 阶段 A：等驱动 sysctl 树注册 + WindowServer 起来，再等 auto-go 稳定
i=0
while [ $i -lt 60 ]; do
    if [ "$DRY" = "1" ]; then break; fi
    sysctl -n debug.nvaccel_iop_flip >/dev/null 2>&1 \
        && pgrep -x WindowServer >/dev/null 2>&1 && break
    sleep 3
    i=$((i+1))
done
log "[present] 驱动/WindowServer 等待 $((i*3)) 秒（上限 180 秒）"
if [ "$DRY" = "0" ]; then sleep "$DELAY"; fi

if [ "$DRY" = "1" ]; then
    log "[present] DRY: 将写 iop_flip=${IOP} latch=${LATCH} , 延迟 ${DELAY} 秒已跳过"
    P_IOP=$IOP
    P_LATCH=$LATCH
    PRESENT_OK=1
else
    CUR=$(sysctl -n debug.nvaccel_iop_flip 2>/dev/null)
    if [ "$CUR" = "$IOP" ]; then
        log "[present] 零拷贝已开启，跳过 iop_flip"
    else
        sysctl -w "debug.nvaccel_iop_flip=${IOP}" >> "$LOG" 2>&1
    fi
    sysctl -w "debug.nvrmfb_flip_latch=${LATCH}" >> "$LOG" 2>&1
    P_IOP=$(sysctl -n debug.nvaccel_iop_flip 2>/dev/null)
    P_LATCH=$(sysctl -n debug.nvrmfb_flip_latch 2>/dev/null)
    log "[present] 应用完成 iop_flip=${P_IOP} flip_latch=${P_LATCH}"
    if [ "$P_IOP" = "$IOP" ] && [ "$P_LATCH" = "$LATCH" ]; then PRESENT_OK=1; else PRESENT_OK=0; fi
fi

# 阶段 B：等 GUI 用户登录，再用 asuser 把音频动作放进该用户的会话
console_uid() {
    u=$(stat -f %Su /dev/console 2>/dev/null)
    [ -z "$u" ] && return 1
    [ "$u" = "root" ] && return 1
    id -u "$u" 2>/dev/null
}

UID_NUM=""
j=0
while [ $j -lt 20 ]; do
    if [ "$DRY" = "1" ]; then UID_NUM=501; break; fi
    UID_NUM=$(console_uid) && break
    UID_NUM=""
    sleep 3
    j=$((j+1))
done

AUDIO_OK=0
if [ -n "$UID_NUM" ] && [ -x "$SETOUTPUT" ]; then
    k=0
    while [ $k -lt 20 ]; do
        if [ "$DRY" = "1" ]; then
            log "[audio] DRY: launchctl asuser ${UID_NUM} ${SETOUTPUT} guard"
            AUDIO_OK=1
            break
        fi
        if /bin/launchctl asuser "$UID_NUM" "$SETOUTPUT" guard >> "$LOG" 2>&1; then
            AUDIO_OK=1
            log "[audio] 默认输出守护完成 (uid=${UID_NUM} , 第 $((k+1)) 次尝试)"
            break
        fi
        sleep 3
        k=$((k+1))
    done
    [ "$AUDIO_OK" = "0" ] && log "[audio] 失败：20 次重试仍不成功 (uid=${UID_NUM} )"
else
    log "[audio] 失败：无 GUI 用户或 ${SETOUTPUT} 不存在 (UID=[${UID_NUM}] )"
fi

printf 'RAPID=%s\nAPPLIED=%s\nPRESENT_OK=%s\nPRESENT_IOP=%s\nPRESENT_LATCH=%s\nAUDIO_OK=%s\nAUDIO_UID=%s\n' \
    "${RAPID:-0}" "$BOOT" "$PRESENT_OK" "$P_IOP" "$P_LATCH" "$AUDIO_OK" "$UID_NUM" > "$STATE"
log "[guard] 完成 present=${PRESENT_OK} audio=${AUDIO_OK} -> ${STATE}"
