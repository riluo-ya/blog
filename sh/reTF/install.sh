#!/data/data/com.termux/files/usr/bin/bash
# =====================================================================
#  reTF 一键安装脚本
#  无 root，用 Termux + OTG 读卡器，救回 TF/SD 卡里被删掉的照片
#
#  用法（Termux 里粘贴这两行就行）：
#    curl -L -o install.sh https://gcore.jsdelivr.net/gh/riluo-ya/blog@main/sh/reTF/install.sh
#    bash install.sh
#
#  它会做六件事：
#    1. 装依赖（python / clang / libusb / termux-api / curl）
#    2. 从 gcore CDN 下载 main.sh 和 install/ 目录下的 6 个脚本
#    3. 把脚本里写死的 $HOME 改成安装目录，保证换个目录也能跑
#    4. 编译核心程序 scsi_dump
#    5. 申请存储权限、生成配置文件
#    6. 进入安装目录，自动启动 main.sh
# =====================================================================

set -u

# ---------- 可改的配置 ----------
# main.sh 放在 sh/reTF/ 下，其余 6 个脚本放在 sh/reTF/install/ 下
BASE="${BASE:-https://gcore.jsdelivr.net/gh/riluo-ya/blog@main/sh/reTF}"
SUB="$BASE/install"
MAIN_FILES="main.sh"
SUB_FILES="scsi_dump.c scsi_wrap.sh seg_scan.sh carve_photos.py rename_by_exif.py generate_fonts_json.py"
RETF="${RETF_DIR:-/retf}"     # 想装到别的目录：RETF_DIR=/sdcard/retf bash install.sh
# --------------------------------

if [ -t 1 ]; then
    G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; B='\033[1;36m'; N='\033[0m'
else
    G=''; Y=''; R=''; B=''; N=''
fi
step() { printf "${B}==>%s${N} %s\n" "" "$*"; }
ok()   { printf "${G}[OK]${N} %s\n" "$*"; }
warn() { printf "${Y}[!]${N} %s\n" "$*"; }
die()  { printf "${R}[X]${N} %s\n" "$*"; exit 1; }

echo ""
echo "=========================================="
echo "  reTF 一键安装  （TF 卡照片恢复工具箱）"
echo "=========================================="
echo ""

# ---------- 1. 环境检查 ----------
step "1/6 检查环境"
if [ -z "${PREFIX:-}" ]; then
    warn "没检测到 Termux 环境（\$PREFIX 为空），本脚本是给 Android Termux 用的"
    printf "    仍然继续？[1=继续 0=退出]（默认 0）："
    read -r go
    [ "${go:-0}" = "1" ] || exit 1
fi
command -v pkg >/dev/null 2>&1 || warn "没找到 pkg（非 Termux？），将跳过依赖安装直接下载脚本"
ok "环境检查通过"

# ---------- 2. 安装依赖 ----------
step "2/6 安装依赖（python / clang / libusb / termux-api / curl）"
echo ""
echo "     ⚠ 这一步要联网下载几十 MB，通常 2~10 分钟"
echo "       下面会滚动很多行，那就是进度，别关掉 Termux、别锁屏"
echo ""

# 包名 -> 装完后用来判断的命令（python 包装完命令叫 python3）
chk() {
    case "$1" in
        python) command -v python3 >/dev/null 2>&1 ;;
        *)      command -v "$1" >/dev/null 2>&1 ;;
    esac
}

PKGS="python clang libusb termux-api curl"
NPKG=$(echo "$PKGS" | wc -w | tr -d ' ')
i=0

if command -v pkg >/dev/null 2>&1; then
    printf "     ${B}· 更新软件源列表...${N}\n"
    pkg update -y
    echo ""

    for p in $PKGS; do
        i=$((i + 1))
        if chk "$p"; then
            printf "     ${G}[%d/%d] %-11s 已经装过了，跳过${N}\n" "$i" "$NPKG" "$p"
            echo ""
            continue
        fi
        printf "     ${B}>>> [%d/%d] 开始安装 %s${N}\n" "$i" "$NPKG" "$p"
        pkg install -y "$p"
        if chk "$p"; then
            printf "     ${G}<<< [%d/%d] %s 安装完成 ✓${N}\n" "$i" "$NPKG" "$p"
        else
            printf "     ${R}<<< [%d/%d] %s 安装失败 ✗${N}\n" "$i" "$NPKG" "$p"
            printf "         重试一次？[1=重试 0=跳过继续]（默认 1）："
            read -r r
            if [ "${r:-1}" = "1" ]; then
                printf "     ${B}>>> 重试安装 %s${N}\n" "$p"
                pkg install -y "$p"
                chk "$p" && printf "     ${G}<<< %s 这次装好了 ✓${N}\n" "$p" \
                         || printf "     ${Y}<<< %s 仍然失败，稍后可手动执行：pkg install %s${N}\n" "$p" "$p"
            fi
        fi
        echo ""
    done
else
    warn "没找到 pkg 命令（不是 Termux？），跳过自动安装，请自己确认依赖齐不齐"
fi

command -v python3 >/dev/null 2>&1 || die "python3 没装上，请手动执行：pkg install python"
command -v clang   >/dev/null 2>&1 || die "clang 没装上，请手动执行：pkg install clang"
command -v curl    >/dev/null 2>&1 || die "curl 没装上，请手动执行：pkg install curl"
ok "python3 / clang / curl 就绪"

