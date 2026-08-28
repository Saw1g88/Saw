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

# 获取同步方向和类型描述
get_sync_direction() {
    case "$YARN_SYNC" in
        "yarn sync_cn")
            echo "（国际→中国，仅活动数据）" ;;
        "yarn sync_global")
            echo "（中国→国际，仅活动数据）" ;;
        "yarn sync_all_cn_to_global")
            echo "（中国→国际，活动数据 + Wellness）" ;;
        "yarn sync_all_global_to_cn")
            echo "（国际→中国，活动数据 + Wellness）" ;;
        "yarn sync_wellness_cn_to_global")
            echo "（中国→国际，仅 Wellness）" ;;
        "yarn sync_wellness_global_to_cn")
            echo "（国际→中国，仅 Wellness）" ;;
        "yarn migrate_garmin_cn_to_global")
            echo "（中国→国际，历史数据迁移）" ;;
        "yarn migrate_garmin_global_to_cn")
            echo "（国际→中国，历史数据迁移）" ;;
        "yarn migrate_all_cn_to_global")
            echo "（中国→国际，历史数据 + Wellness 迁移）" ;;
        "yarn migrate_all_global_to_cn")
            echo "（国际→中国，历史数据 + Wellness 迁移）" ;;
        "yarn migrate_wellness_cn_to_global")
            echo "（中国→国际，历史 Wellness 迁移）" ;;
        "yarn migrate_wellness_global_to_cn")
            echo "（国际→中国，历史 Wellness 迁移）" ;;
        *)
            echo "" ;;
    esac
}

# 初始化环境
init_environment() {
    # 加载环境变量
    [ ! -f .env ] && error_exit "未找到 .env 文件"
    source .env

    # 检查必要变量
    local required_vars=("CONTAINER_NAME" "BOT_TOKEN" "CHAT_ID" "SERVER_NAME" "YARN_SYNC")
    for var in "${required_vars[@]}"; do
        [ -z "${!var}" ] && error_exit "请在 .env 中设置 $var"
    done

    # 创建日志目录
    mkdir -p error

    # 设置同步方向
    SYNC_DIRECTION=$(get_sync_direction)
}

# 导出 Garmin 登录 session（对应 compose 里 profiles: tools 的 garmin-sessions 服务）
# 用于首次登录，或者同步任务因 session 失效而报错时手动/自动重新生成
run_export_sessions() {
    local log_file="error/sessions_$(date '+%Y%m%d_%H%M%S').log"

    echo -e "${GREEN}开始导出 Garmin 登录 session...${NC}"

    # 兜底清理同名残留容器，避免 --rm 未及时清理导致命名冲突
    docker rm -f garmin-sessions 2>/dev/null

    # garmin-sessions 服务打了 profiles: tools 标签，不显式激活 profile 的话
    # compose 会把它过滤掉，导致 "no such service" 报错，所以这里必须加 --profile tools
    if docker compose --profile tools run --rm garmin-sessions > "$log_file" 2>&1; then
        echo -e "${GREEN}Session 导出完成${NC}"
        send_notification "success" "Session 导出完成"
        rm "$log_file"
        return 0
    else
        echo -e "${RED}Session 导出失败${NC}"
        send_notification "error" "Session 导出失败
日志文件：$log_file"
        return 1
    fi
}

# 运行同步任务
run_sync_task() {
    local log_file="error/${CONTAINER_NAME}_$(date '+%Y%m%d_%H%M%S').log"

    echo -e "${GREEN}开始运行 Garmin 同步任务${SYNC_DIRECTION}...${NC}"

    # 兜底清理同名残留容器
    docker rm -f "$CONTAINER_NAME" 2>/dev/null

    # 用 run --rm 一次性执行，避免 up -d 与 start -a 重复触发同一次同步
    if docker compose run --rm "$CONTAINER_NAME" > "$log_file" 2>&1; then
        local last_line
        last_line=$(tail -n 1 "$log_file")

        if echo "$last_line" | grep -q "Done"; then
            # 同步成功
            echo -e "${GREEN}数据同步完成${SYNC_DIRECTION}${NC}"
            send_notification "success" "数据同步完成${SYNC_DIRECTION}"
           # 删除 error 日志
           # rm "$log_file"
           # return 0
        else
            # 同步失败（程序执行了但结果不是 Done，可能是 session 失效等原因）
            echo -e "${RED}数据同步异常${SYNC_DIRECTION}${NC}"
            send_notification "error" "数据同步异常${SYNC_DIRECTION}
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

# 主函数
main() {
    init_environment

    case "$1" in
        sessions)
            # 用法：./garmin-sync.sh sessions
            run_export_sessions
            ;;
        *)
            run_sync_task
            ;;
    esac
}

main "$@"
