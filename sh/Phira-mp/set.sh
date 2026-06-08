#!/data/data/com.termux/files/usr/bin/bash
# ========== 配置 ==========
UPDATE_URL="https://riluo-ya.github.io/blog/sh/Phira-mp/set.sh"
HASH_URL="https://riluo-ya.github.io/blog/sh/Phira-mp/update/set/md5.txt"
CHANGELOG_URL="https://riluo-ya.github.io/blog/sh/Phira-mp/update/update.txt"
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
MAX_RETRY=3
VERSION="3.7.1"
# =================================
# 全局变量
PHIRA_PID=""
FRP_PID=""
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
    # 使用curl显示进度条
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --connect-timeout 10 --max-time 60 --progress-bar "$url" -o "$output" 2>&1 && return 0
    fi
    # 备用：使用wget
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
# ========== 自动更新 ==========
auto_update() {
    check_network || return 0
    local local_hash=$(md5sum "$SCRIPT_PATH" 2>/dev/null | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
    local remote_hash=$(download_text "$HASH_URL" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [ -z "$remote_hash" ] || [ ${#remote_hash} -ne 32 ] && return 0
    [ "$local_hash" = "$remote_hash" ] && return 0
    
    # 发现新版本，询问用户是否更新
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

# ========== 备份类型定义 ==========
BACKUP_TYPE_SCRIPT="script"
BACKUP_TYPE_PHIRA="phira"
BACKUP_TYPE_FRP="frp"

# ========== 获取备份目录 ==========
get_backup_dir() {
    local backup_type="$1"
    case "$backup_type" in
        "$BACKUP_TYPE_SCRIPT")
            echo "$SCRIPT_DIR/.backups"
            ;;
        "$BACKUP_TYPE_PHIRA")
            local phira_dir=$(find_phira_dir)
            [ -n "$phira_dir" ] && echo "$phira_dir/.backups" || echo ""
            ;;
        "$BACKUP_TYPE_FRP")
            local frp_dir=$(find_frp_dir)
            [ -n "$frp_dir" ] && echo "$frp_dir/.backups" || echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

# ========== 获取备份文件模式 ==========
get_backup_pattern() {
    local backup_type="$1"
    case "$backup_type" in
        "$BACKUP_TYPE_SCRIPT")
            echo "*.bak*"
            ;;
        "$BACKUP_TYPE_PHIRA")
            echo "*.bak*"
            ;;
        "$BACKUP_TYPE_FRP")
            echo "*.bak*"
            ;;
        *)
            echo "*.bak*"
            ;;
    esac
}

# ========== 获取备份类型名称 ==========
get_backup_type_name() {
    local backup_type="$1"
    case "$backup_type" in
        "$BACKUP_TYPE_SCRIPT")
            echo "启动脚本"
            ;;
        "$BACKUP_TYPE_PHIRA")
            echo "Phira服务器"
            ;;
        "$BACKUP_TYPE_FRP")
            echo "内网穿透配置"
            ;;
        *)
            echo "未知类型"
            ;;
    esac
}

# ========== 获取备份源文件路径（用于还原） ==========
get_backup_source_file() {
    local backup_type="$1"
    case "$backup_type" in
        "$BACKUP_TYPE_SCRIPT")
            echo "$SCRIPT_PATH"
            ;;
        "$BACKUP_TYPE_PHIRA")
            local phira_dir=$(find_phira_dir)
            [ -n "$phira_dir" ] && echo "$phira_dir/phira-mp-server/src/room.rs" || echo ""
            ;;
        "$BACKUP_TYPE_FRP")
            local frp_dir=$(find_frp_dir)
            [ -n "$frp_dir" ] && echo "$frp_dir/frpc.ini" || echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

