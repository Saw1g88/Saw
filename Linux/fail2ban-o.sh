#!/bin/bash

# 定义颜色
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m' # 无颜色

# 日志文件
LOG_FILE="/var/log/fail2ban_setup.log"

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

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    handle_error "此脚本必须以 root 权限运行" "exit"
fi

# 检查 systemctl 可用性
if ! command -v systemctl &> /dev/null; then
    handle_error "无法检测到 systemctl，无法继续。" "exit"
fi

# 检测操作系统
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        handle_error "无法确定操作系统类型" "exit"
    fi
}

# 安装 fail2ban
install_fail2ban() {
    if ! command -v fail2ban-client &> /dev/null; then
        log "${YELLOW}fail2ban 未安装，正在安装...${NC}"
        case $OS in
            debian|ubuntu)
                apt update || handle_error "更新软件源失败"
                apt install -y fail2ban || handle_error "安装 fail2ban 失败"
                ;;
            centos|rhel|rocky|almalinux)
                yum install -y epel-release || handle_error "安装 EPEL 仓库失败"
                yum install -y fail2ban || handle_error "安装 fail2ban 失败"
                ;;
            *)
                handle_error "不支持的操作系统: $OS" "exit"
                ;;
        esac
    else
        log "${CYAN}fail2ban 已安装，跳过安装。${NC}"
    fi
}

# 配置 fail2ban
configure_fail2ban() {
    # 询问 SSH 端口
    read -p "请输入要保护的 SSH 端口 [默认: 2233]: " ssh_port
    ssh_port=${ssh_port:-2233}
    
    if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1 ] || [ "$ssh_port" -gt 65535 ]; then
        handle_error "无效的端口号" "exit"
    fi

    # 询问最大尝试次数
    read -p "请输入最大失败尝试次数 [默认: 5]: " max_retry
    max_retry=${max_retry:-5}
    
    # 询问封禁时间
    read -p "请输入封禁时间(分钟) [默认: 30]: " ban_time
    ban_time=${ban_time:-30}

    # 备份原始配置文件
    if [ ! -f /etc/fail2ban/jail.local ]; then
        log "${YELLOW}创建 jail.local 配置文件...${NC}"
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local || handle_error "备份失败"
    else
        cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak.$(date +%Y%m%d_%H%M%S)
    fi

    # 配置 SSH 保护
    cat > /etc/fail2ban/jail.d/sshd.conf <<EOF
[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = %(sshd_log)s
maxretry = $max_retry
findtime = 600
bantime = ${ban_time}m
ignoreip = 127.0.0.1/8 ::1
EOF

    # 设置日志路径
    case $OS in
        debian|ubuntu)
            sed -i 's|%(sshd_log)s|/var/log/auth.log|' /etc/fail2ban/jail.d/sshd.conf
            ;;
        centos|rhel|rocky|almalinux)
            sed -i 's|%(sshd_log)s|/var/log/secure|' /etc/fail2ban/jail.d/sshd.conf
            ;;
    esac
}

# 启动并启用 fail2ban
start_service() {
    systemctl start fail2ban || handle_error "启动 fail2ban 失败"
    systemctl enable fail2ban || handle_error "设置自启失败"
}

# 检查 fail2ban 服务状态
check_status() {
    log "${YELLOW}检查 fail2ban 状态...${NC}"
    fail2ban-client status sshd || handle_error "无法获取 fail2ban 状态"
}

# 主函数
main() {
    log "${GREEN}开始配置 fail2ban...${NC}"
    check_os
    install_fail2ban
    configure_fail2ban
    start_service
    check_status
    log "${GREEN}fail2ban 配置完成！${NC}"
}

# 执行主函数
main
