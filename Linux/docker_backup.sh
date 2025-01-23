#!/bin/bash

# 交互式获取服务器标识
read -p "请输入服务器标识(例如: oracle): " SERVER_ID

# 备份脚本路径
BACKUP_SCRIPT="/root/docker_backup.sh"

# 创建备份脚本
cat > "$BACKUP_SCRIPT" << EOF
#!/bin/bash
backup_src="/opt/docker"
backup_dest="onedrive:vps/${SERVER_ID}/docker"
timestamp=\$(date +%Y%m%d_%H%M%S)

docker exec rclone /bin/sh -c "\
    cd / && \
    tar czvf /tmp/backup_\${timestamp}.tar.gz \$backup_src && \
    rclone copy /tmp/backup_\${timestamp}.tar.gz \$backup_dest && \
    rm /tmp/backup_\${timestamp}.tar.gz"
EOF

# 赋予脚本执行权限
chmod +x "$BACKUP_SCRIPT"

# 直接编辑 crontab
(crontab -l 2>/dev/null; echo "0 1 * * 1 $BACKUP_SCRIPT") | crontab -

echo "备份脚本安装完成"
