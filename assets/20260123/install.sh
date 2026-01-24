#!/data/data/com.termux/files/usr/bin/bash
# 修复 dpkg 中断状态
dpkg --configure -a

# 定义颜色与格式变量（确保Termux兼容）
RED="\033[1;31m"       # 鲜艳红色（加粗）
GREEN="\033[1;32m"     # 绿色（加粗）
YELLOW="\033[1;33m"    # 黄色（加粗）
BLUE="\033[1;34m"      # 蓝色（加粗）
PURPLE="\033[1;35m"    # 紫色（加粗）
CYAN="\033[1;36m"      # 青色（加粗）
RESET="\033[0m"        # 重置格式
BOLD="\033[1m"         # 加粗

# 定义分隔线（ASCII字符，避免乱码）
separator() {
    printf "${CYAN}=======================================================${RESET}\n"
}

# 标题显示函数
title() {
    local color="$1"
    local text="$2"
    separator
    echo -e "${BOLD}${color}${text}${RESET}"
    separator
}

# 信息提示函数（带颜文字）
info() {
    local color="$1"
    local message="$2"
    echo -e "${color}[信息]${RESET} ${message} (≧▽≦)"
}

# 错误提示函数
error() {
    local message="$1"
    echo -e "${RED}[错误]${RESET} ${message} (＞﹏＜)" >&2
    exit 1
}

# 成功提示函数
success() {
    local message="$1"
    echo -e "${GREEN}[成功]${RESET} ${message} (≧∇≦)ﾉ"
}

# 警告提示函数
warning() {
    local message="$1"
    echo -e "${YELLOW}[警告]${RESET} ${message} (ｏ・_・)ノ"
}

# 配置.bashrc启动菜单（统一函数）
configure_bashrc() {
    if ! grep -q "Phira多人联机启动器" ~/.bashrc; then
        cat >> ~/.bashrc << 'EOF'

# Phira多人联机启动提示
echo -e "\e[36m┌-----------------------------------------------------\e[0m"
echo -e "\e[1;32m|          Phira 多人联机启动器\e[0m"
echo -e "\e[33m|        按 [1] 启动 Phira-mp 服务\e[0m"
echo -e "\e[33m|        按 [2] 启动 内网穿透 服务\e[0m"
echo -e "\e[33m|        按 [Ctrl+C] 退出\e[0m"
echo -e "\e[36m└-----------------------------------------------------\e[0m"
read -r -p "请选择服务类型: " service_choice

case $service_choice in
    1)
        echo -e "\e[90m[一言]\e[0m $(curl -s https://api.nxvav.cn/api/yiyan/?encode=text)"
        sleep 1
        echo -e "\e[32m正在启动 Phira-mp 服务… (≧▽≦)\e[0m"
        sleep 1
        
        # 检测当前目录并相应调整
        if [ -d phira-mp ]; then
            # 如果当前就在phira-mp目录内，直接使用
            if [ "$(basename "$PWD")" = "phira-mp" ]; then
                RUST_LOG=info target/release/phira-mp-server
            else
                # 否则进入phira-mp目录
                cd phira-mp && RUST_LOG=info target/release/phira-mp-server
            fi
        elif [ "$(basename "$PWD")" = "ChmlFrp-0.51.2_251023_linux_arm64" ]; then
            # 如果在ChmlFrp目录下，先退出到上级再进入phira-mp
            cd .. && [ -d phira-mp ] && cd phira-mp && RUST_LOG=info target/release/phira-mp-server || {
                echo -e "\e[31m错误：未找到 phira-mp 目录\e[0m"
                echo -e "\e[33m提示：请先安装 Phira-mp 服务\e[0m"
            }
        else
            # 其他情况直接尝试进入phira-mp
            [ -d phira-mp ] && cd phira-mp && RUST_LOG=info target/release/phira-mp-server || {
                echo -e "\e[31m错误：未找到 phira-mp 目录\e[0m"
                echo -e "\e[33m提示：请先安装 Phira-mp 服务\e[0m"
            }
        fi
        ;;
    2)
        echo -e "\e[32m正在启动 内网穿透 服务… (≧▽≦)\e[0m"
        sleep 1
        
        # 检测当前目录并相应调整
        if [ -d ChmlFrp-0.51.2_251023_linux_arm64 ]; then
            # 如果当前就在ChmlFrp目录内，直接使用
            if [ "$(basename "$PWD")" = "ChmlFrp-0.51.2_251023_linux_arm64" ]; then
                ./frpc -c frpc.ini
            else
                # 否则进入ChmlFrp目录
                cd ChmlFrp-0.51.2_251023_linux_arm64 && ./frpc -c frpc.ini
            fi
        elif [ "$(basename "$PWD")" = "phira-mp" ]; then
            # 如果在phira-mp目录下，先退出到上级再进入ChmlFrp
            cd .. && [ -d ChmlFrp-0.51.2_251023_linux_arm64 ] && cd ChmlFrp-0.51.2_251023_linux_arm64 && ./frpc -c frpc.ini || {
                echo -e "\e[31m错误：未找到 ChmlFrp 目录或配置文件\e[0m"
                echo -e "\e[33m提示：请先安装内网穿透工具\e[0m"
            }
        else
            # 其他情况直接尝试进入ChmlFrp
            [ -d ChmlFrp-0.51.2_251023_linux_arm64 ] && cd ChmlFrp-0.51.2_251023_linux_arm64 && ./frpc -c frpc.ini || {
                echo -e "\e[31m错误：未找到 ChmlFrp 目录或配置文件\e[0m"
                echo -e "\e[33m提示：请先安装内网穿透工具\e[0m"
            }
        fi
        ;;
    *)
        echo -e "\e[31m无效选项，脚本退出。\e[0m"
        ;;
