安装依赖：
```
apt update -y && apt install curl sudo -y && apt install vim -y
```

安装（更新）Hysteria2：
```
bash <(curl -fsSL https://get.hy2.sh/)
```

生成自签证书：
```
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=bing.com" -days 36500 && sudo chown hysteria /etc/hysteria/server.key && sudo chown hysteria /etc/hysteria/server.crt
```

写配置文件:
```
cat << EOF > /etc/hysteria/config.yaml
listen: :8443 

acme:
  domains:
    - xx.xx.xx
  email: testa@sharklasers.com 

auth:
  type: password
  password: xxxxxx

masquerade: 
  type: proxy
  proxy:
    url: https://bing.com/
    rewriteHost: true

EOF
```

授予可执行文件 cap_net_bind_service 权限：
```
sudo setcap cap_net_bind_service=+ep ./hysteria-linux-amd64-avx
```

启动:
```
systemctl start hysteria-server.service
```

重启:
```
systemctl restart hysteria-server.service
```

查看状态:
```
systemctl status hysteria-server.service
```

查看配置文件：
```
vim /etc/hysteria/config.yaml
```

停止:
```
systemctl stop hysteria-server.service
```

设置开机自启:
```
systemctl enable hysteria-server.service
```

查看日志:
```
journalctl -u hysteria-server.service
```

卸载：
```
bash <(curl -fsSL https://get.hy2.sh/) --remove
```


