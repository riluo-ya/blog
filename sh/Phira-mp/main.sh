#!/data/data/com.termux/files/usr/bin/bash
# ======================================================
# Phira MP 服务器管理脚本 - Termux 专用版
# 作者: Phira MP Team
# 版本: v1.3.1
# ======================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# 配置文件路径
CONFIG_FILE="server_config.yml"
SCRIPT_PATH="$0"

# GitHub 原始地址
UPDATE_URL="https://raw.githubusercontent.com/riluo-ya/blog/main/sh/Phira-mp/main.sh"
MD5_URL="https://raw.githubusercontent.com/riluo-ya/blog/main/sh/Phira-mp/mainmd5.txt"

# 自动检测 tphira-mp 目录位置
find_project_dir() {
    if [ -d "$(pwd)/tphira-mp" ]; then
        PROJECT_DIR="$(pwd)/tphira-mp"
    elif [ -d "$(dirname "$0")/tphira-mp" ]; then
        PROJECT_DIR="$(dirname "$0")/tphira-mp"
    elif [ -d "/data/data/com.termux/files/home/tphira-mp" ]; then
        PROJECT_DIR="/data/data/com.termux/files/home/tphira-mp"
    else
        echo ""
        warn_msg "未自动找到 tphira-mp 目录"
        echo ""
        read -p "请输入 tphira-mp 目录的完整路径: " custom_path
        if [ -d "$custom_path" ]; then
            PROJECT_DIR="$custom_path"
        else
            error_msg "路径不存在！"
            exit 1
        fi
    fi
}

# 打印横幅
print_banner() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║   ██████╗ ██╗  ██╗██╗██████╗  █████╗     ███╗   ███╗██████╗  ║"
    echo "║   ██╔══██╗██║  ██║██║██╔══██╗██╔══██╗    ████╗ ████║██╔══██╗ ║"
    echo "║   ██████╔╝███████║██║██████╔╝███████║    ██╔████╔██║██████╔╝ ║"
    echo "║   ██╔═══╝ ██╔══██║██║██╔══██╗██╔══██║    ██║╚██╔╝██║██╔═══╝  ║"
    echo "║   ██║     ██║  ██║██║██║  ██║██║  ██║    ██║ ╚═╝ ██║██║      ║"
    echo "║   ╚═╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝╚═╝      ║"
    echo "║                                                              ║"
    echo "║                Phira MP 服务器管理面板                        ║"
    echo "║                    Termux 专用版 v1.3.1                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 打印菜单标题
print_menu_title() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${WHITE}$1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

success_msg() { echo -e "${GREEN}✓ $1${NC}"; }
error_msg() { echo -e "${RED}✗ $1${NC}"; }
info_msg() { echo -e "${BLUE}ℹ $1${NC}"; }
warn_msg() { echo -e "${YELLOW}⚠ $1${NC}"; }

# 读取配置值
read_config() {
    local key="$1"
    grep "^${key}:" "$PROJECT_DIR/$CONFIG_FILE" 2>/dev/null | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//'
}

# 读取保存的用户名（从ADMIN_TOKEN注释中）
read_saved_username() {
    grep "# ADMIN_USERNAME:" "$PROJECT_DIR/$CONFIG_FILE" 2>/dev/null | sed 's/.*ADMIN_USERNAME:[[:space:]]*//'
}

# 更新配置值
update_config() {
    local key="$1"
    local value="$2"
    local need_quotes="$3"
    
    cd "$PROJECT_DIR" || exit 1
    
    if [ "$need_quotes" = "true" ]; then
        value="\"$value\""
    fi
    
    if grep -q "^${key}:" "$CONFIG_FILE" 2>/dev/null; then
        sed -i "s/^${key}:.*/${key}: ${value}/" "$CONFIG_FILE"
    elif grep -q "^# *${key}:" "$CONFIG_FILE" 2>/dev/null; then
        sed -i "s/^# *${key}:.*/${key}: ${value}/" "$CONFIG_FILE"
    else
        echo "${key}: ${value}" >> "$CONFIG_FILE"
    fi
}

uncomment_config() {
    local key="$1"
    cd "$PROJECT_DIR" || exit 1
    sed -i "s/^# *${key}:/${key}:/" "$CONFIG_FILE"
}

comment_config() {
    local key="$1"
    cd "$PROJECT_DIR" || exit 1
    sed -i "s/^${key}:/# ${key}:/" "$CONFIG_FILE"
}

