#!/bin/bash

# 检测并安装所需的指令
check_and_install() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 未安装，正在安装..."
        if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
            apt-get install -y $1
        elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
            yum install -y $1
        else
            echo "不支持的操作系统，无法安装 $1"
            exit 1
        fi
    else
        echo "$1 已安装，跳过安装。"
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
    echo "不支持的操作系统类型: $os"
    exit 1
fi

# 更新系统
echo "更新系统..."
if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
    apt-get update && apt-get full-upgrade -y
elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
    yum update -y
fi

# 安装必要的工具
check_and_install jq
check_and_install wget

# 安装 DNS 工具，根据系统类型选择
if [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
    check_and_install bind9-utils # 在 Debian/Ubuntu 上使用 bind9-utils
elif [[ "$os" == "centos" || "$os" == "rhel" ]]; then
    check_and_install bind-utils # 在 CentOS/RHEL 上使用 bind-utils
fi

# 安装 Docker
if ! command -v docker &> /dev/null; then
    echo "安装 Docker..."
    wget -qO- https://get.docker.com | bash -s docker
else
    echo "Docker 已安装，跳过安装。"
fi

# 开启 TCP Fast Open (TFO)
current_tfo_setting=$(cat /proc/sys/net/ipv4/tcp_fastopen)
if [ "$current_tfo_setting" == "3" ]; then
    echo "TCP Fast Open (TFO) 已开启，跳过。"
else
    echo "开启 TCP Fast Open (TFO)..."
    echo "3" > /proc/sys/net/ipv4/tcp_fastopen
    echo "net.ipv4.tcp_fastopen=3" > /etc/sysctl.d/30-tcp_fastopen.conf
    sysctl --system
fi

# 配置 BBR 和 FQ
current_qdisc=$(sysctl net.core.default_qdisc | awk '{print $3}')
current_congestion_control=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$current_qdisc" == "fq" ] && [ "$current_congestion_control" == "bbr" ]; then
    echo "BBR 和 FQ 已开启，跳过。"
else
    echo "配置 BBR 和 FQ..."
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# 设置时区
echo "设置时区为 Asia/Shanghai..."
timedatectl set-timezone Asia/Shanghai

echo "所有步骤完成！"
