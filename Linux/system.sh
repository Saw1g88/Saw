#!/bin/bash

# 检测并安装所需的指令
check_and_install() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 未安装，正在安装..."
        apt-get install -y $1
    else
        echo "$1 已安装，跳过安装。"
    fi
}

# 更新系统
echo "更新系统..."
apt-get update && apt-get full-upgrade -y

# 安装必要的工具
check_and_install jq
check_and_install wget
check_and_install dnsutils

# 安装 Docker
echo "安装 Docker..."
wget -qO- https://get.docker.com | bash -s docker

# 开启 TCP Fast Open (TFO)
echo "开启 TCP Fast Open (TFO)..."
echo "3" > /proc/sys/net/ipv4/tcp_fastopen
echo "net.ipv4.tcp_fastopen=3" > /etc/sysctl.d/30-tcp_fastopen.conf
sysctl --system

# 配置 BBR 和 FQ
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p

# 设置时区
echo "设置时区为 Asia/Shanghai..."
sudo timedatectl set-timezone Asia/Shanghai

echo "所有步骤完成！"
