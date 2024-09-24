#!/bin/bash

# 需要放行的 SSH 端口号
SSH_PORT=2233

# 检查是否已安装 UFW
if ! command -v ufw &> /dev/null; then
    echo "UFW 未安装，正在安装..."
    sudo apt-get update && sudo apt-get install -y ufw
else
    echo "UFW 已安装，跳过安装。"
fi

# 检查 UFW 是否已启用 SSH 端口
if sudo ufw status | grep -q "$SSH_PORT"; then
    echo "SSH 端口 $SSH_PORT 已放行"
else
    echo "放行 SSH 端口 $SSH_PORT..."
    sudo ufw allow "$SSH_PORT"
fi

# 检查 UFW 是否已启用
if sudo ufw status | grep -q "Status: active"; then
    echo "UFW 已启用"
else
    echo "启用 UFW 并设置开机自启..."
    sudo ufw enable
    sudo systemctl enable ufw
fi

# 查看 UFW 状态
echo "当前 UFW 状态："
sudo ufw status
