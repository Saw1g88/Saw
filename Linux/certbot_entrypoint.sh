#!/bin/sh
echo "脚本开始执行..."
apk add --no-cache docker-cli openssl
echo "docker-cli 和 openssl 安装完成..."

CERT_DIR="/etc/letsencrypt/live/ssl"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"
DHPARAMS="/etc/letsencrypt/ssl-dhparams.pem"
echo "证书路径：FULLCHAIN=$FULLCHAIN, PRIVKEY=$PRIVKEY, DHPARAMS=$DHPARAMS"

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
  fix_symlinks
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
  echo "$(date): 修复证书符号链接..." | tee -a /var/log/letsencrypt/certbot.log
  mkdir -p "$CERT_DIR"  # 确保目录存在
  cd "$CERT_DIR"
  # 动态检测最新的存档目录
  ARCHIVE_BASE="/etc/letsencrypt/archive"
  ARCHIVE_DIR=$(ls -d "$ARCHIVE_BASE"/ssl* 2>/dev/null | sort -r | head -n1)
  if [ -n "$ARCHIVE_DIR" ] && [ -d "$ARCHIVE_DIR" ]; then
    LATEST_CERT=$(ls -t "$ARCHIVE_DIR/cert"*.pem | head -n1)
    LATEST_CHAIN=$(ls -t "$ARCHIVE_DIR/chain"*.pem | head -n1)
    LATEST_FULLCHAIN=$(ls -t "$ARCHIVE_DIR/fullchain"*.pem | head -n1)
    LATEST_PRIVKEY=$(ls -t "$ARCHIVE_DIR/privkey"*.pem | head -n1)
    if [ -f "$LATEST_CERT" ] && [ -f "$LATEST_CHAIN" ]; then
      ln -sf "../../archive/$(basename "$ARCHIVE_DIR")/$(basename "$LATEST_CERT")" cert.pem
      ln -sf "../../archive/$(basename "$ARCHIVE_DIR")/$(basename "$LATEST_CHAIN")" chain.pem
      ln -sf "../../archive/$(basename "$ARCHIVE_DIR")/$(basename "$LATEST_FULLCHAIN")" fullchain.pem
      ln -sf "../../archive/$(basename "$ARCHIVE_DIR")/$(basename "$LATEST_PRIVKEY")" privkey.pem
      echo "$(date): 符号链接修复完成，存档目录：$ARCHIVE_DIR" | tee -a /var/log/letsencrypt/certbot.log
    else
      echo "$(date): 存档目录中缺少必要证书文件" | tee -a /var/log/letsencrypt/certbot.log
    fi
  else
    echo "$(date): 未找到存档目录" | tee -a /var/log/letsencrypt/certbot.log
  fi
}

generate_dhparams() {
  echo "$(date): 检查 DH 参数文件..." | tee -a /var/log/letsencrypt/certbot.log
  if [ -f "$FULLCHAIN" ] && [ ! -f "$DHPARAMS" ]; then
    echo "$(date): 证书存在但 DH 参数文件不存在，生成 DH 参数文件..." | tee -a /var/log/letsencrypt/certbot.log
    openssl dhparam -out "$DHPARAMS" 2048 2>&1 | tee -a /var/log/letsencrypt/certbot.log
    if [ $? -eq 0 ]; then
      echo "$(date): DH 参数文件已生成：$DHPARAMS" | tee -a /var/log/letsencrypt/certbot.log
      docker exec nginx nginx -s reload
      echo "$(date): Nginx 已重载以应用 DH 参数" | tee -a /var/log/letsencrypt/certbot.log
    else
      echo "$(date): DH 参数文件生成失败" | tee -a /var/log/letsencrypt/certbot.log
    fi
  elif [ -f "$FULLCHAIN" ] && [ -f "$DHPARAMS" ]; then
    echo "$(date): 证书和 DH 参数文件均已存在，跳过生成" | tee -a /var/log/letsencrypt/certbot.log
  else
    echo "$(date): 证书不存在，跳过 DH 参数生成" | tee -a /var/log/letsencrypt/certbot.log
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
generate_dhparams

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
