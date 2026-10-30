#!/data/data/com.termux/files/usr/bin/bash
# =====================================================================
#  reTF 主页脚本  ——  TF 卡照片恢复工具箱（无 root / Termux + OTG）
#
#  用法：
#    cd /retf && bash main.sh
#    （也可以：bash ~/retf/main.sh，路径随意，脚本会自动定位安装目录）
#
#  设计原则：所有选择都用「数字」输入，需要手写的只有 USB 设备路径
# =====================================================================

set -u

# ---------- 定位安装目录 & 载入配置 ----------
RETF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -z "${RETF:-}" ] && RETF="$HOME/retf"
CONF="$RETF/retf.conf"
[ -f "$CONF" ] && . "$CONF"

# 默认值（配置文件里没有时用这些）
DEVICE="${DEVICE:-}"
SEG_GB="${SEG_GB:-10}"
TOTAL_SECTORS="${TOTAL_SECTORS:-0}"
ONLY="${ONLY:-jpg,png,heic}"
MINSIZE="${MINSIZE:-50000}"
MAXERR="${MAXERR:-256}"
OUTDIR="${OUTDIR:-~/recovered}"
SORTED="${SORTED:-~/recovered_已整理}"
TMP="${TMP:-~/retf_tmp}"
ALBUM="${ALBUM:-/storage/emulated/0/DCIM/Camera}"

exp() { local p="$1"; case "$p" in "~/"*) printf '%s/%s' "$HOME" "${p#\~/}";; *) printf '%s' "$p";; esac; }
OUTDIR="$(exp "$OUTDIR")"; SORTED="$(exp "$SORTED")"; TMP="$(exp "$TMP")"

SECTORS_PER_GB=2097152          # 1GiB = 2097152 个 512 字节扇区
STATE="$TMP/scan_state"
mkdir -p "$TMP" "$OUTDIR" 2>/dev/null

# ---------- 颜色 ----------
if [ -t 1 ]; then
    G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; B='\033[1;36m'; D='\033[2m'; N='\033[0m'
else
    G=''; Y=''; R=''; B=''; D=''; N=''
fi
hr()  { printf "${D}%s${N}\n" "------------------------------------------------------------"; }
ok()  { printf "${G}[OK]${N} %s\n" "$*"; }
warn(){ printf "${Y}[!]${N} %s\n" "$*"; }
err() { printf "${R}[X]${N} %s\n" "$*"; }

save_conf() {
    cat > "$CONF" <<EOF
# reTF 配置（main.sh 自动维护，也可手改）
RETF="$RETF"
DEVICE="$DEVICE"
SEG_GB=$SEG_GB
TOTAL_SECTORS=$TOTAL_SECTORS
ONLY="$ONLY"
MINSIZE=$MINSIZE
MAXERR=$MAXERR
OUTDIR="~/$(exp "$OUTDIR" | sed "s|^$HOME/||")"
SORTED="~/$(exp "$SORTED" | sed "s|^$HOME/||")"
TMP="~/$(exp "$TMP" | sed "s|^$HOME/||")"
ALBUM="$ALBUM"
EOF
}

# ---------- 设备相关 ----------
pick_device() { termux-usb -l 2>/dev/null | grep -o '/dev/bus/usb/[0-9]*/[0-9]*' | head -1; }

# 确保有可用的设备路径：先自动探测，探测不到就让用户输入
need_device() {
    if [ -n "${DEVICE:-}" ] && [ -e "$DEVICE" ]; then return 0; fi
    local d
    d="$(pick_device)"
    [ -n "$d" ] && DEVICE="$d" && save_conf && return 0
    hr
    warn "没自动探测到 USB 设备。请检查：OTG 开关、读卡器是否插好、Termux:API 是否允许后台运行"
    printf "    也可以先选菜单 ${B}1${N} 看 termux-usb -l 的输出，再把路径抄过来\n"
    printf "    请输入设备路径（如 /dev/bus/usb/001/002，直接回车=重新探测）："
    read -r d
    if [ -n "$d" ]; then DEVICE="$d"; save_conf; return 0; fi
    d="$(pick_device)"
    [ -n "$d" ] && DEVICE="$d" && save_conf && return 0
    return 1
}

