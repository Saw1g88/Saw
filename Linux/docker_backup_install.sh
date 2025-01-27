#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

script_url="https://raw.githubusercontent.com/Saw1g88/Saw/main/Linux/docker_backup.sh"
target_path="/root/docker_backup.sh"

if curl -sS "$script_url" -o "$target_path"; then
  if chmod +x "$target_path"; then
    if echo "alias d='sudo $target_path'" >> ~/.bashrc; then
      source ~/.bashrc
      echo -e "${GREEN}脚本安装成功！快捷键为 d${NC}" # 使用颜色变量
    else
      echo -e "${RED}添加 alias 失败！${NC}" # 使用颜色变量
      rm -f "$target_path"
    fi
  else
    echo -e "${RED}设置执行权限失败！${NC}" # 使用颜色变量
    rm -f "$target_path"
  fi
else
  echo -e "${RED}下载脚本失败！${NC}" # 使用颜色变量
fi