# 生成 MD5 Token（确定性：相同用户名始终生成相同 Token）
generate_token() {
    local username="$1"
    local salt="PhiraMP2024SecureSalt"
    local token=$(echo -n "${username}${salt}" | md5sum | cut -d' ' -f1)
    # 保存用户名到配置文件注释
    cd "$PROJECT_DIR" || exit 1
    sed -i '/# ADMIN_USERNAME:/d' "$CONFIG_FILE"
    echo "# ADMIN_USERNAME: ${username}" >> "$CONFIG_FILE"
    echo "$token"
}

# 查看密钥（修复版 - 严格用户名验证）
view_token() {
    print_banner
    print_menu_title "查看管理密钥"
    cd "$PROJECT_DIR" || exit 1
    admin_token=$(read_config "ADMIN_TOKEN")
    saved_username=$(read_saved_username)
    if [ -z "$admin_token" ]; then
        error_msg "API 服务未启用，没有配置管理密钥"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    # 检查是否保存了用户名
    if [ -z "$saved_username" ]; then
        error_msg "无法验证：未找到创建密钥时保存的用户名记录"
        echo ""
        warn_msg "可能原因："
        warn_msg "  1. 密钥是在旧版本脚本中生成的"
        warn_msg "  2. 配置文件被手动修改过"
        warn_msg "  3. 配置文件损坏"
        echo ""
        info_msg "建议：重新生成管理密钥"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    echo ""
    read -p "请输入创建密钥时的用户名进行验证: " input_username
    if [ -z "$input_username" ]; then
        error_msg "验证失败：用户名不能为空"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    # 严格验证用户名是否匹配
    if [ "$input_username" != "$saved_username" ]; then
        error_msg "验证失败：用户名不匹配"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    echo ""
    success_msg "验证通过！"
    echo ""
    echo -e "${YELLOW}═════════════════════════════════════════════════════════════${NC}"
    echo -e "  您的管理密钥:"
    echo -e "  ${GREEN}${admin_token}${NC}"
    echo -e "${YELLOW}═════════════════════════════════════════════════════════════${NC}"
    echo ""
    warn_msg "请妥善保存此密钥！"
    echo ""
    read -p "按回车键继续..."
}

# ==========================================
# 检测更新 v1.3.1 (GitHub Only)
# ==========================================