# 运行 scsi_dump：参数通过 wrapper 传给 termux-usb
run_dump() {  # run_dump <设备> <参数...>
    local dev="$1"; shift
    termux-usb -r -e "$RETF/scsi_wrap.sh $*" "$dev"
}

# =====================================================================
#  菜单功能
# =====================================================================

# 1. 列出 USB 设备
f_list_usb() {
    hr
    printf "${B}当前 USB 设备列表${N}（termux-usb -l）\n"
    hr
    if ! command -v termux-usb >/dev/null 2>&1; then
        err "termux-usb 不存在，请先：pkg install termux-api，并安装 Termux:API App"
        return
    fi
    local out d
    out="$(termux-usb -l 2>&1)"
    printf '%s\n' "$out"
    echo ""
    d="$(printf '%s' "$out" | grep -o '/dev/bus/usb/[0-9]*/[0-9]*' | head -1)"
    if [ -n "$d" ]; then
        printf "检测到设备：${G}%s${N}\n" "$d"
        printf "是否把它设为当前使用的设备？[1=是 0=否]（默认 1）："
        read -r c; [ "${c:-1}" = "1" ] && DEVICE="$d" && save_conf && ok "已保存：$d"
    else
        warn "列表为空 → 检查 OTG 开关 / 重插读卡器 / Termux:API 后台权限，然后重试"
    fi
}

# 2. 看卡信息（容量）
f_info() {
    hr
    need_device || { err "没有可用设备，先去菜单 1 确认"; return; }
    printf "${B}读取卡信息${N}  设备：$DEVICE\n"
    printf "（手机上会弹 USB 授权框，点「允许」，可勾选记住）\n"
    hr
    local out
    out="$(run_dump "$DEVICE" --info 2>&1)"
    printf '%s\n' "$out"
    local tb
    tb="$(printf '%s' "$out" | grep -o 'total_blocks=[0-9]*' | head -1 | cut -d= -f2)"
    if [ -n "${tb:-}" ] && [ "$tb" -gt 0 ] 2>/dev/null; then
        TOTAL_SECTORS="$tb"; save_conf
        ok "卡总扇区 = $TOTAL_SECTORS （约 $((TOTAL_SECTORS / SECTORS_PER_GB)) GB）已写入配置"
        printf "    按 10G 一段算，共 $(( (TOTAL_SECTORS + SEG_GB*SECTORS_PER_GB - 1) / (SEG_GB*SECTORS_PER_GB) )) 段\n"
    else
        warn "没读到容量，链路可能没通。若提示 fd 无效，请重新运行或重插读卡器"
    fi
}

# 3. 探测是否扩容卡
f_probe() {
    hr
    need_device || { err "没有可用设备，先去菜单 1 确认"; return; }
    printf "采样点数（默认 24，越多越准越慢，直接回车用默认）："
    read -r n; n="${n:-24}"
    printf "${B}探测卡的真实容量${N}  设备：$DEVICE  采样 $n 点\n"
    printf "（读错误的点每个最多等 20 秒，请耐心）\n"
    hr
    run_dump "$DEVICE" --probe "$n"
    echo ""
    printf "如果上面提示是扩容卡，把「真实 LBA」填进菜单 ${B}8${N} 的 TOTAL_SECTORS，能省掉几小时\n"
}

