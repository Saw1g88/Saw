#!/bin/bash

# 定义目标目录
TARGET_DIR="/opt/docker/nginx/certbot"
SCRIPT_NAME="certbot_entrypoint.sh"
SCRIPT_PATH="$TARGET_DIR/$SCRIPT_NAME"

# 创建目标目录（如果不存在）
if [ ! -d "$TARGET_DIR" ]; then
  echo "创建目录: $TARGET_DIR"
  mkdir -p "$TARGET_DIR"
fi

# 检查脚本是否已存在
if [ -f "$SCRIPT_PATH" ]; then
  echo "检测到脚本已存在: $SCRIPT_PATH"
  echo "是否覆盖现有脚本? (y/n)"
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "安装已取消。"
    exit 0
  fi
  echo "将覆盖现有脚本。"
fi

# 交互式输入域名
echo "请输入要使用的域名（多个域名用空格分隔，例如：example.com test.com）"
echo "直接按回车将使用默认域名（160603.xyz 20160706.xyz）"
read -r input_domains

# 处理域名输入
if [ -z "$input_domains" ]; then
  DEFAULT_DOMAINS="160603.xyz 20160706.xyz"
  echo "未输入域名，将使用默认域名：$DEFAULT_DOMAINS"
else
  # 验证域名格式
  valid=true
  domains=""
  for domain in $input_domains; do
    if ! echo "$domain" | grep -qE "^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$"; then
      echo "错误：'$domain' 不是有效的域名格式"
      valid=false
    else
      domains="$domains $domain"
    fi
  done
  
  if [ "$valid" = false ]; then
    while [ "$valid" = false ]; do
      echo "请重新输入有效的域名（多个域名用空格分隔）："
      read -r input_domains
      valid=true
      domains=""
      for domain in $input_domains; do
        if ! echo "$domain" | grep -qE "^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$"; then
          echo "错误：'$domain' 不是有效的域名格式"
          valid=false
        else
          domains="$domains $domain"
        fi
      done
    done
  fi
  
  DEFAULT_DOMAINS=$(echo "$domains" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  echo "您输入的域名是：$DEFAULT_DOMAINS"
  echo "确认使用这些域名吗？(y/n)"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "安装已取消。"
    exit 0
  fi
fi

# 创建证书管理脚本
cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/sh
echo "脚本开始执行..."
apk add --no-cache docker-cli openssl
echo "docker-cli 和 openssl 安装完成..."

CERT_DIR="/etc/letsencrypt/live/ssl"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"
echo "证书路径：FULLCHAIN=$FULLCHAIN, PRIVKEY=$PRIVKEY"

# 默认域名
DEFAULT_DOMAINS="PLACEHOLDER_DEFAULT_DOMAINS"

if [ $# -eq 0 ]; then
  echo "$(date): 未提供域名参数，默认使用 $DEFAULT_DOMAINS" | tee -a /var/log/letsencrypt/certbot.log
  EXPECTED_DOMAINS=""
  DOMAIN_ARGS=""
  for domain in $DEFAULT_DOMAINS; do
    EXPECTED_DOMAINS="$EXPECTED_DOMAINS $domain *.$domain"
    DOMAIN_ARGS="$DOMAIN_ARGS -d $domain -d *.$domain"
  done
  EXPECTED_DOMAINS=$(echo "$EXPECTED_DOMAINS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
else
  echo "$(date): 使用传入的域名参数：$@" | tee -a /var/log/letsencrypt/certbot.log
  EXPECTED_DOMAINS=""
  DOMAIN_ARGS=""
  for domain in "$@"; do
    EXPECTED_DOMAINS="$EXPECTED_DOMAINS $domain *.$domain"
    DOMAIN_ARGS="$DOMAIN_ARGS -d $domain -d *.$domain"
  done
  EXPECTED_DOMAINS=$(echo "$EXPECTED_DOMAINS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi
echo "$(date): 域名参数处理完成：EXPECTED_DOMAINS=$EXPECTED_DOMAINS" | tee -a /var/log/letsencrypt/certbot.log

request_new_cert() {
  echo "$(date): 证书不存在或域名不匹配，申请新证书..." | tee -a /var/log/letsencrypt/certbot.log
  if [ -d "$CERT_DIR" ]; then
    BACKUP_DIR="/etc/letsencrypt/archive/ssl-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r "$CERT_DIR"/* "$BACKUP_DIR/" 2>/dev/null || echo "$(date): 备份目录为空" | tee -a /var/log/letsencrypt/certbot.log
    echo "$(date): 已备份旧证书到 $BACKUP_DIR" | tee -a /var/log/letsencrypt/certbot.log
    rm -rf "$CERT_DIR"
    echo "$(date): 已删除旧证书目录 $CERT_DIR" | tee -a /var/log/letsencrypt/certbot.log
  fi
  echo "$(date): 检查 Cloudflare 凭证..." | tee -a /var/log/letsencrypt/certbot.log
  if [ -f "/cloudflare.ini" ]; then
    cat /cloudflare.ini | tee -a /var/log/letsencrypt/certbot.log
  else
    echo "$(date): /cloudflare.ini 不存在" | tee -a /var/log/letsencrypt/certbot.log
    return 1
  fi
  OUTPUT=$(certbot certonly --dns-cloudflare --dns-cloudflare-credentials /cloudflare.ini \
    --email saw19880525@gmail.com --agree-tos --no-eff-email --non-interactive \
    --cert-name ssl --keep-until-expiring --verbose \
    $DOMAIN_ARGS 2>&1)
  echo "$OUTPUT" | tee -a /var/log/letsencrypt/certbot.log
  if echo "$OUTPUT" | grep -q "too many certificates"; then
    RETRY_AFTER=$(echo "$OUTPUT" | grep -o "retry after [0-9- :]\+ UTC" | awk '{print $3 " " $4 " " $5}')
    echo "$(date): 达到 Let's Encrypt 速率限制，将在 $RETRY_AFTER 后重试" | tee -a /var/log/letsencrypt/certbot.log
    sleep $(( $(date -d "$RETRY_AFTER" +%s) - $(date +%s) ))
  elif [ $? -ne 0 ]; then
    echo "$(date): 证书申请失败" | tee -a /var/log/letsencrypt/certbot.log
  fi
  if [ -f "$FULLCHAIN" ]; then
    docker exec nginx nginx -s reload
    echo "$(date): Nginx 已重载以应用新证书" | tee -a /var/log/letsencrypt/certbot.log
  else
    echo "$(date): 证书申请后仍未生成文件" | tee -a /var/log/letsencrypt/certbot.log
  fi
}

check_cert_domains() {
  echo "$(date): 检查证书域名..." | tee -a /var/log/letsencrypt/certbot.log
  if [ -f "$FULLCHAIN" ]; then
    CURRENT_DOMAINS=$(openssl x509 -in "$FULLCHAIN" -noout -text | grep -A1 "Subject Alternative Name" | tail -n1 | sed "s/DNS://g" | tr -d " " | tr "," " ")
    echo "$(date): 当前证书域名：$CURRENT_DOMAINS" | tee -a /var/log/letsencrypt/certbot.log
    for domain in $EXPECTED_DOMAINS; do
      if ! echo "$CURRENT_DOMAINS" | grep -w "$domain" >/dev/null; then
        echo "$(date): 证书缺少域名 $domain" | tee -a /var/log/letsencrypt/certbot.log
        return 1
      fi
    done
    echo "$(date): 证书包含所有预期域名" | tee -a /var/log/letsencrypt/certbot.log
    return 0
  else
    echo "$(date): 证书文件 $FULLCHAIN 不存在" | tee -a /var/log/letsencrypt/certbot.log
    return 1
  fi
}

check_cert_expiry() {
  echo "$(date): 检查证书过期时间..." | tee -a /var/log/letsencrypt/certbot.log
  if [ -f "$FULLCHAIN" ]; then
    if ! openssl x509 -in "$FULLCHAIN" -noout -checkend 2592000 >/dev/null 2>&1; then
      echo "$(date): 证书即将过期（少于30天），尝试续签..." | tee -a /var/log/letsencrypt/certbot.log
      if [ -f "/etc/letsencrypt/renewal/ssl.conf" ]; then
        certbot renew --cert-name ssl --non-interactive --quiet --post-hook "docker exec nginx nginx -s reload" || echo "$(date): 续签失败" | tee -a /var/log/letsencrypt/certbot.log
      else
        echo "$(date): 续订配置文件缺失，尝试重新申请..." | tee -a /var/log/letsencrypt/certbot.log
        request_new_cert
      fi
    else
      echo "$(date): 证书仍然有效（超过30天），无需操作" | tee -a /var/log/letsencrypt/certbot.log
    fi
  else
    echo "$(date): 证书文件 $FULLCHAIN 不存在" | tee -a /var/log/letsencrypt/certbot.log
  fi
}

fix_symlinks() {
  if [ -f "$FULLCHAIN" ]; then
    echo "$(date): 修复证书符号链接..." | tee -a /var/log/letsencrypt/certbot.log
    cd "$CERT_DIR"
    ARCHIVE_DIR="/etc/letsencrypt/archive/ssl"
    if [ -d "$ARCHIVE_DIR" ]; then
      LATEST_CERT=$(ls -t "$ARCHIVE_DIR/cert"*.pem | head -n1)
      LATEST_CHAIN=$(ls -t "$ARCHIVE_DIR/chain"*.pem | head -n1)
      LATEST_FULLCHAIN=$(ls -t "$ARCHIVE_DIR/fullchain"*.pem | head -n1)
      LATEST_PRIVKEY=$(ls -t "$ARCHIVE_DIR/privkey"*.pem | head -n1)
      if [ -f "$LATEST_CERT" ] && [ -f "$LATEST_CHAIN" ]; then
        ln -sf "$LATEST_CERT" cert.pem
        ln -sf "$LATEST_CHAIN" chain.pem
        ln -sf "$LATEST_FULLCHAIN" fullchain.pem
        ln -sf "$LATEST_PRIVKEY" privkey.pem
        echo "$(date): 符号链接修复完成" | tee -a /var/log/letsencrypt/certbot.log
      else
        echo "$(date): 存档目录中缺少必要证书文件" | tee -a /var/log/letsencrypt/certbot.log
      fi
    else
      echo "$(date): 存档目录 $ARCHIVE_DIR 不存在" | tee -a /var/log/letsencrypt/certbot.log
    fi
  fi
}

echo "$(date): 开始初始检查..." | tee -a /var/log/letsencrypt/certbot.log
fix_symlinks
if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ] || ! check_cert_domains; then
  echo "$(date): 条件满足，调用 request_new_cert" | tee -a /var/log/letsencrypt/certbot.log
  request_new_cert
else
  echo "$(date): 条件不满足，调用 check_cert_expiry" | tee -a /var/log/letsencrypt/certbot.log
  check_cert_expiry
fi

echo "$(date): 初始检查完成，进入续签循环..." | tee -a /var/log/letsencrypt/certbot.log
trap exit TERM
while :; do 
  echo "$(date): 检查证书状态..." | tee -a /var/log/letsencrypt/renew.log
  fix_symlinks
  if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ] || ! check_cert_domains; then
    echo "$(date): 条件满足，调用 request_new_cert" | tee -a /var/log/letsencrypt/renew.log
    request_new_cert
  else
    if [ -f "/etc/letsencrypt/renewal/ssl.conf" ]; then
      certbot renew --cert-name ssl --non-interactive --quiet --post-hook "docker exec nginx nginx -s reload" || echo "$(date): 续签失败" | tee -a /var/log/letsencrypt/renew.log
    else
      echo "$(date): 续订配置文件缺失，跳过续签" | tee -a /var/log/letsencrypt/renew.log
    fi
  fi
  echo "$(date): 检查和续签尝试完成" | tee -a /var/log/letsencrypt/renew.log
  sleep 12h & wait ${!}
done
EOF

# 替换占位符
sed -i "s/PLACEHOLDER_DEFAULT_DOMAINS/$DEFAULT_DOMAINS/" "$SCRIPT_PATH"

# 添加执行权限
chmod +x "$SCRIPT_PATH"

# 确保日志目录存在
mkdir -p /var/log/letsencrypt

echo "脚本已成功安装到: $SCRIPT_PATH"
echo ""
echo "使用方法："
echo "1. 使用安装时配置的域名: $SCRIPT_PATH"
echo "2. 指定自定义域名覆盖默认配置: $SCRIPT_PATH domain1.com domain2.org domain3.net"
echo ""
echo "已配置的默认域名：$DEFAULT_DOMAINS"
echo "脚本将自动为每个域名及其通配符版本申请和管理SSL证书。"