check_update() {
    print_banner
    print_menu_title "检测更新"
    
    echo ""
    info_msg "正在连接 GitHub 获取更新信息..."
    echo ""
    
    # 获取远程 MD5
    remote_md5=$(curl -s -L --connect-timeout 15 "$MD5_URL" 2>/dev/null | head -1 | awk '{print $1}')
    
    if [ -z "$remote_md5" ] || [ ${#remote_md5} -ne 32 ]; then
        error_msg "获取更新信息失败，请检查网络连接"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    
    # 计算本地文件 MD5
    local_md5=$(md5sum "$SCRIPT_PATH" 2>/dev/null | awk '{print $1}')
    
    echo -e "  本地版本 MD5:  ${CYAN}${local_md5:0:16}...${NC}"
    echo -e "  最新版本 MD5:  ${CYAN}${remote_md5:0:16}...${NC}"
    echo ""
    
    # 对比 MD5
    if [ "$local_md5" = "$remote_md5" ]; then
        success_msg "当前已是最新版本！"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    
    # 有新版本
    warn_msg "发现新版本！"
    echo ""
    echo -e "${YELLOW}═════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}新版本可用，是否立即更新？${NC}"
    echo -e "${YELLOW}═════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}[1]${NC} 立即更新"
    echo -e "  ${WHITE}[0]${NC} 稍后更新"
    echo ""
    
    read -p "请选择 [1/0]: " do_update
    
    if [ "$do_update" != "1" ]; then
        info_msg "已取消更新"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    
    # 执行更新
    echo ""
    info_msg "正在从 GitHub 下载最新版本..."
    
    # 下载到临时文件
    temp_file="/tmp/main.sh.update"
    curl -s -L --connect-timeout 15 --max-time 30 -o "$temp_file" "$UPDATE_URL" 2>/dev/null
    
    if [ ! -s "$temp_file" ]; then
        error_msg "下载失败，请检查网络连接"
        rm -f "$temp_file"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    
    # 校验下载文件完整性
    download_md5=$(md5sum "$temp_file" 2>/dev/null | awk '{print $1}')
    
    if [ "$download_md5" != "$remote_md5" ]; then
        error_msg "文件校验失败，MD5 不匹配"
        rm -f "$temp_file"
        echo ""
        read -p "按回车键继续..."
        return
    fi
    
    success_msg "下载完成，校验通过！"
    echo ""
    info_msg "正在安装更新..."
    
    # 备份旧版本
    cp "$SCRIPT_PATH" "${SCRIPT_PATH}.bak" 2>/dev/null
    
    # 替换文件
    mv "$temp_file" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    echo ""
    success_msg "更新完成！"
    echo ""
    info_msg "脚本将自动重启以应用更新..."
    echo ""
    sleep 2
    
    # 重启脚本
    exec "$SCRIPT_PATH"
    exit 0
}

# 启动 PhiraMP
start_phiramp() {
    print_banner
    print_menu_title "启动 PhiraMP 服务器"
    
    cd "$PROJECT_DIR" || exit 1
    
    info_msg "项目目录: $PROJECT_DIR"
    info_msg "正在启动 PhiraMP 服务器..."
    echo ""
    echo -e "${GRAY}─────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    pnpm start
    
    echo ""
    echo -e "${GRAY}─────────────────────────────────────────────────────────────${NC}"
    echo ""
    read -p "按回车键返回主菜单..."
}

# 基础配置菜单
basic_config_menu() {
    while true; do
        print_banner
        print_menu_title "基础配置"
        
        http_service=$(read_config "HTTP_SERVICE")
        room_max_users=$(read_config "ROOM_MAX_USERS")
        server_name=$(read_config "SERVER_NAME")
        room_list_tip=$(read_config "ROOM_LIST_TIP")
        
        echo -e "  ${WHITE}[1]${NC} API 服务设置            状态: $( [ "$http_service" = "true" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已禁用${NC}" )"
        echo -e "  ${WHITE}[2]${NC} 房间最大人数            值: ${CYAN}${room_max_users:-12}人${NC}"
        echo -e "  ${WHITE}[3]${NC} 服务器名称              值: ${CYAN}\"${server_name:-Phira MP}\"${NC}"
        echo -e "  ${WHITE}[4]${NC} 房间列表提示文案        值: ${CYAN}\"${room_list_tip:-未设置}\"${NC}"
        echo -e "  ${WHITE}[5]${NC} 查看管理密钥"
        echo ""
        echo -e "  ${WHITE}[0]${NC} 返回上级菜单"
        echo ""
        echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
        echo ""
        
        read -p "请选择操作 [0-5]: " choice
        case $choice in
            1) config_api_service ;;
            2) config_room_max_users ;;
            3) config_server_name ;;
            4) config_room_list_tip ;;
            5) view_token ;;
            0) break ;;
            *) sleep 0.5 ;;
        esac
    done
}

# 配置 API 服务
config_api_service() {
    print_banner
    print_menu_title "API 服务配置"
    
    cd "$PROJECT_DIR" || exit 1
    
    current_status=$(read_config "HTTP_SERVICE")
    
    echo -e "  当前状态: $( [ "$current_status" = "true" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已禁用${NC}" )"
    echo ""
    echo -e "  ${WHITE}[1]${NC} 启用 API 服务"
    echo -e "  ${WHITE}[0]${NC} 禁用 API 服务"
    echo ""
    
    read -p "请选择 [1/0]: " enable_api
    
    if [ "$enable_api" = "1" ]; then
        update_config "HTTP_SERVICE" "true" "false"
        success_msg "API 服务已启用"
        echo ""
        
        # 强制输入用户名
        while true; do
            read -p "请输入您的用户名（用于生成密钥）: " username
            if [ -n "$username" ]; then
                break
            fi
            error_msg "用户名不能为空，请重新输入！"
        done
        
        token=$(generate_token "$username")
        uncomment_config "ADMIN_TOKEN"
        update_config "ADMIN_TOKEN" "$token" "true"
        echo ""
        success_msg "密钥已生成（MD5加密）！"
        echo ""
        echo -e "${YELLOW}═════════════════════════════════════════════════════════════${NC}"
        echo -e "  您的管理密钥:"
        echo -e "  ${GREEN}${token}${NC}"
        echo -e "${YELLOW}═════════════════════════════════════════════════════════════${NC}"
        echo ""
        warn_msg "请妥善保存此密钥，用于管理接口鉴权！"
        warn_msg "提示：查看密钥时需要输入此用户名进行验证"
        echo ""
        
        # 配置 CORS_ORIGINS
        sed -i '/^# *CORS_ORIGINS:/d' "$CONFIG_FILE"
        sed -i '/^CORS_ORIGINS:/d' "$CONFIG_FILE"
        sed -i '/^  - "https:\/\/.*"/d' "$CONFIG_FILE"
        sed -i '/^  - "http:\/\/.*"/d' "$CONFIG_FILE"
        
        read -p "请输入 CORS 允许的域名（回车默认 https://t.phira.link）: " cors_origin
        cors_origin=${cors_origin:-"https://t.phira.link"}
        
        echo "CORS_ORIGINS:" >> "$CONFIG_FILE"
        echo "  - \"$cors_origin\"" >> "$CONFIG_FILE"
        success_msg "CORS 源已设置为: $cors_origin"
        
    elif [ "$enable_api" = "0" ]; then
        update_config "HTTP_SERVICE" "false" "false"
        comment_config "ADMIN_TOKEN"
        comment_config "CORS_ORIGINS"
        sed -i '/# ADMIN_USERNAME:/d' "$CONFIG_FILE"
        success_msg "API 服务已禁用"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