# ========== 获取某类型备份数量 ==========
get_backup_count_by_type() {
    local backup_type="$1"
    local backup_dir=$(get_backup_dir "$backup_type")
    [ -z "$backup_dir" ] && { echo "0"; return; }
    [ ! -d "$backup_dir" ] && { echo "0"; return; }
    local pattern=$(get_backup_pattern "$backup_type")
    local count=$(find "$backup_dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l)
    echo "$count"
}

# ========== 获取某类型备份列表（按时间排序） ==========
get_backup_list_by_type() {
    local backup_type="$1"
    local backup_dir=$(get_backup_dir "$backup_type")
    [ -z "$backup_dir" ] && { echo ""; return; }
    [ ! -d "$backup_dir" ] && { echo ""; return; }
    local pattern=$(get_backup_pattern "$backup_type")
    # 按修改时间排序，最新的在最后
    find "$backup_dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-
}

# ========== 获取最新备份文件 ==========
get_latest_backup() {
    local backup_type="$1"
    local list=$(get_backup_list_by_type "$backup_type")
    [ -z "$list" ] && { echo ""; return; }
    echo "$list" | tail -1
}

# ========== 列出某类型备份（带高亮最新） ==========
list_backups_by_type() {
    local backup_type="$1"
    local type_name=$(get_backup_type_name "$backup_type")
    local backup_dir=$(get_backup_dir "$backup_type")
    local latest=$(get_latest_backup "$backup_type")
    
    echo ""
    draw_line "─"
    printf "  %s%s%s 备份列表%s\n" "$B" "$cyn" "$type_name" "$R"
    draw_line "─"
    echo ""
    
    [ -z "$backup_dir" ] && { wa "未找到 ${type_name} 目录"; return 1; }
    [ ! -d "$backup_dir" ] && { wa "备份目录不存在: $backup_dir"; return 1; }
    
    local list=$(get_backup_list_by_type "$backup_type")
    [ -z "$list" ] && { wa "没有找到 ${type_name} 备份文件"; return 1; }
    
    local idx=1
    echo "$list" | while read -r file; do
        [ -z "$file" ] && continue
        local name=$(basename "$file")
        local size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
        local time_str=$(stat -c "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null | sed 's/^[^-]*-//')
        
        # 高亮最新备份
        if [ "$file" = "$latest" ]; then
            printf "  %s[%2d]%s %s%s%-40s%s %6s  %s[最新]%s\n" \
                "$B$grn" "$idx" "$R" "$rev$grn" "" "$name" "$R" "$size" "$grn" "$R"
        else
            printf "  [%2d] %-40s %6s  %s\n" "$idx" "$name" "$size" "$time_str"
        fi
        idx=$((idx + 1))
    done
    
    echo ""
    local count=$(get_backup_count_by_type "$backup_type")
    printf "  总计: %s%d%s 个备份文件\n" "$yel" "$count" "$R"
    
    return 0
}

# ========== 还原备份 ==========
restore_backup() {
    local backup_type="$1"
    local type_name=$(get_backup_type_name "$backup_type")
    local backup_dir=$(get_backup_dir "$backup_type")
    local source_file=$(get_backup_source_file "$backup_type")
    
    [ -z "$backup_dir" ] && { er "未找到 ${type_name} 备份目录"; return 1; }
    [ ! -d "$backup_dir" ] && { er "备份目录不存在"; return 1; }
    
    local list=$(get_backup_list_by_type "$backup_type")
    [ -z "$list" ] && { wa "没有可还原的 ${type_name} 备份"; return 1; }
    
    # 显示备份列表
    list_backups_by_type "$backup_type"
    
    echo ""
    draw_line "─"
    printf "  %s%s还原 %s 备份%s\n" "$B" "$cyn" "$type_name" "$R"
    draw_line "─"
    echo ""
    printf "  %s[0]%s 取消还原\n" "$yel" "$R"
    printf "  %s[1]%s 还原最新备份（推荐）\n" "$grn" "$R"
    [ $(get_backup_count_by_type "$backup_type") -gt 1 ] && \
        printf "  %s[2]%s 选择指定备份还原\n" "$cyn" "$R"
    echo ""
    printf "  %s请输入选项:%s " "$cyn" "$R"
    read -r choice
    
    local target_backup=""
    case "$choice" in
        0)
            info "已取消还原"
            return 0
            ;;
        1)
            target_backup=$(get_latest_backup "$backup_type")
            ;;
        2)
            if [ $(get_backup_count_by_type "$backup_type") -le 1 ]; then
                wa "只有一个备份，将使用最新备份"
                target_backup=$(get_latest_backup "$backup_type")
            else
                echo ""
                printf "  %s请输入要还原的备份编号:%s " "$cyn" "$R"
                read -r backup_idx
                ! echo "$backup_idx" | grep -qE "^[0-9]+$" && { er "无效的编号"; return 1; }
                [ "$backup_idx" -lt 1 ] && { er "无效的编号"; return 1; }
                target_backup=$(echo "$list" | sed -n "${backup_idx}p")
                [ -z "$target_backup" ] && { er "未找到该编号的备份"; return 1; }
            fi
            ;;
        *)
            wa "无效选项，将使用最新备份"
            target_backup=$(get_latest_backup "$backup_type")
            ;;
    esac
    
    [ -z "$target_backup" ] && { er "未选择有效的备份文件"; return 1; }
    [ ! -f "$target_backup" ] && { er "备份文件不存在"; return 1; }
    
    local backup_name=$(basename "$target_backup")
    echo ""
    info "准备还原备份: $backup_name"
    
    # 执行还原
    case "$backup_type" in
        "$BACKUP_TYPE_SCRIPT")
            # 脚本备份还原
            info "正在还原脚本..."
            if cp "$target_backup" "$SCRIPT_PATH"; then
                chmod +x "$SCRIPT_PATH"
                ok "脚本还原成功！"
                echo ""
                printf "  %s%s⚠️  脚本已更新，需要重启才能生效%s\n" "$B" "$yel" "$R"
                echo ""
                printf "  %s是否立即重启?%s\n" "$B" "$R"
                echo "    [0] 稍后手动重启"
                echo "    [1] 立即重启"
                echo ""
                printf "  %s请输入选项 [0-1]:%s " "$cyn" "$R"
                read -r restart_choice
                [ "$restart_choice" = "1" ] && { ok "正在重启..."; sleep 1; exec "$SCRIPT_PATH"; }
                info "已跳过重启，请稍后手动重启脚本"
            else
                er "脚本还原失败"
                return 1
            fi
            ;;
        "$BACKUP_TYPE_PHIRA")
            # Phira room.rs 还原
            [ -z "$source_file" ] && { er "未找到 Phira 源文件路径"; return 1; }
            info "正在还原 Phira 配置..."
            if cp "$target_backup" "$source_file"; then
                ok "配置还原成功！"
                echo ""
                printf "  %s%s⚠️  配置已更新，需要重新编译才能生效%s\n" "$B" "$yel" "$R"
                echo ""
                printf "  %s是否立即重新编译?%s\n" "$B" "$R"
                echo "    [0] 稍后手动编译"
                echo "    [1] 立即编译"
                echo ""
                printf "  %s请输入选项 [0-1]:%s " "$cyn" "$R"
                read -r rebuild_choice
                if [ "$rebuild_choice" = "1" ]; then
                    if rebuild_phira; then
                        ok "编译完成！"
                        printf "  %s%s⚠️  需要重启服务才能生效%s\n" "$B" "$yel" "$R"
                    else
                        wa "编译失败，请手动执行编译"
                    fi
                else
                    info "已跳过编译，请稍后手动执行"
                    wa "编译命令: cd $(find_phira_dir) && cargo build --release -p phira-mp-server"
                fi
            else
                er "配置还原失败"
                return 1
            fi
            ;;
        "$BACKUP_TYPE_FRP")
            # FRP配置还原
            [ -z "$source_file" ] && { er "未找到 FRP 源文件路径"; return 1; }
            info "正在还原 FRP 配置..."
            if cp "$target_backup" "$source_file"; then
                ok "配置还原成功！"
                echo ""
                printf "  %s%s⚠️  配置已更新，需要重启服务才能生效%s\n" "$B" "$yel" "$R"
                echo ""
                printf "  %s是否立即重启服务?%s\n" "$B" "$R"
                echo "    [0] 稍后手动重启"
                echo "    [1] 立即重启"
                echo ""
                printf "  %s请输入选项 [0-1]:%s " "$cyn" "$R"
                read -r restart_choice
                [ "$restart_choice" = "1" ] && { ok "配置已更新，请手动重启FRP服务"; }
                info "已跳过重启，请稍后手动重启服务"
            else
                er "配置还原失败"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# ========== 删除备份 ==========
