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

# 删除已有备份目录
function delete_existing_backup() {
  if [ ${#backup_sources[@]} -eq 0 ]; then
    echo "没有可删除的备份目录。"
    return
  fi

  echo "现有备份目录:"
  for i in "${!backup_sources[@]}"; do
    echo "$i: ${backup_sources[$i]}"
  done

  while true; do
    read -p "请输入要删除的备份目录的编号 (或输入 'q' 退出): " choice
    if [[ "$choice" == "q" ]]; then
      break
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -lt ${#backup_sources[@]} ]; then
      echo "正在删除: ${backup_sources[$choice]}"
      rm -rf "${backup_sources[$choice]}"
      unset backup_sources[$choice]
      backup_sources=("${backup_sources[@]}")  # 重新索引数组
      echo "已删除备份目录。"
    else
      echo "无效输入，请重新输入。"
    fi
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

# 新增功能: 提示用户选择操作
function main_menu() {
  if [ ${#backup_sources[@]} -eq 0 ]; then
    echo "没有找到已有的备份配置，开始新配置。"
    get_backup_source
    add_more_sources
    get_onedrive_dir
    get_cron_time
    confirm_inputs
  else
    echo "找到已有的备份配置。"
    while true; do
      read -p "选择操作: 1) 立即执行备份 2) 修改配置 3) 退出 (输入1/2/3): " choice
      case "$choice" in
        1)
          echo "正在执行备份..."
          backup
          break
          ;;
        2)
          modify_configuration
          break
          ;;
        3)
          exit 0
          ;;
        *) 
          echo "无效输入，请重新输入。"
          ;;
      esac
    done
  fi
}

# 备份操作
function backup() {
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
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Backup completed successfully." >> "$backup_log_file"

    # 保留最近7天的备份，删除其他备份
    find "$backup_dir" -type f -mtime +7 -delete
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Old backups deleted successfully." >> "$backup_log_file"

    # 保留最近7天的日志文件，删除其他日志文件
    find "$log_dir" -type f -mtime +7 -delete
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Old logs deleted successfully." >> "$backup_log_file"

    # 使用 rclone 同步本地备份到 OneDrive
    rclone sync "$backup_dir" "onedrive:$onedrive_dir" --log-file="$rclone_log_file"

    if [ $? -eq 0 ]; then
      echo "$(date +%Y-%m-%d_%H:%M:%S) - Sync to OneDrive completed successfully." >> "$rclone_log_file"
    else
      echo "$(date +%Y-%m-%d_%H:%M:%S) - Sync to OneDrive failed." >> "$rclone_log_file"
    fi
  else
    echo "$(date +%Y-%m-%d_%H:%M:%S) - Backup failed." >> "$backup_log_file"
  fi

  # 设置自动备份的cron任务
  (crontab -l | grep -v "$(realpath $0)"; echo "$minute $hour * * * /bin/bash $(realpath $0)") | crontab -
  echo "自动备份任务已设置为每天 $hour:$minute 运行。"
}

# 修改配置
function modify_configuration() {
  delete_existing_backup
  add_more_sources
  get_onedrive_dir
  get_cron_time
  confirm_inputs
}

# 执行主菜单
main_menu
