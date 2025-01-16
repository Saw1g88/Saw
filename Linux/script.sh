#!/bin/bash

# 定义颜色
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m' # 无颜色

# 设置OpenSSH的版本号
OPENSSH_VERSION="9.8p1"
# 需要放行的 SSH 端口号，默认2233
SSH_PORT=2233

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

    # 检查 UFW 是否已放行 SSH 端口
    if sudo ufw status | grep -q "$SSH_PORT"; then
        echo -e "${YELLOW}SSH 端口 $SSH_PORT 已放行。${NC}"
    else
        echo -e "${YELLOW}放行 SSH 端口 $SSH_PORT...${NC}"
        sudo ufw allow "$SSH_PORT"
    fi

    # 检查 UFW 是否已启用
    if sudo ufw status | grep -q "Status: active"; then
        echo -e "${YELLOW}UFW 已启用。${NC}"
    else
        echo -e "${YELLOW}启用 UFW 并设置开机自启...${NC}"
        sudo ufw enable
        sudo systemctl enable ufw
    fi

    # 查看 UFW 状态
    echo -e "${YELLOW}当前 UFW 状态：${NC}"
    sudo ufw status
}

# ================ Fail2ban 配置功能 ================
configure_fail2ban() {
    echo -e "\n${YELLOW}====== 配置 Fail2ban ======${NC}"
    # 检查 fail2ban 是否已安装且正在运行
    if command -v fail2ban-client &> /dev/null; then
        if systemctl is-active --quiet fail2ban; then
            echo -e "${YELLOW}fail2ban 已安装且正在运行。${NC}"
            return 0
        fi
    fi

    # 更新系统并安装 fail2ban
    echo -e "${YELLOW}正在安装 fail2ban...${NC}"
    case $OS in
        ubuntu|debian)
            apt update
            apt install fail2ban -y
            ;;
        centos|rhel|almalinux|rocky|fedora)
            yum install -y epel-release
            yum install -y fail2ban
            ;;
        *)
            echo -e "${RED}不支持的操作系统：$OS${NC}"
            return 1
            ;;
    esac

    # 备份原始配置文件（仅在不存在 jail.local 时执行）
    if [ ! -f /etc/fail2ban/jail.local ]; then
        echo -e "${YELLOW}备份原始 fail2ban 配置...${NC}"
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    fi

    # 写入 fail2ban 配置文件
    echo -e "${YELLOW}配置 fail2ban 以保护 SSH 端口 ${SSH_PORT}...${NC}"
    cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
backend = systemd
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

    # 重新启动并启用 fail2ban 服务
    echo -e "${YELLOW}重启并启用 fail2ban 服务...${NC}"
    systemctl enable fail2ban
    systemctl restart fail2ban

    # 检查 fail2ban 状态
    echo -e "${YELLOW}fail2ban 状态：${NC}"
    systemctl status fail2ban --no-pager

    # 验证 fail2ban 是否已生效
    echo -e "${YELLOW}fail2ban 规则检查：${NC}"
    fail2ban-client status sshd
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
