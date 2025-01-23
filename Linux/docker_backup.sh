#!/bin/bash

# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 交互式获取服务器标识
read -p "请输入服务器标识(例如: oracle): " SERVER_ID
if [[ -z "$SERVER_ID" ]]; then
    echo -e "${RED}错误：服务器标识不能为空！${NC}"
    exit 1
fi

# 备份脚本路径
BACKUP_SCRIPT="/root/docker_backup.sh"

# 创建备份脚本
cat > "$BACKUP_SCRIPT" << EOF
#!/bin/bash
# 定义变量
backup_src="/opt/docker"
backup_dest="onedrive:vps/${SERVER_ID}/docker"
LOG_FILE="/var/log/docker_backup.log"
GREEN='\033[0;36m'  
RED='\033[0;31m'    
NC='\033[0m'       

# 获取当前时间戳
timestamp=\$(date +%Y%m%d_%H%M%S)

# 开始日志
echo "\$(date +"%Y-%m-%d %H:%M:%S") - 备份开始" >> \$LOG_FILE

# 压缩文件
docker exec rclone /bin/sh -c "cd / && tar czvf /tmp/backup_\${timestamp}.tar.gz \$backup_src"
if [ \$? -ne 0 ]; then
    echo -e "\${RED}压缩文件失败，请检查源路径或容器状态！\${NC}" | tee -a \$LOG_FILE
    exit 1
fi

# 上传到目标路径
docker exec rclone /bin/sh -c "rclone copy /tmp/backup_\${timestamp}.tar.gz \$backup_dest"
if [ \$? -ne 0 ]; then
    echo -e "\${RED}上传到目标路径失败，请检查 Rclone 配置！\${NC}" | tee -a \$LOG_FILE
    exit 1
fi

# 删除临时文件
docker exec rclone /bin/sh -c "rm /tmp/backup_\${timestamp}.tar.gz"

# 完成日志
echo "\$(date +"%Y-%m-%d %H:%M:%S") - 备份完成：backup_\${timestamp}.tar.gz" >> \$LOG_FILE
echo -e "\${GREEN}备份成功！备份文件：backup_\${timestamp}.tar.gz\${NC}"
EOF

# 赋予脚本执行权限
chmod +x "$BACKUP_SCRIPT"

# 配置定时任务
(crontab -l 2>/dev/null; echo "0 1 * * 1 /bin/bash $BACKUP_SCRIPT") | crontab -

# 验证定时任务
if crontab -l | grep -q "$BACKUP_SCRIPT"; then
    echo -e "${GREEN}备份脚本已安装完成！${NC}"
    echo -e "备份目标路径：onedrive:vps/${SERVER_ID}/docker"
    echo -e "定时任务：每周一凌晨1点自动备份"
else
    echo -e "${RED}警告：定时任务配置失败，请手动检查 crontab！${NC}"
fi