# 核心：扫描一轮（读一段 + 抠图 + 整理）
scan_one_round() {  # scan_one_round <段号>  -> 0 成功 / 1 失败
    local seg="$1" segimg start_lba n remain rc
    start_lba=$(( seg * SEG_GB * SECTORS_PER_GB ))
    remain=$(( TOTAL_SECTORS - start_lba ))
    [ "$remain" -le 0 ] && return 1
    n=$(( SEG_GB * SECTORS_PER_GB ))
    [ "$remain" -lt "$n" ] && n="$remain"
    segimg="$TMP/seg_$(printf '%04d' "$seg").img"

    local total_segs=$(( (TOTAL_SECTORS + SEG_GB*SECTORS_PER_GB - 1) / (SEG_GB*SECTORS_PER_GB) ))
    hr
    printf "${B}第 %d / %d 段${N}   LBA %d + %d   约 %d GB\n" \
        "$((seg+1))" "$total_segs" "$start_lba" "$n" "$(( n / SECTORS_PER_GB ))"
    printf "开始：%s\n" "$(date '+%H:%M:%S')"
    hr

    # 设备号重插会变，每轮重新确认
    need_device || { err "没探测到设备"; return 1; }

    local attempt=1 okd=0
    while [ "$attempt" -le 3 ]; do
        rm -f "$segimg"
        run_dump "$DEVICE" -s "$start_lba" -n "$n" -b 128 --max-errors "$MAXERR" -o "$segimg"
        rc=$?
        if [ "$rc" -eq 0 ] && [ -s "$segimg" ]; then okd=1; break; fi
        err "第 $seg 段第 $attempt 次读取失败（退出码 $rc）"
        if [ "$rc" -eq 4 ]; then
            printf "    读卡器可能中途掉线或超出真实容量。${Y}重新插卡${N}后选 1 重试\n"
        else
            printf "    设备可能断了，检查读卡器后选 1 重试\n"
        fi
        printf "    [1=重试 2=跳过本段 3=结束扫描]（默认 1）："
        read -r c
        case "${c:-1}" in
            1) attempt=$((attempt+1)); DEVICE=""; need_device >/dev/null 2>&1 ;;
            2) rm -f "$segimg"; return 1 ;;
            *) rm -f "$segimg"; return 2 ;;
        esac
    done
    [ "$okd" = "1" ] || { rm -f "$segimg"; return 1; }

    printf "${B}抠图中...${N} %s\n" "$(date '+%H:%M:%S')"
    python3 "$RETF/carve_photos.py" "$segimg" "$OUTDIR" \
        --only "$ONLY" --min-size "$MINSIZE" --total "$(( TOTAL_SECTORS * 512 / 1000000000 ))G"
    rm -f "$segimg"
    echo "$((seg+1))" > "$STATE"
    ok "第 $((seg+1)) 段完成 $(date '+%H:%M:%S')"
    return 0
}

# 整理：按 EXIF 时间重命名 + 去重 + 挑坏图
f_rename() {
    hr
    printf "${B}整理照片${N}（按拍摄时间重命名、按年月分子目录、md5 去重）\n"
    local cnt
    cnt=$(ls -1 "$OUTDIR" 2>/dev/null | wc -l)
    if [ "${cnt:-0}" -eq 0 ]; then warn "待整理目录是空的：$OUTDIR"; return; fi
    printf "源目录：$OUTDIR（%s 个文件）\n目标：$SORTED\n" "$cnt"
    mkdir -p "$SORTED"
    python3 "$RETF/rename_by_exif.py" "$OUTDIR" "$SORTED" --min-size "$MINSIZE"
    hr
    printf "整理后：${G}%s${N} 个文件  ->  %s\n" "$(find "$SORTED" -type f 2>/dev/null | wc -l)" "$SORTED"
}