if command -v termux-usb >/dev/null 2>&1; then
    ok "termux-usb 就绪"
else
    warn "termux-usb 不可用！请确认：① 装了 termux-api 包 ② 从 F-Droid 装了 Termux:API App（和 Termux 同渠道），并给它开自启动 + 后台运行"
fi

# ---------- 3. 准备安装目录 ----------
step "3/6 准备安装目录"
if ! ( mkdir -p "$RETF" 2>/dev/null && [ -w "$RETF" ] ); then
    warn "$RETF 不可写（手机没 root 时根目录只读，属于正常现象）"
    RETF="$HOME/retf"
    mkdir -p "$RETF" 2>/dev/null || die "目录创建失败：$RETF"
    warn "已自动改用：$RETF（功能完全一样）"
fi
ok "安装目录：$RETF"

# ---------- 4. 下载脚本 ----------
step "4/6 从 gcore CDN 下载脚本"
dl() {  # dl 基础URL 文件名
    local url="$1/$2" f="$2" i sz
    for i in 1 2 3; do
        printf "     ${B}↓ %s${N}（第 %d 次）\n" "$f" "$i"
        if curl -fL --retry 2 --connect-timeout 15 --max-time 180 -# "$url" -o "$RETF/$f" \
            && [ -s "$RETF/$f" ]; then
            sz=$(wc -c < "$RETF/$f" 2>/dev/null | tr -d ' ')
            printf "     ${G}√ %s 下载完成${N}（%s 字节）\n" "$f" "$sz"
            return 0
        fi
        printf "     ${Y}%s 第 %d 次失败，2 秒后重试...${N}\n" "$f" "$i"
        sleep 2
    done
    return 1
}
fail=0
for f in $MAIN_FILES; do
    dl "$BASE" "$f" || { printf "     ${R}x %s 下载失败${N}\n" "$f"; fail=$((fail+1)); }
done
for f in $SUB_FILES; do
    dl "$SUB" "$f" || { printf "     ${R}x %s 下载失败${N}\n" "$f"; fail=$((fail+1)); }
done
[ "$fail" -gt 0 ] && die "有 $fail 个文件下载失败。请检查网络，或确认仓库路径：$BASE"
ok "7 个文件全部下载完成"

# 脚本里写死了 $HOME，替换成真实安装目录，这样放到 /retf 也能照常跑
for f in scsi_wrap.sh seg_scan.sh; do
    [ -f "$RETF/$f" ] && sed -i "s|[\$]HOME|$RETF|g" "$RETF/$f" 2>/dev/null
done
chmod +x "$RETF"/*.sh "$RETF"/*.py 2>/dev/null
ok "已适配安装目录并加上执行权限"

# ---------- 5. 编译核心程序 ----------
step "5/6 编译 scsi_dump（核心读卡程序）"
printf "     正在编译，通常十几秒...\n"
if clang -O2 -o "$RETF/scsi_dump" "$RETF/scsi_dump.c" -lusb-1.0 2>"$RETF/compile.log"; then
    ok "编译成功：$RETF/scsi_dump"
else
    printf "${R}编译失败，日志：${N}\n"
    tail -20 "$RETF/compile.log" 2>/dev/null
    die "请执行 pkg install clang libusb 后重新运行本脚本"
fi

# ---------- 6. 权限 + 配置 ----------
step "6/6 申请存储权限并写入配置"
command -v termux-setup-storage >/dev/null 2>&1 && termux-setup-storage >/dev/null 2>&1
mkdir -p /storage/emulated/0/DCIM/Camera 2>/dev/null

cat > "$RETF/retf.conf" <<EOF
# reTF 配置（main.sh 会自动读写，也可以手改）
RETF="$RETF"
DEVICE=""
SEG_GB=10
TOTAL_SECTORS=0
ONLY="jpg,png,heic,avi"
MINSIZE=50000
MAXERR=256
MAXFILEMB=120
OUTDIR="~/recovered"
SORTED="~/recovered_已整理"
TMP="~/retf_tmp"
ALBUM="/storage/emulated/0/DCIM/Camera"
EOF
[ -f "$RETF/compile.log" ] && rm -f "$RETF/compile.log"
ok "配置已写入 $RETF/retf.conf"

echo ""
echo "=========================================="
printf "${G}  安装完成！${N}\n"
echo "=========================================="
echo "  安装目录：$RETF"
echo "    main.sh                主页菜单"
echo "    scsi_dump              读卡核心程序（已编译）"
echo "    scsi_wrap.sh           参数换位器"
echo "    seg_scan.sh            分段全自动扫描"
echo "    carve_photos.py        按文件头抠图"
echo "    rename_by_exif.py      按拍摄时间整理命名"
echo "    generate_fonts_json.py 字体索引工具"
echo ""
echo "  开始之前请确认："
echo "    ① Termux:API App 已装好并允许后台运行"
echo "    ② 手机 OTG 开关已打开（小米默认关、10 分钟自动关）"
echo "    ③ 读卡器 + TF 卡已插好，且不要再往卡里写任何东西"
echo ""
echo "  以后想更新脚本：进 main.sh 选菜单 11（在线更新）"
echo "  不用再跑本安装脚本，配置和已恢复的照片都会保留"
echo ""
printf "${B}马上进入 $RETF 并启动 main.sh ...${N}\n"
sleep 1

cd "$RETF" || exit 1
exec bash "$RETF/main.sh"
