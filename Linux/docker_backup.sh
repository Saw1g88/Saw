#!/bin/bash
# 定义颜色变量
YELLOW='\033[1;33m'
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 服务器标识确认函数
confirm_server_id() {
    while true; do
        # 交互式获取服务器标识
        read -p "请输入服务器标识(例如: oracle): " SERVER_ID
        
        if [ -z "$SERVER_ID" ]; then
            echo -e "${RED}服务器标识不能为空，请重新输入。${NC}"
            continue
        fi
        
        # 确认服务器标识
        printf "您输入的服务器标识是 ${YELLOW}%s${NC}，是否确认？(1: 确认，2: 重新输入): " "$SERVER_ID"
        read confirm
        
        case $confirm in
            1)
                echo -e "${GREEN}服务器标识已确认。${NC}"
                break  # 修改为break，确保可以继续执行后续脚本
                ;;
            2)
                echo "请重新输入服务器标识。"
                continue
                ;;
            *)
                echo -e "${RED}无效的选择，请输入 1 或 2。${NC}"
                ;;
        esac
    done
}

# 调用服务器标识确认函数
confirm_server_id

# 备份脚本路径
BACKUP_SCRIPT="/root/docker_backup.sh"

# 创建备份脚本
cat > "$BACKUP_SCRIPT" << EOF
#!/bin/bash
# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 定义变量
backup_src="/opt/docker"
backup_dest="onedrive:vps/${SERVER_ID}/docker"
timestamp=\$(date +%Y%m%d_%H%M%S)

# 在容器内执行备份操作
docker exec rclone /bin/sh -c "\
    cd / && \
    tar czvf /tmp/backup_\${timestamp}.tar.gz \$backup_src && \
    rclone copy /tmp/backup_\${timestamp}.tar.gz \$backup_dest && \
    rm /tmp/backup_\${timestamp}.tar.gz"

# 检查执行结果
if [ \$? -eq 0 ]; then
    echo -e "\${GREEN}备份成功！备份文件：backup_\${timestamp}.tar.gz\${NC}"
else
    echo -e "\${RED}备份失败！请检查错误信息。\${NC}"
fi
EOF

# 赋予脚本执行权限
chmod +x "$BACKUP_SCRIPT"

# 安装完成提示
echo -e "${GREEN}
---------------------------------------
Docker 备份脚本安装完成！
脚本路径：$BACKUP_SCRIPT
服务器标识：$SERVER_ID

使用说明：
1. 确保已配置 rclone 容器
2. 检查 /opt/docker 目录是否正确
3. 可使用 $BACKUP_SCRIPT 手动触发备份

祝您使用愉快！
---------------------------------------
${NC}"
