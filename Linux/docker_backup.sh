#!/bin/bash

# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 交互式获取服务器标识
read -p "请输入服务器标识(例如: oracle): " SERVER_ID

# 备份脚本路径
BACKUP_SCRIPT="/root/docker_backup.sh"

# 输出调试信息
echo "开始创建备份脚本..."

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

# 输出调试信息
echo "备份脚本已创建：$BACKUP_SCRIPT"

# 赋予脚本执行权限
chmod +x "$BACKUP_SCRIPT"

# 输出调试信息
echo "备份脚本安装完成"
