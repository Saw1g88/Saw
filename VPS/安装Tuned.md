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

优化网络延迟模式：
```
tuned-adm profile network-latency

```

优化网络吞吐量模式：
```
tuned-adm profile network-throughput

```

同时优化网络延迟及吞吐量：
```
tuned-adm profile network-latency network-throughput

```

查看当前优化配置：
```
tuned-adm active
```

列出所有可用配置：
```
sudo tuned-adm list
```

停止：
```
sudo systemctl stop tuned.service
```

卸载：
```
sudo apt-get remove tuned
