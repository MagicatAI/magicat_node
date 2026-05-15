#!/bin/bash
set -e  # 遇错即止

# 安装参数
DOWNLOAD_URL="https://github.com/MagicatAI/magicat_node/releases/download/node_v1.0.0.0/sing-box"
SINGBOX_BIN="/usr/local/bin/sing-box"
SINGBOX_CONF="/etc/sing-box/config.json"

# 系统优化 (BBR)
grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf || {
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
}
sysctl -p

# 创建目录
mkdir -p /etc/sing-box

# 下载内核
systemctl stop sing-box 2>/dev/null || true
curl -L -o "$SINGBOX_BIN" "$DOWNLOAD_URL"
chmod +x "$SINGBOX_BIN"

# 生成配置参数
UUID=$("$SINGBOX_BIN" generate uuid)
KEYS=$("$SINGBOX_BIN" generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'PublicKey' | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 4)

# 写入配置文件
cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "disabled": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.cloudflare.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.cloudflare.com",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# 写入 Systemd 服务文件
cat > /etc/systemd/system/sing-box.service << 'EOF'
[Unit]
Description=sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1000000
LimitNPROC=65535
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
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

# 启动服务
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# 查看运行状态
systemctl status sing-box --no-pager

# 获取服务器IP
SERVER_IP=$(curl -s https://api.ipify.org)

# 客户端配置
cat << EOF
{
  "serverdomain": "${SERVER_IP}",
  "uuid": "${UUID}",
  "publicKey": "${PUBLIC_KEY}",
  "shortid": "${SHORT_ID}"
}
EOF
