#!/bin/bash
# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 开启调试模式，便于排查问题
set -x  # 输出所有执行的命令

# 交互式获取服务器标识
read -p "请输入服务器标识(例如: oracle): " SERVER_ID

# 检查输入是否为空
if [ -z "$SERVER_ID" ]; then
    echo -e "${RED}错误：服务器标识不能为空！${NC}"
    exit 1
fi

# 显示输入的服务器标识
echo -e "${GREEN}输入的服务器标识是：$SERVER_ID${NC}"

# 备份脚本路径
BACKUP_SCRIPT="/root/docker_backup.sh"

# 创建备份脚本
if cat > "$BACKUP_SCRIPT" << EOF
#!/bin/bash
# 定义颜色变量
GREEN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 定义变量
backup_src="/opt/docker"
backup_dest="onedrive:vps/${SERVER_ID}/docker"
timestamp=\$(date +%Y%m%d%H%M%S)

# 在容器内执行备份操作
docker exec rclone /bin/sh -c "\
    cd / && \
    tar czvf /tmp/backup_\${timestamp}.tar.gz \${backup_src} && \
    rclone copy /tmp/backup_\${timestamp}.tar.gz \${backup_dest} && \
    rm /tmp/backup_\${timestamp}.tar.gz"

# 检查执行结果
if [ \$? -eq 0 ]; then
    echo -e "\${GREEN}备份成功！备份文件：backup_\${timestamp}.tar.gz\${NC}"
else
    echo -e "\${RED}备份失败！请检查错误信息。\${NC}"
fi
EOF
then
    echo -e "${GREEN}备份脚本创建完成：$BACKUP_SCRIPT${NC}"
else
    echo -e "${RED}错误：备份脚本创建失败！${NC}"
    exit 1
fi

# 为备份脚本添加可执行权限
chmod +x "$BACKUP_SCRIPT" && echo -e "${GREEN}已添加可执行权限：$BACKUP_SCRIPT${NC}" || {
    echo -e "${RED}错误：无法添加可执行权限！${NC}"
    exit 1
}

# 关闭调试模式
set +x
