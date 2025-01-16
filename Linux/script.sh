#!/bin/bash

# 定义颜色
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m' # 无颜色

# 设置OpenSSH的版本号
OPENSSH_VERSION="9.8p1"

# 确保以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}请以 root 权限运行此脚本。${NC}"
   exit 1
fi

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}无法检测操作系统类型。${NC}"
    exit 1
fi

# 配置SSH端口
configure_ssh_port() {
    echo -e "\n${YELLOW}====== 配置 SSH 端口 ======${NC}"
    # 获取当前SSH端口
    current_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [ -z "$current_port" ] && current_port=22
    
    echo -e "${YELLOW}当前SSH端口: ${current_port}${NC}"
    read -p "请输入新的SSH端口 (默认: 2233): " SSH_PORT
    SSH_PORT=${SSH_PORT:-2233}

    # 验证端口号是否合法
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
        echo -e "${RED}无效的端口号，使用默认端口 2233${NC}"
        SSH_PORT=2233
    fi

    # 更新SSH配置文件
    if [ -f /etc/ssh/sshd_config ]; then
        # 备份原配置
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        # 更新端口配置
        sed -i "s/^#*Port [0-9]*/Port $SSH_PORT/" /etc/ssh/sshd_config
        if ! grep -q "^Port" /etc/ssh/sshd_config; then
            echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
        fi
        echo -e "${GREEN}SSH端口已设置为: $SSH_PORT${NC}"
    else
        echo -e "${RED}未找到 SSH 配置文件${NC}"
        return 1
    fi
}

# ================ UFW 配置功能 ================
configure_ufw() {
    echo -e "\n${YELLOW}====== 配置 UFW 防火墙 ======${NC}"
    
    # 检查是否已安装 UFW
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}UFW 未安装，正在安装...${NC}"
        if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
            apt-get update && apt-get install -y ufw
        else
            echo -e "${RED}当前系统不支持自动安装UFW，请手动安装${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}UFW 已安装，跳过安装。${NC}"
    fi

    # 配置UFW规则
    echo -e "\n${YELLOW}配置UFW规则：${NC}"
    
    # SSH端口
    echo -e "${CYAN}SSH端口配置：${NC}"
    if sudo ufw status | grep -q "$SSH_PORT"; then
        echo -e "${YELLOW}SSH 端口 $SSH_PORT 已放行。${NC}"
    else
        read -p "是否放行SSH端口 $SSH_PORT？(Y/N): " allow_ssh
        case "$allow_ssh" in
            [Yy])
                sudo ufw allow "$SSH_PORT"
                echo -e "${GREEN}已放行SSH端口 $SSH_PORT${NC}"
                ;;
            *)
                echo -e "${YELLOW}未放行SSH端口${NC}"
                ;;
        esac
    fi

    # HTTP/HTTPS端口
    echo -e "\n${CYAN}Web服务端口配置：${NC}"
    read -p "是否放行HTTP端口(80)？(Y/N): " allow_http
    case "$allow_http" in
        [Yy])
            sudo ufw allow 80
            echo -e "${GREEN}已放行HTTP端口${NC}"
            ;;
        *)
            echo -e "${YELLOW}未放行HTTP端口${NC}"
            ;;
    esac

    read -p "是否放行HTTPS端口(443)？(Y/N): " allow_https
    case "$allow_https" in
        [Yy])
            sudo ufw allow 443
            echo -e "${GREEN}已放行HTTPS端口${NC}"
            ;;
        *)
            echo -e "${YELLOW}未放行HTTPS端口${NC}"
            ;;
    esac

    # 自定义端口
    echo -e "\n${CYAN}自定义端口配置：${NC}"
    read -p "是否需要放行其他端口？(Y/N): " custom_ports
    case "$custom_ports" in
        [Yy])
            while true; do
                read -p "请输入要放行的端口号（输入q退出）: " port
                if [ "$port" = "q" ]; then
                    break
                fi
                if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
                    read -p "请选择协议（1:TCP 2:UDP 3:TCP+UDP）: " protocol
                    case "$protocol" in
                        1)
                            sudo ufw allow "$port"/tcp
                            echo -e "${GREEN}已放行TCP端口 $port${NC}"
                            ;;
                        2)
                            sudo ufw allow "$port"/udp
                            echo -e "${GREEN}已放行UDP端口 $port${NC}"
                            ;;
                        3)
                            sudo ufw allow "$port"
                            echo -e "${GREEN}已放行TCP/UDP端口 $port${NC}"
                            ;;
                        *)
                            echo -e "${RED}无效的协议选择${NC}"
                            ;;
                    esac
                else
                    echo -e "${RED}无效的端口号${NC}"
                fi
            done
            ;;
    esac

    # 检查 UFW 是否已启用
    if sudo ufw status | grep -q "Status: active"; then
        echo -e "${YELLOW}UFW 已启用。${NC}"
    else
        echo -e "${YELLOW}启用 UFW 并设置开机自启...${NC}"
        read -p "确认启用UFW防火墙？(Y/N): " enable_ufw
        case "$enable_ufw" in
            [Yy])
                sudo ufw enable
                sudo systemctl enable ufw
                ;;
            *)
                echo -e "${YELLOW}UFW未启用${NC}"
                ;;
        esac
    fi

    # 查看 UFW 状态
    echo -e "\n${YELLOW}当前 UFW 状态：${NC}"
    sudo ufw status verbose
}

