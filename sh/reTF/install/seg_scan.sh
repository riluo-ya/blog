#!/data/data/com.termux/files/usr/bin/bash
#
# seg_scan.sh —— 分段扫描：一段一段「读卡 → 存临时镜像 → 抠图 → 删镜像」
#
# 为什么要用它：
#   管道模式一旦中断（OTG 掉线、息屏、读卡器松脱）就得从头再来。分段模式每段
#   单独落一个临时镜像，抠完立刻删，中断后重跑本脚本会自动跳过已完成的段。
#
# 用法（在普通 shell 里跑，不用套 termux-usb）：
#   chmod +x seg_scan.sh
#   ./seg_scan.sh
#
# 可用环境变量：
#   DEVICE=/dev/bus/usb/001/002  USB 设备路径。留空则自动探测（推荐留空，
#                                因为每次重插读卡器设备号都会变）
#   TOTAL_SECTORS=1048576000     卡总扇区数。强烈建议先用 scsi_dump --probe
#                                测出真实容量再填，能省掉扫无用区域的时间
#   SEG_GB=10                    每段多少 GB，默认 10
#   OUTDIR=$HOME/recovered       最终照片输出目录
#   TMPDIR=$HOME/segtmp          临时镜像目录（每段抠完自动删）
#   ONLY=jpg,png,heic            抠哪些类型
#   MINSIZE=50000                小于多少字节丢弃（过滤缩略图）
#   START_SEG=-1                 从第几段开始，-1 表示自动跳过已完成的
#   MAXERR=256                   连续读失败多少次判定掉线（见 scsi_dump）
#
# 注意：本脚本会反复调用 termux-usb，每次弹权限确认，勾选"记住"即可。
#

HOME_DIR="$HOME"
OUTDIR="${OUTDIR:-$HOME_DIR/recovered}"
TMPDIR="${TMPDIR:-$HOME_DIR/segtmp}"
SEG_GB="${SEG_GB:-10}"
ONLY="${ONLY:-jpg,png,heic}"
MINSIZE="${MINSIZE:-50000}"
START_SEG="${START_SEG:--1}"
MAXERR="${MAXERR:-256}"
DEVICE="${DEVICE:-}"
TOTAL_SECTORS="${TOTAL_SECTORS:-1048576000}"

DONEFILE="$TMPDIR/done.txt"
mkdir -p "$OUTDIR" "$TMPDIR"
[ -f "$DONEFILE" ] || touch "$DONEFILE"

# 从 termux-usb -l 的 JSON 输出里抽出第一个设备路径
pick_device() {
    termux-usb -l 2>/dev/null \
        | grep -o '/dev/bus/usb/[0-9]*/[0-9]*' \
        | head -1
}

SECTORS_PER_GB=$(( 1024 * 1024 * 1024 / 512 ))   # 2097152
SEG_SECTORS=$(( SEG_GB * SECTORS_PER_GB ))
TOTAL_SEGS=$(( (TOTAL_SECTORS + SEG_SECTORS - 1) / SEG_SECTORS ))

echo "卡总容量: $TOTAL_SECTORS 扇区 ($(( TOTAL_SECTORS / SECTORS_PER_GB )) GB)"
echo "每段: ${SEG_GB}GB  共 $TOTAL_SEGS 段"
echo "输出: $OUTDIR   临时镜像: $TMPDIR"
echo "----------------------------------------"

if [ "$START_SEG" = "-1" ]; then
    START_SEG=0
    while grep -qx "$START_SEG" "$DONEFILE"; do
        START_SEG=$(( START_SEG + 1 ))
    done
    [ "$START_SEG" -gt 0 ] && echo "从第 $START_SEG 段继续（前面的已完成）"
fi

for (( i = START_SEG; i < TOTAL_SEGS; i++ )); do
    if grep -qx "$i" "$DONEFILE"; then
        continue
    fi

    START_LBA=$(( i * SEG_SECTORS ))
    REMAIN=$(( TOTAL_SECTORS - START_LBA ))
    [ "$REMAIN" -le 0 ] && break
    N=$SEG_SECTORS
    [ "$REMAIN" -lt "$N" ] && N=$REMAIN

    SEGIMG="$TMPDIR/seg_$(printf '%03d' "$i").img"
    echo ""
    echo "===== 第 $i / $((TOTAL_SEGS - 1)) 段  LBA $START_LBA + $N ($(( N / SECTORS_PER_GB ))GB) ====="
    echo "开始: $(date '+%H:%M:%S')"

    ok=0
    for attempt in 1 2; do
        # 设备号可能因为重插/OTG 重连而变，每次都重新探测
        if [ -z "$DEVICE" ] || [ ! -e "$DEVICE" ]; then
            DEV="$(pick_device)"
            if [ -z "$DEV" ]; then
                echo "  !! 没探测到 USB 设备。读卡器掉了？重新插一下再回车继续"
                read -r
                DEV="$(pick_device)"
                [ -z "$DEV" ] && { echo "  !! 仍未探测到，跳过本段"; continue; }
            fi
            echo "  使用设备: $DEV"
        else
            DEV="$DEVICE"
        fi

        rm -f "$SEGIMG"
        termux-usb -r -e "$HOME_DIR/scsi_wrap.sh -s $START_LBA -n $N -b 128 --max-errors $MAXERR -o $SEGIMG" "$DEV"
        rc=$?

        if [ $rc -eq 0 ] && [ -s "$SEGIMG" ]; then
            ok=1
            break
        fi

        echo "  !! 第 $i 段第 $attempt 次失败（退出码 $rc）"
        if [ $rc -eq 4 ]; then
            echo "     读卡器中途掉线或超出真实容量。请重新插卡后回车重试"
        else
            echo "     设备可能已断开，请检查后回车重试"
        fi
        rm -f "$SEGIMG"
        read -r
    done

    if [ "$ok" != "1" ]; then
        echo "  !! 第 $i 段放弃，继续下一段"
        continue
    fi

    echo "抠图中... $(date '+%H:%M:%S')"
    python3 "$HOME_DIR/carve_photos.py" "$SEGIMG" "$OUTDIR" \
        --only "$ONLY" --min-size "$MINSIZE" --state "$TMPDIR/state_$i.json"

    rm -f "$SEGIMG"
    echo "$i" >> "$DONEFILE"
    echo "第 $i 段完成 $(date '+%H:%M:%S')  已恢复: $(ls "$OUTDIR" 2>/dev/null | wc -l) 个"
done

echo ""
echo "======================================"
echo "结束。共恢复 $(ls "$OUTDIR" 2>/dev/null | wc -l) 个文件 -> $OUTDIR"
echo "整理照片："
echo "  python3 $HOME_DIR/rename_by_exif.py $OUTDIR ${OUTDIR}_已整理 --min-size 50000"
