#!/data/data/com.termux/files/usr/bin/bash
# ========== 配置 ==========
UPDATE_URL="https://riluo-ya.github.io/blog/sh/Phira-mp/start.sh"
HASH_URL="https://riluo-ya.github.io/blog/sh/Phira-mp/update/start/md5.txt"
INSTALL_URL="https://riluo-ya.github.io/blog/sh/Phira-mp/install.sh"
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
MAX_RETRY=3
VERSION="3.7.1"
# =================================
# 全局变量
PHIRA_PID=""
FRP_PID=""
FOUND_INSTALL_SCRIPT=""
# ========== 颜色 ==========
R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
red=$'\033[31m'; grn=$'\033[32m'; yel=$'\033[33m'
blu=$'\033[34m'; mag=$'\033[35m'; cyn=$'\033[36m'
wht=$'\033[37m'; ora=$'\033[38;5;208m'
bg_blk=$'\033[40m'; bg_red=$'\033[41m'; bg_grn=$'\033[42m'
bg_yel=$'\033[43m'; bg_blu=$'\033[44m'; bg_mag=$'\033[45m'
bg_cyn=$'\033[46m'; bg_wht=$'\033[47m'
rev=$'\033[7m'; bold=$'\033[1m'; dim=$'\033[2m'
# ========== 简写函数 ==========
ok() { echo -e " ${grn}[OK]${R} $1"; }
er() { echo -e " ${red}[ER]${R} $1" >&2; }
wa() { echo -e " ${yel}[WW]${R} $1"; }
info() { echo -e " ${cyn}[II]${R} $1"; }
# ========== 工具函数 ==========
get_saying() {
    local resp=$(curl -s -X GET 'https://uapis.cn/api/v1/saying' 2>/dev/null)
    local saying=$(echo "$resp" | grep -o '"text":"[^"]*' | sed 's/"text":"//')
    [ -z "$saying" ] && saying="生活不止眼前的苟且，还有诗和远方。"
    echo "$saying"
}
check_network() {
    ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1 || \
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1
}
download_file() {
    local url="$1" output="$2" retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$output" 2>/dev/null && return 0
        wget -q --timeout=10 -O "$output" "$url" 2>/dev/null && return 0
        retry=$((retry + 1)); [ $retry -lt $MAX_RETRY ] && sleep 2
    done
    return 1
}
download_file_with_progress() {
    local url="$1" output="$2"
    info "正在下载更新..."
    echo ""
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --connect-timeout 10 --max-time 60 --progress-bar "$url" -o "$output" 2>&1 && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget --timeout=10 --show-progress -O "$output" "$url" 2>&1 && return 0
    fi
    return 1
}
download_text() {
    local url="$1" retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        curl -fsSL --connect-timeout 10 --max-time 15 "$url" 2>/dev/null && return 0
        wget -q --timeout=10 -O - "$url" 2>/dev/null && return 0
        retry=$((retry + 1)); [ $retry -lt $MAX_RETRY ] && sleep 1
    done
    return 1
}
# ========== 目录查找 ==========
find_phira_dir() {
    if [ -d "$HOME/phira-mp-0.1.0" ]; then echo "$HOME/phira-mp-0.1.0"
    elif [ -d "phira-mp-0.1.0" ]; then echo "phira-mp-0.1.0"
    elif [ -d "../phira-mp-0.1.0" ]; then echo "../phira-mp-0.1.0"
    else echo ""; fi
}
find_frp_dir() {
    if [ -d "$HOME/ChmlFrp-0.51.2_251023_linux_arm64" ]; then echo "$HOME/ChmlFrp-0.51.2_251023_linux_arm64"
    elif [ -d "ChmlFrp-0.51.2_251023_linux_arm64" ]; then echo "ChmlFrp-0.51.2_251023_linux_arm64"
    elif [ -d "../ChmlFrp-0.51.2_251023_linux_arm64" ]; then echo "../ChmlFrp-0.51.2_251023_linux_arm64"
    else echo ""; fi
}
# ========== 服务状态 ==========
is_phira_running() { [ -n "$PHIRA_PID" ] && kill -0 "$PHIRA_PID" 2>/dev/null; }
is_frp_running() { [ -n "$FRP_PID" ] && kill -0 "$FRP_PID" 2>/dev/null; }
check_existing_service() {
    local phira_dir=$(find_phira_dir)
    [ -z "$phira_dir" ] && return 0
    local existing=$(pgrep -f "phira-mp-server" 2>/dev/null | head -1)
    [ -z "$existing" ] && return 0
    wa "检测到已有服务在运行 (PID: $existing)"
    printf "  %s是否停止并重启? [Y/n]:%s " "$cyn" "$R"
    read -r confirm
    [ -n "$confirm" ] && [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 1
    kill "$existing" 2>/dev/null; sleep 1
    ok "已停止旧服务"
    return 0
}
# ========== 自动更新 ==========
auto_update() {
    check_network || return 0
    local local_hash=$(md5sum "$SCRIPT_PATH" 2>/dev/null | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
    local remote_hash=$(download_text "$HASH_URL" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [ -z "$remote_hash" ] || [ ${#remote_hash} -ne 32 ] && return 0
    [ "$local_hash" = "$remote_hash" ] && return 0
    
    echo ""
    draw_line "═"
    printf "  %s%s📦 发现新版本!%s\n" "$B" "$grn" "$R"
    draw_line "═"
    echo ""
    echo "  本地版本: ${D}$VERSION${R}"
    echo "  本地MD5:  ${local_hash:0:16}..."
    echo "  远程MD5:  ${remote_hash:0:16}..."
    echo ""
    printf "  %s是否立即更新?%s\n" "$B" "$R"
    echo "    [0] 取消更新"
    echo "    [1] 立即更新"
    echo ""
    printf "  %s请输入选项 [0-1]:%s " "$cyn" "$R"
    read -r update_choice
    
    [ "$update_choice" != "1" ] && { info "已取消更新"; sleep 1; return 0; }
    
    local tmp_file="${SCRIPT_PATH}.tmp.$$"
    if ! download_file_with_progress "$UPDATE_URL" "$tmp_file"; then
        rm -f "$tmp_file"
        er "下载更新失败"
        sleep 2
        return 0
    fi
    
    local dl_hash=$(md5sum "$tmp_file" 2>/dev/null | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
    [ "$dl_hash" != "$remote_hash" ] && { rm -f "$tmp_file"; er "文件校验失败"; sleep 2; return 0; }
    
    mkdir -p "$SCRIPT_DIR/.backups" 2>/dev/null
    cp "$SCRIPT_PATH" "$SCRIPT_DIR/.backups/${SCRIPT_NAME}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
    
    if mv "$tmp_file" "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH"; then
        ok "更新完成，正在重启..."
        sleep 1; exec "$SCRIPT_PATH"
    fi
    return 0
}
# ========== install.sh 管理 ==========
find_install_script() {
    FOUND_INSTALL_SCRIPT=""
    local locs=("$HOME/install.sh" "/data/data/com.termux/files/home/install.sh" \
                "$SCRIPT_DIR/install.sh" "$PWD/install.sh" "$PWD/../install.sh")
    for loc in "${locs[@]}"; do
        [ -f "$loc" ] && { FOUND_INSTALL_SCRIPT="$loc"; return 0; }
    done
    local found=$(find "$HOME" -maxdepth 3 -name "install.sh" -type f 2>/dev/null | head -1)
    [ -n "$found" ] && { FOUND_INSTALL_SCRIPT="$found"; return 0; }
    return 1
}
download_install_script() {
    info "下载 install.sh..."
    check_network || { er "无网络连接"; return 1; }
    download_file "$INSTALL_URL" "$1" || { er "下载失败"; return 1; }
    chmod +x "$1"; FOUND_INSTALL_SCRIPT="$1"
    ok "下载完成"; return 0
}
get_install_script() {
    find_install_script && { ok "找到本地版本: $FOUND_INSTALL_SCRIPT"; return 0; }
    wa "未找到本地版本"
    download_install_script "$HOME/install.sh"
}
# ========== 自动安装 ==========
auto_install() {
    local svc_type=$1 svc_name opt
    if [ "$svc_type" = "phira" ]; then
        svc_name="游戏服务器 (Phira-mp)"; opt="1"
    else
        svc_name="内网穿透 (ChmlFrp)"; opt="2"
    fi
    wa "检测到 $svc_name 未安装"
    info "开始自动安装..."
    get_install_script || { er "无法获取 install.sh"; return 1; }
    [ ! -f "$FOUND_INSTALL_SCRIPT" ] && { er "install.sh 无效"; return 1; }
    echo ""; info "安装 $svc_name..."; echo ""
    echo "$opt" | bash "$FOUND_INSTALL_SCRIPT"; local ret=$?
    echo ""
    [ $ret -eq 0 ] && { ok "$svc_name 安装完成"; return 0; }
    er "安装失败 (错误码: $ret)"; return 1
}
# ========== 服务启动 ==========
start_phira_service() {
    local dir=$(find_phira_dir)
    [ -z "$dir" ] && { er "未找到 Phira-mp 目录"; return 1; }
    check_existing_service || return 1
    info "启动游戏服务..."
    cd "$dir" || return 1
    RUST_LOG=debug target/release/phira-mp-server --port 12345 > phira.log 2>&1 &
    PHIRA_PID=$!; cd - > /dev/null
    sleep 1
    if kill -0 "$PHIRA_PID" 2>/dev/null; then
        ok "游戏服务已启动 (PID: $PHIRA_PID)"
        echo "   日志: $dir/phira.log"; return 0
    fi
    er "启动失败"; PHIRA_PID=""; return 1
}
start_frp_service() {
    local dir=$(find_frp_dir)
    [ -z "$dir" ] && { er "未找到内网穿透目录"; return 1; }
    info "启动内网穿透..."
    cd "$dir" || return 1
    ./frpc -c frpc.ini > frp.log 2>&1 &
    FRP_PID=$!; cd - > /dev/null
    sleep 1
    if kill -0 "$FRP_PID" 2>/dev/null; then
        ok "内网穿透已启动 (PID: $FRP_PID)"
        echo "   日志: $dir/frp.log"; return 0
    fi
    er "启动失败"; FRP_PID=""; return 1
}
stop_all_services() {
    echo ""
    is_phira_running && { kill "$PHIRA_PID" 2>/dev/null; info "游戏服务已停止"; }
    is_frp_running && { kill "$FRP_PID" 2>/dev/null; info "内网穿透已停止"; }
    exit 0
}
# ========== 智能启动 ==========
smart_start_phira() {
    local dir=$(find_phira_dir)
    if [ -z "$dir" ]; then
        auto_install "phira" || return 1
        dir=$(find_phira_dir)
        [ -z "$dir" ] && { er "安装后仍未找到目录"; return 1; }
    fi
    start_phira_service
}
smart_start_frp() {
    local dir=$(find_frp_dir)
    if [ -z "$dir" ]; then
        auto_install "frp" || return 1
        dir=$(find_frp_dir)
        [ -z "$dir" ] && { er "安装后仍未找到目录"; return 1; }
    fi
    start_frp_service
}
smart_start_both() {
    local pdir=$(find_phira_dir) fdir=$(find_frp_dir) installed=0
    [ -z "$pdir" ] && auto_install "phira" && installed=1
    [ -z "$fdir" ] && auto_install "frp" && installed=1
    [ $installed -eq 1 ] && { pdir=$(find_phira_dir); fdir=$(find_frp_dir); }
    [ -z "$pdir" ] && [ -z "$fdir" ] && { er "没有可用服务"; return 1; }
    local err=0
    [ -n "$pdir" ] && start_phira_service || err=1
    [ -n "$fdir" ] && start_frp_service || err=1
    [ -n "$PHIRA_PID" ] || [ -n "$FRP_PID" ] || { [ $err -eq 1 ] && wa "部分服务启动失败" || er "没有可启动的服务"; return 1; }
    echo ""; ok "所有服务已启动"
    draw_line "="; echo "  按 Ctrl+C 停止所有服务"; draw_line "="
    trap 'stop_all_services' SIGINT
    local pids=""
    [ -n "$PHIRA_PID" ] && pids="$pids $PHIRA_PID"
    [ -n "$FRP_PID" ] && pids="$pids $FRP_PID"
    for pid in $pids; do wait "$pid"; done
    echo ""
}
# ========== 界面绘制 ==========
draw_line() {
    local c="${1:-─}"; printf "  "; for ((i=0;i<40;i++)); do printf "%s" "$c"; done; printf "\n"
}
draw_header() {
    echo ""; draw_line "═"
    printf "  %s%sPhira 多人联机启动器%s\n" "$B" "$cyn" "$R"
    printf "  %s版本 %s • 作者: 日落-ya%s\n" "$D" "$VERSION" "$R"
    draw_line "═"; echo ""
}
draw_box_top() { echo "  ┌──────────────────────────────────────┐"; }
draw_box_mid() { echo "  ├──────────────────────────────────────┤"; }
draw_box_bottom() { echo "  └──────────────────────────────────────┘"; }
# ========== 主界面 ==========
show_saying() {
    printf "  %s今日一言:%s %s%s%s\n" "$yel" "$R" "$D" "$(get_saying)" "$R"
    echo ""
}
show_status() {
    local pdir=$(find_phira_dir) fdir=$(find_frp_dir)
    draw_box_top; printf "  │%s 服务状态                            %s│\n" "$B" "$R"; draw_box_mid
    if [ -n "$pdir" ]; then
        printf "  │  %s●%s Phira-mp      %s已安装%s            │\n" "$grn" "$R" "$grn" "$R"
    else
        printf "  │  %s○%s Phira-mp      %s未安装%s            │\n" "$red" "$R" "$D" "$R"
    fi
    if [ -n "$fdir" ]; then
        printf "  │  %s●%s 内网穿透      %s已安装%s            │\n" "$grn" "$R" "$grn" "$R"
    else
        printf "  │  %s○%s 内网穿透      %s未安装%s            │\n" "$red" "$R" "$D" "$R"
    fi
    draw_box_bottom; echo ""
}
show_main_menu() {
    local pdir=$(find_phira_dir) fdir=$(find_frp_dir)
    draw_box_top; printf "  │%s 主菜单                              %s│\n" "$B" "$R"; draw_box_mid
    [ -n "$pdir" ] && printf "  │  [1] 启动游戏服务器 (Phira-mp)       │\n" || \
        printf "  │  %s[1] 自动安装并启动游戏服务器%s        │\n" "$yel" "$R"
    [ -n "$fdir" ] && printf "  │  [2] 启动内网穿透 (ChmlFrp)          │\n" || \
        printf "  │  %s[2] 自动安装并启动内网穿透%s          │\n" "$yel" "$R"
    [ -n "$pdir" ] && [ -n "$fdir" ] && \
        printf "  │  [3] 同时启动两者                    │\n" || \
        printf "  │  %s[3] 自动安装并启动全部服务%s          │\n" "$yel" "$R"
    draw_box_mid
    printf "  │  [4] 设置                            │\n"
    printf "  │  [0] 退出                            │\n"
    draw_box_bottom; echo ""
}
# ========== 启动设置脚本 ==========
launch_settings() {
    echo ""
    draw_line "─"
    printf "  %s%s正在启动设置...%s\n" "$B" "$cyn" "$R"
    draw_line "─"
    sleep 1
    local set_script="$SCRIPT_DIR/set.sh"
    # 如果当前目录没有，尝试下载
    if [ ! -f "$set_script" ]; then
        info "未找到 set.sh，尝试下载..."
        if check_network; then
            download_file "https://riluo-ya.github.io/blog/sh/Phira-mp/set.sh" "$set_script" 2>/dev/null && \
                chmod +x "$set_script"
        fi
    fi
    # 检查set.sh是否存在
    if [ -f "$set_script" ]; then
        chmod +x "$set_script"
        exec "$set_script"
    else
        er "无法找到或下载 set.sh"
        printf "  %s按回车键继续...%s" "$D" "$R"; read -r
    fi
}
# ========== 主程序 ==========
main() {
    # 静默检查更新
    auto_update
    while true; do
        PHIRA_PID=""; FRP_PID=""
        draw_header
        show_saying
        show_status
        show_main_menu
        printf "  %s请输入选项 [0-4]:%s " "$cyn" "$R"
        read -r choice; echo ""
        case $choice in
            1)
                smart_start_phira && {
                    echo ""; draw_line "-"
                    echo "  按 Ctrl+C 停止服务"; draw_line "-"
                    trap 'stop_all_services' SIGINT
                    wait "$PHIRA_PID"; echo ""
                }
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            2)
                smart_start_frp && {
                    echo ""; draw_line "-"
                    echo "  按 Ctrl+C 停止服务"; draw_line "-"
                    trap 'stop_all_services' SIGINT
                    wait "$FRP_PID"; echo ""
                }
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            3)
                smart_start_both
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            4)
                launch_settings
                ;;
            0)
                echo ""; printf "  %s感谢使用，再见！%s\n" "$grn" "$R"; echo ""
                exit 0
                ;;
            *)
                wa "无效选项: $choice"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
        esac
    done
}
main
