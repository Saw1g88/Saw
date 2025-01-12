#!/bin/bash

# 定义颜色
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m' # 重置颜色

# 确保以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}请以 root 权限运行此脚本。${NC}"
   exit 1
fi

# 检查 fail2ban 是否已安装且正在运行
if command -v fail2ban-client &> /dev/null; then
    if systemctl is-active --quiet fail2ban; then
        echo -e "${YELLOW}fail2ban 已安装且正在运行，无需重复配置。${NC}"
        exit 0
    fi
fi

# 更新系统并安装 fail2ban
echo -e "${YELLOW}正在安装 fail2ban...${NC}"
apt update
apt install fail2ban -y

# 提示用户输入 SSH 端口，默认 2233
read -p "请输入需要保护的 SSH 端口 (回车默认 2233): " ssh_port
ssh_port=${ssh_port:-2233}

# 备份原始配置文件（仅在不存在 jail.local 时执行）
if [ ! -f /etc/fail2ban/jail.local ]; then
    echo -e "${YELLOW}备份原始 fail2ban 配置...${NC}"
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
fi

# 写入 fail2ban 配置文件
echo -e "${YELLOW}配置 fail2ban 以保护 SSH 端口 ${ssh_port}...${NC}"
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
backend = systemd
port = ${ssh_port}
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

# 防火墙设置 (如使用 ufw)
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}检测到 ufw，开放端口 ${ssh_port}...${NC}"
    ufw allow ${ssh_port}/tcp
    ufw reload
fi

# 验证 fail2ban 是否已生效
echo -e "${YELLOW}fail2ban 规则检查：${NC}"
fail2ban-client status sshd

# 完成
echo -e "${GREEN}fail2ban 已成功安装并保护端口 ${ssh_port}。${NC}"