# ================ Fail2ban 配置功能 ================
configure_fail2ban() {
    echo -e "\n${YELLOW}====== 配置 Fail2ban ======${NC}"
    
    # 检查 fail2ban 是否已安装且正在运行
    if command -v fail2ban-client &> /dev/null; then
        if systemctl is-active --quiet fail2ban; then
            echo -e "${YELLOW}fail2ban 已安装且正在运行。${NC}"
            read -p "是否要重新配置fail2ban？(Y/N): " reconfigure
            case "$reconfigure" in
                [Nn])
                    return 0
                    ;;
            esac
        fi
    fi

    # 安装 fail2ban
    echo -e "${YELLOW}正在安装 fail2ban...${NC}"
    case $OS in
        ubuntu|debian)
            apt update && apt install fail2ban -y
            ;;
        centos|rhel|almalinux|rocky|fedora)
            yum install -y epel-release && yum install -y fail2ban
            ;;
        *)
            echo -e "${RED}不支持的操作系统：$OS${NC}"
            return 1
            ;;
    esac

    # 配置 fail2ban
    echo -e "\n${CYAN}配置 fail2ban 参数：${NC}"
    
    # 询问基本配置
    read -p "请输入最大尝试次数 (默认: 5): " maxretry
    maxretry=${maxretry:-5}
    
    read -p "请输入封禁时间（秒）(默认: 3600): " bantime
    bantime=${bantime:-3600}
    
    read -p "请输入检测时间窗口（秒）(默认: 600): " findtime
    findtime=${findtime:-600}

    # 备份原始配置文件
    if [ ! -f /etc/fail2ban/jail.local ]; then
        echo -e "${YELLOW}备份原始 fail2ban 配置...${NC}"
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    fi

    # 写入 fail2ban 配置文件
    echo -e "${YELLOW}写入 fail2ban 配置...${NC}"
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = ${bantime}
findtime = ${findtime}
maxretry = ${maxretry}

[sshd]
enabled = true
backend = systemd
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = ${maxretry}
bantime = ${bantime}
findtime = ${findtime}
EOF

    # 询问是否配置邮件通知
    read -p "是否配置邮件通知？(Y/N): " configure_email
    case "$configure_email" in
        [Yy])
            read -p "请输入发送通知的邮箱地址: " destemail
            if [ ! -z "$destemail" ]; then
                cat >> /etc/fail2ban/jail.local <<EOF

# 邮件通知配置
destemail = ${destemail}
sendername = Fail2Ban
mta = sendmail
action = %(action_mwl)s
EOF
                echo -e "${GREEN}已配置邮件通知${NC}"
            fi
            ;;
    esac

    # 重新启动并启用 fail2ban 服务
    echo -e "${YELLOW}重启并启用 fail2ban 服务...${NC}"
    systemctl enable fail2ban
    systemctl restart fail2ban

    # 检查 fail2ban 状态
    echo -e "${YELLOW}fail2ban 状态：${NC}"
    systemctl status fail2ban --no-pager

    # 验证 fail2ban 是否已生效
    echo -e "\n${YELLOW}fail2ban 规则检查：${NC}"
    fail2ban-client status sshd
    
    echo -e "\n${GREEN}fail2ban 配置完成！${NC}"
    echo -e "配置信息：
- 最大尝试次数：${maxretry}次
- 封禁时间：${bantime}秒
- 检测时间窗口：${findtime}秒
- 保护的SSH端口：${SSH_PORT}"
}

# ================ OpenSSH 升级功能 ================
# 等待并检查锁文件
wait_for_lock() {
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo -e "${YELLOW}等待dpkg锁释放...${NC}"
        sleep 1
    done
}

# 修复dpkg中断问题
fix_dpkg() {
    echo -e "${YELLOW}修复 dpkg 中断问题...${NC}"
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a
}

