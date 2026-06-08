#!/data/data/com.termux/files/usr/bin/bash
dpkg --configure -a 2>/dev/null || true

# 版本号
VERSION="2.1.1"

# 颜色
R="\033[0m"; B="\033[1m"; D="\033[2m"
red="\033[31m"; grn="\033[32m"; yel="\033[33m"
blu="\033[34m"; mag="\033[35m"; cyn="\033[36m"; wht="\033[37m"

# 简写
ok() { echo -e " ${grn}✓${R} $1"; }
er() { echo -e " ${red}✗${R} $1" >&2; exit 1; }
wa() { echo -e " ${yel}!${R} $1"; }
info() { echo -e " ${cyn}→${R} $1"; }

# 配置区
START_SCRIPT_URL="https://riluo-ya.github.io/blog/sh/Phira-mp/start.sh"
START_SCRIPT_HASH_URL="https://riluo-ya.github.io/blog/sh/Phira-mp/update/md5.txt"
START_SCRIPT_PATH="$HOME/start.sh"
MAX_RETRY=3

# 获取脚本真实路径（修复：使用更可靠的方式）
get_script_path() {
    if [ -n "$BASH_SOURCE" ]; then
        echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    else
        echo "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    fi
}

SCRIPT_PATH=$(get_script_path)

# 网络检查
check_network() {
    ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1 || \
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1
}

# 下载函数（带重试）
download_file() {
    local url="$1"
    local output="$2"
    local retries=${3:-$MAX_RETRY}
    local count=0
    
    while [ $count -lt $retries ]; do
        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$output" 2>/dev/null; then
                return 0
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q --timeout=10 -O "$output" "$url" 2>/dev/null; then
                return 0
            fi
        fi
        
        count=$((count + 1))
        [ $count -lt $retries ] && sleep 2
    done
    
    return 1
}

# 下载文本
download_text() {
    local url="$1"
    local retries=${2:-$MAX_RETRY}
    local count=0
    
    while [ $count -lt $retries ]; do
        if curl -fsSL --connect-timeout 10 --max-time 15 "$url" 2>/dev/null; then
            return 0
        fi
        
        if wget -q --timeout=10 -O - "$url" 2>/dev/null; then
            return 0
        fi
        
        count=$((count + 1))
        [ $count -lt $retries ] && sleep 1
    done
    
    return 1
}

# 获取远程哈希
get_remote_hash() {
    download_text "$START_SCRIPT_HASH_URL" 2 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
}

# 获取本地哈希
get_local_hash() {
    if [ -f "$START_SCRIPT_PATH" ]; then
        md5sum "$START_SCRIPT_PATH" 2>/dev/null | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]'
    else
        echo ""
    fi
}

