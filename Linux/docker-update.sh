#!/bin/bash
set -e

# 发送 Telegram 通知
send_notification() {
    local status=$1
    local message=$2
    local icon="❌"
    
    case $status in
        "success") icon="✅" ;;
        "warning") icon="⚠️" ;;
        "info") icon="ℹ️" ;;
    esac
    
    local telegram_message="*[$SERVER_NAME | Watchtower]*
$icon $message"
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="$telegram_message" \
        -d parse_mode="Markdown" > /dev/null
}

# 错误退出函数
error_exit() {
    echo "❌ $1"
    send_notification "error" "$1"
    exit 1
}

# 初始化环境
init_environment() {
    # 加载环境变量
    [ ! -f .env ] && error_exit "未找到 .env 文件"
    source .env
    
    # 检查必要变量
    local required_vars=("TELEGRAM_BOT_TOKEN" "TELEGRAM_CHAT_ID" "SERVER_NAME")
    for var in "${required_vars[@]}"; do
        [ -z "${!var}" ] && error_exit "请在 .env 中设置 $var"
    done
    
    # 创建临时日志文件
    WT_LOG=$(mktemp -t watchtower.XXXXXX) || error_exit "无法创建临时日志文件"
    
    # 确保退出时删除临时文件
    trap 'rm -f "$WT_LOG"' EXIT
}

# 检查容器更新情况
check_updates() {
    if grep -qE "Updated=[1-9][0-9]*" "$WT_LOG"; then
        # 提取更新的容器信息
        local updated_info=$(grep -E "Updated=[1-9][0-9]*" "$WT_LOG" | head -1)
        local updated_count=$(echo "$updated_info" | grep -oE "Updated=[0-9]+" | cut -d= -f2)
        
        # 从 Watchtower 日志中提取容器名称
        # 方法1: 从 "Stopping /容器名" 中提取
        UPDATED_CONTAINERS_RAW=$(grep -oE "Stopping /[a-zA-Z0-9_-]+" "$WT_LOG" | sed 's|Stopping /||g' | sort -u)
        
        # 方法2: 如果方法1没找到，尝试从 "Creating /容器名" 中提取
        if [ -z "$UPDATED_CONTAINERS_RAW" ]; then
            UPDATED_CONTAINERS_RAW=$(grep -oE "Creating /[a-zA-Z0-9_-]+" "$WT_LOG" | sed 's|Creating /||g' | sort -u)
        fi
        
        # 方法3: 如果还没找到，尝试从镜像信息中推断
        if [ -z "$UPDATED_CONTAINERS_RAW" ]; then
            UPDATED_CONTAINERS_RAW=$(grep -oE "Found new [a-zA-Z0-9/_.-]+:[a-zA-Z0-9._-]+ image" "$WT_LOG" | sed 's/Found new //g' | sed 's/ image.*//g' | sed 's/.*\///g' | sed 's/:.*//g' | sort -u)
        fi
        
        # 格式化容器列表，每行一个容器，前面加上项目符号
        if [ -n "$UPDATED_CONTAINERS_RAW" ]; then
            UPDATED_CONTAINERS_FORMATTED=$(echo "$UPDATED_CONTAINERS_RAW" | sed 's/^/- /')
            UPDATED_CONTAINERS_LIST=$(echo "$UPDATED_CONTAINERS_RAW" | paste -sd ", " -)
        else
            UPDATED_CONTAINERS_FORMATTED="- 未知"
            UPDATED_CONTAINERS_LIST="未知"
        fi
        
        echo "🔄 检测到 $updated_count 个容器更新: $UPDATED_CONTAINERS_LIST"
        return 0
    else
        echo "✅ 无容器更新"
        return 1
    fi
}

# 重载 Nginx 配置
reload_nginx() {
    # 检查是否需要重载 Nginx
    if [[ "$RELOAD_NGINX" != "true" ]]; then
        echo "ℹ️ 设置为不重载 Nginx，跳过"
        return 0
    fi
    
    # 检查 Nginx 容器名称是否设置
    if [ -z "$NGINX_CONTAINER_NAME" ]; then
        echo "⚠️ 未设置 NGINX_CONTAINER_NAME，跳过重载"
        send_notification "warning" "检测到容器更新，但未设置 NGINX_CONTAINER_NAME
更新的容器:
${UPDATED_CONTAINERS_FORMATTED:-- 未知}"
        return 1
    fi
    
    # 检查容器是否运行
    if ! docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER_NAME}$"; then
        echo "❌ Nginx 容器 ($NGINX_CONTAINER_NAME) 未运行"
        send_notification "warning" "检测到容器更新，但 NGINX 容器未运行
更新的容器:
${UPDATED_CONTAINERS_FORMATTED:-- 未知}"
        return 1
    fi
    
    # 重载配置
    if docker exec "$NGINX_CONTAINER_NAME" nginx -s reload; then
        echo "✅ Nginx ($NGINX_CONTAINER_NAME) 配置已成功重载"
        return 0
    else
        echo "❌ Nginx 重载命令执行失败"
        send_notification "warning" "检测到容器更新，但 NGINX 重载失败
更新的容器:
${UPDATED_CONTAINERS_FORMATTED:-- 未知}"
        return 1
    fi
}

# 运行 Watchtower
run_watchtower() {
    echo "🚀 正在运行 Watchtower..."
    
    if docker compose run --rm watchtower 2>&1 | tee "$WT_LOG"; then
        echo "✅ Watchtower 执行完成"
        return 0
    else
        error_exit "Watchtower 执行失败，请手动检查更新情况"
    fi
}

# 主函数
main() {
    # 初始化环境
    init_environment
    
    # 运行 Watchtower
    run_watchtower
    
    # 检查更新情况
    if check_updates; then
        # 有容器更新
        local nginx_result=""
        local container_info=""
        
        # 添加容器名称信息（每行一个）
        if [ -n "$UPDATED_CONTAINERS_FORMATTED" ]; then
            container_info="
更新的容器:
$UPDATED_CONTAINERS_FORMATTED"
        fi
        
        if reload_nginx; then
            if [[ "$RELOAD_NGINX" == "true" ]]; then
                nginx_result="，NGINX 已重载配置"
            fi
        else
            # Nginx 重载失败的通知已在 reload_nginx 函数中发送
            return
        fi
        
        send_notification "success" "检测到容器更新${nginx_result}${container_info}"
    else
        # 无容器更新
        send_notification "info" "无容器更新，所有服务保持最新状态"
    fi
}

# 执行主函数
main