# 安装依赖包
install_dependencies() {
    echo -e "${YELLOW}安装依赖包...${NC}"
    case $OS in
        ubuntu|debian)
            wait_for_lock
            fix_dpkg
            DEBIAN_FRONTEND=noninteractive apt update
            DEBIAN_FRONTEND=noninteractive apt install -y build-essential zlib1g-dev libssl-dev libpam0g-dev wget ntpdate -o Dpkg::Options::="--force-confnew"
            ;;
        centos|rhel|almalinux|rocky|fedora)
            yum install -y epel-release
            yum groupinstall -y "Development Tools"
            yum install -y zlib-devel openssl-devel pam-devel wget ntpdate
            ;;
        alpine)
            apk add build-base zlib-dev openssl-dev pam-dev wget ntpdate
            ;;
        *)
            echo -e "${RED}不支持的操作系统：$OS${NC}"
            return 1
            ;;
    esac
}

# 下载、编译和安装OpenSSH
install_openssh() {
    echo -e "${YELLOW}下载、编译和安装 OpenSSH ${OPENSSH_VERSION}...${NC}"
    wget --no-check-certificate https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz
    tar -xzf openssh-${OPENSSH_VERSION}.tar.gz
    cd openssh-${OPENSSH_VERSION}
    ./configure
    make
    make install
    cd ..
}

# 重启SSH服务
restart_ssh() {
    echo -e "${YELLOW}重启 SSH 服务...${NC}"
    case $OS in
        ubuntu|debian)
            systemctl restart ssh
            ;;
        centos|rhel|almalinux|rocky|fedora)
            systemctl restart sshd
            ;;
        alpine)
            rc-service sshd restart
            ;;
        *)
            echo -e "${RED}不支持的操作系统：$OS${NC}"
            return 1
            ;;
    esac
}

# 设置路径优先级
set_path_priority() {
    echo -e "${YELLOW}设置 SSH 路径优先级...${NC}"
    NEW_SSH_PATH=$(which sshd)
    NEW_SSH_DIR=$(dirname "$NEW_SSH_PATH")
    if [[ ":$PATH:" != *":$NEW_SSH_DIR:"* ]]; then
        export PATH="$NEW_SSH_DIR:$PATH"
        echo "export PATH=\"$NEW_SSH_DIR:\$PATH\"" >> ~/.bashrc
    fi
}

# 验证更新
verify_installation() {
    echo -e "${YELLOW}验证安装的 SSH 版本...${NC}"
    ssh -V
}

# 清理下载的文件
clean_up() {
    echo -e "${YELLOW}清理安装文件...${NC}"
    rm -rf openssh-${OPENSSH_VERSION}*
}

# 检查OpenSSH版本并升级
upgrade_openssh() {
    echo -e "\n${YELLOW}====== 检查并升级 OpenSSH ======${NC}"
    echo -e "${YELLOW}检查当前 SSH 版本...${NC}"
    current_version=$(ssh -V 2>&1 | awk '{print $1}' | cut -d_ -f2 | cut -d'p' -f1)
    
    # 版本范围
    min_version=8.5
    max_version=9.7
    
    if awk -v ver="$current_version" -v min="$min_version" -v max="$max_version" 'BEGIN{if(ver>=min && ver<=max) exit 0; else exit 1}'; then
        echo -e "${RED}SSH版本: $current_version 在8.5到9.7之间，需要修复。${NC}"
        read -p "确定继续升级OpenSSH吗？(Y/N): " choice
        case "$choice" in
            [Yy])
                install_dependencies
                install_openssh
                restart_ssh
                set_path_priority
                verify_installation
                clean_up
                ;;
            [Nn])
                echo -e "${CYAN}已取消OpenSSH升级${NC}"
                ;;
            *)
                echo -e "${RED}无效的选择，跳过OpenSSH升级。${NC}"
                ;;
        esac
    else
        echo -e "${CYAN}SSH版本: $current_version 不在8.5到9.7之间，无需修复。${NC}"
    fi
}

# ================ 主函数 ================
main() {
    echo -e "${GREEN}===== 开始系统安全加固 =====${NC}"
    
    # 询问是否配置UFW
    read -p "是否配置UFW防火墙？(Y/N): " configure_ufw_choice
    case "$configure_ufw_choice" in
        [Yy])
            configure_ufw
            ;;
        *)
            echo -e "${CYAN}跳过UFW配置${NC}"
            ;;
    esac

    # 询问是否配置Fail2ban
    read -p "是否配置Fail2ban？(Y/N): " configure_fail2ban_choice
    case "$configure_fail2ban_choice" in
        [Yy])
            configure_fail2ban
            ;;
        *)
            echo -e "${CYAN}跳过Fail2ban配置${NC}"
            ;;
    esac

    # 询问是否检查并升级OpenSSH
    read -p "是否检查并升级OpenSSH？(Y/N): " upgrade_openssh_choice
    case "$upgrade_openssh_choice" in
        [Yy])
            upgrade_openssh
            ;;
        *)
            echo -e "${CYAN}跳过OpenSSH检查与升级${NC}"
            ;;
    esac

    echo -e "${GREEN}===== 系统安全加固完成 =====${NC}"
}

# 运行主函数
main