# 下载并安装 start.sh
install_start_script() {
    info "检查网络连接..."
    if ! check_network; then
        wa "网络不可用"
        if [ -f "$START_SCRIPT_PATH" ]; then
            wa "将使用本地已有的 start.sh"
            return 0
        else
            er "本地也没有 start.sh，请检查网络后重试"
        fi
    fi
    ok "网络连接正常"
    
    info "获取远程版本信息..."
    local remote_hash=$(get_remote_hash)
    if [ -z "$remote_hash" ] || [ ${#remote_hash} -ne 32 ]; then
        wa "无法获取远程版本信息"
        if [ -f "$START_SCRIPT_PATH" ]; then
            wa "将使用本地版本"
            return 0
        else
            er "无法下载且本地无版本，安装失败"
        fi
    fi
    ok "远程版本: ${remote_hash:0:8}..."
    
    local local_hash=$(get_local_hash)
    if [ -n "$local_hash" ]; then
        ok "本地版本: ${local_hash:0:8}..."
        if [ "$local_hash" = "$remote_hash" ]; then
            ok "start.sh 已是最新版本"
            return 0
        fi
        info "发现新版本，开始更新..."
    else
        info "本地未找到 start.sh，开始下载..."
    fi
    
    # 下载新脚本
    local tmp_file=$(mktemp)
    info "下载 start.sh..."
    
    if ! download_file "$START_SCRIPT_URL" "$tmp_file"; then
        rm -f "$tmp_file"
        if [ -f "$START_SCRIPT_PATH" ]; then
            wa "下载失败，保留现有版本"
            return 0
        else
            er "下载失败，请检查链接: $START_SCRIPT_URL"
        fi
    fi
    
    # 验证下载的哈希
    local download_hash=$(md5sum "$tmp_file" 2>/dev/null | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
    if [ "$download_hash" != "$remote_hash" ]; then
        wa "哈希校验失败，文件可能损坏"
        rm -f "$tmp_file"
        if [ -f "$START_SCRIPT_PATH" ]; then
            wa "保留现有版本"
            return 0
        else
            er "下载文件校验失败且无本地版本"
        fi
    fi
    ok "哈希校验通过"
    
    # 备份旧版本
    if [ -f "$START_SCRIPT_PATH" ]; then
        local backup_name="$HOME/start.sh.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$START_SCRIPT_PATH" "$backup_name" 2>/dev/null && ok "已备份旧版本: $backup_name"
    fi
    
    # 安装新版本
    mv "$tmp_file" "$START_SCRIPT_PATH"
    chmod +x "$START_SCRIPT_PATH"
    ok "start.sh 安装/更新完成"
    
    return 0
}

# 配置 .bashrc
config_bashrc() {
    # 清理旧配置
    if grep -q "Phira启动器" ~/.bashrc 2>/dev/null; then
        wa "检测到旧配置，正在清理..."
        sed -i '/# === Phira启动器/,/# === 结束 ===/d' ~/.bashrc
        sed -i '/^$/N;/^\n$/D' ~/.bashrc
        ok "旧配置已清理"
    fi
    
    cat >> ~/.bashrc << EOF

# === Phira启动器 v${VERSION} ===
# 自动检测并启动 start.sh
START_SCRIPT="\$HOME/start.sh"
START_URL="$START_SCRIPT_URL"

# 检查 start.sh 是否存在，不存在则下载
if [ ! -f "\$START_SCRIPT" ]; then
    echo -e "\033[33m[首次启动] 未检测到启动脚本，正在下载...\033[0m"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "\$START_URL" -o "\$START_SCRIPT" 2>/dev/null && chmod +x "\$START_SCRIPT"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "\$START_SCRIPT" "\$START_URL" 2>/dev/null && chmod +x "\$START_SCRIPT"
    fi
    
    if [ ! -f "\$START_SCRIPT" ]; then
        echo -e "\033[31m[错误] 下载失败，请手动运行 install.sh\033[0m"
    else
        echo -e "\033[32m[成功] 启动脚本已就绪\033[0m"
    fi
    echo ""
fi

# 如果存在则执行
if [ -f "\$START_SCRIPT" ]; then
    bash "\$START_SCRIPT"
fi
# === 结束 ===
EOF
    ok "启动配置已写入 .bashrc"
    info "下次打开 Termux 将自动运行 start.sh"
}

# 简单配置方式：直接粘贴配置文件
configure_frp_simple() {
    local frp_dir="$1"
    local config_file="$frp_dir/frpc.ini"
    
    echo ""
    info "内网穿透配置"
    echo -e " ${D}────────────────────────────────${R}"
    echo -e "  请从 ChmlFrp 面板复制配置，然后粘贴到这里"
    echo -e "  ${D}（长按粘贴，输入完成后输入数字 0 结束）${R}"
    echo -e " ${D}────────────────────────────────${R}"
    echo ""
    
    echo -e "  ${yel}请粘贴配置内容（输入 0 结束）:${R}"
    echo ""
    
    local tmp_file=$(mktemp)
    
    # 关键修复：从 /dev/tty 读取，确保即使脚本被管道执行也能正常交互
    while IFS= read -r line < /dev/tty; do
        if [ "$line" = "0" ]; then
            break
        fi
        echo "$line" >> "$tmp_file"
    done
    
    if [ ! -s "$tmp_file" ]; then
        wa "未检测到输入，使用默认配置"
        cat > "$config_file" << 'EOF'
[common]
server_addr = frp.chmlfrp.cn
server_port = 7000
token = 你的Token
[phira]
type = tcp
local_ip = 127.0.0.1
local_port = 12345
remote_port = 你的远程端口
EOF
    else
        cp "$tmp_file" "$config_file"
    fi
    
    rm -f "$tmp_file"
    
    if [ -f "$config_file" ] && grep -q "\[common\]" "$config_file"; then
        echo ""
        ok "配置已保存"
        echo ""
        echo -e "  ${D}配置预览:${R}"
        echo -e "  ${D}─────────────────────────────${R}"
        cat "$config_file" | sed 's/^/  /'
        echo -e "  ${D}─────────────────────────────${R}"
        echo ""
        
        echo -e "  ${B}${grn}[1]${R} 配置正确，继续"
        echo -e "  ${B}${red}[2]${R} 重新配置"
        echo ""
        # 同样从 /dev/tty 读取确认
        read -p " 选择[1-2]: " confirm < /dev/tty
        case $confirm in
            2) configure_frp_simple "$frp_dir" ;;
            *) ok "配置完成" ;;
        esac
    else
        wa "配置可能不完整，请检查"
    fi
}

# 检测另一个软件是否安装（修复版）
check_and_install_other() {
    local current="$1"
    local missing=""
    local option=""
    
    if [ "$current" = "phira" ]; then
        if [ ! -d "ChmlFrp-0.51.2_251023_linux_arm64" ] && [ ! -d "../ChmlFrp-0.51.2_251023_linux_arm64" ] && [ ! -d "$HOME/ChmlFrp-0.51.2_251023_linux_arm64" ]; then
            missing="内网穿透 (ChmlFrp)"
            option="2"
        fi
    else
        if [ ! -d "phira-mp-0.1.0" ] && [ ! -d "../phira-mp-0.1.0" ] && [ ! -d "$HOME/phira-mp-0.1.0" ]; then
            missing="游戏服务器 (Phira-mp)"
            option="1"
        fi
    fi
    
    if [ -n "$missing" ]; then
        echo ""
        wa "检测到 $missing 尚未安装"
        echo ""
        echo -e "  ${B}${grn}[1]${R} 立即安装 $missing"
        echo -e "  ${B}${red}[0]${R} 跳过，稍后手动安装"
        echo ""
        read -p " 选择[0-1]: " confirm < /dev/tty
        case $confirm in
            1)
                echo -e "\n ${cyn}→ 开始安装 $missing...${R}\n"
                # 修复：直接调用函数而不是递归执行脚本，避免 exit 问题
                if [ "$option" = "1" ]; then
                    install_phira
                else
                    install_frp
                fi
                ;;
            0) info "已跳过，稍后可通过脚本单独安装" ;;
            *) wa "无效选项，默认跳过" ;;
        esac
    fi
}

