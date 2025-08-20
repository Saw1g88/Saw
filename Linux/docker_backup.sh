#!/bin/bash

# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 发送Telegram通知的函数
send_notification() {
    local status=$1
    local message=$2
    local icon="❌"
    
    if [ "$status" = "success" ]; then
        icon="✅"
    fi
    
    # 构建消息，使用实际换行符
    local telegram_message="*[$BACKUP_NAME | Rclone]*
$icon $message
时间：$(date "+%Y年%m月%d日 %H:%M:%S")"
    
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode="Markdown" \
        -d text="$telegram_message" > /dev/null
}

# 错误退出函数
error_exit() {
    echo -e "${RED}错误：$1${NC}"
    send_notification "error" "$1"
    docker compose down 2>/dev/null
    exit 1
}

# 加载环境变量
[ ! -f .env ] && error_exit ".env 文件不存在"
source .env

# 检查必要变量
required_vars=("BACKUP_SRC" "BACKUP_PATH" "BACKUP_NAME" "BOT_TOKEN" "CHAT_ID")
for var in "${required_vars[@]}"; do
    [ -z "${!var}" ] && error_exit ".env 文件中缺少变量: $var"
done

# 定义变量
BACKUP_DEST="onedrive:$BACKUP_PATH"
timestamp=$(date +%Y%m%d%H%M%S)
backup_file="backup${timestamp}.tar.gz"

# 启动容器
echo -e "${GREEN}正在启动 rclone 容器...${NC}"
docker compose up -d rclone || error_exit "Rclone 容器启动失败"

# 创建备份包
echo -e "${GREEN}正在创建备份包...${NC}"
docker exec rclone sh -c "cd $BACKUP_SRC && tar czf /tmp/$backup_file --exclude=/tmp/backup*.tar.gz ." || error_exit "打包失败"

# 上传备份
echo -e "${GREEN}正在上传备份文件...${NC}"
docker exec rclone sh -c "rclone copy /tmp/$backup_file $BACKUP_DEST/ --progress" || error_exit "rclone 上传失败"

# 验证上传
echo -e "${GREEN}正在验证上传文件...${NC}"
docker exec rclone sh -c "rclone ls $BACKUP_DEST/$backup_file" || error_exit "上传验证失败！文件未找到"

# 清理临时文件
docker exec rclone sh -c "rm /tmp/$backup_file"

# 停止容器
echo -e "${GREEN}正在停止容器...${NC}"
docker compose down

# 成功通知
echo -e "${GREEN}备份成功！备份文件：$backup_file${NC}"
send_notification "success" "容器备份成功！
文件：$backup_file"
