#!/bin/bash

# 定义变量
backup_src="/opt/docker"                  # 实际要备份的路径
backup_dest="onedrive:vps/oracle/docker"  # OneDrive目标路径

# 定义颜色变量
GREEN='\033[0;36m'  
RED='\033[0;31m'    
NC='\033[0m'       

# 获取当前时间戳
timestamp=$(date +%Y%m%d_%H%M%S)

# 在容器内执行备份操作
docker exec rclone /bin/sh -c "\
    cd / && \
    tar czvf /tmp/backup_${timestamp}.tar.gz $backup_src && \
    rclone copy /tmp/backup_${timestamp}.tar.gz $backup_dest && \
    rm /tmp/backup_${timestamp}.tar.gz"

# 检查执行结果
if [ $? -eq 0 ]; then
    echo -e "${GREEN}备份成功！备份文件：backup_${timestamp}.tar.gz${NC}"
else
    echo -e "${RED}备份失败！请检查错误信息。${NC}"
fi