# 清理残留文件
clean_residual() {
    local files="$1"
    rm -f $files 2>/dev/null && ok "已清理残留文件" || info "无残留文件需要清理"
}

# 安装Phira-mp
install_phira() {
    clear
    echo -e "\n ${B}${mag}◆ Phira-mp 安装${R} ${D}[${VERSION}]${R}\n"
    [ -d "phira-mp-0.1.0" ] && { rm -rf phira-mp-0.1.0; ok "清理旧版本"; }
    
    info "更新软件包..."
    yes | pkg update -y 2>/dev/null || pkg update -y </dev/null 2>/dev/null || er "更新失败"
    ok "更新完成"
    
    info "安装Rust..."
    yes | pkg install -y rust 2>/dev/null || pkg install -y rust </dev/null 2>/dev/null || er "Rust安装失败"
    ok "Rust就绪"
    
    info "安装依赖..."
    yes | pkg install -y pkg-config wget unzip 2>/dev/null || pkg install -y pkg-config wget unzip </dev/null 2>/dev/null || er "依赖安装失败"
    ok "依赖就绪"
    
    info "下载源码..."
    wget -q https://codeload.github.com/TeamFlos/phira-mp/zip/refs/tags/v0.1.0 -O v0.1.0.zip || er "下载失败"
    ok "下载完成"
    
    info "解压..."
    unzip -q v0.1.0.zip || er "解压失败"
    ok "解压完成"
    
    chmod -R 755 phira-mp-0.1.0
    cd phira-mp-0.1.0 || er "进入目录失败"
    
    info "更新依赖..."
    cargo update || er "更新失败"
    ok "依赖更新"
    
    [ -f "phira-mp-server/src/session.rs" ] && {
        sed -i 's/if token.len() != 32 {/if token.len() > 32 {/' phira-mp-server/src/session.rs
        ok "应用安全补丁"
    }
    
    info "编译中(耗时较长)..."
    cargo build --release -p phira-mp-server || er "编译失败"
    ok "编译完成"
    
    cd ..
    
    # 下载/更新 start.sh 并配置 .bashrc
    install_start_script
    config_bashrc
    
    clean_residual "v0.1.0.zip"
    check_and_install_other "phira"
    
    echo -e "\n ${B}${grn}✓ 安装完成!${R}\n"
    echo -e "  下次启动 Termux 将自动运行 start.sh"
    echo -e "  手动运行: bash ~/start.sh\n"
}

