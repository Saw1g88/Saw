#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

main_menu() {
    clear
    echo -e "${GREEN}UFW 防火墙管理脚本${NC}"
    echo "1. 放行端口"
    echo "2. 删除端口"
    echo "3. 查看状态"
    echo "0. 退出"
    read -p "请选择操作: " choice
    case $choice in
        1) allow_port ;;
        2) delete_port ;;
        3) check_status ;;
        0) exit 0 ;;
        *) echo "无效选项！"; sleep 2; main_menu ;;
    esac
}

allow_port() {
    read -p "请输入要放行的端口号: " port
    sudo ufw allow $port
    echo -e "${GREEN}已放行 $port 端口${NC}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

delete_port() {
    read -p "请输入要删除的端口号: " port
    sudo ufw delete allow $port
    echo -e "${RED}已删除 $port 端口${NC}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

check_status() {
    sudo ufw status
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 检查并添加别名
if ! grep -q "alias u='$0'" ~/.bashrc; then
    echo "alias u='$0'" >> ~/.bashrc
    source ~/.bashrc
fi

# 启动主菜单
main_menu
