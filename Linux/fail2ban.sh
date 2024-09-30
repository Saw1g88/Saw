#!/bin/bash

# 定义颜色
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # 无颜色

# 检查fail2ban是否已经安装
if ! command -v fail2ban-client &> /dev/null; then
    echo -e "${YELLOW}fail2ban 未安装，正在安装...${NC}"
    sudo apt update
    sudo apt install -y fail2ban
else
    echo -e "${YELLOW}fail2ban 已安装，跳过安装。${NC}"
fi

# 备份原始配置文件
if [ ! -f /etc/fail2ban/jail.local ]; then
    echo -e "${YELLOW}正在创建 jail.local 配置文件...${NC}"
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
else
    echo -e "${YELLOW}jail.local 配置文件已经存在，跳过创建。${NC}"
fi

# 修改SSH端口配置为2233
echo -e "${YELLOW}正在配置 fail2ban 以保护 SSH 端口 2233...${NC}"

# 检查并更新jail.local文件中的sshd部分
sudo sed -i '/^\[sshd\]/,/^\[/{s/^enabled.*/enabled = true/; s/^port.*/port = 2233/; s/^maxretry.*/maxretry = 5/}' /etc/fail2ban/jail.local

# 确保日志路径配置正确
sudo sed -i '/^\[sshd\]/,/^\[/{s|^logpath.*|logpath = /var/log/auth.log|}' /etc/fail2ban/jail.local

# 启动并启用fail2ban服务
echo -e "${YELLOW}启动并启用 fail2ban 服务...${NC}"
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# 检查fail2ban状态
echo -e "${YELLOW}fail2ban 服务状态：${NC}"
sudo fail2ban-client status

# 输出最终配置状态
echo -e "${CYAN}SSH保护已配置，端口为2233，最大失败尝试为5次。${NC}"
