安装：
```
cat > /etc/sysctl.conf << EOF
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr
EOF
sudo sysctl -p
```

检查状态：
```
sysctl net.ipv4.tcp_congestion_control
```

成功提示：
```
net.ipv4.tcp_congestion_control = bbr
```
