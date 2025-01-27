#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 全局变量
ufw_enabled=false
VALID_PROTOCOLS=("tcp" "udp" "both")

# 检查 UFW 状态
check_ufw_status() {
    if sudo ufw status | grep -q "Status: active"; then
        ufw_enabled=true
        return 0
    else
        ufw_enabled=false
        echo -e "${RED}警告: UFW 未启用！${NC}"
        echo -e "运行 ${YELLOW}sudo ufw enable${NC} 来启用 UFW"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return 1
    fi
}

# 验证端口号
validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

# 验证协议
validate_protocol() {
    local protocol=$1
    for valid_protocol in "${VALID_PROTOCOLS[@]}"; do
        if [ "$protocol" == "$valid_protocol" ]; then
            return 0
        fi
    done
    return 1
}

# 处理端口操作
handle_port() {
    local action="$1"
    local prompt="请输入要${action}的端口号 (0返回主菜单): "
    
    while true; do
        read -p "$prompt" port
        
        if [ "$port" = "0" ]; then
            main_menu
            return
        fi
        
        if ! validate_port "$port"; then
            echo -e "${RED}错误: 端口号必须在 1-65535 之间${NC}"
            continue
        fi
        
        read -p "请选择协议 (tcp/udp/both, 默认为 both): " protocol
        protocol=${protocol:-both}
        
        if ! validate_protocol "$protocol"; then
            echo -e "${RED}错误: 无效的协议！请使用 tcp, udp, 或 both${NC}"
            continue
        fi
        
        if [ "$action" = "allow" ]; then
            if [ "$protocol" = "both" ]; then
                if sudo ufw allow "$port"; then
                    echo -e "${GREEN}成功: 已允许 ${port} 端口 (tcp 和 udp)${NC}"
                    show_current_rules
                else
                    echo -e "${RED}错误: 允许 ${port} 端口失败${NC}"
                fi
            else
                if sudo ufw allow "$port"/"$protocol"; then
                    echo -e "${GREEN}成功: 已允许 ${port} 端口 (${protocol})${NC}"
                    show_current_rules
                else
                    echo -e "${RED}错误: 允许 ${port} 端口失败${NC}"
                fi
            fi
        elif [ "$action" = "delete" ]; then
            local success=false
            
            if [ "$protocol" = "both" ]; then
                # 删除没有协议指定的规则
                printf "y\ny\n" | sudo ufw delete allow "$port" >/dev/null 2>&1
                # 删除 TCP 规则
                printf "y\ny\n" | sudo ufw delete allow "$port"/tcp >/dev/null 2>&1
                # 删除 UDP 规则
                printf "y\ny\n" | sudo ufw delete allow "$port"/udp >/dev/null 2>&1
                
                echo -e "${GREEN}已尝试删除 ${port} 端口的所有规则${NC}"
                success=true
            else
                if printf "y\ny\n" | sudo ufw delete allow "$port"/"$protocol" >/dev/null 2>&1; then
                    echo -e "${GREEN}成功: 已删除 ${port} 端口规则 (${protocol})${NC}"
                    success=true
                else
                    echo -e "${RED}错误: 删除 ${port} 端口规则失败${NC}"
                fi
            fi
            
            if [ "$success" = true ]; then
                show_current_rules
            fi
        fi
        
        read -n 1 -s -r -p "按任意键返回主菜单..."
        main_menu
        return
    done
}

# 显示当前 UFW 规则
show_current_rules() {
    echo -e "\n${YELLOW}当前 UFW 规则:${NC}"
    sudo ufw status numbered
}

# 按规则序号删除
delete_by_rule_number() {
    while true; do
        show_current_rules
        
        read -p "请输入要删除的规则序号 (0返回主菜单): " rule_number
        
        if [ "$rule_number" = "0" ]; then
            main_menu
            return
        fi
        
        if [[ "$rule_number" =~ ^[0-9]+$ ]]; then
            # 修改规则匹配方式
            rule_details=$(sudo ufw status numbered | grep -E "^\[\s*$rule_number\]" || echo "")
            
            if [ -z "$rule_details" ]; then
                echo -e "${RED}错误: 未找到规则 $rule_number${NC}"
            else
                echo -e "将要删除以下规则:"
                echo -e "${YELLOW}$rule_details${NC}"
                read -p "确认删除? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    # 使用 printf 和管道来自动回答所有的确认提示
                    printf "y\ny\n" | sudo ufw delete "$rule_number" >/dev/null 2>&1
                    
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}成功: 已删除规则 $rule_number${NC}"
                    else
                        echo -e "${RED}错误: 删除规则 $rule_number 失败${NC}"
                    fi
                else
                    echo -e "${YELLOW}操作已取消${NC}"
                fi
            fi
        else
            echo -e "${RED}错误: 无效的规则序号${NC}"
        fi
        
        echo -e "\n按任意键继续删除规则，按 0 返回主菜单..."
        read -n 1 key
        if [ "$key" = "0" ]; then
            main_menu
            return
        fi
        # 如果不是按 0，继续循环
        clear
    done
}

# 主菜单
main_menu() {
    clear
    echo -e "${YELLOW}=== UFW 防火墙管理脚本 ===${NC}"
    echo "1. 放行端口"
    echo "2. 删除端口"
    echo "3. 查看状态"
    echo "4. 按规则序号删除"
    echo "0. 退出"
    echo -e "${YELLOW}======================${NC}"
    
    check_ufw_status
    
    read -p "请选择操作: " choice
    case $choice in
        1) handle_port "allow" ;;
        2) handle_port "delete" ;;
        3) show_current_rules; read -n 1 -s -r -p "按任意键返回主菜单..."; main_menu ;;
        4) delete_by_rule_number ;;
        0) echo -e "${GREEN}感谢使用！${NC}"; exit 0 ;;
        *) echo -e "${RED}错误: 无效选项${NC}"; sleep 2; main_menu ;;
    esac
}

# 启动脚本
main_menu
