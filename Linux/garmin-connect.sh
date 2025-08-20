#!/bin/bash

# 颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 发送 Telegram 通知
send_notification() {
    local status=$1
    local message=$2
    local icon="❌"
    
    if [ "$status" = "success" ]; then
        icon="✅"
    fi
    
    local telegram_message="*[$SERVER_NAME | Garmin Connect]*
$icon $message"
    
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode chat_id="$CHAT_ID" \
        --data-urlencode parse_mode="Markdown" \
        --data-urlencode text="$telegram_message" > /dev/null
}

# 错误退出函数
error_exit() {
    echo -e "${RED}错误：$1${NC}"
    exit 1
}

# 获取同步方向
get_sync_direction() {
    case "$YARN_SYNC" in
        *sync_global*) echo "（国际→中国）" ;;
        *sync_cn*) echo "（中国→国际）" ;;
        *) echo "" ;;
    esac
}

# 初始化环境
init_environment() {
    # 加载环境变量
    [ ! -f .env ] && error_exit "未找到 .env 文件"
    source .env
    
    # 检查必要变量
    local required_vars=("CONTAINER_NAME" "BOT_TOKEN" "CHAT_ID" "SERVER_NAME")
    for var in "${required_vars[@]}"; do
        [ -z "${!var}" ] && error_exit "请在 .env 中设置 $var"
    done
    
    # 创建日志目录
    mkdir -p logs
    
    # 设置同步方向
    SYNC_DIRECTION=$(get_sync_direction)
}

# 运行同步任务
run_sync_task() {
    local log_file="logs/${CONTAINER_NAME}_$(date '+%Y%m%d_%H%M%S').log"
    
    echo -e "${GREEN}开始运行 Garmin 同步任务${SYNC_DIRECTION}...${NC}"
    
    # 启动容器并运行任务，将输出重定向到日志文件
    if docker compose up -d && docker start -a "$CONTAINER_NAME" > "$log_file" 2>&1; then
        local last_line=$(tail -n 1 "$log_file")
        
        if echo "$last_line" | grep -q "Done"; then
            # 同步成功
            echo -e "${GREEN}运动数据同步完成${SYNC_DIRECTION}${NC}"
            send_notification "success" "运动数据同步完成${SYNC_DIRECTION}"
            
            # 成功时删除日志文件（可选）
            rm "$log_file"
            return 0
        else
            # 同步失败（程序执行了但结果不是 Done）
            echo -e "${RED}运动数据同步异常${SYNC_DIRECTION}${NC}"
            send_notification "error" "运动数据同步异常${SYNC_DIRECTION}
日志文件：$log_file"
            return 1
        fi
    else
        # Docker 命令执行失败
        echo -e "${RED}Docker 容器启动或执行失败${NC}"
        send_notification "error" "Docker 容器启动或执行失败${SYNC_DIRECTION}
日志文件：$log_file"
        return 1
    fi
}

# 清理环境
cleanup() {
    echo -e "${GREEN}正在清理容器...${NC}"
    docker compose down > /dev/null 2>&1
}

# 主函数
main() {
    # 初始化环境
    init_environment
    
    # 设置退出时自动清理
    trap cleanup EXIT
    
    # 运行同步任务
    run_sync_task
}

# 执行主函数
main
