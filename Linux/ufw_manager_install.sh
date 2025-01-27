#!/bin/bash
# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
script_url="https://raw.githubusercontent.com/Saw1g88/Saw/main/Linux/ufw_manager.sh"
target_path="/root/ufw_manager.sh"

if curl -sS "$script_url" -o "$target_path"; then
  if chmod +x "$target_path"; then
    # 移除已存在的别名定义
    sed -i '/alias u=/d' ~/.bashrc
    
    # 添加新的别名定义
    echo "alias u='sudo $target_path'" >> ~/.bashrc
    
    # 在当前 shell 中直接定义别名
    alias u="sudo $target_path"
    
    echo -e "${GREEN}脚本安装成功！快捷键 u 已生效${NC}"
  else
    echo -e "${RED}设置执行权限失败！${NC}"
    rm -f "$target_path"
  fi
else
  echo -e "${RED}下载脚本失败！${NC}"
fi
