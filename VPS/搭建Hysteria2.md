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

quic:
  initStreamReceiveWindow: 26843545 
  maxStreamReceiveWindow: 26843545 
  initConnReceiveWindow: 67108864 
  maxConnReceiveWindow: 67108864

EOF
```

写配置文件（Warp分流）:
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

quic:
  initStreamReceiveWindow: 26843545 
  maxStreamReceiveWindow: 26843545 
  initConnReceiveWindow: 67108864 
  maxConnReceiveWindow: 67108864

acl:  
  inline: 
    - warp(geosite:openai)
    - warp(geosite:netflix)
    - warp(suffix:ip.gs)
    - direct(all)

outbounds:
  - name: direct
    type: direct
  - name: warp
    type: socks5
    socks5:
      addr: 127.0.0.1:40000

EOF
```

Linux 性能优化：
```
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
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

一键脚本：
```
curl -sS -o Hysteria.sh https://raw.githubusercontent.com/passeway/Hysteria/main/Hysteria.sh  && chmod +x Hysteria.sh && ./Hysteria.sh
```