config_room_max_users() {
    print_banner
    print_menu_title "房间最大人数配置"
    
    cd "$PROJECT_DIR" || exit 1
    current=$(read_config "ROOM_MAX_USERS")
    
    echo -e "  当前值: ${CYAN}${current:-12}人${NC}"
    echo ""
    read -p "请输入房间最大人数 (回车保持默认): " max_users
    
    if [ -n "$max_users" ] && [ "$max_users" -eq "$max_users" ] 2>/dev/null; then
        update_config "ROOM_MAX_USERS" "$max_users" "false"
        success_msg "房间最大人数已设置为: $max_users 人"
    else
        info_msg "保持默认值不变"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

config_server_name() {
    print_banner
    print_menu_title "服务器名称配置"
    
    cd "$PROJECT_DIR" || exit 1
    current=$(read_config "SERVER_NAME")
    
    echo -e "  当前值: ${CYAN}\"${current:-Phira MP}\"${NC}"
    echo ""
    read -p "请输入服务器名称（回车保持默认）: " server_name
    
    if [ -n "$server_name" ]; then
        update_config "SERVER_NAME" "$server_name" "true"
        success_msg "服务器名称已设置为: \"$server_name\""
    else
        info_msg "保持默认值不变"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

config_room_list_tip() {
    print_banner
    print_menu_title "房间列表提示文案"
    
    cd "$PROJECT_DIR" || exit 1
    current=$(read_config "ROOM_LIST_TIP")
    
    echo -e "  当前值: ${CYAN}\"${current:-未设置}\"${NC}"
    echo ""
    read -p "请输入提示文案（留空回车则禁用）: " tip_text
    
    if [ -n "$tip_text" ]; then
        uncomment_config "ROOM_LIST_TIP"
        update_config "ROOM_LIST_TIP" "$tip_text" "true"
        success_msg "提示文案已设置为: \"$tip_text\""
    else
        comment_config "ROOM_LIST_TIP"
        info_msg "提示文案已禁用"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

# 进阶配置菜单
advanced_config_menu() {
    while true; do
        print_banner
        print_menu_title "进阶配置"
        
        echo -e "  ${WHITE}[1]${NC} 网络配置"
        echo -e "  ${WHITE}[2]${NC} 日志等级配置"
        echo -e "  ${WHITE}[3]${NC} 功能开关"
        echo -e "  ${WHITE}[4]${NC} 回放录制配置"
        echo -e "  ${WHITE}[5]${NC} API 端点与代理"
        echo -e "  ${WHITE}[6]${NC} Redis 缓存配置"
        echo -e "  ${WHITE}[7]${NC} 分享站配置"
        echo -e "  ${WHITE}[8]${NC} 连接数与房间数限制"
        echo -e "  ${WHITE}[9]${NC} 安全配置"
        echo -e "  ${WHITE}[10]${NC} 账号配置（观战/测试账号）"
        echo ""
        echo -e "  ${WHITE}[0]${NC} 返回上级菜单"
        echo ""
        echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
        echo ""
        
        read -p "请选择操作 [0-10]: " choice
        case $choice in
            1) config_network ;;
            2) config_log_level ;;
            3) config_features ;;
            4) config_replay ;;
            5) config_api_endpoints ;;
            6) config_redis ;;
            7) config_share_station ;;
            8) config_limits ;;
            9) config_security ;;
            10) config_accounts ;;
            0) break ;;
            *) sleep 0.5 ;;
        esac
    done
}