# 5. 分段扫描主流程
f_scan() {
    hr
    printf "${B}开始分段扫描${N}\n"
    hr

    # 容量
    if [ "${TOTAL_SECTORS:-0}" -le 0 ]; then
        printf "还没测过卡容量。现在自动测一下？[1=测 0=手填]（默认 1）："
        read -r c
        if [ "${c:-1}" = "1" ]; then
            need_device || { err "没有设备，取消扫描"; return; }
            local out tb
            out="$(run_dump "$DEVICE" --info 2>&1)"
            tb="$(printf '%s' "$out" | grep -o 'total_blocks=[0-9]*' | head -1 | cut -d= -f2)"
            [ -n "${tb:-}" ] && TOTAL_SECTORS="$tb"
        fi
        if [ "${TOTAL_SECTORS:-0}" -le 0 ]; then
            while : ; do
                printf "请输入卡总扇区数（数字，可先跑菜单 2 看；0=取消）："
                read -r tb
                case "${tb:-0}" in
                    ''|*[!0-9]*) printf "    要纯数字，再来一次\n";;
                    *) TOTAL_SECTORS="$tb"; break;;
                esac
            done
            [ "${TOTAL_SECTORS:-0}" -le 0 ] && { warn "已取消"; return; }
        fi
        save_conf
    fi

    # 每段大小
    printf "每轮扫描多少 GB？（默认 ${SEG_GB}，直接回车用默认，手机存储紧张就填小一点）："
    read -r g
    case "${g:-}" in
        ''|*[!0-9]*) : ;;
        *) SEG_GB="$g"; [ "$SEG_GB" -lt 1 ] && SEG_GB=10 ;;
    esac
    save_conf

    # 起始段
    local seg=0
    if [ -f "$STATE" ]; then
        seg="$(cat "$STATE" 2>/dev/null)"
        case "${seg:-}" in ''|*[!0-9]*) seg=0;; esac
        [ "$seg" -gt 0 ] && printf "上次扫到第 %d 段，本次从第 %d 段继续\n" "$seg" "$((seg+1))"
    else
        printf "从第几段开始？（默认 0，直接回车=从头）："
        read -r s
        case "${s:-}" in ''|*[!0-9]*) : ;; *) seg="$s";; esac
    fi

    local total_segs=$(( (TOTAL_SECTORS + SEG_GB*SECTORS_PER_GB - 1) / (SEG_GB*SECTORS_PER_GB) ))
    printf "\n卡总容量：%d 扇区（约 %d GB）  每段 %dGB   共 %d 段\n" \
        "$TOTAL_SECTORS" "$((TOTAL_SECTORS / SECTORS_PER_GB))" "$SEG_GB" "$total_segs"
    printf "照片输出：$OUTDIR   整理后：$SORTED\n"
    printf "临时镜像：$TMP（每轮抠完自动删，峰值占用约 %dGB）\n" "$SEG_GB"
    hr
    printf "确认开始？[1=开始 0=返回菜单]（默认 1）："
    read -r c
    [ "${c:-1}" = "1" ] || return

    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
    echo ""
    printf "${Y}提示：扫描期间别锁屏、别拔读卡器；小米的 OTG 空闲 10 分钟会自动关${N}\n"

    while [ "$seg" -lt "$total_segs" ]; do
        scan_one_round "$seg"
        local rc=$?
        if [ "$rc" -eq 2 ]; then
            warn "已结束扫描（用户中止）"
            break
        fi

        # 每轮扫完：整理一次
        f_rename

        hr
        printf "已扫完 ${B}%d / %d${N} 段，已恢复 ${G}%s${N} 张\n" \
            "$((seg+1))" "$total_segs" "$(find "$SORTED" -type f 2>/dev/null | wc -l)"
        hr
        if [ "$rc" -ne 0 ]; then
            printf "本段未成功。下一步？\n"
        else
            printf "下一步？\n"
        fi
        echo "  1 = 继续扫描下一段"
        echo "  2 = 结束扫描，并把照片移动到手机相册（$ALBUM）"
        echo "  3 = 结束扫描，先不移动"
        printf "请输入数字（默认 1）："
        read -r c
        case "${c:-1}" in
            1) seg=$((seg+1)); DEVICE="";;
            2) f_to_album; break;;
            *) break;;
        esac
    done

    command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock
    hr
    printf "${G}扫描流程结束${N}\n"
    printf "  已整理照片：%s 张  ->  %s\n" "$(find "$SORTED" -type f 2>/dev/null | wc -l)" "$SORTED"
    printf "  进度已保存，下次选菜单 5 会自动接着扫\n"
    hr
}

