#!/bin/bash

# 设置备份目录
backup_dir="/root/backup"
# 设置日志目录
log_dir="/root/backup/log"

# 创建备份目录（如果不存在）
mkdir -p "$backup_dir"
# 创建日志文件目录（如果不存在）
mkdir -p "$log_dir"

# 初始化需要备份的文件夹列表
backup_sources=()

# 提示输入要备份的文件夹
read -p "请输入要备份的文件夹路径: " source_dir
# 如果输入为空，退出脚本
if [ -z "$source_dir" ]; then
  echo "未输入有效的文件夹路径，备份中止。"
  exit 1
fi

# 将第一个输入的文件夹添加到备份列表
backup_sources+=("$source_dir")

# 提示是否添加更多文件夹
while true; do
  read -p "是否要添加另一个需要备份的文件夹？(y/n): " add_more
  case "$add_more" in
    [Yy]* ) 
      read -p "请输入要备份的文件夹路径: " source_dir
      if [ -z "$source_dir" ]; then
        echo "未输入有效的文件夹路径，请重试。"
      else
        # 添加新输入的文件夹到备份列表
        backup_sources+=("$source_dir")
      fi
      ;;
    [Nn]* ) 
      break
      ;;
    * ) 
      echo "请输入 y 或 n。"
      ;;
  esac
done

# 提示输入要备份到OneDrive的文件夹路径
read -p "请输入要备份到OneDrive的文件夹路径: " onedrive_dir
# 如果输入为空，退出脚本
if [ -z "$onedrive_dir" ]; then
  echo "未输入有效的OneDrive文件夹路径，备份中止。"
  exit 1
fi

# 提示输入自动备份的时间
echo "请输入自动备份时间 (格式为: 分钟 小时)。例如: 30 2 表示每天凌晨2:30。"
read -p "请输入自动备份的分钟和小时 (如 30 2): " minute hour

# 检查输入的分钟和小时是否有效
if [[ ! "$minute" =~ ^[0-9]+$ ]] || [[ ! "$hour" =~ ^[0-9]+$ ]] || [ "$minute" -lt 0 ] || [ "$minute" -ge 60 ] || [ "$hour" -lt 0 ] || [ "$hour" -ge 24 ]; then
  echo "无效的时间格式，备份中止。"
  exit 1
fi

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
(crontab -l ; echo "$minute $hour * * * /bin/bash $(realpath $0)") | crontab -

echo "自动备份任务已设置为每天 $hour:$minute 运行。"