delete_backup() {
    local backup_type="$1"
    local type_name=$(get_backup_type_name "$backup_type")
    local backup_dir=$(get_backup_dir "$backup_type")
    local latest=$(get_latest_backup "$backup_type")
    
    [ -z "$backup_dir" ] && { er "未找到 ${type_name} 备份目录"; return 1; }
    [ ! -d "$backup_dir" ] && { er "备份目录不存在"; return 1; }
    
    local list=$(get_backup_list_by_type "$backup_type")
    [ -z "$list" ] && { wa "没有可删除的 ${type_name} 备份"; return 1; }
    
    # 显示备份列表
    list_backups_by_type "$backup_type"
    
    echo ""
    draw_line "─"
    printf "  %s%s删除 %s 备份%s\n" "$B" "$cyn" "$type_name" "$R"
    draw_line "─"
    echo ""
    printf "  %s[0]%s 取消删除\n" "$yel" "$R"
    printf "  %s[1]%s 删除所有备份（除最新外）\n" "$cyn" "$R"
    printf "  %s[2]%s 删除所有备份\n" "$red" "$R"
    [ $(get_backup_count_by_type "$backup_type") -gt 1 ] && \
        printf "  %s[3]%s 选择指定备份删除\n" "$cyn" "$R"
    echo ""
    printf "  %s请输入选项:%s " "$cyn" "$R"
    read -r choice
    
    case "$choice" in
        0)
            info "已取消删除"
            return 0
            ;;
        1)
            # 删除除最新外的所有备份
            echo ""
            info "正在删除旧备份..."
            local deleted=0
            echo "$list" | while read -r file; do
                [ "$file" = "$latest" ] && continue
                rm -f "$file" && deleted=$((deleted + 1))
            done
            ok "已删除旧备份"
            ;;
        2)
            # 删除所有备份
            echo ""
            wa "即将删除所有 ${type_name} 备份"
            printf "  %s⚠️  此操作不可恢复，确认删除?%s\n" "$red" "$R"
            echo "    [0] 取消"
            echo "    [1] 确认删除"
            echo ""
            printf "  %s请输入选项 [0-1]:%s " "$cyn" "$R"
            read -r confirm
            [ "$confirm" != "1" ] && { info "已取消删除"; return 0; }
            rm -f "$backup_dir"/*.bak*
            ok "已删除所有备份"
            ;;
        3)
            if [ $(get_backup_count_by_type "$backup_type") -le 1 ]; then
                wa "只有一个备份，无法选择删除"
                return 1
            fi
            echo ""
            printf "  %s请输入要删除的备份编号（输入0取消）:%s " "$cyn" "$R"
            read -r backup_idx
            [ "$backup_idx" = "0" ] && { info "已取消删除"; return 0; }
            ! echo "$backup_idx" | grep -qE "^[0-9]+$" && { er "无效的编号"; return 1; }
            [ "$backup_idx" -lt 1 ] && { er "无效的编号"; return 1; }
            local target_backup=$(echo "$list" | sed -n "${backup_idx}p")
            [ -z "$target_backup" ] && { er "未找到该编号的备份"; return 1; }
            
            # 检查是否是最新备份
            if [ "$target_backup" = "$latest" ]; then
                echo ""
                wa "您选择的是最新备份"
                printf "  %s⚠️  删除最新备份后无法还原到最新状态，确认删除?%s\n" "$red" "$R"
                echo "    [0] 取消"
                echo "    [1] 确认删除"
                echo ""
                printf "  %s请输入选项 [0-1]:%s " "$cyn" "$R"
                read -r confirm
                [ "$confirm" != "1" ] && { info "已取消删除"; return 0; }
            fi
            
            if rm -f "$target_backup"; then
                ok "备份已删除"
            else
                er "删除失败"
                return 1
            fi
            ;;
        *)
            wa "无效选项"
            return 1
            ;;
    esac
    
    return 0
}

# ========== 备份管理子菜单 ==========
backup_manage_submenu() {
    local backup_type="$1"
    local type_name=$(get_backup_type_name "$backup_type")
    local count=$(get_backup_count_by_type "$backup_type")
    
    while true; do
        draw_header
        draw_box_top
        printf "  │%s %s备份管理 (%s个)          %s│\n" "$B" "$type_name" "$count" "$R"
        draw_box_mid
        [ $count -gt 0 ] && \
            printf "  │  [1] 查看备份列表                    │\n" || \
            printf "  │  %s[1] 查看备份列表%s                   │\n" "$D" "$R"
        [ $count -gt 0 ] && \
            printf "  │  [2] 还原备份                        │\n" || \
            printf "  │  %s[2] 还原备份%s                      │\n" "$D" "$R"
        [ $count -gt 0 ] && \
            printf "  │  [3] 删除备份                        │\n" || \
            printf "  │  %s[3] 删除备份%s                      │\n" "$D" "$R"
        draw_box_mid
        printf "  │  [0] 返回上级菜单                    │\n"
        draw_box_bottom
        echo ""
        printf "  %s请输入选项 [0-3]:%s " "$cyn" "$R"
        read -r choice; echo ""
        
        case "$choice" in
            1)
                list_backups_by_type "$backup_type"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            2)
                restore_backup "$backup_type"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            3)
                delete_backup "$backup_type"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            0)
                return 0
                ;;
            *)
                wa "无效选项: $choice"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
        esac
        
        # 更新计数
        count=$(get_backup_count_by_type "$backup_type")
    done
}

# ========== 备份管理主菜单（整合扫描所有备份） ==========
backup_manage_menu() {
    while true; do
        local script_count=$(get_backup_count_by_type "$BACKUP_TYPE_SCRIPT")
        local phira_count=$(get_backup_count_by_type "$BACKUP_TYPE_PHIRA")
        local frp_count=$(get_backup_count_by_type "$BACKUP_TYPE_FRP")
        local type_total=$((script_count + phira_count + frp_count))
        local all_count=$(get_all_backup_count)
        local all_size=$(get_all_backup_size)
        
        draw_header
        draw_box_top
        printf "  │%s 备份管理                            %s│\n" "$B" "$R"
        draw_box_mid
        printf "  │  %s分类备份%s                            │\n" "$B" "$R"
        printf "  │  [1] 启动脚本备份 (%s个)             │\n" "$script_count"
        printf "  │  [2] Phira服务器备份 (%s个)          │\n" "$phira_count"
        printf "  │  [3] 内网穿透配置备份 (%s个)         │\n" "$frp_count"
        draw_box_mid
        printf "  │  %s全盘扫描%s                            │\n" "$B" "$R"
        printf "  │  [4] 扫描所有目录 (%s个, %s)         │\n" "$all_count" "$all_size"
        draw_box_mid
        printf "  │  [0] 返回设置菜单                    │\n"
        draw_box_bottom
        echo ""
        printf "  %s请输入选项 [0-4]:%s " "$cyn" "$R"
        read -r choice; echo ""
        
        case $choice in
            1)
                backup_manage_submenu "$BACKUP_TYPE_SCRIPT"
                ;;
            2)
                local phira_dir=$(find_phira_dir)
                [ -z "$phira_dir" ] && { wa "Phira-mp 未安装"; echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r; continue; }
                backup_manage_submenu "$BACKUP_TYPE_PHIRA"
                ;;
            3)
                local frp_dir=$(find_frp_dir)
                [ -z "$frp_dir" ] && { wa "ChmlFrp 未安装"; echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r; continue; }
                backup_manage_submenu "$BACKUP_TYPE_FRP"
                ;;
            4)
                scan_and_manage_backups
                ;;
            0)
                return 0
                ;;
            *)
                wa "无效选项: $choice"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
        esac
    done
}

# ========== 全目录备份扫描管理 ==========
get_all_backup_count() {
    local count=$(find "$HOME" -maxdepth 10 -type f \
        \( -name "*.bak" -o -name "*.bak.*" \) \
        -not -path "$HOME/.cache/*" \
        -not -path "$HOME/.cargo/*" \
        -not -path "$HOME/.termux/*" \
        -not -path "$HOME/.local/*" \
        -not -path "$HOME/.git/*" 2>/dev/null | wc -l)
    echo "$count"
}

get_all_backup_size() {
    local size=$(find "$HOME" -maxdepth 10 -type f \
        \( -name "*.bak" -o -name "*.bak.*" \) \
        -not -path "$HOME/.cache/*" \
        -not -path "$HOME/.cargo/*" \
        -not -path "$HOME/.termux/*" \
        -not -path "$HOME/.local/*" \
        -not -path "$HOME/.git/*" 2>/dev/null \
        -exec du -ch {} + 2>/dev/null | grep total | cut -f1)
    [ -z "$size" ] && size="0"
    echo "$size"
}

list_all_backups() {
    local files=$(find "$HOME" -maxdepth 10 -type f \
        \( -name "*.bak" -o -name "*.bak.*" \) \
        -not -path "$HOME/.cache/*" \
        -not -path "$HOME/.cargo/*" \
        -not -path "$HOME/.termux/*" \
        -not -path "$HOME/.local/*" \
        -not -path "$HOME/.git/*" 2>/dev/null | sort)
    [ -z "$files" ] && { wa "没有找到任何备份文件"; return 1; }

    echo "  扫描到的所有备份文件（含带日期后缀）："
    local current_dir=""
    echo "$files" | while read -r f; do
        local dir=$(dirname "$f")
        local name=$(basename "$f")
        local size=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
        local backup_time=$(stat -c "%y" "$f" 2>/dev/null | cut -d' ' -f1,2 | sed 's/\..*//')
        
        if [ "$dir" != "$current_dir" ]; then
            echo ""
            echo "  📂 目录: $dir"
            current_dir="$dir"
        fi
        printf "    %-45s %6s  备份时间: %s\n" "$name" "$size" "$backup_time"
    done

    echo ""
    local total_count=$(get_all_backup_count)
    local total_size=$(get_all_backup_size)
    echo "  📊 总计: $total_count 个备份文件，总占用大小: $total_size"
    return 0
}

