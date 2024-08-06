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

# 内核调优
echo "进行内核调优..."
wget https://raw.githubusercontent.com/Saw1g88/Saw/main/Linux/kernel_optimization.sh
chmod +x kernel_optimization.sh
bash kernel_optimization.sh

# 设置时区
echo "设置时区为 Asia/Shanghai..."
sudo timedatectl set-timezone Asia/Shanghai

# 开启 tuned 并设置网络性能优化
echo "开启 tuned 并设置网络性能优化配置..."
check_and_install tuned
systemctl enable tuned.service
systemctl start tuned.service
tuned-adm profile network-throughput

echo "所有步骤完成！"