# 安装FRP
install_frp() {
    clear
    echo -e "\n ${B}${blu}◆ 内网穿透安装${R} ${D}[${VERSION}]${R}\n"
    
    yes | pkg install -y wget tar 2>/dev/null || pkg install -y wget tar </dev/null 2>/dev/null || er "安装失败"
    
    info "下载ChmlFrp..."
    wget -q https://cf-v1.uapis.cn/download/ChmlFrp-0.51.2_251023_linux_arm64.tar.gz || er "下载失败"
    ok "下载完成"
    
    info "解压..."
    tar -zxf ChmlFrp-0.51.2_251023_linux_arm64.tar.gz || er "解压失败"
    ok "解压完成"
    
    cd ChmlFrp-0.51.2_251023_linux_arm64 || er "进入目录失败"
    chmod +x frpc
    
    configure_frp_simple "$(pwd)"
    
    cd ..
    
    # 下载/更新 start.sh 并配置 .bashrc
    install_start_script
    config_bashrc
    
    clean_residual "ChmlFrp-0.51.2_251023_linux_arm64.tar.gz"
    check_and_install_other "frp"
    
    echo -e "\n ${B}${grn}✓ 安装完成!${R}\n"
    echo -e "  下次启动 Termux 将自动运行 start.sh"
    echo -e "  手动运行: bash ~/start.sh\n"
}

# 主菜单
clear
echo -e "\n ${B}${cyn}╔════════════════════════════════╗${R}"
echo -e " ${B}${cyn}║${R}                                ${B}${cyn}║${R}"
echo -e " ${B}${cyn}║${R}   ${B}${wht}Phira 多人联机一键安装脚本${R}   ${B}${cyn}║${R}"
echo -e " ${B}${cyn}║${R}     ${D}版本 ${VERSION}  |  作者:日落-ya${R}    ${B}${cyn}║${R}"
echo -e " ${B}${cyn}║${R}                                ${B}${cyn}║${R}"
echo -e " ${B}${cyn}╚════════════════════════════════╝${R}\n"
echo -e " ${D}────────────────────────────────${R}"
echo -e "  ${B}${grn}[1]${R} 安装游戏服务器 ${D}(Phira-mp)${R}"
echo -e "  ${B}${blu}[2]${R} 安装内网穿透 ${D}(ChmlFrp)${R}"
echo -e "  ${B}${yel}[3]${R} 仅更新启动脚本 ${D}(start.sh)${R}"
echo -e "  ${B}${red}[0]${R} 退出脚本"
echo -e " ${D}────────────────────────────────${R}\n"
read -p " 选择[0-3]: " n < /dev/tty
case $n in
    1) install_phira ;;
    2) install_frp ;;
    3) 
        install_start_script
        config_bashrc
        echo -e "\n ${B}${grn}✓ 更新完成!${R}\n"
        ;;
    0) echo -e "\n ${D}已退出${R}\n"; exit 0 ;;
    *) er "无效选项" ;;
esac