delete_all_backups() {
    local files=$(find "$HOME" -maxdepth 10 -type f \
        \( -name "*.bak" -o -name "*.bak.*" \) \
        -not -path "$HOME/.cache/*" \
        -not -path "$HOME/.cargo/*" \
        -not -path "$HOME/.termux/*" \
        -not -path "$HOME/.local/*" \
        -not -path "$HOME/.git/*" 2>/dev/null)
    [ -z "$files" ] && { wa "没有备份可删除"; return 0; }

    local total_count=$(echo "$files" | wc -l)
    local total_size=$(get_all_backup_size)
    wa "即将删除所有扫描到的备份文件"
    echo "  总数量: $total_count 个"
    echo "  总大小: $total_size"
    echo ""
    printf "  %s⚠️  此操作不可恢复，确认删除? [y/N]:%s " "$red" "$R"
    read -r confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { info "已取消删除"; return 0; }

    echo "$files" | while read -r f; do rm -f "$f"; done
    ok "已成功删除所有备份文件"
    return 0
}

scan_and_manage_backups() {
    while true; do
        draw_header
        local total_count=$(get_all_backup_count)
        local total_size=$(get_all_backup_size)
        draw_box_top
        printf "  │%s 扫描所有目录的全部备份              %s│\n" "$B" "$R"
        draw_box_mid
        printf "  │  扫描范围: Termux HOME 全目录        │\n"
        printf "  │  匹配规则: *.bak / *.bak.* 全格式    │\n"
        printf "  │  备份总数: %s%-4s%s  总大小: %-10s   │\n" "$yel" "$total_count" "$R" "$total_size"
        draw_box_mid
        [ $total_count -gt 0 ] && \
            printf "  │  [1] 查看所有备份文件                │\n" || \
            printf "  │  %s[1] 查看所有备份文件%s               │\n" "$D" "$R"
        [ $total_count -gt 0 ] && \
            printf "  │  [2] 删除所有备份文件                │\n" || \
            printf "  │  %s[2] 删除所有备份文件%s               │\n" "$D" "$R"
        draw_box_mid
        printf "  │  [0] 返回设置菜单                    │\n"
        draw_box_bottom
        echo ""
        printf "  %s请输入选项 [0-2]:%s " "$cyn" "$R"
        read -r choice; echo ""
        case $choice in
            1)
                list_all_backups
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            2)
                delete_all_backups
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            0)
                return
                ;;
            *)
                wa "无效选项: $choice"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
        esac
    done
}

