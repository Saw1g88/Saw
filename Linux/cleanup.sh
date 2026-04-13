#!/bin/bash
# =========================================
# VPS 安全清理脚本
# 功能：
# 1. 清理 systemd 日志并限制大小
# 2. 安全清理 /tmp 和 /var/tmp（基于时间）
# 3. 清理 apt/yum 缓存
# 4. 清理 pip/npm 缓存
# 5. 清理旧日志文件
# 6. 输出清理前后对比
# =========================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 权限检查
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 此脚本需要 root 权限运行${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

echo -e "${GREEN}====== VPS 清理开始 ======${NC}"

# 记录清理前的磁盘占用
BEFORE=$(df / | tail -1 | awk '{print $3}')
echo -e "${YELLOW}清理前磁盘占用:${NC}"
df -h /

# ------------------------------
# 1️⃣ systemd 日志清理与限制
# ------------------------------
echo -e "\n${YELLOW}[1/5] 清理 systemd 日志并限制大小...${NC}"
journalctl --vacuum-time=7d
journalctl --vacuum-size=200M

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
# 2️⃣ /tmp 安全清理
# ------------------------------
echo -e "\n${YELLOW}[2/5] 清理 /tmp 和 /var/tmp（7天前的文件）...${NC}"
find /tmp -type f -atime +7 -delete 2>/dev/null || true
find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
find /tmp -type d -empty -mindepth 1 -not -path '/tmp/.*' -delete 2>/dev/null || true
find /var/tmp -type d -empty -mindepth 1 -delete 2>/dev/null || true
chmod 1777 /tmp 2>/dev/null || true
echo -e "${GREEN}✓ /tmp 清理完成${NC}"

# ------------------------------
# 3️⃣ 软件包缓存清理（只清理缓存，不删包）
# ------------------------------
echo -e "\n${YELLOW}[3/5] 清理软件包缓存...${NC}"
if command -v apt >/dev/null 2>&1; then
    echo "检测到 Debian/Ubuntu 系统"

    # 检查是否有 apt 进程在运行
    if fuser /var/lib/dpkg/lock* > /dev/null 2>&1; then
        echo -e "${YELLOW}警告: apt 正在被其他进程使用，跳过缓存清理${NC}"
    else
        # 只清理缓存，不执行 autoremove，避免误删容器依赖
        apt autoclean 2>/dev/null || echo "警告: apt autoclean 失败"
        apt clean 2>/dev/null || echo "警告: apt clean 失败"
        echo -e "${GREEN}✓ apt 缓存清理完成${NC}"
        echo -e "${YELLOW}提示: 如需清理无用包，请手动确认后执行 apt autoremove --purge --dry-run${NC}"
    fi
elif command -v yum >/dev/null 2>&1; then
    echo "检测到 RHEL/CentOS 系统"
    yum clean all 2>/dev/null || echo "警告: yum clean 失败"
    echo -e "${GREEN}✓ yum 缓存清理完成${NC}"
fi

# ------------------------------
# 4️⃣ 清理 pip/npm 缓存
# ------------------------------
echo -e "\n${YELLOW}[4/5] 清理开发工具缓存...${NC}"

if command -v pip3 >/dev/null 2>&1; then
    pip3 cache purge 2>/dev/null || true
    echo -e "${GREEN}✓ pip3 缓存清理完成${NC}"
fi

if command -v pip >/dev/null 2>&1; then
    pip cache purge 2>/dev/null || true
    echo -e "${GREEN}✓ pip 缓存清理完成${NC}"
fi

if command -v npm >/dev/null 2>&1; then
    npm cache clean --force 2>/dev/null || true
    echo -e "${GREEN}✓ npm 缓存清理完成${NC}"
fi

if command -v yarn >/dev/null 2>&1; then
    yarn cache clean 2>/dev/null || true
    echo -e "${GREEN}✓ yarn 缓存清理完成${NC}"
fi

if command -v composer >/dev/null 2>&1; then
    composer clear-cache 2>/dev/null || true
    echo -e "${GREEN}✓ composer 缓存清理完成${NC}"
fi

# ------------------------------
# 5️⃣ 清理旧日志文件
# ------------------------------
echo -e "\n${YELLOW}[5/5] 清理旧日志文件（30天前）...${NC}"

find /var/log -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
find /var/log -name "*.gz" -mtime +30 -delete 2>/dev/null || true

if [ -d /var/log/nginx ]; then
    find /var/log/nginx -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
    find /var/log/nginx -name "*.gz" -mtime +30 -delete 2>/dev/null || true
fi

if [ -d /var/log/apache2 ]; then
    find /var/log/apache2 -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
    find /var/log/apache2 -name "*.gz" -mtime +30 -delete 2>/dev/null || true
fi

if [ -d /var/log/mysql ]; then
    find /var/log/mysql -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
fi

# 清理 core dump（排除虚拟文件系统）
find / -name "core.*" -type f -mtime +7 \
    -not -path "/proc/*" \
    -not -path "/sys/*" \
    -not -path "/dev/*" \
    -not -path "/run/*" \
    -delete 2>/dev/null || true

echo -e "${GREEN}✓ 旧日志清理完成${NC}"

# ------------------------------
# 清理后统计
# ------------------------------
echo -e "\n${YELLOW}清理后磁盘占用:${NC}"
df -h /

AFTER=$(df / | tail -1 | awk '{print $3}')
FREED=$(( (BEFORE - AFTER) / 1024 ))

if [ "$FREED" -gt 0 ]; then
    echo -e "\n${GREEN}✓ 本次清理释放空间: ${FREED} MB${NC}"
else
    echo -e "\n${GREEN}✓ 清理完成（空间变化较小）${NC}"
fi

echo -e "\n${GREEN}====== VPS 清理完成 ======${NC}"
