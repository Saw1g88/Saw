#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查 UFW 是否已启用
check_ufw_enabled() {
    if ! sudo ufw status | grep -q "Status: active"; then
        echo -e "${RED}UFW 未启用，请先启用 UFW！${NC}"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        main_menu
    fi
}

# 主菜单
main_menu() {
    clear
    echo -e "${GREEN}UFW 防火墙管理脚本${NC}"
    echo "1. 放行端口"
    echo "2. 删除端口"
    echo "3. 查看状态"
    echo "4. 添加快捷启动方式"
    echo "5. 移除快捷启动方式"
    echo "0. 退出"
    read -p "请选择操作: " choice
    case $choice in
        1) allow_port ;;
        2) delete_port ;;
        3) check_status ;;
        4) add_alias ;;
        5) remove_alias ;;
        0) exit 0 ;;
        *) echo "无效选项！"; sleep 2; main_menu ;;
    esac
}

# 放行端口
allow_port() {
    check_ufw_enabled
    read -p "请输入要放行的端口号: " port
    if [[ "$port" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        if sudo ufw allow "$port"; then
            echo -e "${GREEN}已放行 $port 端口${NC}"
        else
            echo -e "${RED}放行 $port 端口失败！${NC}"
        fi
    else
        echo -e "${RED}输入的端口号无效！${NC}"
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 删除端口
delete_port() {
    check_ufw_enabled
    read -p "请输入要删除的端口号: " port
    if [[ "$port" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        if sudo ufw delete allow "$port"; then
            echo -e "${RED}已删除 $port 端口${NC}"
        else
            echo -e "${RED}删除 $port 端口失败！${NC}"
        fi
    else
        echo -e "${RED}输入的端口号无效！${NC}"
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 查看 UFW 状态
check_status() {
    check_ufw_enabled
    sudo ufw status
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 添加快捷启动方式
add_alias() {
    read -p "请输入你希望使用的快捷启动方式（例如 u 或 w）: " alias_name
    if [ -z "$alias_name" ]; then
        echo -e "${RED}别名不能为空，请重新输入！${NC}"
        add_alias
        return
    fi

    SCRIPT_PATH=$(readlink -f "$0")
    
    # 如果 alias 已经存在，跳过添加
    if grep -q "alias $alias_name='$SCRIPT_PATH'" ~/.bashrc; then
        echo -e "${YELLOW}快捷启动方式 '$alias_name' 已存在，无需重复添加。${NC}"
    else
        echo "alias $alias_name='$SCRIPT_PATH'" >> ~/.bashrc
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}快捷启动方式 '$alias_name' 已添加。${NC}"
            # 强制刷新 .bashrc 文件使更改生效
            source ~/.bashrc
        else
            echo -e "${RED}添加快捷启动方式失败！${NC}"
        fi
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 移除快捷启动方式
remove_alias() {
    read -p "请输入要移除的快捷启动方式（例如 u 或 w）: " alias_name
    if [ -z "$alias_name" ]; then
        echo -e "${RED}别名不能为空，请重新输入！${NC}"
        remove_alias
        return
    fi

    if grep -q "alias $alias_name=" ~/.bashrc; then
        sed -i "/alias $alias_name=/d" ~/.bashrc
        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}快捷启动方式 '$alias_name' 已移除。${NC}"
            # 强制刷新 .bashrc 文件使更改生效
            source ~/.bashrc
        else
            echo -e "${RED}移除快捷启动方式失败！${NC}"
        fi
    else
        echo -e "${YELLOW}未找到快捷启动方式 '$alias_name'，跳过移除操作。${NC}"
    fi
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 初始化
main_menu