# ========== 房间人数设置 ==========
get_room_max_users() {
    local dir=$(find_phira_dir)
    [ -z "$dir" ] && { er "未找到 Phira-mp 目录"; return 1; }
    local file="$dir/phira-mp-server/src/room.rs"
    [ ! -f "$file" ] && { er "未找到 room.rs"; return 1; }
    local val=$(grep -E "const ROOM_MAX_USERS: usize = [0-9]+;" "$file" | grep -oE "[0-9]+")
    [ -z "$val" ] && val="8"
    echo "$val"
}
set_room_max_users() {
    local dir=$(find_phira_dir) val=$1
    [ -z "$dir" ] && { er "未找到 Phira-mp 目录"; return 1; }
    local file="$dir/phira-mp-server/src/room.rs"
    [ ! -f "$file" ] && { er "未找到 room.rs"; return 1; }
    [ -z "$val" ] && { er "未指定人数"; return 1; }
    ! echo "$val" | grep -qE "^[0-9]+$" && { er "必须是数字"; return 1; }
    [ "$val" -lt 1 ] || [ "$val" -gt 100 ] && { er "必须在 1-100 之间"; return 1; }
    info "修改房间人数上限为: $val"
    cp "$file" "$file.bak.$(date +%Y%m%d_%H%M%S)"
    sed -i "s/const ROOM_MAX_USERS: usize = [0-9]\+;/const ROOM_MAX_USERS: usize = $val;/" "$file"
    local verify=$(grep -E "const ROOM_MAX_USERS: usize = [0-9]+;" "$file" | grep -oE "[0-9]+")
    [ "$verify" = "$val" ] && { ok "修改成功"; return 0; }
    er "修改失败"; return 1
}
rebuild_phira() {
    local dir=$(find_phira_dir)
    [ -z "$dir" ] && { er "未找到 Phira-mp 目录"; return 1; }
    info "开始重新编译..."
    cd "$dir" || return 1
    info "清理旧构建..."
    cargo clean -p phira-mp-server
    info "编译中（可能需要几分钟）..."
    echo "  ${D}cargo build --release -p phira-mp-server${R}"
    echo ""
    if cargo build --release -p phira-mp-server 2>&1; then
        ok "编译完成"; cd - > /dev/null; return 0
    else
        er "编译失败"; cd - > /dev/null; return 1
    fi
}
config_room_max_users() {
    local dir=$(find_phira_dir)
    [ -z "$dir" ] && { wa "Phira-mp 未安装"; return 1; }
    local current=$(get_room_max_users)
    [ $? -ne 0 ] && return 1
    echo ""; draw_line "─"
    echo "  当前房间人数上限: ${B}$current${R}"
    draw_line "─"; echo ""
    echo "  请输入新的人数上限 (1-100)，回车保持 $current:"
    echo ""
    printf "  %s人数:%s " "$cyn" "$R"
    read -r new_val; echo ""
    [ -z "$new_val" ] && { info "保持原值: $current"; return 0; }
    [ "$new_val" = "$current" ] && { info "数值未改变"; return 0; }
    set_room_max_users "$new_val" || return 1
    echo ""; info "需要重新编译才能生效"
    printf "  %s是否立即编译? [Y/n]:%s " "$cyn" "$R"
    read -r confirm
    [ -n "$confirm" ] && [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && \
        { wa "已跳过编译，修改将在下次编译后生效"; return 0; }
    echo ""
    if rebuild_phira; then
        ok "配置已更新并编译完成"
        echo "  新房间人数上限: ${B}$new_val${R}"
    else
        wa "编译失败，请手动执行:"
        echo "  cd $dir"
        echo "  cargo clean -p phira-mp-server"
        echo "  cargo build --release -p phira-mp-server"
    fi
}

# ========== 内网穿透配置管理 ==========
get_frp_config_path() {
    local dir=$(find_frp_dir)
    [ -z "$dir" ] && { echo ""; return 1; }
    echo "$dir/frpc.ini"
}
view_frp_config() {
    local config_file=$(get_frp_config_path)
    [ -z "$config_file" ] && { wa "未找到内网穿透目录"; return 1; }
    [ ! -f "$config_file" ] && { wa "配置文件不存在"; return 1; }
    echo ""
    draw_line "─"
    echo "  ${B}当前内网穿透配置${R}"
    draw_line "─"
    echo ""
    cat "$config_file" | sed 's/^/  /'
    echo ""
    draw_line "─"
    echo ""
    return 0
}
configure_frp() {
    local frp_dir=$(find_frp_dir)
    [ -z "$frp_dir" ] && { wa "ChmlFrp 未安装"; return 1; }
    local config_file="$frp_dir/frpc.ini"
    echo ""
    draw_line "═"
    printf "  %s%s内网穿透配置%s\n" "$B" "$blu" "$R"
    draw_line "═"
    echo ""
    info "请从 ChmlFrp 面板复制配置，然后粘贴到这里"
    echo -e "  ${D}（长按粘贴，输入完成后输入数字 0 结束）${R}"
    echo ""
    echo -e "  ${yel}请粘贴配置内容（输入 0 结束）:${R}"
    echo ""
    local tmp_file=$(mktemp)
    while IFS= read -r line; do
        if [ "$line" = "0" ]; then
            break
        fi
        echo "$line" >> "$tmp_file"
    done
    if [ ! -s "$tmp_file" ]; then
        wa "未检测到输入，配置未更改"
        rm -f "$tmp_file"
        return 1
    fi
    # 备份原配置
    if [ -f "$config_file" ]; then
        cp "$config_file" "$config_file.bak.$(date +%Y%m%d_%H%M%S)"
        ok "已备份原配置"
    fi
    cp "$tmp_file" "$config_file"
    rm -f "$tmp_file"
    if [ -f "$config_file" ] && grep -q "\[common\]" "$config_file"; then
        echo ""
        ok "配置已保存"
        echo ""
        draw_line "─"
        echo "  ${D}配置预览:${R}"
        draw_line "─"
        cat "$config_file" | sed 's/^/  /'
        echo ""
        draw_line "─"
        echo ""
        echo -e "  ${B}${grn}[1]${R} 配置正确，完成"
        echo -e "  ${B}${red}[2]${R} 重新配置"
        echo ""
        printf "  %s选择 [1-2]:%s " "$cyn" "$R"
        read -r confirm
        case $confirm in
            2) configure_frp ;;
            *) ok "配置完成" ;;
        esac
    else
        wa "配置可能不完整，请检查"
        return 1
    fi
}
config_frp_menu() {
    local frp_dir=$(find_frp_dir)
    [ -z "$frp_dir" ] && { wa "ChmlFrp 未安装"; return 1; }
    while true; do
        draw_header
        local config_status="${D}未配置${R}"
        local config_file=$(get_frp_config_path)
        [ -f "$config_file" ] && config_status="${grn}已配置${R}"
        draw_box_top
        printf "  │%s 内网穿透配置                        %s│\n" "$B" "$R"
        draw_box_mid
        printf "  │  状态: %s                          │\n" "$config_status"
        draw_box_mid
        printf "  │  [1] 查看当前配置                    │\n"
        printf "  │  [2] 修改配置                        │\n"
        draw_box_mid
        printf "  │  [0] 返回设置菜单                    │\n"
        draw_box_bottom
        echo ""
        printf "  %s请输入选项 [0-2]:%s " "$cyn" "$R"
        read -r choice; echo ""
        case $choice in
            1)
                view_frp_config
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            2)
                configure_frp
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            0)
                return
                ;;
            *)
                wa "无效选项: $choice"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
        esac
    done
}

# ========== 更新日志美化功能 ==========
tag_add() { printf "%s%s[新增]%s" "$bg_grn" "$wht" "$R"; }
tag_fix() { printf "%s%s[修复]%s" "$bg_red" "$wht" "$R"; }
tag_opt() { printf "%s%s[优化]%s" "$bg_blu" "$wht" "$R"; }
tag_del() { printf "%s%s[删除]%s" "$bg_mag" "$wht" "$R"; }
tag_doc() { printf "%s%s[文档]%s" "$bg_cyn" "$wht" "$R"; }
tag_other() { printf "%s%s[其他]%s" "$bg_yel" "$blk" "$R"; }