config_network() {
    print_banner
    print_menu_title "网络配置"
    
    cd "$PROJECT_DIR" || exit 1
    
    host=$(read_config "HOST")
    port=$(read_config "PORT")
    http_port=$(read_config "HTTP_PORT")
    real_ip_header=$(read_config "REAL_IP_HEADER")
    
    echo -e "  当前配置:"
    echo -e "    监听地址: ${CYAN}${host:-::}${NC}"
    echo -e "    TCP 端口: ${CYAN}${port:-12346}${NC}"
    echo -e "    HTTP 端口: ${CYAN}${http_port:-12347}${NC}"
    echo -e "    真实IP头: ${CYAN}${real_ip_header:-X-Forwarded-For}${NC}"
    echo ""
    
    read -p "监听地址（回车保持默认）: " new_host
    read -p "TCP 端口（回车保持默认）: " new_port
    read -p "HTTP 端口（回车保持默认）: " new_http_port
    read -p "真实IP头（回车保持默认）: " new_real_ip
    
    [ -n "$new_host" ] && update_config "HOST" "$new_host" "true"
    [ -n "$new_port" ] && update_config "PORT" "$new_port" "false"
    [ -n "$new_http_port" ] && update_config "HTTP_PORT" "$new_http_port" "false"
    [ -n "$new_real_ip" ] && update_config "REAL_IP_HEADER" "$new_real_ip" "false"
    
    success_msg "网络配置已更新"
    echo ""
    read -p "按回车键继续..."
}

config_log_level() {
    print_banner
    print_menu_title "日志等级配置"
    
    cd "$PROJECT_DIR" || exit 1
    log_level=$(read_config "LOG_LEVEL")
    
    echo -e "  当前日志等级: ${CYAN}${log_level:-INFO}${NC}"
    echo ""
    echo -e "  可选: DEBUG, INFO, MARK, WARN, ERROR"
    echo ""
    
    read -p "日志等级（回车保持默认）: " new_log
    [ -n "$new_log" ] && update_config "LOG_LEVEL" "$new_log" "false"
    
    success_msg "日志配置已更新"
    echo ""
    read -p "按回车键继续..."
}

config_features() {
    print_banner
    print_menu_title "功能开关"
    
    cd "$PROJECT_DIR" || exit 1
    
    chat_enabled=$(read_config "CHAT_ENABLED")
    haproxy=$(read_config "HAPROXY_PROTOCOL")
    
    echo -e "  当前配置:"
    echo -e "    聊天功能: $( [ "$chat_enabled" = "true" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已禁用${NC}" )"
    echo -e "    HAProxy 协议: $( [ "$haproxy" = "true" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已禁用${NC}" )"
    echo ""
    echo -e "  ${WHITE}[1]${NC} 启用 / ${WHITE}[0]${NC} 禁用"
    echo ""
    
    read -p "聊天功能 [1/0，回车保持默认]: " chat_choice
    read -p "HAProxy PROXY 协议 [1/0，回车保持默认]: " haproxy_choice
    
    if [ -n "$chat_choice" ]; then
        [ "$chat_choice" = "1" ] && update_config "CHAT_ENABLED" "true" "false" || update_config "CHAT_ENABLED" "false" "false"
    fi
    
    if [ -n "$haproxy_choice" ]; then
        [ "$haproxy_choice" = "1" ] && update_config "HAPROXY_PROTOCOL" "true" "false" || update_config "HAPROXY_PROTOCOL" "false" "false"
    fi
    
    success_msg "功能配置已更新"
    echo ""
    read -p "按回车键继续..."
}

