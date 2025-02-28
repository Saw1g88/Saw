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
echo "脚本开始执行..."
apk add --no-cache docker-cli openssl
echo "docker-cli 和 openssl 安装完成..."

# 定义证书路径
CERT_DIR="/etc/letsencrypt/live/ssl"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"
echo "证书路径：FULLCHAIN=$FULLCHAIN, PRIVKEY=$PRIVKEY"

# 从参数获取域名
if [ $# -eq 0 ]; then
  echo "$(date): 未提供域名参数，默认使用 160603.xyz 和 20160706.xyz" | tee -a /var/log/letsencrypt/certbot.log
  EXPECTED_DOMAINS="160603.xyz *.160603.xyz 20160706.xyz *.20160706.xyz"
  DOMAIN_ARGS="-d 160603.xyz -d *.160603.xyz -d 20160706.xyz -d *.20160706.xyz"
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

# 函数：申请新证书（备份旧证书）
request_new_cert() {
  echo "$(date): 证书不存在或域名不匹配，申请新证书..." | tee -a /var/log/letsencrypt/certbot.log
  if [ -d "$CERT_DIR" ]; then
    BACKUP_DIR="/etc/letsencrypt/archive/ssl-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r "$CERT_DIR"/* "$BACKUP_DIR/"
    echo "$(date): 已备份旧证书到 $BACKUP_DIR" | tee -a /var/log/letsencrypt/certbot.log
    rm -rf "$CERT_DIR"
    echo "$(date): 已删除旧证书目录 $CERT_DIR" | tee -a /var/log/letsencrypt/certbot.log
  fi
  certbot certonly --dns-cloudflare --dns-cloudflare-credentials /cloudflare.ini \
    --email saw19880525@gmail.com --agree-tos --no-eff-email --non-interactive \
    --cert-name ssl --keep-until-expiring \
    $DOMAIN_ARGS || echo "$(date): 证书申请失败" | tee -a /var/log/letsencrypt/certbot.log
  if [ -f "$FULLCHAIN" ]; then
    docker exec nginx nginx -s reload
    echo "$(date): Nginx 已重载以应用新证书" | tee -a /var/log/letsencrypt/certbot.log
  else
    echo "$(date): 证书申请后仍未生成文件" | tee -a /var/log/letsencrypt/certbot.log
  fi
}

# 函数：检查证书是否包含所有预期域名
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

# 函数：检查证书是否即将过期（剩余时间少于30天）
check_cert_expiry() {
  echo "$(date): 检查证书过期时间..." | tee -a /var/log/letsencrypt/certbot.log
  if [ -f "$FULLCHAIN" ]; then
    if ! openssl x509 -in "$FULLCHAIN" -noout -checkend 2592000 >/dev/null 2>&1; then
      echo "$(date): 证书即将过期（少于30天），尝试续签..." | tee -a /var/log/letsencrypt/certbot.log
      certbot renew --cert-name ssl --non-interactive --quiet --post-hook "docker exec nginx nginx -s reload" || echo "$(date): 续签失败" | tee -a /var/log/letsencrypt/certbot.log
    else
      echo "$(date): 证书仍然有效（超过30天），无需操作" | tee -a /var/log/letsencrypt/certbot.log
    fi
  else
    echo "$(date): 证书文件 $FULLCHAIN 不存在" | tee -a /var/log/letsencrypt/certbot.log
  fi
}

# 初始检查
echo "$(date): 开始初始检查..." | tee -a /var/log/letsencrypt/certbot.log
if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ] || ! check_cert_domains; then
  echo "$(date): 条件满足，调用 request_new_cert" | tee -a /var/log/letsencrypt/certbot.log
  request_new_cert
else
  echo "$(date): 条件不满足，调用 check_cert_expiry" | tee -a /var/log/letsencrypt/certbot.log
  check_cert_expiry
fi

# 设置定时续签
echo "$(date): 初始检查完成，进入续签循环..." | tee -a /var/log/letsencrypt/certbot.log
trap exit TERM
while :; do 
  echo "$(date): 检查证书状态..." | tee -a /var/log/letsencrypt/renew.log
  if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ] || ! check_cert_domains; then
    echo "$(date): 条件满足，调用 request_new_cert" | tee -a /var/log/letsencrypt/renew.log
    request_new_cert
  else
    certbot renew --cert-name ssl --non-interactive --quiet --post-hook "docker exec nginx nginx -s reload" || echo "$(date): 续签失败" | tee -a /var/log/letsencrypt/renew.log
  fi
  echo "$(date): 检查和续签尝试完成" | tee -a /var/log/letsencrypt/renew.log
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