esac
EOF
        success "启动交互已配置，下次打开Termux将显示启动提示"
    else
        warning "启动交互已存在，无需重复配置"
    fi
}

# 安装Phira-mp的函数
install_phira_mp() {
    # 若已存在 phira-mp 目录则删除
    if [ -d "phira-mp" ]; then
        info "$YELLOW" "检测到已存在 phira-mp 目录，正在删除..."
        rm -rf phira-mp || error "无法删除旧目录 phira-mp"
        success "旧目录已清理"
        echo
    fi

    # 步骤1：更新软件包
    title "$BLUE" "步骤1/6：更新软件包列表"
    sleep 1
    info "$YELLOW" "正在更新软件包..."
    pkg update -y || error "软件包更新失败"
    success "更新软件包完成"
    echo

    # 步骤2：安装依赖工具
    title "$BLUE" "步骤2/6：安装必要工具"
    sleep 1
    info "$YELLOW" "检查并安装git..."
    sleep 1
    if ! command -v git &> /dev/null; then
        pkg install -y git || error "git安装失败"
        success "git安装完成"
    else
        success "git已安装，跳过"
    fi

    info "$YELLOW" "检查并安装Rust工具链..."
    sleep 1
    if ! command -v rustc &> /dev/null; then
        pkg install -y rust || error "Rust安装失败"
        success "Rust安装完成"
    else
        success "Rust已安装，跳过"
    fi

    info "$YELLOW" "安装基础构建工具..."
    sleep 1
    pkg install -y build-essential || error "构建工具安装失败"
    success "所有依赖安装完成"
    echo

    # 步骤3：克隆仓库
    title "$BLUE" "步骤3/6：克隆phira-mp仓库"
    sleep 1
    info "$YELLOW" "正在克隆代码仓库..."
    sleep 1
    git clone https://github.com/TeamFlos/phira-mp.git || error "仓库克隆失败"
    success "仓库克隆完成"
    echo

    # 步骤4：进入目录并更新依赖
    title "$BLUE" "步骤4/6：更新项目依赖"
    sleep 1
    info "$YELLOW" "进入项目目录..."
    cd phira-mp || error "无法进入项目目录"

    info "$YELLOW" "正在更新依赖包..."
    sleep 1
    cargo update || error "依赖更新失败"
    success "依赖更新完成"
    echo

    # 步骤5：构建项目
    title "$BLUE" "步骤5/6：构建服务程序"
    sleep 1
    info "$YELLOW" "即将开始构建..."
    sleep 1
    title "$PURPLE" "注意:该过程耗时可能较长，请耐心等待"
    cargo build --release -p phira-mp-server || error "构建失败"
    success "程序构建完成"
    echo

    # 步骤6：配置启动提示
    title "$BLUE" "步骤6/6：配置启动交互"
    sleep 1
    info "$YELLOW" "设置启动提示与自动执行逻辑..."
    sleep 1
    configure_bashrc
    echo

    # 安装完成提示
    title "$GREEN" "安装全部完成！"
    info "$YELLOW" "下次启动Termux时，将显示启动提示，按需选择服务即可"
    sleep 1
    info "$YELLOW" "本次可直接按以下步骤启动："
    echo -e "${CYAN}1. 输入: cd phira-mp${RESET}"
    echo -e "${CYAN}2. 输入: RUST_LOG=info target/release/phira-mp-server${RESET}"
}

