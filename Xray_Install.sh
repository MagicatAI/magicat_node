#!/bin/bash
set -e  # 遇错即止

DOWNLOAD_URL="https://github.com/MagicatAI/magicat_X/releases/download/X_v1.0.0.0/xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"

# 1. 系统优化 (BBR) - 避免重复写入
grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf || {
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
}
sysctl -p

# 2. 创建目录
mkdir -p /usr/local/bin /usr/local/etc/xray

# 3. 下载内核
systemctl stop xray 2>/dev/null || true
curl -L -o "$XRAY_BIN" "$DOWNLOAD_URL"
chmod +x "$XRAY_BIN"

# 4. 生成配置参数
UUID=$("$XRAY_BIN" uuid)
KEYS=$("$XRAY_BIN" x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'Password' | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

# 5. 写入配置文件
cat > "$XRAY_CONF" << EOF
{
  "log": {
    "access": "none",
    "error": "none",
    "loglevel": "none",
    "dnsLog": false
  },
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "${UUID}",
        "flow": "xtls-rprx-vision"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "www.cloudflare.com:443",
        "serverNames": ["www.cloudflare.com", "cloudflare.com"],
        "privateKey": "${PRIVATE_KEY}",
        "shortIds": ["${SHORT_ID}"],
        "fingerprint": "chrome"
      },
      "sockopt": {
        "tcpFastOpen": 256,
        "tcpCongestion": "bbr"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {
      "domainStrategy": "UseIPv4"
    }
  }]
}
EOF

# 6. 写入 Systemd 服务文件
cat > /etc/systemd/system/xray.service << 'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1000000
LimitNPROC=65535
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=2s
RestartPreventExitStatus=23
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

# 7. 启动服务（只启动一次）
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 8. 输出客户端参数
sleep 2
echo ""
echo "======== 客户端配置参数 ========"
echo "UUID      : ${UUID}"
echo "PublicKey : ${PUBLIC_KEY}"
echo "ShortId   : ${SHORT_ID}"
echo "================================"
echo ""

systemctl status xray --no-pager
