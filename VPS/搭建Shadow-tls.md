系统更新：
```
apt update && apt upgrade -y
```

安装 Shadow-tls：

ARM
```
wget https://github.com/ihciah/shadow-tls/releases/download/v0.2.25/shadow-tls-aarch64-unknown-linux-musl -O /usr/local/bin/shadow-tls
```
AMD
```
wget https://github.com/ihciah/shadow-tls/releases/download/v0.2.25/shadow-tls-x86_64-unknown-linux-musl -O /usr/local/bin/shadow-tls
```

赋予权限：
```
chmod +x /usr/local/bin/shadow-tls
```

写配置文件：
```
vim /etc/systemd/system/shadow-tls.service
```

配置文件内容：
```
[Unit]
Description=Shadow-TLS Server Service
Documentation=man:sstls-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/shadow-tls --fastopen --v3 server --listen 0.0.0.0:18880 --server 127.0.0.1:40660（原协议端口） --tls   douyin.com  --password xxxxxxxxxxxxx
StandardOutput=syslog
StandardError=syslog
Environment=MONOIO_FORCE_LEGACY_DRIVER=1
SyslogIdentifier=shadow-tls

[Install]
WantedBy=multi-user.target
```

重载服务：
```
systemctl daemon-reload
```

启动：
```
systemctl start shadow-tls.service
```

停止：
```
systemctl stop shadow-tls.service
```

重启：
```
systemctl restart shadow-tls.service
```

开机自启：
```
systemctl enable shadow-tls.service
```

查看状态：
```
systemctl status shadow-tls.service
```