format_changelog_line() {
    local line="$1"
    local indent="    "
    local ver_regex="[vV]?[0-9]+\.[0-9]+\.[0-9]+"
    local date_regex="[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}"

    if echo "$line" | grep -qE "$ver_regex" && echo "$line" | grep -qE "$date_regex"; then
        local ver=$(echo "$line" | grep -oE "$ver_regex" | head -1)
        local date=$(echo "$line" | grep -oE "$date_regex" | head -1)
        
        printf "\n"
        draw_line "━"
        printf "  %s%s📦 版本 %s%s" "$B" "$cyn" "$ver" "$R"
        [ -n "$date" ] && printf "  %s%s📅 %s%s" "$D" "$yel" "$date" "$R"
        printf "\n"
        draw_line "━"
        return
    fi
    
    if echo "$line" | grep -qE "^[#vV]*[ ]*$ver_regex"; then
        local ver=$(echo "$line" | grep -oE "$ver_regex" | head -1)
        local date=$(echo "$line" | grep -oE "$date_regex" | head -1)
        
        printf "\n"
        draw_line "━"
        printf "  %s%s📦 版本 %s%s" "$B" "$cyn" "$ver" "$R"
        [ -n "$date" ] && printf "  %s%s📅 %s%s" "$D" "$yel" "$date" "$R"
        printf "\n"
        draw_line "━"
        return
    fi
    
    if echo "$line" | grep -qE "^$date_regex"; then
        local date=$(echo "$line" | grep -oE "$date_regex" | head -1)
        printf "  %s%s📅 %s%s\n" "$D" "$yel" "$date" "$R"
        return
    fi
    
    [ -z "$(echo "$line" | tr -d '[:space:]')" ] && return
    
    local prefix="$indent"
    local tag=""
    
    if echo "$line" | grep -qiE '^\s*[-*+]*\s*(新增|添加|增加|实现|支持|引入)'; then
        tag=$(tag_add)
        line=$(echo "$line" | sed -E 's/^\s*[-*+]*\s*(新增|添加|增加|实现|支持|引入)[：:]?\s*//i')
    elif echo "$line" | grep -qiE '^\s*[-*+]*\s*(修复|解决|修正|处理|bug|错误)'; then
        tag=$(tag_fix)
        line=$(echo "$line" | sed -E 's/^\s*[-*+]*\s*(修复|解决|修正|处理)[：:]?\s*//i')
    elif echo "$line" | grep -qiE '^\s*[-*+]*\s*(优化|改进|提升|调整|重构|完善)'; then
        tag=$(tag_opt)
        line=$(echo "$line" | sed -E 's/^\s*[-*+]*\s*(优化|改进|提升|调整|重构|完善)[：:]?\s*//i')
    elif echo "$line" | grep -qiE '^\s*[-*+]*\s*(删除|移除|清理|废弃)'; then
        tag=$(tag_del)
        line=$(echo "$line" | sed -E 's/^\s*[-*+]*\s*(删除|移除|清理|废弃)[：:]?\s*//i')
    elif echo "$line" | grep -qiE '^\s*[-*+]*\s*(文档|说明|注释|readme)'; then
        tag=$(tag_doc)
        line=$(echo "$line" | sed -E 's/^\s*[-*+]*\s*(文档|说明|注释)[：:]?\s*//i')
    else
        if echo "$line" | grep -qE '^\s*[-*+]+\s'; then
            line=$(echo "$line" | sed 's/^\s*[-*+]\s*//')
            tag=$(tag_other)
        fi
    fi
    
    if [ -n "$tag" ]; then
        printf "  %s%s %s%s\n" "$prefix" "$tag" "$line" "$R"
    else
        printf "  %s%s%s\n" "$indent" "$line" "$R"
    fi
}

show_changelog() {
    clear
    
    local changelog_content=""
    local download_success=0
    
    if check_network; then
        changelog_content=$(download_text "$CHANGELOG_URL" 2>/dev/null)
        [ -n "$changelog_content" ] && download_success=1
    fi
    
    printf "\n"
    printf "  %s%s╔════════════════════════════════════════════════════════════╗%s\n" "$B" "$cyn" "$R"
    printf "  %s%s║%s                                                            %s%s║%s\n" "$B" "$cyn" "$R" "$B" "$cyn" "$R"
    printf "  %s%s║%s     %s📋  系 统 更 新 日 志  📋%s                                 %s%s║%s\n" "$B" "$cyn" "$R" "$B$rev" "$R" "$B" "$cyn" "$R"
    printf "  %s%s║%s                                                            %s%s║%s\n" "$B" "$cyn" "$R" "$B" "$cyn" "$R"
    printf "  %s%s╚════════════════════════════════════════════════════════════╝%s\n" "$B" "$cyn" "$R"
    printf "\n"
    
    if [ $download_success -eq 1 ]; then
        echo "$changelog_content" | while IFS= read -r line; do
            format_changelog_line "$line"
        done
        
        printf "\n"
        draw_line "─"
        printf "  %s%s✨ 当前版本: %s%s%s\n" "$B" "$grn" "$VERSION" "$R"
    else
        printf "\n"
        wa "无法获取更新日志，请检查网络连接"
        echo ""
        printf "  %s更新日志地址: %s%s%s\n" "$D" "$blu" "$CHANGELOG_URL" "$R"
    fi
    
    printf "\n"
    printf "  %s%s┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓%s\n" "$bg_blu" "$wht" "$R"
    printf "  %s%s┃%s                                                            %s%s┃%s\n" "$bg_blu" "$wht" "$R" "$bg_blu" "$wht" "$R"
    printf "  %s%s┃%s        %s⏎  按 %s回车键%s 退出更新日志并返回设置菜单  ⏎%s          %s%s┃%s\n" "$bg_blu" "$wht" "$R" "$B" "$rev" "$R$B" "$R" "$bg_blu" "$wht" "$R"
    printf "  %s%s┃%s                                                            %s%s┃%s\n" "$bg_blu" "$wht" "$R" "$bg_blu" "$wht" "$R"
    printf "  %s%s┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛%s\n" "$bg_blu" "$wht" "$R"
    printf "\n"
    
    read -r
    clear
}

