#!/bin/bash

# 配置变量
DOCKER_DIR="$(pwd)"
CERT_BASE_DIR="$DOCKER_DIR/conf/live"
LOG_FILE="$DOCKER_DIR/logs/certbot-renew/certbot-renew.log"
NGINX_CONTAINER_NAME="nginx"

# 日志函数
log() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
}

# 发送 Telegram 通知
send_notification() {
    local status=$1
    local message=$2
    local icon="❌"
    
    case $status in
        "success") icon="✅" ;;
        "info") icon="🟢" ;;
        "warning") icon="ℹ️" ;;
    esac
    
    local telegram_message="*[$SERVER_NAME | Certbot]*
$icon $message"
    
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$telegram_message" \
        -d parse_mode="Markdown" > /dev/null
}

# 错误退出函数
error_exit() {
    log "错误: $1"
    send_notification "error" "证书更新过程中出现错误: $1
$(get_all_certs_status)
请检查日志获取详细信息。"
    exit 1
}

# 初始化环境
init_environment() {
    # 加载环境变量
    [ -f .env ] && export $(grep -v '^#' .env | xargs)
    
    # 检查必要变量
    [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && error_exit "TELEGRAM_BOT_TOKEN 或 TELEGRAM_CHAT_ID 未设置"
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "开始证书更新流程..."
}

# 获取证书信息 (域名:修改时间:剩余天数)
get_cert_info() {
    local result=""
    
    for domain_dir in $(find "$CERT_BASE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do
        local domain_name=$(basename "$domain_dir")
        local cert_file="$domain_dir/fullchain.pem"
        
        if [ -f "$cert_file" ]; then
            local modified_time=$(stat -c %Y "$cert_file")
            local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
            local expiry_epoch=$(date -d "$expiry_date" +%s)
            local current_epoch=$(date +%s)
            local days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            result="${result}${domain_name}:${modified_time}:${days_remaining}\n"
        fi
    done
    
    echo -e "$result"
}

# 格式化证书状态显示
format_cert_status() {
    local cert_info="$1"
    local result=""
    
    while IFS=: read -r domain modified_time days_remaining; do
        if [[ -n "$domain" && -n "$days_remaining" ]]; then
            result="${result}- \`${domain}\`: 剩余 ${days_remaining} 天
"
        fi
    done < <(echo -e "$cert_info")
    
    echo -n "$result"
}

# 获取所有证书状态
get_all_certs_status() {
    format_cert_status "$(get_cert_info)"
}

# 运行证书更新
renew_certificates() {
    log "运行 certbot 更新证书..."
    
    local current_dir=$(pwd)
    cd "$DOCKER_DIR" || error_exit "无法切换到 Docker 目录"
    
    # 使用 --dry-run 模式检查是否需要更新，然后实际执行
    local output=$(docker compose run --rm certbot certbot renew --non-interactive --agree-tos 2>&1)
    local result=$?
    
    # 将输出写入日志
    echo "$output" >> "$LOG_FILE"
    
    cd "$current_dir" || exit
    
    # 返回输出和结果
    echo "$output"
    return $result
}

# 重载 Nginx 配置
reload_nginx() {
    log "重载 Nginx 配置..."
    
    if docker exec "$NGINX_CONTAINER_NAME" nginx -s reload; then
        log "Nginx 配置重载成功"
        return 0
    else
        log "Nginx 配置重载失败"
        return 1
    fi
}

# 检查是否有证书需要更新（剩余天数 <= 30）
check_if_renewal_needed() {
    local cert_info="$1"
    local renewal_needed=0
    
    while IFS=: read -r domain modified_time days_remaining; do
        if [[ -n "$domain" && -n "$days_remaining" ]]; then
            if [ "$days_remaining" -le 30 ]; then
                log "域名 $domain 需要更新 (剩余 $days_remaining 天)"
                renewal_needed=1
            else
                log "域名 $domain 无需更新 (剩余 $days_remaining 天)"
            fi
        fi
    done < <(echo -e "$cert_info")
    
    return $renewal_needed
}

# 主逻辑
main() {
    # 初始化环境
    init_environment
    
    # 获取当前证书状态
    local current_cert_info=$(get_cert_info)
    local all_certs_status=$(format_cert_status "$current_cert_info")
    
    # 先检查是否有证书需要更新
    check_if_renewal_needed "$current_cert_info"
    local renewal_needed=$?
    
    if [ $renewal_needed -eq 0 ]; then
        log "所有证书都在有效期内，无需更新"
        send_notification "info" "证书无需更新:
$all_certs_status"
        return
    fi
    
    log "检测到有证书需要更新，开始运行 certbot..."
    
    # 运行证书更新并获取输出
    local certbot_output=$(renew_certificates)
    local renew_result=$?
    
    if [ $renew_result -ne 0 ]; then
        error_exit "证书更新过程出错，退出码: $renew_result"
    fi
    
    # 重新获取证书状态
    current_cert_info=$(get_cert_info)
    all_certs_status=$(format_cert_status "$current_cert_info")
    
    # 既然运行了更新且成功了，就重载 nginx
    log "证书更新完成，重载 Nginx 配置"
    
    if reload_nginx; then
        send_notification "success" "证书更新成功, NGINX 已重载配置:
$all_certs_status"
    else
        send_notification "warning" "证书更新成功, NGINX 重载配置失败:
$all_certs_status"
    fi
}

# 执行主逻辑
main#!/bin/bash

# 配置变量
DOCKER_DIR="$(pwd)"
CERT_BASE_DIR="$DOCKER_DIR/conf/live"
LOG_FILE="$DOCKER_DIR/logs/certbot-renew/certbot-renew.log"
NGINX_CONTAINER_NAME="nginx"

# 日志函数
log() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
}

# 发送 Telegram 通知
send_notification() {
    local status=$1
    local message=$2
    local icon="❌"
    
    case $status in
        "success") icon="✅" ;;
        "info") icon="🟢" ;;
        "warning") icon="ℹ️" ;;
    esac
    
    local telegram_message="*[$SERVER_NAME | Certbot]*
