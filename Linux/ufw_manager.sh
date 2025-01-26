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
    echo -e "${YELLOW}UFW 防火墙管理脚本${NC}"
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

# 放行端口
allow_port() {
    check_ufw_enabled
    while true; do
        read -p "请输入要放行的端口号(0返回主菜单): " port
        if [ "$port" = "0" ]; then
            main_menu
            return
        fi
        if [[ "$port" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            if sudo ufw allow "$port"; then
                echo -e "${GREEN}已放行 $port 端口${NC}"
                read -n 1 -s -r -p "按任意键返回主菜单..."
                main_menu
                return
            else
                echo -e "${RED}放行 $port 端口失败！${NC}"
            fi
        else
            echo -e "${RED}输入的端口号无效！${NC}"
        fi
    done
}

# 删除端口
delete_port() {
    check_ufw_enabled
    while true; do
        read -p "请输入要删除的端口号(0返回主菜单): " port
        if [ "$port" = "0" ]; then
            main_menu
            return
        fi
        if [[ "$port" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            if sudo ufw delete allow "$port"; then
                echo -e "${RED}已删除 $port 端口${NC}"
                read -n 1 -s -r -p "按任意键返回主菜单..."
                main_menu
                return
            else
                echo -e "${RED}删除 $port 端口失败！${NC}"
            fi
        else
            echo -e "${RED}输入的端口号无效！${NC}"
        fi
    done
}

# 查看 UFW 状态
check_status() {
    check_ufw_enabled
    sudo ufw status
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}

# 安装完成提示
installation_complete() {
    # 清屏并显示提示
    clear
    echo -e "${GREEN}安装和配置已完成！${NC}"
    echo -e "${YELLOW}您可以通过运行脚本来管理 UFW 防火墙。${NC}"
    echo -e "${YELLOW}感谢使用！${NC}"
    # 等待用户输入
    read -n 1 -s -r -p "按任意键进入主菜单..."
    echo "进入主菜单"
}

# 调试信息：显示是否进入安装完成提示
echo "脚本开始执行"

# 执行安装完成提示
installation_complete

# 调试信息：确认提示是否结束，开始主菜单
echo "提示结束，进入主菜单"
main_menu