# 6. 移动到相册
f_to_album() {
    hr
    printf "${B}把照片移动到手机相册${N}\n"
    local cnt
    cnt=$(find "$SORTED" -type f 2>/dev/null | wc -l)
    if [ "${cnt:-0}" -eq 0 ]; then
        warn "整理目录里还没有照片：$SORTED"
        printf "    去菜单 5 扫描，或菜单 6 先整理一次\n"
        return
    fi
    printf "源：$SORTED（%s 张）\n目标：$ALBUM\n" "$cnt"
    hr
    printf "注意：移动后照片会出现在系统相册里。确认？[1=移动 0=取消]（默认 1）："
    read -r c
    [ "${c:-1}" = "1" ] || { warn "已取消"; return; }

    mkdir -p "$ALBUM" 2>/dev/null || { err "打不开 $ALBUM，先执行 termux-setup-storage 授予存储权限"; return; }

    # 先复制，再把源删掉，避免中途失败丢文件
    if cp -r "$SORTED"/. "$ALBUM"/ 2>/dev/null; then
        ok "已复制到相册：$ALBUM"
        printf "删掉临时目录里的原件以省空间？[1=删除 0=保留]（默认 1）："
        read -r d
        if [ "${d:-1}" = "1" ]; then
            find "$SORTED" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
            ok "原件已清理"
        fi
    else
        err "复制失败（存储空间不够？），原件仍保留在 $SORTED"
        return
    fi

    command -v termux-media-scan >/dev/null 2>&1 && {
        printf "刷新相册索引中...\n"
        termux-media-scan -r "$ALBUM" >/dev/null 2>&1
        ok "已通知系统刷新相册"
    }
    printf "现在打开手机自带的相册 App 就能看到了（一般在「Camera」相册）\n"
}

# 7. 查看结果
f_view() {
    hr
    printf "${B}当前进度${N}\n"
    printf "  卡总扇区：%s%s\n" "${TOTAL_SECTORS:-0}" "$([ "${TOTAL_SECTORS:-0}" -gt 0 ] 2>/dev/null && printf '（约 %s GB）' "$((TOTAL_SECTORS / SECTORS_PER_GB))")"
    printf "  已扫段数：%s\n" "$([ -f "$STATE" ] && cat "$STATE" || echo 0)"
    printf "  待整理：%s 个  -> %s\n" "$(ls -1 "$OUTDIR" 2>/dev/null | wc -l)" "$OUTDIR"
    printf "  已整理：%s 张  -> %s\n" "$(find "$SORTED" -type f 2>/dev/null | wc -l)" "$SORTED"
    printf "  临时镜像目录占用：%s\n" "$(du -sh "$TMP" 2>/dev/null | cut -f1)"
    printf "  可用空间：%s\n" "$(df -h "$HOME" 2>/dev/null | tail -1)"
    echo ""
    printf "打开文件管理器看看？[1=看已整理目录 2=看相册目录 0=不用]（默认 0）："
    read -r c
    case "${c:-0}" in
        1) command -v termux-open >/dev/null 2>&1 && termux-open "$SORTED";;
        2) command -v termux-open >/dev/null 2>&1 && termux-open "$ALBUM";;
    esac
}

