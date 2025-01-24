#!/bin/bash
set -x

# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 交互式获取服务器标识
read -p "请输入服务器标识(例如: oracle): " SERVER_ID
echo "输入的服务器标识是：$SERVER_ID"  # 添加这行
if [ -z "$SERVER_ID" ]; then
    echo "服务器标识不能为空"
    exit 1
fi

# 备份脚本路径
BACKUP_SCRIPT="/root/docker_backup.sh"

# 创建备份脚本
cat > "$BACKUP_SCRIPT" << EOF
#!/bin/bash

# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 定义变量
backup_src="/opt/docker"
backup_dest="onedrive:vps/${SERVER_ID}/docker"
timestamp=\$(date +%Y%m%d_%H%M%S)

# 在容器内执行备份操作
docker exec rclone /bin/sh -c "\
    cd / && \
    tar czvf /tmp/backup_\${timestamp}.tar.gz \$backup_src && \
    rclone copy /tmp/backup_\${timestamp}.tar.gz \$backup_dest && \
    rm /tmp/backup_\${timestamp}.tar.gz"

# 检查执行结果
if [ \$? -eq 0 ]; then
    echo -e "\${GREEN}备份成功！备份文件：backup_\${timestamp}.tar.gz\${NC}"
else
    echo -e "\${RED}备份失败！请检查错误信息。\${NC}"
fi
EOF

# 赋予脚本执行权限
chmod +x "$BACKUP_SCRIPT"

# 输出安装完成消息
bash "$BACKUP_SCRIPT" && echo -e "${GREEN}Docker备份脚本安装并测试成功！${NC}"