# ========== 欢迎消息配置 ==========
get_welcome_config_status() {
    local dir=$(find_phira_dir)
    [ -z "$dir" ] && { echo "未安装"; return 1; }
    local session_file="$dir/phira-mp-server/src/session.rs"
    [ ! -f "$session_file" ] && { echo "未安装"; return 1; }
    if grep -q "自定义欢迎消息" "$session_file" 2>/dev/null; then
        echo "已配置"
    else
        echo "未配置"
    fi
}
config_welcome_message() {
    local dir=$(find_phira_dir)
    [ -z "$dir" ] && { wa "Phira-mp 未安装"; return 1; }
    local server_dir="$dir/phira-mp-server"
    cd "$server_dir" || { er "无法进入目录"; return 1; }
    local FIXED_DETAIL_TEXT="安卓设备搭建同款服务器"
    local FIXED_DETAIL_LINK="https://riluo-ya.github.io/blog/posts/6/"
    local FIXED_YIYAN_API="https://api.yviii.com/yiyan/yi.php/?syz=txt&charset=utf-8"
    draw_header
    echo ""
    draw_line "═"
    printf "  %s%s欢迎消息配置%s\n" "$B" "$cyn" "$R"
    draw_line "═"
    echo ""
    local current_status=$(get_welcome_config_status)
    printf "  当前状态: %s\n" "$current_status"
    echo ""
    printf "  %s请输入服务器名称（默认：Phira联机服务器）：%s" "$cyn" "$R"
    read -r SERVER_NAME
    SERVER_NAME="${SERVER_NAME:-Phira联机服务器}"
    printf "  %s请输入联机群号（留空不显示）：%s" "$cyn" "$R"
    read -r GROUP_INFO
    GROUP_INFO="${GROUP_INFO:-}"
    echo ""

    if [ -z "$SERVER_NAME" ] && [ -z "$GROUP_INFO" ]; then
        info "检测到服务器名称和群号均为空，正在清理欢迎消息配置"
        if grep -q "自定义欢迎消息" src/session.rs 2>/dev/null; then
            awk '
                /自定义欢迎消息.*开始/ { in_block=1; next }
                /自定义欢迎消息.*结束/ { in_block=0; next }
                !in_block { print }
            ' src/session.rs > src/session.rs.tmp && mv src/session.rs.tmp src/session.rs
        fi
        sed -i '/^use crate::config::CUSTOM_CONFIG;$/d' src/session.rs 2>/dev/null || true
        sed -i '/^mod config;$/d' src/main.rs 2>/dev/null || true
        rm -f src/config.rs 2>/dev/null
        sed -i '/^once_cell =/d' Cargo.toml 2>/dev/null || true
        sed -i '/^reqwest =/d' Cargo.toml 2>/dev/null || true
        
        ok "欢迎消息配置已完全清理，将不显示欢迎页面"
        echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
        return 0
    fi

    info "正在配置欢迎消息..."
    if grep -q "自定义欢迎消息" src/session.rs 2>/dev/null; then
        awk '
            /自定义欢迎消息.*开始/ { in_block=1; next }
            /自定义欢迎消息.*结束/ { in_block=0; next }
            !in_block { print }
        ' src/session.rs > src/session.rs.tmp && mv src/session.rs.tmp src/session.rs
    fi
    sed -i '/^use crate::config::CUSTOM_CONFIG;$/d' src/session.rs 2>/dev/null || true
    sed -i '/^use crate::config::CONFIG;$/d' src/session.rs 2>/dev/null || true
    sed -i '/^mod config;$/d' src/main.rs 2>/dev/null || true
    
    cat > src/config.rs << EOF
use once_cell::sync::Lazy;
pub static CUSTOM_CONFIG: Lazy<CustomConfig> = Lazy::new(|| CustomConfig {
    server_name: "${SERVER_NAME}".to_string(),
    group_info: "${GROUP_INFO}".to_string(),
    detail_text: "${FIXED_DETAIL_TEXT}".to_string(),
    detail_link: "${FIXED_DETAIL_LINK}".to_string(),
    yiyan_api: "${FIXED_YIYAN_API}".to_string(),
});
#[derive(Debug, Clone)]
pub struct CustomConfig {
    pub server_name: String,
    pub group_info: String,
    pub detail_text: String,
    pub detail_link: String,
    pub yiyan_api: String,
}
EOF
    
    if ! grep -q "^mod config;" src/main.rs; then
        if head -n 1 src/main.rs | grep -q "^#!"; then
            sed -i '2i mod config;' src/main.rs
        else
            sed -i '1i mod config;' src/main.rs
        fi
    fi
    
    if ! grep -q "^once_cell" Cargo.toml; then
        echo 'once_cell = "1.19"' >> Cargo.toml
    fi
    if ! grep -q "^reqwest" Cargo.toml; then
        echo 'reqwest = { version = "0.11", features = ["rustls-tls-native-roots", "json"] }' >> Cargo.toml
    fi
    
    if ! grep -q "use crate::config::CUSTOM_CONFIG;" src/session.rs; then
        local LAST_USE_LINE=$(grep -n "^use " src/session.rs | tail -1 | cut -d: -f1)
        if [ -n "$LAST_USE_LINE" ]; then
            sed -i "${LAST_USE_LINE}a use crate::config::CUSTOM_CONFIG;" src/session.rs
        else
            sed -i '1i use crate::config::CUSTOM_CONFIG;' src/session.rs
        fi
    fi
    
    local WELCOME_FILE=$(mktemp)
    cat > "$WELCOME_FILE" << 'ENDOFCODE'
        // ========== 自定义欢迎消息 - 开始 ==========
        let _ = send_tx.send(ServerCommand::Message(Message::Chat {
            user: user.id,
            content: format!("\"{}\" 你好！欢迎来到 {}！", user.name, CUSTOM_CONFIG.server_name),
        })).await;
        let _ = send_tx.send(ServerCommand::Message(Message::Chat {
            user: user.id,
            content: "--------------------------------------------".to_string(),
        })).await;
        let _ = send_tx.send(ServerCommand::Message(Message::Chat {
            user: user.id,
            content: "当前可用的房间如下：".to_string(),
        })).await;
        let rooms_guard = user.server.rooms.read().await;
        let room_ids: Vec<String> = rooms_guard.keys().map(|id| id.to_string()).collect();
        drop(rooms_guard);
        let room_msg = if room_ids.is_empty() {
            "当前没有可用房间".to_string()
        } else {
            format!("可用房间ID：{}", room_ids.join("、"))
        };
        let _ = send_tx.send(ServerCommand::Message(Message::Chat {
            user: user.id,
            content: room_msg,
        })).await;
        let _ = send_tx.send(ServerCommand::Message(Message::Chat {
            user: user.id,
            content: "--------------------------------------------".to_string(),
        })).await;
        if !CUSTOM_CONFIG.group_info.is_empty() {
            let _ = send_tx.send(ServerCommand::Message(Message::Chat {
                user: user.id,
                content: CUSTOM_CONFIG.group_info.clone(),
            })).await;
        }
        let _ = send_tx.send(ServerCommand::Message(Message::Chat {
            user: user.id,
            content: format!("{}：{}", CUSTOM_CONFIG.detail_text, CUSTOM_CONFIG.detail_link),
        })).await;
        let api_url = CUSTOM_CONFIG.yiyan_api.clone();
        let user_clone = Arc::clone(&user);
        tokio::spawn(async move {
            match reqwest::get(&api_url).await {
                Ok(resp) if resp.status().is_success() => {
                    if let Ok(yiyan_text) = resp.text().await {
                        let yiyan_text = yiyan_text.trim();
                        if !yiyan_text.is_empty() {
                            let _ = user_clone.try_send(ServerCommand::Message(Message::Chat {
                                user: user_clone.id,
                                content: format!("一言: {}", yiyan_text),
                            })).await;
                        }
                    }
                }
                _ => {}
            }
        });
        // ========== 自定义欢迎消息 - 结束 ==========
ENDOFCODE
    
    local INSERTED=false
    if grep -q "waiting_for_authenticate.store(false" src/session.rs; then
        local TARGET_LINE=$(grep -n "waiting_for_authenticate.store(false" src/session.rs | head -1 | cut -d: -f1)
        if [ -n "$TARGET_LINE" ]; then
            head -n "$((TARGET_LINE - 1))" src/session.rs > src/session.rs.new
            cat "$WELCOME_FILE" >> src/session.rs.new
            tail -n +"$TARGET_LINE" src/session.rs >> src/session.rs.new
            if [ -s src/session.rs.new ]; then
                mv src/session.rs.new src/session.rs
                INSERTED=true
            fi
        fi
    fi
    rm -f "$WELCOME_FILE"
    if [ "$INSERTED" = false ]; then
        er "无法找到合适的代码插入位置"
        return 1
    fi
    ok "配置已写入"
    echo ""
    info "开始重新编译..."
    echo "  ${D}cargo clean -p phira-mp-server${R}"
    cargo clean -p phira-mp-server 2>/dev/null || cargo clean
    echo "  ${D}cargo build --release -p phira-mp-server${R}"
    echo ""
    if cargo build --release -p phira-mp-server 2>&1; then
        ok "编译成功！"
        echo ""
        echo "  服务器名称: ${B}$SERVER_NAME${R}"
        [ -n "$GROUP_INFO" ] && echo "  联机群号: ${B}$GROUP_INFO${R}" || echo "  联机群号: ${D}未设置${R}"
        return 0
    else
        er "编译失败"
        return 1
    fi
}