# 8. 设置
f_settings() {
    while : ; do
        hr
        printf "${B}参数设置${N}（直接回车=不改）\n"
        echo "  1  当前 USB 设备      ：${DEVICE:-（未设置，留空则每轮自动探测）}"
        echo "  2  每轮扫描 GB 数     ：$SEG_GB"
        echo "  3  卡总扇区数         ：$TOTAL_SECTORS（0 = 自动测）"
        echo "  4  抠图类型           ：$ONLY"
        echo "  5  最小文件大小(字节) ：$MINSIZE"
        echo "  6  连续失败上限       ：$MAXERR"
        echo "  7  照片输出目录       ：$OUTDIR"
        echo "  8  整理后目录         ：$SORTED"
        echo "  9  相册目录           ：$ALBUM"
        echo "  10 清空扫描进度（重新开始）"
        echo "  0  返回主菜单"
        hr
        printf "请输入数字："
        read -r c
        case "${c:-0}" in
            1) printf "设备路径（留空=自动探测）："; read -r v; DEVICE="${v:-}";;
            2) printf "GB 数："; read -r v; case "${v:-}" in ''|*[!0-9]*) :;; *) SEG_GB="$v";; esac;;
            3) printf "总扇区数："; read -r v; case "${v:-}" in ''|*[!0-9]*) :;; *) TOTAL_SECTORS="$v";; esac;;
            4) printf "类型（逗号分隔，如 jpg,png,heic,mp4）："; read -r v; [ -n "${v:-}" ] && ONLY="$v";;
            5) printf "最小字节："; read -r v; case "${v:-}" in ''|*[!0-9]*) :;; *) MINSIZE="$v";; esac;;
            6) printf "失败上限："; read -r v; case "${v:-}" in ''|*[!0-9]*) :;; *) MAXERR="$v";; esac;;
            7) printf "输出目录："; read -r v; [ -n "${v:-}" ] && OUTDIR="$(exp "$v")";;
            8) printf "整理目录："; read -r v; [ -n "${v:-}" ] && SORTED="$(exp "$v")";;
            9) printf "相册目录："; read -r v; [ -n "${v:-}" ] && ALBUM="$v";;
            10) rm -f "$STATE"; rm -f "$TMP"/seg_*.img; warn "扫描进度已清空，下次从第 1 段开始";;
            0) break;;
            *) :;;
        esac
        mkdir -p "$TMP" "$OUTDIR" 2>/dev/null
        save_conf
    done
}

# 0. 环境自检
f_check() {
    hr
    printf "${B}环境自检${N}\n"
    local p
    for p in python3 clang termux-usb termux-open curl; do
        if command -v "$p" >/dev/null 2>&1; then ok "$p"; else err "$p 缺失"; fi
    done
    if [ -x "$RETF/scsi_dump" ]; then ok "scsi_dump 已编译：$RETF/scsi_dump"; else err "scsi_dump 没编译，请重新运行 install.sh"; fi
    for p in main.sh scsi_wrap.sh seg_scan.sh carve_photos.py rename_by_exif.py generate_fonts_json.py scsi_dump.c; do
        [ -f "$RETF/$p" ] && ok "$p" || err "$p 缺失"
    done
    [ -d /storage/emulated/0 ] && ok "存储可访问" || err "存储不可访问，执行 termux-setup-storage 授权"
    hr
}

# =====================================================================
#  主菜单
# =====================================================================
show_menu() {
    clear 2>/dev/null
    echo "=========================================="
    printf "  ${B}reTF${N} —— TF 卡照片恢复工具箱\n"
    echo "=========================================="
    echo "  当前设备：${DEVICE:-自动探测}"
    echo "  已扫段数：$([ -f "$STATE" ] && cat "$STATE" || echo 0)   已恢复：$(find "$SORTED" -type f 2>/dev/null | wc -l) 张"
    hr
    echo "  1  查看 USB 设备（termux-usb -l）"
    echo "  2  读取卡的容量信息"
    echo "  3  探测是不是扩容卡（省时间）"
    echo "  4  环境自检"
    echo "  5  开始 / 继续扫描照片    ★ 主要用这个"
    echo "  6  整理照片（按拍摄时间重命名）"
    echo "  7  把照片移动到手机相册"
    echo "  8  查看进度"
    echo "  9  参数设置"
    echo "  0  退出"
    hr
    printf "请输入数字："
}

while : ; do
    show_menu
    read -r CH
    case "${CH:-}" in
        1) f_list_usb;;
        2) f_info;;
        3) f_probe;;
        4) f_check;;
        5) f_scan;;
        6) f_rename;;
        7) f_to_album;;
        8) f_view;;
        9) f_settings;;
        0) echo "已退出。下次运行：cd $RETF && bash main.sh"; exit 0;;
        *) warn "看不懂，请输入菜单里的数字";;
    esac
    echo ""
    printf "${D}按回车返回菜单...${N}"
    read -r _
done
