#!/bin/bash

# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 交互式获取服务器标识
read -p "请输入服务器标识(例如: oracle): " SERVER_ID

# 备份脚本路径
BACKUP_SCRIPT="/root/docker_backup.sh"

# 创建备份脚本
cat > "$BACKUP_SCRIPT" << EOF
#!/bin/bash
# 定义变量
backup_src="/opt/docker"
backup_dest="onedrive:vps/${SERVER_ID}/docker"
timestamp=\$(date +%Y%m%d_%H%M%S)

docker exec rclone /bin/sh -c "\
    cd / && \
    tar czvf /tmp/backup_\${timestamp}.tar.gz \$backup_src && \
    rclone copy /tmp/backup_\${timestamp}.tar.gz \$backup_dest && \
    rm /tmp/backup_\${timestamp}.tar.gz"

if [ \$? -eq 0 ]; then
    echo -e "\${GREEN}备份成功！备份文件：backup_\${timestamp}.tar.gz\${NC}"
else
    echo -e "\${RED}备份失败！请检查错误信息。\${NC}"
fi
EOF

# 赋予脚本执行权限
chmod +x "$BACKUP_SCRIPT"

# 配置定时任务
CRON_JOB="0 1 * * 1 /bin/bash $BACKUP_SCRIPT"
if ! crontab -l 2>/dev/null | grep -q "$CRON_JOB"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}定时任务添加成功：${CRON_JOB}${NC}"
else
    echo -e "${RED}定时任务已存在：${CRON_JOB}${NC}"
fi