config_replay() {
    print_banner
    print_menu_title "回放录制配置"
    
    cd "$PROJECT_DIR" || exit 1
    
    replay_enabled=$(read_config "REPLAY_ENABLED")
    replay_auto_upload=$(read_config "REPLAY_AUTO_UPLOAD")
    replay_ttl=$(read_config "REPLAY_TTL_DAYS")
    replay_dir=$(read_config "REPLAY_BASE_DIR")
    
    echo -e "  当前配置:"
    echo -e "    回放录制: $( [ "$replay_enabled" = "true" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已禁用${NC}" )"
    echo -e "    自动上传: $( [ "$replay_auto_upload" = "true" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已禁用${NC}" )"
    echo -e "    保留天数: ${CYAN}${replay_ttl:-4}天${NC}"
    echo -e "    录制目录: ${CYAN}${replay_dir:-./record}${NC}"
    echo ""
    echo -e "  ${WHITE}[1]${NC} 启用 / ${WHITE}[0]${NC} 禁用"
    echo ""
    
    read -p "回放录制 [1/0，回车保持默认]: " replay_choice
    read -p "自动上传到分享站 [1/0，回车保持默认]: " upload_choice
    read -p "回放保留天数（回车保持默认）: " ttl_days
    read -p "回放录制目录（回车保持默认）: " replay_dir_input
    
    if [ -n "$replay_choice" ]; then
        [ "$replay_choice" = "1" ] && uncomment_config "REPLAY_ENABLED" && update_config "REPLAY_ENABLED" "true" "false" || comment_config "REPLAY_ENABLED"
    fi
    
    if [ -n "$upload_choice" ]; then
        [ "$upload_choice" = "1" ] && uncomment_config "REPLAY_AUTO_UPLOAD" && update_config "REPLAY_AUTO_UPLOAD" "true" "false" || comment_config "REPLAY_AUTO_UPLOAD"
    fi
    
    [ -n "$ttl_days" ] && uncomment_config "REPLAY_TTL_DAYS" && update_config "REPLAY_TTL_DAYS" "$ttl_days" "false"
    [ -n "$replay_dir_input" ] && uncomment_config "REPLAY_BASE_DIR" && update_config "REPLAY_BASE_DIR" "$replay_dir_input" "true"
    
    success_msg "回放配置已更新"
    echo ""
    read -p "按回车键继续..."
}

config_api_endpoints() {
    print_banner
    print_menu_title "API 端点与代理"
    
    cd "$PROJECT_DIR" || exit 1
    
    phira_api=$(read_config "PHIRA_API_ENDPOINT")
    hitokoto_api=$(read_config "HITOKOTO_API_URL")
    outbound_proxy=$(read_config "OUTBOUND_PROXY")
    
    echo -e "  当前配置:"
    echo -e "    Phira API: ${CYAN}${phira_api}${NC}"
    echo -e "    一言 API: ${CYAN}${hitokoto_api}${NC}"
    echo -e "    出站代理: ${CYAN}${outbound_proxy:-未设置}${NC}"
    echo ""
    
    read -p "Phira API 端点（回车保持默认）: " new_phira
    read -p "一言 API 地址（回车保持默认）: " new_hitokoto
    read -p "出站代理（false=直连，回车保持默认）: " new_proxy
    
    [ -n "$new_phira" ] && update_config "PHIRA_API_ENDPOINT" "$new_phira" "true"
    [ -n "$new_hitokoto" ] && update_config "HITOKOTO_API_URL" "$new_hitokoto" "true"
    
    if [ -n "$new_proxy" ]; then
        uncomment_config "OUTBOUND_PROXY"
        [ "$new_proxy" = "false" ] && update_config "OUTBOUND_PROXY" "false" "false" || update_config "OUTBOUND_PROXY" "$new_proxy" "true"
    fi
    
    success_msg "API 端点与代理配置已更新"
    echo ""
    read -p "按回车键继续..."
}

