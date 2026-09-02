#!/bin/bash

# ============================================================
# Garmin Coros Sync
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'


# ============================================================
# 发送 Telegram 通知
# ============================================================

send_notification() {
    local status=$1
    local message=$2
    local icon="❌"

    if [ "$status" = "success" ]; then
        icon="✅"
    fi

    local telegram_message="*[$SERVER_NAME | Garmin Coros Sync]*
$icon $message"

    curl -s -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode chat_id="$CHAT_ID" \
        --data-urlencode parse_mode="Markdown" \
        --data-urlencode text="$telegram_message" \
        > /dev/null
}


# ============================================================
# 错误退出
# ============================================================

error_exit() {
    echo -e "${RED}错误：$1${NC}"
    exit 1
}


# ============================================================
# 根据 SYNC_COMMAND 生成通知里用的方向描述
#
# 不需要额外维护 SYNC_DIRECTION 变量——直接从实际要跑的命令里
# 识别方向，两者不会对不上；识别不出来的命令就直接把命令本身
# 当描述用，不会报错
# ============================================================

get_sync_description() {
    case "$SYNC_COMMAND" in
        *sync_garmin_to_coros*)
            echo "（Garmin → Coros）"
            ;;
        *sync_coros_to_garmin*)
            echo "（Coros → Garmin）"
            ;;
        *)
            echo "（${SYNC_COMMAND}）"
            ;;
    esac
}


# ============================================================
# 初始化环境
# ============================================================

init_environment() {

    # --------------------------------------------------------
    # 加载 .env
    # --------------------------------------------------------

    [ ! -f .env ] && error_exit "未找到 .env 文件"

    source .env


    # --------------------------------------------------------
    # 检查必要变量
    # --------------------------------------------------------

    local required_vars=(
        "CONTAINER_NAME"
        "SYNC_COMMAND"
        "BOT_TOKEN"
        "CHAT_ID"
        "SERVER_NAME"
    )

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error_exit "请在 .env 中设置 $var"
        fi
    done


    # --------------------------------------------------------
    # 创建日志目录
    # --------------------------------------------------------

    mkdir -p error


    # --------------------------------------------------------
    # 通知文案里用的同步方向描述
    # --------------------------------------------------------

    SYNC_DESCRIPTION=$(get_sync_description)
}


# ============================================================
# 运行同步任务
#
# 只根据 Docker 返回码判断成功/失败
#
# 0     = 成功
# 非 0  = 异常
#
# 有没有新数据都算同步完成
#
# 注意：docker compose run --rm "$CONTAINER_NAME" 里的
# $CONTAINER_NAME 传的是 docker-compose.yml 里的 service 名，
# 要跟 .env 里 CONTAINER_NAME 的值对上（也就是 compose 文件里
# 那个固定的 "garmin-coros-sync"），跑哪个方向由同一个 .env
# 里的 SYNC_COMMAND 决定
# ============================================================

run_sync_task() {

    local log_file="error/${CONTAINER_NAME}_$(date '+%Y%m%d_%H%M%S').log"

    echo -e "${GREEN}开始运行 Garmin Sync COROS${SYNC_DESCRIPTION}...${NC}"

    docker rm -f "$CONTAINER_NAME" 2>/dev/null

    if docker compose run --rm "$CONTAINER_NAME" \
        > "$log_file" 2>&1; then

        echo -e "${GREEN}数据同步完成${SYNC_DESCRIPTION}${NC}"

        send_notification \
            "success" \
            "数据同步完成${SYNC_DESCRIPTION}"

        rm -f "$log_file"

        return 0

    else

        echo -e "${RED}同步异常${SYNC_DESCRIPTION}${NC}"

        send_notification \
            "error" \
            "同步异常${SYNC_DESCRIPTION}
日志文件：$log_file"

        return 1
    fi
}


# ============================================================
# 主函数
# ============================================================

main() {

    init_environment
    run_sync_task
}


# ============================================================
# 执行
# ============================================================

main "$@"
