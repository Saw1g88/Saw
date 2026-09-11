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

    [ ! -f .env ] && error_exit "未找到 .env 文件"

    source .env

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

    mkdir -p error

    SYNC_DESCRIPTION=$(get_sync_description)
}


# ============================================================
# 运行同步任务
#
# 注意：不能只看 docker compose run 的退出码来判断成功/失败——
# 单条活动同步失败时（比如 COROS token 失效导致某条导入失败），
# 进程本身仍然会正常 exit 0（失败的活动标记为未同步，下次自动
# 重试，不会因为一条失败就让整个任务报异常退出）。真正有没有
# 失败要从日志里"成功: N / 失败: N"这一行解析出来
#
# 注意：docker compose run --rm "$CONTAINER_NAME" 里的
# $CONTAINER_NAME 传的是 docker-compose.yml 里的 service 名，
# 要跟 .env 里 CONTAINER_NAME 的值对上（也就是 compose 文件里
# 那个固定的 "garmin-coros-sync"），跑哪个方向由同一个 .env
# 里的 SYNC_COMMAND 决定
# ============================================================

run_sync_task() {

    local log_file="error/${CONTAINER_NAME}_$(date '+%Y%m%d_%H%M%S').log"

    echo -e "${GREEN}开始运行 Garmin Coros Sync${SYNC_DESCRIPTION}...${NC}"

    docker rm -f "$CONTAINER_NAME" 2>/dev/null

    # 用 tee 把输出同时打到屏幕（方便你直接在 VPS 上盯着看进度）和日志文件；
    # 用 PIPESTATUS[0] 拿 docker 命令本身的退出码，而不是 tee 的（管道里 $? 默认是最后一个命令的）
    docker compose run --rm "$CONTAINER_NAME" 2>&1 | tee "$log_file"
    local exit_code=${PIPESTATUS[0]}

    local failed_count
    failed_count=$(grep -o '失败: [0-9]*' "$log_file" | tail -n 1 | grep -o '[0-9]*')

    if [ "$exit_code" -ne 0 ]; then

        echo -e "${RED}同步异常${SYNC_DESCRIPTION}${NC}"

        send_notification \
            "error" \
            "同步异常${SYNC_DESCRIPTION}
日志文件：$log_file"

        return 1

    elif [ -n "$failed_count" ] && [ "$failed_count" -gt 0 ]; then

        echo -e "${RED}同步存在失败项${SYNC_DESCRIPTION}（失败 ${failed_count} 条）${NC}"

        send_notification \
            "error" \
            "同步存在失败项${SYNC_DESCRIPTION}
失败 ${failed_count} 条，详情见：$log_file"

        return 1

    else

        echo -e "${GREEN}数据同步完成${SYNC_DESCRIPTION}${NC}"

        send_notification \
            "success" \
            "数据同步完成${SYNC_DESCRIPTION}"

        rm -f "$log_file"

        return 0

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
