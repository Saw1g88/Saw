#!/bin/bash

# 定义颜色
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m' # 无颜色

# 定义日志文件
LOG_FILE="/var/log/system_init.log"

# 日志函数
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$message" | tee -a "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    log "${RED}错误: $1${NC}"
    if [ "$2" == "exit" ]; then
        exit 1
    fi
}

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    handle_error "此脚本必须以 root 权限运行" "exit"
fi

# 检查磁盘空间
check_disk_space() {
    log "${YELLOW}检查磁盘空间...${NC}"
    available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$available_space" -lt 5 ]; then
        log "${RED}警告：磁盘空间不足 5GB${NC}"
        read -p "磁盘空间可能不足，是否继续？(y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            handle_error "用户取消安装" "exit"
        fi
    fi
    log "${GREEN}磁盘空间检查完成${NC}"
}

# 检测并安装所需的指令
check_and_install() {
    local package_name=$1
    if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
        if ! dpkg -l | grep -q "^ii.*$package_name "; then
            log "${YELLOW}$package_name 未安装，正在安装...${NC}"
            apt-get install -y $package_name || handle_error "安装 $package_name 失败"
        else
            log "${CYAN}$package_name 已安装，跳过安装。${NC}"
        fi
    elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
        if ! rpm -q $package_name &> /dev/null; then
            log "${YELLOW}$package_name 未安装，正在安装...${NC}"
            yum install -y $package_name || handle_error "安装 $package_name 失败"
        else
            log "${CYAN}$package_name 已安装，跳过安装。${NC}"
        fi
    fi
}

# 检查操作系统类型
detect_os() {
    log "${YELLOW}检测操作系统类型...${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os=$ID
    elif [ -f /etc/redhat-release ]; then
        os="centos"
    else
        handle_error "无法检测操作系统类型" "exit"
    fi

    if [[ "$os" != "ubuntu" && "$os" != "debian" && "$os" != "centos" && "$os" != "rhel" ]]; then
        handle_error "不支持的操作系统类型: $os" "exit"
    fi
    
    log "${GREEN}检测到操作系统: $os${NC}"
}

# 系统更新
update_system() {
    log "${YELLOW}更新系统...${NC}"
    if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
        apt-get update || handle_error "系统更新失败"
        apt-get full-upgrade -y || handle_error "系统升级失败"
    elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
        yum update -y || handle_error "系统更新失败"
    fi
    log "${GREEN}系统更新完成${NC}"
}

# 安装 Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        log "${YELLOW}安装 Docker...${NC}"
        if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
            # 添加 Docker 官方 GPG 密钥和仓库
            apt-get install -y ca-certificates curl gnupg lsb-release || handle_error "安装 Docker 依赖失败"
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$os/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || handle_error "添加 Docker GPG 密钥失败"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$os $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update || handle_error "更新软件源失败"
            apt-get install -y docker-ce docker-ce-cli containerd.io || handle_error "安装 Docker 失败"
        elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
            yum install -y yum-utils || handle_error "安装 yum-utils 失败"
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || handle_error "添加 Docker 仓库失败"
            yum install -y docker-ce docker-ce-cli containerd.io || handle_error "安装 Docker 失败"
        fi
        systemctl start docker || handle_error "启动 Docker 失败"
        systemctl enable docker || handle_error "设置 Docker 开机自启动失败"
        log "${GREEN}Docker 安装完成${NC}"
    else
        log "${CYAN}Docker 已安装，跳过安装。${NC}"
    fi
}

# 配置 BBR 和 FQ
configure_bbr_fq() {
    log "${YELLOW}检查 BBR 和 FQ 设置...${NC}"
    current_qdisc=$(sysctl net.core.default_qdisc | awk '{print $3}')
    current_congestion_control=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    
    if [ "$current_qdisc" == "fq" ] && [ "$current_congestion_control" == "bbr" ]; then
        log "${CYAN}BBR 和 FQ 已开启，跳过设置。${NC}"
    else
        log "${YELLOW}配置 BBR 和 FQ...${NC}"
        cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        sysctl -p || handle_error "应用 sysctl 设置失败"
        log "${GREEN}已配置 BBR 和 FQ${NC}"
    fi
}

# TCP 优化参数配置
configure_tcp_optimization() {
    log "${YELLOW}检查是否已设置 TCP 优化参数...${NC}"

    if grep -q "# TCP_OPTIMIZED_MARKER_BEGIN" /etc/sysctl.conf; then
        log "${CYAN}检测到已存在 TCP 优化参数配置，跳过设置。${NC}"
        return
    fi

    read -p "是否应用 TCP 优化？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "${YELLOW}应用 TCP 优化参数...${NC}"

        # 确保 BBR 和 FQ 相关设置存在
        grep -q "net.core.default_qdisc" /etc/sysctl.conf || echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
        grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf

        # 添加 TCP 优化参数（带标识）
        cat >> /etc/sysctl.conf <<EOF

# TCP_OPTIMIZED_MARKER_BEGIN
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.rmem_max = 25625000
net.core.wmem_max = 25625000
net.ipv4.tcp_rmem = 4096 87380 25625000
net.ipv4.tcp_wmem = 4096 65536 25625000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_syncookies = 1
# TCP_OPTIMIZED_MARKER_END
EOF

        sysctl --system || handle_error "应用 TCP 优化参数失败"
        log "${GREEN}TCP 优化参数已成功应用${NC}"
    else
        log "${CYAN}用户选择跳过 TCP 优化配置${NC}"
    fi
}

