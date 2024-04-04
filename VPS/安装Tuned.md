安装：
```
apt update -y && apt full-upgrade -y && apt autoremove -y && apt autoclean -y && apt install -y tuned
```

启动：
```
sudo systemctl start tuned.service
```

开机自启：
```
sudo systemctl enable tuned.service
```

列出所有可用的tuned配置文件：
```
sudo tuned-adm list
```

使用标准模式：
```
tuned-adm profile balanced
```
```
tuned-adm profile throughput-performance
```

使用低延迟模式：

```
tuned-adm profile network-latency

```

使用低配置下网络优化模式：
```
tuned-adm profile virtual-guest
```
```
tuned-adm profile network-throughput
```

查看当前调用的优化配置：
```
tuned-adm active
```

停止：
```
sudo systemctl stop tuned.service
```

卸载：
```
sudo apt-get remove tuned