# ========== 界面绘制 ==========
draw_line() {
    local c="${1:-─}"; printf "  "; for ((i=0;i<40;i++)); do printf "%s" "$c"; done; printf "\n"
}
draw_header() {
    echo ""; draw_line "═"
    printf "  %s%sPhira 设置工具%s\n" "$B" "$cyn" "$R"
    printf "  %s版本 %s • 作者: 日落-ya%s\n" "$D" "$VERSION" "$R"
    draw_line "═"; echo ""
}
draw_box_top() { echo "  ┌──────────────────────────────────────┐"; }
draw_box_mid() { echo "  ├──────────────────────────────────────┤"; }
draw_box_bottom() { echo "  └──────────────────────────────────────┘"; }

# ========== 设置界面 ==========
show_settings_menu() {
    local pdir=$(find_phira_dir)
    local fdir=$(find_frp_dir)
    local script_count=$(get_backup_count_by_type "$BACKUP_TYPE_SCRIPT")
    local phira_count=$(get_backup_count_by_type "$BACKUP_TYPE_PHIRA")
    local frp_count=$(get_backup_count_by_type "$BACKUP_TYPE_FRP")
    local total_bcount=$((script_count + phira_count + frp_count))
    draw_box_top; printf "  │%s 设置                                %s│\n" "$B" "$R"; draw_box_mid
    # 1. 房间人数上限
    if [ -n "$pdir" ]; then
        local max=$(get_room_max_users 2>/dev/null || echo "?")
        printf "  │  [1] 房间人数上限 (当前: %s)          │\n" "$max"
    else
        printf "  │  %s[1] 房间人数上限 (需先安装)%s         │\n" "$D" "$R"
    fi
    # 2. 内网穿透配置
    if [ -n "$fdir" ]; then
        local config_status="${D}未配置${R}"
        local config_file=$(get_frp_config_path)
        [ -f "$config_file" ] && config_status="${grn}已配置${R}"
        printf "  │  [2] 内网穿透配置 (%s)           │\n" "$config_status"
    else
        printf "  │  %s[2] 内网穿透配置 (需先安装)%s         │\n" "$D" "$R"
    fi
    # 3. 备份管理（已整合扫描所有备份）
    printf "  │  [3] 备份管理 (%s个)                 │\n" "$total_bcount"
    # 4. 欢迎消息配置
    local welcome_status=$(get_welcome_config_status)
    if [ "$welcome_status" = "已配置" ]; then
        printf "  │  [4] 欢迎消息配置 (${grn}已配置${R})          │\n"
    else
        printf "  │  [4] 欢迎消息配置 (${D}未配置${R})          │\n"
    fi
    # 5. 更新日志
    printf "  │  [5] 更新日志                        │\n"
    # 6. 刷新状态
    printf "  │  [6] 刷新状态                        │\n"
    draw_box_mid
    printf "  │  [0] 返回主菜单                      │\n"
    draw_box_bottom; echo ""
}

handle_settings() {
    while true; do
        draw_header
        show_settings_menu
        printf "  %s请输入选项 [0-6]:%s " "$cyn" "$R"
        read -r choice; echo ""
        case $choice in
            1)
                config_room_max_users
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            2)
                config_frp_menu
                ;;
            3)
                backup_manage_menu
                ;;
            5)
                show_changelog
                ;;
            6)
                info "已刷新服务与备份状态"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
            0)
                echo ""
                draw_line "─"
                printf "  %s%s正在返回主菜单...%s\n" "$B" "$cyn" "$R"
                draw_line "─"
                sleep 1
                launch_start
                ;;
            *)
                wa "无效选项: $choice"
                echo ""; printf "  %s按回车键继续...%s" "$D" "$R"; read -r
                ;;
        esac
    done
}

# ========== 启动 start.sh ==========
launch_start() {
    local start_script="$SCRIPT_DIR/start.sh"
    # 如果当前目录没有，尝试下载
    if [ ! -f "$start_script" ]; then
        info "未找到 start.sh，尝试下载..."
        if check_network; then
            download_file "https://riluo-ya.github.io/blog/sh/Phira-mp/start.sh" "$start_script" 2>/dev/null && \
                chmod +x "$start_script"
        fi
    fi
    # 检查start.sh是否存在
    if [ -f "$start_script" ]; then
        chmod +x "$start_script"
        exec "$start_script"
    else
        er "无法找到或下载 start.sh"
        printf "  %s按回车键继续...%s" "$D" "$R"; read -r
    fi
}

# ========== 主程序 ==========
main() {
    # 检查更新
    auto_update
    # 进入设置菜单
    handle_settings
}

main