# IPv4 优先设置
configure_ipv4_preference() {
    log "${YELLOW}检查 IPv4 优先设置...${NC}"

    # 若规则已存在则无需重复添加
    if grep -q "precedence ::ffff:0:0/96" /etc/gai.conf; then
        log "${CYAN}IPv4 优先规则已存在，跳过。${NC}"
        return
    fi

    # 让用户自行选择
    read -p "是否添加 IPv4 优先规则？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
        log "${GREEN}已成功添加 IPv4 优先规则${NC}"
    else
        log "${CYAN}用户选择跳过 IPv4 优先设置${NC}"
    fi
}

# 配置 DNS
configure_dns() {
    log "${YELLOW}检查 DNS 配置...${NC}"
    
    # 检查是否安装了 chattr
    if ! command -v chattr &> /dev/null; then
        log "${YELLOW}安装 chattr...${NC}"
        if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
            apt-get install -y e2fsprogs || handle_error "安装 e2fsprogs 失败"
        elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
            yum install -y e2fsprogs || handle_error "安装 e2fsprogs 失败"
        fi
    fi

    # 检查当前 DNS 设置
    if grep -q 'nameserver 8.8.8.8' /etc/resolv.conf && \
       grep -q 'nameserver 1.1.1.1' /etc/resolv.conf && \
       grep -q 'nameserver 2001:4860:4860::8888' /etc/resolv.conf && \
       grep -q 'nameserver 2606:4700:4700::1111' /etc/resolv.conf; then
        # 检查是否已经设置了不可变属性
        if lsattr /etc/resolv.conf | grep -q 'i'; then
            log "${CYAN}DNS 已正确设置且已锁定，跳过设置。${NC}"
            return
        fi
    fi

    # 如果文件有不可变属性，先移除
    if lsattr /etc/resolv.conf | grep -q 'i'; then
        chattr -i /etc/resolv.conf || handle_error "移除 resolv.conf 不可变属性失败"
    fi

    # 备份当前 DNS 配置
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.bak || handle_error "DNS 配置备份失败"
    fi

    # 如果存在 systemd-resolved，停用它
    if systemctl is-active systemd-resolved &>/dev/null; then
        log "${YELLOW}停用 systemd-resolved...${NC}"
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
    fi

    # 如果是符号链接，则删除它
    if [ -L /etc/resolv.conf ]; then
        rm /etc/resolv.conf
    fi

    # 设置新的 DNS 配置
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 2001:4860:4860::8888
nameserver 2606:4700:4700::1111
EOF

    # 设置文件为不可变
    chattr +i /etc/resolv.conf || handle_error "设置 resolv.conf 不可变属性失败"

    # 如果存在 NetworkManager，配置其 DNS 设置
    if command -v nmcli &> /dev/null; then
        log "${YELLOW}配置 NetworkManager DNS 设置...${NC}"
        # 获取所有连接
        connections=$(nmcli -g NAME connection show)
        for conn in $connections; do
            log "${YELLOW}配置连接 '$conn' 的 DNS 设置...${NC}"
            nmcli connection modify "$conn" ipv4.dns "8.8.8.8 1.1.1.1" || log "${YELLOW}NetworkManager IPv4 DNS 配置失败: $conn${NC}"
            nmcli connection modify "$conn" ipv6.dns "2001:4860:4860::8888 2606:4700:4700::1111" || log "${YELLOW}NetworkManager IPv6 DNS 配置失败: $conn${NC}"
            nmcli connection modify "$conn" ipv4.ignore-auto-dns yes || log "${YELLOW}设置忽略自动DNS失败: $conn${NC}"
            nmcli connection modify "$conn" ipv6.ignore-auto-dns yes || log "${YELLOW}设置忽略自动DNS失败: $conn${NC}"
        done
        systemctl restart NetworkManager || handle_error "重启 NetworkManager 失败"
    fi

    log "${GREEN}DNS 设置完成并已锁定配置文件${NC}"
    
    # 验证设置
    if ! grep -q 'nameserver 8.8.8.8' /etc/resolv.conf; then
        handle_error "DNS 配置验证失败"
    fi
    
    # 验证不可变属性
    if ! lsattr /etc/resolv.conf | grep -q 'i'; then
        handle_error "DNS 配置文件锁定验证失败"
    fi
}