# 安装内网穿透的函数
install_frp() {
    title "$BLUE" "内网穿透安装程序"
    info "$YELLOW" "即将安装ChmlFrp内网穿透工具..."
    echo
    
    # 步骤1：安装wget
    title "$BLUE" "步骤1/5：安装wget"
    sleep 1
    if ! command -v wget &> /dev/null; then
        info "$YELLOW" "正在安装wget..."
        pkg install -y wget || error "wget安装失败"
        success "wget安装完成"
    else
        success "wget已安装，跳过"
    fi
    echo

    # 步骤2：下载ChmlFrp
    title "$BLUE" "步骤2/5：下载ChmlFrp"
    sleep 1
    info "$YELLOW" "正在下载ChmlFrp..."
    wget https://cf-v1.uapis.cn/download/ChmlFrp-0.51.2_251023_linux_arm64.tar.gz || error "下载失败"
    success "下载完成"
    echo

    # 步骤3：解压文件
    title "$BLUE" "步骤3/5：解压文件"
    sleep 1
    info "$YELLOW" "正在解压..."
    tar -zxf ChmlFrp-0.51.2_251023_linux_arm64.tar.gz || error "解压失败"
    success "解压完成"
    echo

    # 步骤4：进入目录并配置
    title "$BLUE" "步骤4/5：配置frpc"
    sleep 1
    info "$YELLOW" "进入ChmlFrp目录..."
    cd ChmlFrp-0.51.2_251023_linux_arm64 || error "无法进入目录"

    info "$YELLOW" "请前往文件管理器编辑 frpc.ini 配置文件..."
    warning "文件路径: $(pwd)/frpc.ini"
    echo -e "${CYAN}┌-----------------------------------------------------${RESET}"
    echo -e "${CYAN}|  提示：建议用文本编辑器打开frpc.ini进行配置${RESET}"
    echo -e "${CYAN}|  配置完成后返回Termux并按下回车继续${RESET}"
    echo -e "${CYAN}└-----------------------------------------------------${RESET}"
    
    read -p "编辑完成后请在此按下回车键..."
    
    info "$YELLOW" "正在设置执行权限..."
    chmod +x frpc || error "权限设置失败"
    
    # 步骤5：配置启动提示
    title "$BLUE" "步骤5/5：配置启动交互"
    sleep 1
    info "$YELLOW" "设置启动提示与自动执行逻辑..."
    sleep 1
    configure_bashrc
    echo
    
    success "内网穿透工具安装完成！"
    info "$YELLOW" "下次启动Termux时，将显示启动提示，按[2]即可启动内网穿透服务"
    sleep 1
    info "$YELLOW" "本次可直接按以下步骤启动："
    echo -e "${CYAN}1. 输入: cd ChmlFrp-0.51.2_251023_linux_arm64${RESET}"
    echo -e "${CYAN}2. 输入: ./frpc -c frpc.ini${RESET}"
}

# 主流程
main() {
    title "$YELLOW" "Phira多人联机一键安装脚本"
    info "$CYAN" "作者: 日落-ya"
    info "$CYAN" "请选择要安装的服务："
    echo
    echo -e "${GREEN}1) 安装 Phira-mp 游戏服务器${RESET}"
    echo -e "${GREEN}2) 安装 内网穿透工具 (ChmlFrp)${RESET}"
    echo
    read -p "请输入选项 [1-2]: " choice
    
    case $choice in
        1)
            install_phira_mp
            ;;
        2)
            install_frp
            ;;
        *)
            error "无效选项，请输入1或2"
            ;;
    esac
}

# 执行主函数
main
