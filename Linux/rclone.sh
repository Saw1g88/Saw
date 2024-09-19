#!/bin/bash

# 设置时区为中国上海
export TZ="Asia/Shanghai"

# 设置备份目录
backup_dir="/root/backup"
# 设置日志目录
log_dir="/root/backup/log"
# 设置备份目录存储文件
backup_list_file="$backup_dir/backup_sources.txt"

# 创建备份目录（如果不存在）
mkdir -p "$backup_dir"
# 创建日志文件目录（如果不存在）
mkdir -p "$log_dir"

# 初始化需要备份的文件夹列表
backup_sources=()

# 读取已有的备份目录
if [ -f "$backup_list_file" ]; then
  while IFS= read -r line; do
    backup_sources+=("$line")
  done < "$backup_list_file"
fi

# 提示输入要备份的文件夹
function get_backup_source() {
  while true; do
    read -p "请输入要备份的文件夹路径: " source_dir
    # 检查文件夹是否存在
    if [ -d "$source_dir" ]; then
      # 检查文件夹是否已在备份列表中
      if [[ ! " ${backup_sources[@]} " =~ " ${source_dir} " ]]; then
        backup_sources+=("$source_dir")
        echo "$source_dir" >> "$backup_list_file"
        echo "文件夹已添加到备份列表。"
      else
        echo "文件夹已经在备份列表中。"
      fi
      break
    else
      echo "文件夹不存在，请重新输入。"
    fi
  done
}

# 提示是否添加更多文件夹
function add_more_sources() {
  while true; do
    read -p "是否要添加另一个需要备份的文件夹？(y/n): " add_more
    case "$add_more" in
      [Yy]* ) get_backup_source ;;
      [Nn]* ) break ;;
      * ) echo "请输入 y 或 n。" ;;
    esac
  done
}

# 获取备份到OneDrive的文件夹路径
function get_onedrive_dir() {
  while true; do
    read -p "请输入要备份到OneDrive的文件夹路径: " onedrive_dir
    # 如果输入为空，提示重新输入
    if [ -n "$onedrive_dir" ]; then
      break
    else
      echo "路径不能为空，请重新输入。"
    fi
  done
}

# 获取自动备份时间
function get_cron_time() {
  while true; do
    echo "请输入自动备份时间 (格式为: 分钟 小时)。例如: 30 2 表示每天凌晨2:30。"
    read -p "请输入自动备份的分钟和小时 (如 30 2): " minute hour

    # 检查输入的分钟和小时是否有效
    if [[ "$minute" =~ ^[0-9]+$ ]] && [[ "$hour" =~ ^[0-9]+$ ]] && [ "$minute" -ge 0 ] && [ "$minute" -lt 60 ] && [ "$hour" -ge 0 ] && [ "$hour" -lt 24 ]; then
      break
    else
      echo "无效的时间格式，请重新输入。"
    fi
  done
}

# 显示并确认用户输入
function confirm_inputs() {
  echo
  echo "以下是您的输入信息："
  echo "备份文件夹: ${backup_sources[@]}"
  echo "OneDrive 备份目录: $onedrive_dir"
  echo "自动备份时间: $hour:$minute"
  echo
  while true; do
    read -p "这些信息是否正确？(y/n): " confirm
    case "$confirm" in
      [Yy]* ) break ;;
      [Nn]* )
        echo "请选择需要重新输入的项："
        echo "1. 备份文件夹"
        echo "2. OneDrive 备份目录"
        echo "3. 自动备份时间"
        echo "4. 退出"
        read -p "请输入选项 (1/2/3/4): " option
        case "$option" in
          1 ) backup_sources=(); rm "$backup_list_file"; get_backup_source; add_more_sources ;;
          2 ) get_onedrive_dir ;;
          3 ) get_cron_time ;;
          4 ) exit 1 ;;
          * ) echo "无效选项，请重新输入。" ;;
        esac
        ;;
      * ) echo "请输入 y 或 n。" ;;
    esac
  done
}

# 获取用户输入
get_backup_source
add_more_sources
get_onedrive_dir
get_cron_time

# 确认输入信息
confirm_inputs

# 设置备份文件名，包含日期
backup_file="docker-backup-$(date +%Y-%m-%d).tar.gz"
# 设置备份日志文件名，包含日期
backup_log_file="$log_dir/backup-$(date +%Y-%m-%d).log"
# 设置同步日志文件名，包含日期
rclone_log_file="$log_dir/rclone-$(date +%Y-%m-%d).log"

# 使用tar命令进行压缩备份，并将输出和错误信息重定向到备份日志文件
tar -czvf "$backup_dir/$backup_file" "${backup_sources[@]}" > "$backup_log_file" 2>&1

# 检查备份是否成功
if [ $? -eq 0 ]; then
  # 在备份日志文件中记录备份完成信息
  echo "$(date +%Y-%m-%d_%H:%M:%S) - Backup completed successfully." >> "$backup_log_file"

  # 保留最近7天的备份，删除其他备份
  find "$backup_dir" -type f -mtime +7 -delete
  if [ $? -eq 0 ]; then
    # 在备份日志文件中记录删除完成信息
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Old backups deleted successfully." >> "$backup_log_file"
  else
    # 在备份日志文件中记录删除失败信息
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Deleting old backups failed." >> "$backup_log_file"
  fi

  # 保留最近7天的日志文件，删除其他日志文件
  find "$log_dir" -type f -mtime +7 -delete
  if [ $? -eq 0 ]; then
    # 在备份日志文件中记录删除完成信息
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Old logs deleted successfully." >> "$backup_log_file"
  else
    # 在备份日志文件中记录删除失败信息
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Deleting old logs failed." >> "$backup_log_file"
  fi

  # 使用 rclone 同步本地备份到 OneDrive，设置同步日志文件名
  rclone sync "$backup_dir" "onedrive:$onedrive_dir" --log-file="$rclone_log_file"

  # 检查同步是否成功
  if [ $? -eq 0 ]; then
    # 在同步日志文件中记录同步完成信息
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Sync to OneDrive completed successfully." >> "$rclone_log_file"
  else
    # 在同步日志文件中记录同步失败信息
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Sync to OneDrive failed." >> "$rclone_log_file"
  fi
else
  # 在备份日志文件中记录备份失败信息
  echo "$(date +%Y-%m-%d_%H:%M:%S) - Backup failed." >> "$backup_log_file"
fi

# 设置自动备份的cron任务
(crontab -l | grep -v "$(realpath $0)"; echo "$minute $hour * * * /bin/bash $(realpath $0)") | crontab -

echo "自动备份任务已设置为每天 $hour:$minute 运行。"