$icon $message"
    
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$telegram_message" \
        -d parse_mode="Markdown" > /dev/null
}

# 错误退出函数
error_exit() {
    log "错误: $1"
    send_notification "error" "证书更新过程中出现错误: $1
$(get_all_certs_status)
请检查日志获取详细信息。"
    exit 1
}

# 初始化环境
init_environment() {
    # 加载环境变量
    [ -f .env ] && export $(grep -v '^#' .env | xargs)
    
    # 检查必要变量
    [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && error_exit "TELEGRAM_BOT_TOKEN 或 TELEGRAM_CHAT_ID 未设置"
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "开始证书更新流程..."
}

# 获取证书信息 (域名:修改时间:剩余天数)
get_cert_info() {
    local result=""
    
    for domain_dir in $(find "$CERT_BASE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do
        local domain_name=$(basename "$domain_dir")
        local cert_file="$domain_dir/fullchain.pem"
        
        if [ -f "$cert_file" ]; then
            local modified_time=$(stat -c %Y "$cert_file")
            local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
            local expiry_epoch=$(date -d "$expiry_date" +%s)
            local current_epoch=$(date +%s)
            local days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            result="${result}${domain_name}:${modified_time}:${days_remaining}\n"
        fi
    done
    
    echo -e "$result"
}

# 格式化证书状态显示
format_cert_status() {
    local cert_info="$1"
    local result=""
    
    while IFS=: read -r domain modified_time days_remaining; do
        if [[ -n "$domain" && -n "$days_remaining" ]]; then
            result="${result}- \`${domain}\`: 剩余 ${days_remaining} 天
"
        fi
    done < <(echo -e "$cert_info")
    
    echo -n "$result"
}

# 获取所有证书状态
get_all_certs_status() {
    format_cert_status "$(get_cert_info)"
}

# 运行证书更新
renew_certificates() {
    log "运行 certbot 更新证书..."
    
    local current_dir=$(pwd)
    cd "$DOCKER_DIR" || error_exit "无法切换到 Docker 目录"
    
    # 使用 --dry-run 模式检查是否需要更新，然后实际执行
    local output=$(docker compose run --rm certbot certbot renew --non-interactive --agree-tos 2>&1)
    local result=$?
    
    # 将输出写入日志
    echo "$output" >> "$LOG_FILE"
    
    cd "$current_dir" || exit
    
    # 返回输出和结果
    echo "$output"
    return $result
}

# 重载 Nginx 配置
reload_nginx() {
    log "重载 Nginx 配置..."
    
    if docker exec "$NGINX_CONTAINER_NAME" nginx -s reload; then
        log "Nginx 配置重载成功"
        return 0
    else
        log "Nginx 配置重载失败"
        return 1
    fi
}

# 检查是否有证书需要更新（剩余天数 <= 30）
check_if_renewal_needed() {
    local cert_info="$1"
    local renewal_needed=0
    
    while IFS=: read -r domain modified_time days_remaining; do
        if [[ -n "$domain" && -n "$days_remaining" ]]; then
            if [ "$days_remaining" -le 30 ]; then
                log "域名 $domain 需要更新 (剩余 $days_remaining 天)"
                renewal_needed=1
            else
                log "域名 $domain 无需更新 (剩余 $days_remaining 天)"
            fi
        fi
    done < <(echo -e "$cert_info")
    
    return $renewal_needed
}

# 主逻辑
main() {
    # 初始化环境
    init_environment
    
    # 获取当前证书状态
    local current_cert_info=$(get_cert_info)
    local all_certs_status=$(format_cert_status "$current_cert_info")
    
    # 先检查是否有证书需要更新
    check_if_renewal_needed "$current_cert_info"
    local renewal_needed=$?
    
    if [ $renewal_needed -eq 0 ]; then
        log "所有证书都在有效期内，无需更新"
        send_notification "info" "证书无需更新:
$all_certs_status"
        return
    fi
    
    log "检测到有证书需要更新，开始运行 certbot..."
    
    # 运行证书更新并获取输出
    local certbot_output=$(renew_certificates)
    local renew_result=$?
    
    if [ $renew_result -ne 0 ]; then
        error_exit "证书更新过程出错，退出码: $renew_result"
    fi
    
    # 重新获取证书状态
    current_cert_info=$(get_cert_info)
    all_certs_status=$(format_cert_status "$current_cert_info")
    
    # 既然运行了更新且成功了，就重载 nginx
    log "证书更新完成，重载 Nginx 配置"
    
    if reload_nginx; then
        send_notification "success" "证书更新成功, NGINX 已重载配置:
$all_certs_status"
    else
        send_notification "warning" "证书更新成功, NGINX 重载配置失败:
$all_certs_status"
    fi
}

# 执行主逻辑
main