# 配置虚拟内存
configure_swap() {
    log "${YELLOW}检查虚拟内存设置...${NC}"
    
    # 如果已存在 swap，询问是否重新配置
    if swapon --show | grep -q "/swapfile"; then
        log "${CYAN}检测到已存在 Swap 配置${NC}"
        read -p "是否要重新配置 Swap？(y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "${CYAN}保留现有 Swap 配置${NC}"
            return
        fi
        # 如果选择重新配置，先关闭并移除现有的 swap
        swapoff /swapfile || handle_error "关闭现有 swap 失败"
        rm -f /swapfile || handle_error "删除现有 swap 文件失败"
        sed -i '/\/swapfile/d' /etc/fstab || handle_error "从 fstab 移除 swap 配置失败"
    fi

    # 检查系统内存
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
    suggested_swap=$((total_mem / 2))
    
    # 询问用户想要设置的 swap 大小
    while true; do
        read -p "请输入要设置的 Swap 大小(MB)[建议值: ${suggested_swap}MB, 输入0取消设置]: " swap_size
        if [[ "$swap_size" =~ ^[0-9]+$ ]]; then
            break
        else
            log "${RED}请输入有效的数字${NC}"
        fi
    done

    # 如果输入0，取消设置
    if [ "$swap_size" -eq 0 ]; then
        log "${YELLOW}取消 Swap 设置${NC}"
        return
    fi

    log "${YELLOW}开始创建 ${swap_size}MB 的 swap 文件...${NC}"
    
    # 创建 swap 文件
    if ! dd if=/dev/zero of=/swapfile bs=1M count="$swap_size" status=progress; then
        handle_error "创建 swap 文件失败"
        return
    fi

    chmod 600 /swapfile || handle_error "设置 swap 文件权限失败"
    mkswap /swapfile || handle_error "格式化 swap 文件失败"
    swapon /swapfile || handle_error "启用 swap 失败"

    # 添加到 fstab
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab || handle_error "更新 fstab 失败"
    fi

    # 验证 swap 是否成功启用
    if swapon --show | grep -q "/swapfile"; then
        actual_swap_size=$(free -m | awk '/^Swap:/{print $2}')
        log "${GREEN}Swap 设置完成！当前 Swap 大小: ${actual_swap_size}MB${NC}"
    else
        handle_error "Swap 设置失败"
    fi
}

# 设置时区
configure_timezone() {
    log "${YELLOW}检查时区设置...${NC}"
    current_timezone=$(timedatectl | grep "Time zone" | awk '{print $3}')
    
    if [ "$current_timezone" == "Asia/Shanghai" ]; then
        log "${CYAN}时区已经是 Asia/Shanghai，跳过设置。${NC}"
    else
        log "${YELLOW}设置时区为 Asia/Shanghai...${NC}"
        timedatectl set-timezone Asia/Shanghai || handle_error "设置时区失败"
        log "${GREEN}时区设置完成${NC}"
    fi
}

# 检查并配置语言环境
configure_locale() {
    log "${YELLOW}检查语言环境配置...${NC}"
    
    # 1. 安装 locales 包
    if ! dpkg -l | grep -q "^ii.*locales"; then
        log "${YELLOW}安装 locales 包...${NC}"
        apt-get install -y locales || handle_error "安装 locales 失败"
    else
        log "${CYAN}locales 已安装，跳过安装步骤${NC}"
    fi

    # 2. 检查并修改 locale.gen
    if ! grep -q "^zh_CN.UTF-8 UTF-8" /etc/locale.gen; then
        log "${YELLOW}添加中文语言支持...${NC}"
        # 先备份原文件
        cp /etc/locale.gen /etc/locale.gen.bak
        # 添加中文支持
        echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
        echo "zh_TW.UTF-8 UTF-8" >> /etc/locale.gen
    else
        log "${CYAN}中文语言环境已在配置文件中，跳过添加步骤${NC}"
    fi

    # 3. 生成语言文件
    log "${YELLOW}生成语言文件...${NC}"
    locale-gen zh_CN.UTF-8 || handle_error "生成中文语言环境失败"
    locale-gen zh_TW.UTF-8 || handle_error "生成繁体中文语言环境失败"

    # 4. 验证语言环境是否已生成
    if locale -a | grep -q "zh_CN.utf8"; then
        log "${CYAN}中文语言环境已成功生成${NC}"
        # 5. 设置系统默认语言
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 || handle_error "设置默认语言失败"
        log "${GREEN}语言环境配置完成${NC}"
    else
        handle_error "中文语言环境生成失败"
    fi
}

# 检查并安装中文字体
configure_fonts() {
    log "${YELLOW}检查中文字体...${NC}"
    
    if ! dpkg -l | grep -q "^ii.*fonts-noto-cjk"; then
        log "${YELLOW}安装中文字体...${NC}"
        sudo apt install -y fonts-noto-cjk || handle_error "安装字体失败"
    else
        log "${CYAN}中文字体已安装，跳过安装步骤${NC}"
    fi
}

# 主函数
main() {
    log "${GREEN}开始系统初始化配置...${NC}"
    
    # 执行各项配置
    check_disk_space
    detect_os
    update_system
    
    # 安装必要工具
    check_and_install jq
    check_and_install wget
    check_and_install curl
    check_and_install ntp
    check_and_install unzip
    
    install_docker
    configure_bbr_fq
    configure_tcp_optimization
    configure_ipv4_preference
    configure_dns
    configure_swap
    configure_timezone
    configure_locale
    configure_fonts
    
    log "${GREEN}所有配置完成！${NC}"
}

# 运行主函数
main
