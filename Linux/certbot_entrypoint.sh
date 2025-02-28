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

# 创建证书管理脚本
cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/sh
# 安装 docker-cli
apk add --no-cache docker-cli
# 定义证书路径
CERT_DIR="/etc/letsencrypt/live/ssl"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"
# 从参数获取域名（例如 "160706.xyz" -> "160706.xyz *.160706.xyz"）
if [ $# -eq 0 ]; then
  echo "$(date): 未提供域名参数，默认使用 160603.xyz 和 20160706.xyz" >> /var/log/letsencrypt/certbot.log
  EXPECTED_DOMAINS="160603.xyz *.160603.xyz 20160706.xyz *.20160706.xyz"
  DOMAIN_ARGS="-d 160603.xyz -d *.160603.xyz -d 20160706.xyz -d *.20160706.xyz"
else
  EXPECTED_DOMAINS=""
  DOMAIN_ARGS=""
  for domain in "$@"; do
    EXPECTED_DOMAINS="$EXPECTED_DOMAINS $domain *.$domain"
    DOMAIN_ARGS="$DOMAIN_ARGS -d $domain -d *.$domain"
  done
  # 去除首尾多余空格
  EXPECTED_DOMAINS=$(echo "$EXPECTED_DOMAINS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi
# 函数：申请新证书（备份旧证书）
request_new_cert() {
  echo "$(date): 证书不存在或域名不匹配，尝试申请新证书..." >> /var/log/letsencrypt/certbot.log
  # 如果证书目录已存在，备份旧证书
  if [ -d "$CERT_DIR" ]; then
    BACKUP_DIR="/etc/letsencrypt/archive/ssl-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r "$CERT_DIR"/* "$BACKUP_DIR/"
    echo "$(date): 已备份旧证书到 $BACKUP_DIR" >> /var/log/letsencrypt/certbot.log
    # 删除旧证书目录
    rm -rf "$CERT_DIR"
    echo "$(date): 已删除旧证书目录 $CERT_DIR" >> /var/log/letsencrypt/certbot.log
  fi
  # 动态申请新证书
  certbot certonly --dns-cloudflare --dns-cloudflare-credentials /cloudflare.ini \
    --email saw19880525@gmail.com --agree-tos --no-eff-email --non-interactive \
    --cert-name ssl --keep-until-expiring \
    $DOMAIN_ARGS || true
  # 重载 Nginx 以应用新证书
  if [ -f "$FULLCHAIN" ]; then
    docker exec nginx nginx -s reload
    echo "$(date): Nginx 已重载以应用新证书" >> /var/log/letsencrypt/certbot.log
  fi
}
# 函数：检查证书是否包含所有预期域名
check_cert_domains() {
  if [ -f "$FULLCHAIN" ]; then
    CURRENT_DOMAINS=$(openssl x509 -in "$FULLCHAIN" -noout -text | grep -A1 "Subject Alternative Name" | tail -n1 | sed "s/DNS://g" | tr -d " " | tr "," " ")
    for domain in $EXPECTED_DOMAINS; do
      if ! echo "$CURRENT_DOMAINS" | grep -w "$domain" >/dev/null; then
        echo "$(date): 证书缺少域名 $domain" >> /var/log/letsencrypt/certbot.log
        return 1
      fi
    done
    echo "$(date): 证书包含所有预期域名" >> /var/log/letsencrypt/certbot.log
    return 0
  fi
  return 1
}
# 函数：检查证书是否即将过期（剩余时间少于30天）
check_cert_expiry() {
  if [ -f "$FULLCHAIN" ]; then
    if ! openssl x509 -in "$FULLCHAIN" -noout -checkend 2592000 >/dev/null 2>&1; then
      echo "$(date): 证书即将过期（少于30天），尝试续签..." >> /var/log/letsencrypt/certbot.log
      certbot renew --non-interactive --quiet --post-hook "docker exec nginx nginx -s reload" || true
    else
      echo "$(date): 证书仍然有效（超过30天），无需操作" >> /var/log/letsencrypt/certbot.log
    fi
  fi
}
# 初始检查
if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ] || ! check_cert_domains; then
  request_new_cert
else
  check_cert_expiry
fi
# 设置定时续签
trap exit TERM
while :; do 
  echo "$(date): 检查证书状态..." >> /var/log/letsencrypt/renew.log
  if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ] || ! check_cert_domains; then
    request_new_cert
  else
    certbot renew --non-interactive --quiet --post-hook "docker exec nginx nginx -s reload" || true
  fi
  echo "$(date): 检查和续签尝试完成" >> /var/log/letsencrypt/renew.log
  sleep 12h & wait ${!}
done
EOF

# 添加执行权限
chmod +x "$SCRIPT_PATH"

# 确保日志目录存在
mkdir -p /var/log/letsencrypt

echo "脚本已成功安装到: $SCRIPT_PATH"
echo ""
echo "使用方法："
echo "1. 使用默认域名: $SCRIPT_PATH"
echo "2. 指定自定义域名: $SCRIPT_PATH domain1.com domain2.org domain3.net"
echo ""
echo "脚本将自动为每个域名及其通配符版本申请和管理SSL证书。"
