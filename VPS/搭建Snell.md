安装依赖:
```
sudo apt update && apt upgrade -y && sudo apt install wget unzip && apt install vim
```

AMD安装:
```
wget https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip
```

ARM安装：
```
wget https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-aarch64.zip
```

AMD解压：
```
sudo unzip snell-server-v4.0.1-linux-amd64.zip -d /usr/local/bin
```

ARM解压：
```
sudo unzip snell-server-v4.0.1-linux-aarch64.zip -d /usr/local/bin
```
赋予服务权限：
```
chmod +x /usr/local/bin/snell-server
```

新建文件夹：
```
sudo mkdir /etc/snell
```

写配置文件：
```
sudo vim /etc/snell/snell-server.conf
```

文件内容：
```
[snell-server]
listen = 0.0.0.0:11807
psk = xxxxxxx
ipv6 = false
```

写 Systemd 服务文件：
```
sudo vim /lib/systemd/system/snell.service
```

文件内容：
```
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
```

重载服务：
```
sudo systemctl daemon-reload
```

启动：
```
sudo systemctl start snell
```

开机运行：
```
sudo systemctl enable snell
```

关闭：
```
sudo systemctl stop snell
```

查看状态：
```
sudo systemctl status snell
```

停止原snell服务：
```
sudo systemctl disable snell
sudo systemctl stop snell
```

卸载snell：
```
rm /path/to/snell-server
```

移除所有snell文件：
```
rm -rf snell-server-v4.0.1-linux-amd64.zip
rm -rf /usr/local/bin/snell-server
rm -rf /lib/systemd/system/snell.service
rm -rf /etc/snell-server.conf 
```

一键脚本：
```
wget -O snell.sh --no-check-certificate https://git.io/Snell.sh && chmod +x snell.sh && ./snell.sh
