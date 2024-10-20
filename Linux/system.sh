#!/bin/bash

# 定义颜色
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m' # 无颜色

# 检测并安装所需的指令
check_and_install() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${YELLOW}$1 未安装，正在安装...${NC}"
        if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
            apt-get install -y $1
        elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
            yum install -y $1
        else
            echo -e "${RED}不支持的操作系统，无法安装 $1${NC}"
            exit 1
        fi
    else
        echo -e "${CYAN}$1 已安装，跳过安装。${NC}"
    fi
}

# 检查操作系统类型
os=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    os=$ID
elif [ -f /etc/redhat-release ]; then
    os="centos"
fi

# 判断操作系统是否支持
if [[ "$os" != "ubuntu" && "$os" != "debian" && "$os" != "centos" && "$os" != "rhel" ]]; then
    echo -e "${RED}不支持的操作系统类型: $os${NC}"
    exit 1
fi

# 更新系统
echo -e "${YELLOW}更新系统...${NC}"
if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
    apt-get update && apt-get full-upgrade -y
elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
    yum update -y
fi

# 安装必要的工具
check_and_install jq
check_and_install wget
check_and_install ntp
check_and_install unzip

# 安装 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}安装 Docker...${NC}"
    wget -qO- https://get.docker.com | bash -s docker
    echo -e "${CYAN}Docker 安装完成。${NC}"
else
    echo -e "${CYAN}Docker 已安装，跳过安装。${NC}"
fi

# 开启 TCP Fast Open (TFO)
current_tfo_setting=$(cat /proc/sys/net/ipv4/tcp_fastopen)
if [ "$current_tfo_setting" == "3" ]; then
    echo -e "${CYAN}TCP Fast Open 已开启，跳过设置。${NC}"
else
    echo -e "${YELLOW}开启 TCP Fast Open...${NC}"
    echo "3" > /proc/sys/net/ipv4/tcp_fastopen
    echo "net.ipv4.tcp_fastopen=3" > /etc/sysctl.d/30-tcp_fastopen.conf
    sysctl --system
    echo -e "${CYAN}已开启 TCP Fast Open。${NC}"
fi

# 配置 BBR 和 FQ
current_qdisc=$(sysctl net.core.default_qdisc | awk '{print $3}')
current_congestion_control=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$current_qdisc" == "fq" ] && [ "$current_congestion_control" == "bbr" ]; then
    echo -e "${CYAN}bbr fq 已开启，跳过设置。${NC}"
else
    echo -e "${YELLOW}配置 bbr...${NC}"
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p
    echo -e "${CYAN}已配置 BBR 和 FQ。${NC}"
fi

# 调整 DNS
adjust_dns() {
    echo -e "${YELLOW}检查当前 DNS 配置...${NC}"
    if [ -f /etc/resolv.conf ]; then
        echo -e "${YELLOW}备份当前的 /etc/resolv.conf 文件到 /etc/resolv.conf.bak...${NC}"
        cp /etc/resolv.conf /etc/resolv.conf.bak
    fi

    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
    echo -e "${CYAN}DNS 设置已更新为 (8.8.8.8, 1.1.1.1)。${NC}"
}

# 检查是否调整过 DNS
dns_check() {
    if grep -q 'nameserver 8.8.8.8' /etc/resolv.conf && grep -q 'nameserver 1.1.1.1' /etc/resolv.conf; then
        echo -e "${CYAN}DNS 已设置为 (8.8.8.8, 1.1.1.1)，跳过设置。${NC}"
    else
        adjust_dns
    fi
}

# 执行 DNS 检查和调整
dns_check

# 检查和设置虚拟内存（Swap）
check_and_setup_swap() {
    swap_file="/swapfile"
    
    # 检查是否已经存在 swap
    if swapon --show | grep -q "$swap_file"; then
        echo -e "${CYAN}Swap 已设置，跳过设置。${NC}"
        return
    fi

    echo -e "${YELLOW}正在设置 Swap...${NC}"
    
    # 创建一个1GB的交换文件
    sudo fallocate -l 1G "$swap_file" || sudo dd if=/dev/zero of="$swap_file" bs=1G count=1
    sudo chmod 600 "$swap_file"
    sudo mkswap "$swap_file"
    sudo swapon "$swap_file"

    # 更新 /etc/fstab 以在重启时自动挂载 swap
    echo "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab

    echo -e "${CYAN}Swap 已设置为 1024MB。${NC}"
}

# 执行虚拟内存检查和设置
check_and_setup_swap

# 设置时区
set_timezone() {
    echo -e "${YELLOW}设置时区为 Asia/Shanghai...${NC}"
    timedatectl set-timezone Asia/Shanghai
    echo -e "${CYAN}时区已设置为 Asia/Shanghai。${NC}"
}

# 检查时区是否已经是 Asia/Shanghai
timezone_check() {
    current_timezone=$(timedatectl | grep "Time zone" | awk '{print $3}')
    if [ "$current_timezone" == "Asia/Shanghai" ]; then
        echo -e "${CYAN}时区已设置为 Asia/Shanghai，跳过设置。${NC}"
    else
        set_timezone
    fi
}

# 执行时区检查和设置
timezone_check

echo -e "${CYAN}所有步骤完成！${NC}"
