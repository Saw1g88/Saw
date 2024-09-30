#!/bin/bash

# 需要放行的 SSH 端口号
SSH_PORT=2233

# 定义颜色
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # 无颜色

# 检查是否已安装 UFW
if ! command -v ufw &> /dev/null; then
    echo -e "${YELLOW}UFW 未安装，正在安装...${NC}"
    sudo apt-get update && sudo apt-get install -y ufw
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
