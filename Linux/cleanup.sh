#!/bin/bash
# =========================================
# VPS 安全清理脚本
# 功能：
# 1. 清理 systemd 日志并限制大小
# 2. 安全清理 /tmp 和 /var/tmp（基于时间）
# 3. 清理 apt/yum 缓存和旧内核
# 4. 清理 pip/npm 缓存
# 5. 清理旧日志文件
# 6. 输出清理前后对比
# =========================================

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 权限检查
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 此脚本需要 root 权限运行${NC}" 
   echo "请使用: sudo $0"
   exit 1
fi

echo -e "${GREEN}====== VPS 年度清理开始 ======${NC}"

# 记录清理前的磁盘占用
BEFORE=$(df / | tail -1 | awk '{print $3}')
echo -e "${YELLOW}清理前磁盘占用:${NC}"
df -h /

# ------------------------------
# 1️⃣ systemd 日志清理与限制
# ------------------------------
echo -e "\n${YELLOW}[1/7] 清理 systemd 日志并限制大小...${NC}"
journalctl --vacuum-time=7d
journalctl --vacuum-size=200M

# 配置日志大小限制
mkdir -p /etc/systemd
if [ ! -f /etc/systemd/journald.conf.bak ]; then
    cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak 2>/dev/null || true
fi

cat > /etc/systemd/journald.conf <<'EOF'
[Journal]
SystemMaxUse=200M
SystemKeepFree=50M
SystemMaxFileSize=50M
MaxRetentionSec=1week
EOF

systemctl restart systemd-journald
echo -e "${GREEN}✓ systemd 日志清理完成，当前占用:${NC}"
journalctl --disk-usage

# ------------------------------
# 2️⃣ /tmp 安全清理（只删除 7 天前的文件）
# ------------------------------
echo -e "\n${YELLOW}[2/7] 清理 /tmp 和 /var/tmp（7天前的文件）...${NC}"
# 只删除文件，保留目录结构
find /tmp -type f -atime +7 -delete 2>/dev/null || true
find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
# 删除空目录（但排除重要的系统目录）
find /tmp -type d -empty -not -path '/tmp' -not -path '/tmp/.*' -mindepth 1 -delete 2>/dev/null || true
find /var/tmp -type d -empty -not -path '/var/tmp' -mindepth 1 -delete 2>/dev/null || true

# 确保关键目录存在且权限正确
chmod 1777 /tmp 2>/dev/null || true
mkdir -p /tmp/.X11-unix /tmp/.ICE-unix /tmp/.font-unix 2>/dev/null || true
chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix /tmp/.font-unix 2>/dev/null || true

echo -e "${GREEN}✓ /tmp 清理完成${NC}"

# ------------------------------
# 3️⃣ 软件包缓存清理
# ------------------------------
echo -e "\n${YELLOW}[3/7] 清理软件包缓存和旧内核...${NC}"
if command -v apt >/dev/null 2>&1; then
    echo "检测到 Debian/Ubuntu 系统"
    # 清理 apt 锁文件（如果存在）
    rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    rm -f /var/lib/dpkg/lock* 2>/dev/null || true
    
    # 执行清理
    apt autoremove --purge -y 2>/dev/null || echo "警告: apt autoremove 失败"
    apt autoclean -y 2>/dev/null || echo "警告: apt autoclean 失败"
    apt clean -y 2>/dev/null || echo "警告: apt clean 失败"
    echo -e "${GREEN}✓ apt 缓存清理完成${NC}"
elif command -v yum >/dev/null 2>&1; then
    echo "检测到 RHEL/CentOS 系统"
    yum autoremove -y
    yum clean all -y
    # 清理旧内核（CentOS）
    package-cleanup --oldkernels --count=1 -y 2>/dev/null || true
    echo -e "${GREEN}✓ yum 缓存清理完成${NC}"
fi

# ------------------------------
# 4️⃣ 清理 pip/npm 缓存
# ------------------------------
echo -e "\n${YELLOW}[5/7] 清理开发工具缓存...${NC}"

# pip 缓存
if command -v pip3 >/dev/null 2>&1; then
    pip3 cache purge 2>/dev/null || true
    echo -e "${GREEN}✓ pip3 缓存清理完成${NC}"
fi

if command -v pip >/dev/null 2>&1; then
    pip cache purge 2>/dev/null || true
    echo -e "${GREEN}✓ pip 缓存清理完成${NC}"
fi

# npm 缓存
if command -v npm >/dev/null 2>&1; then
    npm cache clean --force 2>/dev/null || true
    echo -e "${GREEN}✓ npm 缓存清理完成${NC}"
fi

# yarn 缓存
if command -v yarn >/dev/null 2>&1; then
    yarn cache clean 2>/dev/null || true
    echo -e "${GREEN}✓ yarn 缓存清理完成${NC}"
fi

# composer 缓存（PHP）
if command -v composer >/dev/null 2>&1; then
    composer clear-cache 2>/dev/null || true
    echo -e "${GREEN}✓ composer 缓存清理完成${NC}"
fi

# ------------------------------
# 5️⃣ 清理旧日志文件
# ------------------------------
echo -e "\n${YELLOW}[6/7] 清理旧日志文件（30天前）...${NC}"

# 清理系统日志
find /var/log -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
find /var/log -name "*.gz" -mtime +30 -delete 2>/dev/null || true

# 清理 Nginx 日志
if [ -d /var/log/nginx ]; then
    find /var/log/nginx -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
    find /var/log/nginx -name "*.gz" -mtime +30 -delete 2>/dev/null || true
fi

# 清理 Apache 日志
if [ -d /var/log/apache2 ]; then
    find /var/log/apache2 -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
    find /var/log/apache2 -name "*.gz" -mtime +30 -delete 2>/dev/null || true
fi

# 清理 MySQL 日志
if [ -d /var/log/mysql ]; then
    find /var/log/mysql -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
fi

# 清理 core dump 文件
find / -name "core.*" -type f -mtime +7 -delete 2>/dev/null || true

echo -e "${GREEN}✓ 旧日志清理完成${NC}"

# ------------------------------
# 6️⃣ 清理后统计
# ------------------------------
echo -e "\n${YELLOW}[7/7] 清理后磁盘占用:${NC}"
df -h /

# 计算释放的空间
AFTER=$(df / | tail -1 | awk '{print $3}')
FREED=$((($BEFORE - $AFTER) / 1024))

if [ $FREED -gt 0 ]; then
    echo -e "\n${GREEN}✓ 本次清理释放空间: ${FREED} MB${NC}"
else
    echo -e "\n${GREEN}✓ 清理完成（空间变化较小）${NC}"
fi

echo -e "\n${GREEN}====== VPS 清理完成 ======${NC}"