config_redis() {
    print_banner
    print_menu_title "Redis 缓存配置"
    
    cd "$PROJECT_DIR" || exit 1
    
    echo ""
    warn_msg "此功能需要安装 Redis 服务"
    echo ""
    echo -e "  ${WHITE}[1]${NC} 启用 / ${WHITE}[0]${NC} 禁用"
    echo ""
    
    read -p "启用 Redis 缓存？[1/0，回车保持默认]: " enable_redis
    
    if [ "$enable_redis" = "1" ]; then
        read -p "Redis 地址（默认 127.0.0.1）: " redis_host
        read -p "Redis 端口（默认 6379）: " redis_port
        read -p "Redis 密码（无则留空）: " redis_pass
        read -p "Redis 数据库号（默认 0）: " redis_db
        
        sed -i '/^REDIS:/,/^  DB:/d' "$CONFIG_FILE"
        
        echo "REDIS:" >> "$CONFIG_FILE"
        echo "  ENABLED: true" >> "$CONFIG_FILE"
        echo "  HOST: \"${redis_host:-127.0.0.1}\"" >> "$CONFIG_FILE"
        echo "  PORT: ${redis_port:-6379}" >> "$CONFIG_FILE"
        [ -n "$redis_pass" ] && echo "  PASSWORD: \"$redis_pass\"" >> "$CONFIG_FILE"
        echo "  DB: ${redis_db:-0}" >> "$CONFIG_FILE"
        
        success_msg "Redis 配置已启用"
    elif [ "$enable_redis" = "0" ]; then
        sed -i 's/  ENABLED: true/  ENABLED: false/' "$CONFIG_FILE"
        info_msg "Redis 缓存已禁用"
    else
        info_msg "保持默认值不变"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

config_share_station() {
    print_banner
    print_menu_title "分享站配置"
    
    cd "$PROJECT_DIR" || exit 1
    
    echo ""
    info_msg "用于上传回放到 Phira 分享站"
    echo ""
    
    read -p "分享站地址（回车保持默认）: " ss_url
    read -p "分享站 Token（回车保持默认）: " ss_token
    
    if [ -n "$ss_url" ]; then
        sed -i "s|  URL: \".*\"|  URL: \"$ss_url\"|" "$CONFIG_FILE"
    fi
    
    if [ -n "$ss_token" ]; then
        sed -i "s|  TOKEN: \".*\"|  TOKEN: \"$ss_token\"|" "$CONFIG_FILE"
        success_msg "分享站 Token 已更新"
    fi
    
    echo ""
    read -p "按回车键继续..."
}

config_limits() {
    print_banner
    print_menu_title "连接数与房间数限制"
    
    cd "$PROJECT_DIR" || exit 1
    
    max_rooms=$(read_config "MAX_ROOMS")
    max_connections=$(read_config "MAX_CONNECTIONS")
    
    echo -e "  当前配置:"
    echo -e "    最大房间数: ${CYAN}${max_rooms:-不限制}${NC}"
    echo -e "    最大连接数: ${CYAN}${max_connections:-不限制}${NC}"
    echo ""
    echo -e "  输入 0 表示不限制"
    echo ""
    
    read -p "最大房间数（回车保持默认）: " max_rooms_input
    read -p "最大连接数（回车保持默认）: " max_connections_input
    
    if [ -n "$max_rooms_input" ]; then
        [ "$max_rooms_input" = "0" ] && comment_config "MAX_ROOMS" || uncomment_config "MAX_ROOMS" && update_config "MAX_ROOMS" "$max_rooms_input" "false"
    fi
    
    if [ -n "$max_connections_input" ]; then
        [ "$max_connections_input" = "0" ] && comment_config "MAX_CONNECTIONS" || uncomment_config "MAX_CONNECTIONS" && update_config "MAX_CONNECTIONS" "$max_connections_input" "false"
    fi
    
    success_msg "限制配置已更新"
    echo ""
    read -p "按回车键继续..."
}

config_security() {
    print_banner
    print_menu_title "安全配置"
    
    cd "$PROJECT_DIR" || exit 1
    
    allow_token_query=$(read_config "ALLOW_TOKEN_IN_QUERY")
    admin_data_path=$(read_config "ADMIN_DATA_PATH")
    
    echo -e "  当前配置:"
    echo -e "    URL参数传Token: $( [ "$allow_token_query" = "true" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}已禁用${NC}" )"
    echo -e "    管理数据路径: ${CYAN}${admin_data_path:-./admin_data.json}${NC}"
    echo ""
    warn_msg "启用URL参数传Token会降低安全性，仅在必要时开启"
    echo ""
    echo -e "  ${WHITE}[1]${NC} 启用 / ${WHITE}[0]${NC} 禁用"
    echo ""
    
    read -p "允许URL参数传Token [1/0，回车保持默认]: " token_query_choice
    read -p "管理数据路径（回车保持默认）: " admin_path_input
    
    if [ -n "$token_query_choice" ]; then
        [ "$token_query_choice" = "1" ] && uncomment_config "ALLOW_TOKEN_IN_QUERY" && update_config "ALLOW_TOKEN_IN_QUERY" "true" "false" || comment_config "ALLOW_TOKEN_IN_QUERY"
    fi
    
    [ -n "$admin_path_input" ] && uncomment_config "ADMIN_DATA_PATH" && update_config "ADMIN_DATA_PATH" "$admin_path_input" "true"
    
    success_msg "安全配置已更新"
    echo ""
    read -p "按回车键继续..."
}

