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
 
    local telegram_message="*[$SERVER_NAME | Garmin Sync]*
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
            echo "（国际 → 中国，仅活动数据）" ;;
        "yarn sync_global")
            echo "（中国 → 国际，仅活动数据）" ;;
        "yarn sync_all_cn_to_global")
            echo "（中国 → 国际，活动数据 + Wellness）" ;;
        "yarn sync_all_global_to_cn")
            echo "（国际 → 中国，活动数据 + Wellness）" ;;
        "yarn sync_wellness_cn_to_global")
            echo "（中国 → 国际，仅 Wellness）" ;;
        "yarn sync_wellness_global_to_cn")
            echo "（国际 → 中国，仅 Wellness）" ;;
        "yarn migrate_garmin_cn_to_global")
            echo "（中国 → 国际，历史数据迁移）" ;;
        "yarn migrate_garmin_global_to_cn")
            echo "（国际 → 中国，历史数据迁移）" ;;
        "yarn migrate_all_cn_to_global")
            echo "（中国 → 国际，历史数据 + Wellness 迁移）" ;;
        "yarn migrate_all_global_to_cn")
            echo "（国际 → 中国，历史数据 + Wellness 迁移）" ;;
        "yarn migrate_wellness_cn_to_global")
            echo "（中国 → 国际，历史 Wellness 迁移）" ;;
        "yarn migrate_wellness_global_to_cn")
            echo "（国际 → 中国，历史 Wellness 迁移）" ;;
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
    mkdir -p log
 
    # 设置同步方向
    SYNC_DIRECTION=$(get_sync_direction)
}
 
# 清理旧日志：只保留最新的 N 个日志文件，其余删除
cleanup_logs() {
    local keep_count=3
    local log_dir="log"
 
    # 按修改时间从新到旧排序，跳过前 keep_count 个，其余的删掉
    # -mindepth/-maxdepth 1 避免误处理子目录；只处理普通文件
    mapfile -d '' -t old_logs < <(
        find "$log_dir" -maxdepth 1 -type f -printf '%T@ %p\0' \
            | sort -znr -k1,1 \
            | cut -z -d' ' -f2- \
            | tail -z -n +"$((keep_count + 1))"
    )
 
    if [ "${#old_logs[@]}" -gt 0 ]; then
        rm -f -- "${old_logs[@]}"
        echo -e "${GREEN}已清理 ${#old_logs[@]} 个旧日志文件，仅保留最新 ${keep_count} 个${NC}"
    fi
}
 
# 运行同步任务
run_sync_task() {
    local log_file="log/${CONTAINER_NAME}_$(date '+%Y%m%d_%H%M%S').log"
 
    echo -e "${GREEN}开始运行 Garmin 同步任务${SYNC_DIRECTION}...${NC}"
 
    # 兜底清理同名残留容器
    docker rm -f "$CONTAINER_NAME" 2>/dev/null
 
    # 用 tee 把输出同时打到屏幕（方便直接在 VPS 上盯着看进度）和日志文件；
    # 用 PIPESTATUS[0] 拿 docker 命令本身的退出码，而不是 tee 的
    docker compose run --rm "$CONTAINER_NAME" 2>&1 | tee "$log_file"
    local exit_code=${PIPESTATUS[0]}
 
    # 不能只看最后一行有没有 "Done"——那只是 yarn 命令跑完固定打印的收尾提示
    # （"Done in Xs."），跟这次同步里每一天 wellness 数据有没有真的传成功没有
    # 必然关系：只要 yarn 进程没崩溃退出，就会打印这行，哪怕中间某一天真的
    # 有失败也一样。真正的结果要看日志里每一行
    # "sync <日期> done, total=X, uploaded=Y, duplicate=Z, failed=N"
    # 里的 failed 字段（duplicate 是正常重复跳过，不算失败），把所有天数的
    # failed 加总，才是这次运行真正失败了多少条
    local total_failed=0
    while IFS= read -r n; do
        total_failed=$((total_failed + n))
    done < <(grep -o 'failed=[0-9]*' "$log_file" | grep -o '[0-9]*')
 
    # 无论本次同步成功与否，都清理旧日志，只保留最新的几个
    cleanup_logs
 
    if [ "$exit_code" -ne 0 ]; then
        # Docker 命令本身执行失败
        echo -e "${RED}Docker 容器启动或执行失败${NC}"
        send_notification "error" "Docker 容器启动或执行失败${SYNC_DIRECTION}
日志文件：$log_file"
        return 1
 
    elif [ "$total_failed" -gt 0 ]; then
        # 进程正常跑完，但里面有真正失败（非重复）的条目
        echo -e "${RED}数据同步存在失败项${SYNC_DIRECTION}（失败 ${total_failed} 条）${NC}"
        send_notification "error" "数据同步存在失败项${SYNC_DIRECTION}
失败 ${total_failed} 条，详情见：$log_file"
        return 1
 
    else
        # 同步成功
        echo -e "${GREEN}数据同步完成${SYNC_DIRECTION}${NC}"
        send_notification "success" "数据同步完成${SYNC_DIRECTION}"
        # 日志始终保留，方便随时查看，不删除
        return 0
    fi
}
 
# 主函数
main() {
    init_environment
    run_sync_task
}
 
main "$@"
