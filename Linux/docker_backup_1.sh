#!/bin/bash
# 定义颜色变量
YELLOW='\033[1;33m'
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 备份名称确认函数（兼作服务器标识）
confirm_backup_name() {
    while true; do
        read -p "请输入备份实例名称(例如: oracle, aws, vultr): " BACKUP_NAME
        if [ -z "$BACKUP_NAME" ]; then
            echo -e "${RED}备份实例名称不能为空，请重新输入。${NC}"
            continue
        fi
        printf "您输入的备份实例名称是 ${YELLOW}%s${NC}，是否确认？(1: 确认，2: 重新输入): " "$BACKUP_NAME"
        read confirm
        case $confirm in
            1) break ;;
            2) continue ;;
            *) echo -e "${RED}无效的选择，请输入 1 或 2。${NC}" ;;
        esac
    done
}

# Telegram Bot Token 确认函数
confirm_bot_token() {
    while true; do
        read -p "请输入 Telegram Bot Token: " BOT_TOKEN
        if [ -z "$BOT_TOKEN" ]; then
            echo -e "${RED}Bot Token 不能为空，请重新输入。${NC}"
            continue
        fi
        printf "您输入的 Bot Token 是 ${YELLOW}%s${NC}，是否确认？(1: 确认，2: 重新输入): " "$BOT_TOKEN"
        read confirm
        case $confirm in
            1) break ;;
            2) continue ;;
            *) echo -e "${RED}无效的选择，请输入 1 或 2。${NC}" ;;
        esac
    done
}

# Telegram Chat ID 确认函数
confirm_chat_id() {
    while true; do
        read -p "请输入 Telegram Chat ID: " CHAT_ID
        if [ -z "$CHAT_ID" ]; then
            echo -e "${RED}Chat ID 不能为空，请重新输入。${NC}"
            continue
        fi
        printf "您输入的 Chat ID 是 ${YELLOW}%s${NC}，是否确认？(1: 确认，2: 重新输入): " "$CHAT_ID"
        read confirm
        case $confirm in
            1) break ;;
            2) continue ;;
            *) echo -e "${RED}无效的选择，请输入 1 或 2。${NC}" ;;
        esac
    done
}

# 调用确认函数
confirm_backup_name
confirm_bot_token
confirm_chat_id

# 备份脚本路径
BACKUP_SCRIPT="/root/docker_backup.sh"

# 创建备份脚本
if cat > "$BACKUP_SCRIPT" << EOF
#!/bin/bash
# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 定义变量
backup_src="/opt/docker"
backup_dest="onedrive:vps/${BACKUP_NAME}/docker"
timestamp=\$(date +%Y%m%d%H%M%S)
BACKUP_NAME="${BACKUP_NAME}"
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

# 在容器内执行备份操作
docker exec rclone /bin/sh -c "\
    cd / && \
    tar czvf /tmp/backup_\${timestamp}.tar.gz \${backup_src} && \
    rclone copy /tmp/backup_\${timestamp}.tar.gz \${backup_dest} && \
    rm /tmp/backup_\${timestamp}.tar.gz"

# 检查执行结果并发送 Telegram 通知
if [ \$? -eq 0 ]; then
    echo -e "\${GREEN}备份成功！备份文件：backup_\${timestamp}.tar.gz\${NC}"
    MESSAGE="\${BACKUP_NAME} 备份成功！备份文件：backup_\${timestamp}.tar.gz 时间: \$(date)"
    curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \\
        -d chat_id="\${CHAT_ID}" \\
        -d text="\${MESSAGE}"
else
    echo -e "\${RED}备份失败！请检查错误信息。\${NC}"
    MESSAGE="\${BACKUP_NAME} 备份失败！请检查错误信息。时间: \$(date)"
    curl -s -X POST "https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage" \\
        -d chat_id="\${CHAT_ID}" \\
        -d text="\${MESSAGE}"
fi
EOF
then
    echo -e "${GREEN}备份脚本创建完成！${NC}"
else
    echo -e "${RED}错误：备份脚本创建失败！${NC}"
    exit 1
fi

# 为备份脚本添加可执行权限
chmod +x "$BACKUP_SCRIPT" && echo -e "${GREEN}已添加可执行权限：$BACKUP_SCRIPT${NC}" || {
    echo -e "${RED}错误：无法添加可执行权限！${NC}"
    exit 1
}