# 账号配置（观战/测试账号）- 可编辑版
config_accounts() {
    print_banner
    print_menu_title "账号配置（观战/测试账号）"
    
    cd "$PROJECT_DIR" || exit 1
    
    echo -e "  ${GRAY}当前配置:${NC}"
    echo ""
    
    # 读取并显示 MONITORS
    echo -e "  ${WHITE}观战用户 ID (MONITORS):${NC}"
    grep -A 10 "^MONITORS:" "$CONFIG_FILE" 2>/dev/null | grep "^\s*-" | head -5
    echo ""
    
    # 读取并显示 TEST_ACCOUNT_IDS
    echo -e "  ${WHITE}测试账号 ID (TEST_ACCOUNT_IDS):${NC}"
    grep -A 10 "^TEST_ACCOUNT_IDS:" "$CONFIG_FILE" 2>/dev/null | grep "^\s*-" | head -5
    echo ""
    
    echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${WHITE}[1]${NC} 添加观战用户 ID"
    echo -e "  ${WHITE}[2]${NC} 添加测试账号 ID"
    echo -e "  ${WHITE}[3]${NC} 重置为默认值"
    echo ""
    echo -e "  ${WHITE}[0]${NC} 返回上级菜单"
    echo ""
    
    read -p "请选择操作 [0-3]: " choice
    case $choice in
        1)
            read -p "请输入要添加的观战用户 ID（数字）: " monitor_id
            if [ -n "$monitor_id" ] && [ "$monitor_id" -eq "$monitor_id" ] 2>/dev/null; then
                if ! grep -q "^\s*- $monitor_id" "$CONFIG_FILE"; then
                    sed -i "/^MONITORS:/a\  - $monitor_id" "$CONFIG_FILE"
                    success_msg "已添加观战用户 ID: $monitor_id"
                else
                    info_msg "该 ID 已存在"
                fi
            else
                error_msg "请输入有效的数字 ID"
            fi
            ;;
        2)
            read -p "请输入要添加的测试账号 ID（数字）: " test_id
            if [ -n "$test_id" ] && [ "$test_id" -eq "$test_id" ] 2>/dev/null; then
                if ! grep -q "^\s*- $test_id" "$CONFIG_FILE"; then
                    sed -i "/^TEST_ACCOUNT_IDS:/a\  - $test_id" "$CONFIG_FILE"
                    success_msg "已添加测试账号 ID: $test_id"
                else
                    info_msg "该 ID 已存在"
                fi
            else
                error_msg "请输入有效的数字 ID"
            fi
            ;;
        3)
            sed -i '/^MONITORS:/,/^[^ ]/{/^MONITORS:/!d}' "$CONFIG_FILE"
            sed -i '/^TEST_ACCOUNT_IDS:/,/^[^ ]/{/^TEST_ACCOUNT_IDS:/!d}' "$CONFIG_FILE"
            sed -i "/^MONITORS:/a\  - 2" "$CONFIG_FILE"
            sed -i "/^TEST_ACCOUNT_IDS:/a\  - 1739989" "$CONFIG_FILE"
            success_msg "已重置为默认值"
            ;;
        0) return ;;
        *) info_msg "保持不变" ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
}

# 设置菜单
settings_menu() {
    while true; do
        print_banner
        print_menu_title "服务器设置"
        
        echo -e "  ${WHITE}[1]${NC} 基础配置"
        echo -e "  ${WHITE}[2]${NC} 进阶配置"
        echo ""
        echo -e "  ${WHITE}[0]${NC} 返回主菜单"
        echo ""
        echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
        echo ""
        
        read -p "请选择操作 [0-2]: " choice
        case $choice in
            1) basic_config_menu ;;
            2) advanced_config_menu ;;
            0) break ;;
            *) sleep 0.5 ;;
        esac
    done
}

# 主菜单
main_menu() {
    find_project_dir
    
    while true; do
        print_banner
        echo ""
        echo -e "  ${WHITE}[1]${NC} 启动 PhiraMP 服务器"
        echo -e "  ${WHITE}[2]${NC} 服务器设置"
        echo -e "  ${WHITE}[3]${NC} 检测更新"
        echo ""
        echo -e "  ${WHITE}[0]${NC} 退出脚本"
        echo ""
        echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
        echo ""
        info_msg "项目目录: $PROJECT_DIR"
        echo ""
        
        read -p "请选择操作 [0-3]: " choice
        case $choice in
            1) start_phiramp ;;
            2) settings_menu ;;
            3) check_update ;;
            0) 
                print_banner
                echo ""
                success_msg "感谢使用 Phira MP 服务器管理脚本！"
                echo ""
                exit 0
                ;;
            *) sleep 0.5 ;;
        esac
    done
}

main_menu
