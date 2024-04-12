```
echo "3" > /proc/sys/net/ipv4/tcp_fastopen && echo "net.ipv4.tcp_fastopen=3" > /etc/sysctl.d/30-tcp_fastopen.conf
