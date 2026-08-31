#!/bin/bash

# ============================================================
# Garmin Sync COROS
# ============================================================

# 颜色变量
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

    local telegram_message="*[$SERVER_NAME | Garmin Sync COROS]*
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
# 获取同步方向描述
# ============================================================

get_sync_direction() {
    case "$SYNC_DIRECTION" in
        "GARMIN_TO_COROS")
            echo "（Garmin Sync COROS）"
            ;;
        "COROS_TO_GARMIN")
            echo "（COROS Sync Garmin）"
            ;;
        "BIDIRECTIONAL")
            echo "（COROS ↔ Garmin）"
            ;;    
        *)
            echo ""
            ;;
    esac
}


# ============================================================
# 清理 FIT 文件
#
# 每个目录只保留最近 10 个文件
# 按文件修改时间判断新旧
# ============================================================

cleanup_fit_files() {

    local fit_dir=$1
    local keep_num=10

    # 目录不存在则直接跳过
    [ ! -d "$fit_dir" ] && return 0

    # 文件数量
    local file_count
    file_count=$(find "$fit_dir" -maxdepth 1 -type f | wc -l)

    # 不超过 10 个，不需要清理
    if [ "$file_count" -le "$keep_num" ]; then
        return 0
    fi

    echo "清理 FIT 文件：$fit_dir"

    # 按修改时间从新到旧排序
    # 删除第 11 个以及更旧的文件
    find "$fit_dir" \
        -maxdepth 1 \
        -type f \
        -printf '%T@ %p\n' |
        sort -nr |
        tail -n +$((keep_num + 1)) |
        cut -d' ' -f2- |
        while IFS= read -r file; do

            if [ -n "$file" ] && [ -f "$file" ]; then
                echo "删除：$file"
                rm -f "$file"
            fi

        done
}


# ============================================================
# 清理所有 FIT 文件
# ============================================================

cleanup_all_fit_files() {

    echo "检查 FIT 文件..."

    cleanup_fit_files "data/garmin-fit"
    cleanup_fit_files "data/coros-fit"

    echo "FIT 文件清理完成"
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
        "BOT_TOKEN"
        "CHAT_ID"
        "SERVER_NAME"
        "SYNC_DIRECTION"
    )

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error_exit "请在 .env 中设置 $var"
        fi
    done


    # --------------------------------------------------------
    # 检查同步方向
    # --------------------------------------------------------

    case "$SYNC_DIRECTION" in
        "GARMIN_TO_COROS")
            ;;
        "COROS_TO_GARMIN")
            ;;
        "BIDIRECTIONAL")
            ;;    
        *)
            error_exit "SYNC_DIRECTION 设置错误：$SYNC_DIRECTION"
            ;;
    esac


    # --------------------------------------------------------
    # 创建日志目录
    # --------------------------------------------------------

    mkdir -p error


    # --------------------------------------------------------
    # 获取同步方向描述
    # --------------------------------------------------------

    SYNC_DESCRIPTION=$(get_sync_direction)
}


# ============================================================
# 导出 Garmin Session
# ============================================================

run_export_sessions() {

    local log_file="error/sessions_$(date '+%Y%m%d_%H%M%S').log"

    echo -e "${GREEN}开始导出 Garmin 登录 session...${NC}"


    # --------------------------------------------------------
    # 清理可能残留的容器
    # --------------------------------------------------------

    docker rm -f garmin-sessions 2>/dev/null


    # --------------------------------------------------------
    # 执行 session 导出
    # --------------------------------------------------------

    if docker compose --profile tools run --rm garmin-sessions \
        > "$log_file" 2>&1; then

        echo -e "${GREEN}Session 导出完成${NC}"

        send_notification \
            "success" \
            "Session 导出完成"

        # 正常日志删除
        rm -f "$log_file"

        return 0

    else

        echo -e "${RED}Session 导出失败${NC}"

        send_notification \
            "error" \
            "Session 导出失败
日志文件：$log_file"

        # 异常日志保留
        return 1
    fi
}


# ============================================================
# 运行同步任务
# ============================================================

run_sync_task() {

    local log_file="error/${CONTAINER_NAME}_$(date '+%Y%m%d_%H%M%S').log"

    echo -e "${GREEN}开始运行 Garmin Sync COROS${SYNC_DESCRIPTION}...${NC}"


    # --------------------------------------------------------
    # 清理可能残留的同名容器
    # --------------------------------------------------------

    docker rm -f "$CONTAINER_NAME" 2>/dev/null


    # --------------------------------------------------------
    # 执行同步任务
    #
    # 只根据 Docker 返回码判断成功/失败
    #
    # 0     = 成功
    # 非 0  = 异常
    #
    # 有没有新数据都算同步完成
    # --------------------------------------------------------

    if docker compose run --rm "$CONTAINER_NAME" \
        > "$log_file" 2>&1; then

        echo -e "${GREEN}数据同步完成${SYNC_DESCRIPTION}${NC}"

        send_notification \
            "success" \
            "数据同步完成${SYNC_DESCRIPTION}"

        # 正常日志删除
        rm -f "$log_file"

        return 0

    else

        echo -e "${RED}同步异常${SYNC_DESCRIPTION}${NC}"

        send_notification \
            "error" \
            "同步异常${SYNC_DESCRIPTION}
日志文件：$log_file"

        # 异常日志保留
        return 1
    fi
}


# ============================================================
# 主函数
# ============================================================

main() {

    # 初始化环境
    init_environment


    # --------------------------------------------------------
    # 根据参数决定执行什么
    # --------------------------------------------------------

    case "$1" in

        sessions)

            # 用法：
            # ./garmin-sync.sh sessions

            run_export_sessions
            ;;


        *)

            # 默认执行同步

            run_sync_task
            ;;

    esac


    # --------------------------------------------------------
    # 同步任务结束后清理 FIT 文件
    # --------------------------------------------------------

    cleanup_all_fit_files
}


# ============================================================
# 执行
# ============================================================

main "$@"
