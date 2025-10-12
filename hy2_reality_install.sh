#!/bin/bash

#####################################################################
# Sing-box 完整安装脚本
# 协议: Hysteria 2 + VLESS Reality Vision
# 证书: Cloudflare DNS API 自动申请
# 作者: Claude
# 版本: 2.0
#####################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置参数
HY2_PORT=""
REALITY_PORT=""
HY2_PASSWORD=""
REALITY_UUID=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""
REALITY_SHORT_ID=""
CERT_DOMAIN=""
CF_API_TOKEN=""
SNI=""
SERVER_IP=""

echo -e "${PURPLE}"
cat << "EOF"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║       Sing-box 双协议一键安装脚本                 ║
║                                                   ║
║   Hysteria 2 + VLESS Reality Vision               ║
║   Cloudflare DNS API 自动证书                     ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

#####################################################################
# 函数定义
#####################################################################

# 打印信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测操作系统
detect_os() {
    print_info "检测操作系统..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "无法检测操作系统"
        exit 1
    fi
    
    print_success "检测到系统: $OS $VERSION"
}

# 检查是否为 root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    print_info "安装依赖包..."
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt update -qq
        apt install -y curl wget tar openssl jq qrencode socat cron >/dev/null 2>&1
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" || "$OS" == "alma" ]]; then
        yum install -y curl wget tar openssl jq qrencode socat cronie >/dev/null 2>&1
    else
        print_error "不支持的操作系统: $OS"
        exit 1
    fi
    
    print_success "依赖包安装完成"
}

# 检查并安装 sing-box
check_install_singbox() {
    print_info "检查 sing-box 安装状态..."
    
    if command -v sing-box &> /dev/null; then
        CURRENT_VERSION=$(sing-box version 2>&1 | grep -oP 'version \K[0-9.]+' | head -1)
        print_success "检测到 sing-box 已安装 (版本: $CURRENT_VERSION)"
        
        read -p "是否重新安装最新版本? (y/n) [n]: " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    install_singbox
}

# 安装 sing-box
install_singbox() {
    print_info "正在安装 sing-box..."
    
    # 获取最新版本
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/v//')
    
    if [ -z "$LATEST_VERSION" ]; then
        print_error "无法获取 sing-box 最新版本"
        exit 1
    fi
    
    print_info "最新版本: v${LATEST_VERSION}"
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    # 下载并安装
    DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
    
    print_info "下载地址: $DOWNLOAD_URL"
    wget -q --show-progress -O /tmp/sing-box.tar.gz "$DOWNLOAD_URL"
    
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/
    cp /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    rm -rf /tmp/sing-box*
    
    # 验证安装
    if command -v sing-box &> /dev/null; then
        print_success "sing-box 安装成功 (v${LATEST_VERSION})"
    else
        print_error "sing-box 安装失败"
        exit 1
    fi
}

# 交互式配置
interactive_config() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  配置向导${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 获取服务器 IP
    print_info "正在获取服务器 IP..."
    SERVER_IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me || curl -s icanhazip.com)
    if [ -z "$SERVER_IP" ]; then
        read -p "无法自动获取 IP，请手动输入服务器 IP: " SERVER_IP
    fi
    print_success "服务器 IP: $SERVER_IP"
    echo ""
    
    # 域名配置
    echo -e "${YELLOW}━━━ 域名配置 ━━━${NC}"
    while true; do
        read -p "请输入你的域名 (例: proxy.example.com): " CERT_DOMAIN
        if [ -z "$CERT_DOMAIN" ]; then
            print_error "域名不能为空"
            continue
        fi
        
        # 验证域名格式
        if [[ ! "$CERT_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
            print_error "域名格式不正确"
            continue
        fi
        
        break
    done
    
    echo ""
    print_warning "请确保域名 ${CERT_DOMAIN} 已在 Cloudflare 添加并解析到: ${SERVER_IP}"
    read -p "域名是否已正确解析? (y/n): " dns_ready
    if [[ ! "$dns_ready" =~ ^[Yy]$ ]]; then
        print_error "请先配置 DNS 解析后再运行此脚本"
        exit 1
    fi
    
    echo ""
    
    # Cloudflare API Token
    echo -e "${YELLOW}━━━ Cloudflare API Token ━━━${NC}"
    echo -e "${BLUE}获取 API Token 步骤:${NC}"
    echo "1. 访问: https://dash.cloudflare.com/profile/api-tokens"
    echo "2. Create Token → Edit zone DNS"
    echo "3. Zone Resources: 选择你的域名"
    echo "4. 复制生成的 Token"
    echo ""
    
    while true; do
        read -p "请输入 Cloudflare API Token: " CF_API_TOKEN
        if [ -z "$CF_API_TOKEN" ]; then
            print_error "API Token 不能为空"
            continue
        fi
        break
    done
    
    echo ""
    
    # 端口配置
    echo -e "${YELLOW}━━━ 端口配置 ━━━${NC}"
    read -p "Hysteria 2 端口 [默认: 443]: " input_hy2_port
    HY2_PORT=${input_hy2_port:-443}
    
    read -p "Reality 端口 [默认: 8443]: " input_reality_port
    REALITY_PORT=${input_reality_port:-8443}
    
    # 验证端口
    if ! [[ "$HY2_PORT" =~ ^[0-9]+$ ]] || [ "$HY2_PORT" -lt 1 ] || [ "$HY2_PORT" -gt 65535 ]; then
        print_error "端口无效，使用默认值 443"
        HY2_PORT=443
    fi
    
    if ! [[ "$REALITY_PORT" =~ ^[0-9]+$ ]] || [ "$REALITY_PORT" -lt 1 ] || [ "$REALITY_PORT" -gt 65535 ]; then
        print_error "端口无效，使用默认值 8443"
        REALITY_PORT=8443
    fi
    
    echo ""
    
    # SNI 配置
    echo -e "${YELLOW}━━━ Reality SNI 配置 ━━━${NC}"
    echo "推荐的 SNI 域名:"
    echo "  1) www.bing.com (推荐)"
    echo "  2) www.apple.com"
    echo "  3) www.cloudflare.com"
    echo "  4) www.samsung.com"
    echo "  5) 自定义"
    
    read -p "请选择 [默认: 1]: " sni_choice
    sni_choice=${sni_choice:-1}
    
    case $sni_choice in
        1) SNI="www.bing.com" ;;
        2) SNI="www.apple.com" ;;
        3) SNI="www.cloudflare.com" ;;
        4) SNI="www.samsung.com" ;;
        5)
            read -p "请输入自定义 SNI 域名: " custom_sni
            SNI=${custom_sni:-www.bing.com}
            ;;
        *) SNI="www.bing.com" ;;
    esac
    
    echo ""
    
    # 配置确认
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  配置确认${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}服务器 IP:${NC}      $SERVER_IP"
    echo -e "${GREEN}域名:${NC}           $CERT_DOMAIN"
    echo -e "${GREEN}Hysteria 2 端口:${NC} $HY2_PORT"
    echo -e "${GREEN}Reality 端口:${NC}    $REALITY_PORT"
    echo -e "${GREEN}Reality SNI:${NC}     $SNI"
    echo -e "${GREEN}证书申请:${NC}       Cloudflare DNS API"
    echo ""
    
    read -p "确认以上配置并开始安装? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "安装已取消"
        exit 0
    fi
    
    echo ""
}

# 申请 SSL 证书
setup_certificate() {
    print_info "配置证书申请..."
    
    # 安装 acme.sh
    if [ ! -d "$HOME/.acme.sh" ]; then
        print_info "安装 acme.sh..."
        curl -s https://get.acme.sh | sh -s email=admin@${CERT_DOMAIN} >/dev/null 2>&1
        
        # 设置别名
        source ~/.bashrc 2>/dev/null || true
    fi
    
    # 设置 Cloudflare API
    export CF_Token="$CF_API_TOKEN"
    export CF_Account_ID=""
    export CF_Zone_ID=""
    
    # 设置默认 CA
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    
    print_info "使用 Cloudflare DNS API 申请证书..."
    print_info "域名: ${CERT_DOMAIN}"
    
    # 申请证书
    ~/.acme.sh/acme.sh --issue \
        --dns dns_cf \
        -d ${CERT_DOMAIN} \
        --keylength ec-256 \
        --force 2>&1 | grep -E "success|error|failed" || true
    
    # 安装证书
    mkdir -p /etc/sing-box/certs
    
    ~/.acme.sh/acme.sh --install-cert \
        -d ${CERT_DOMAIN} \
        --ecc \
        --key-file /etc/sing-box/certs/private.key \
        --fullchain-file /etc/sing-box/certs/cert.crt \
        --reloadcmd "systemctl reload sing-box 2>/dev/null || true" \
        >/dev/null 2>&1
    
    # 验证证书
    if [ -f "/etc/sing-box/certs/cert.crt" ] && [ -f "/etc/sing-box/certs/private.key" ]; then
        print_success "证书申请成功"
        
        # 设置权限
        chmod 644 /etc/sing-box/certs/cert.crt
        chmod 600 /etc/sing-box/certs/private.key
        
        # 显示证书信息
        CERT_EXPIRE=$(openssl x509 -in /etc/sing-box/certs/cert.crt -noout -enddate | cut -d= -f2)
        print_info "证书有效期至: $CERT_EXPIRE"
    else
        print_error "证书申请失败"
        print_error "请检查:"
        print_error "1. Cloudflare API Token 是否正确"
        print_error "2. 域名是否在 Cloudflare 托管"
        print_error "3. DNS 记录是否正确"
        exit 1
    fi
}

# 生成配置
generate_config() {
    print_info "生成配置参数..."
    
    # Hysteria 2 密码
    HY2_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    
    # Reality UUID
    REALITY_UUID=$(cat /proc/sys/kernel/random/uuid)
    
    # Reality 密钥对
    REALITY_KEYS=$(sing-box generate reality-keypair)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep "PrivateKey:" | awk '{print $2}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep "PublicKey:" | awk '{print $2}')
    
    # Reality Short ID
    REALITY_SHORT_ID=$(openssl rand -hex 8)
    
    print_success "配置参数生成完成"
}

# 创建 sing-box 配置文件
create_singbox_config() {
    print_info "创建 sing-box 配置文件..."
    
    mkdir -p /etc/sing-box
    
    cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "password": "${HY2_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${CERT_DOMAIN}",
        "key_path": "/etc/sing-box/certs/private.key",
        "certificate_path": "/etc/sing-box/certs/cert.crt",
        "alpn": [
          "h3"
        ]
      }
    },
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "users": [
        {
          "uuid": "${REALITY_UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI}",
            "server_port": 443
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": [
            "${REALITY_SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    
    # 验证配置文件
    if ! sing-box check -c /etc/sing-box/config.json; then
        print_error "配置文件验证失败"
        echo ""
        echo "当前配置内容:"
        cat /etc/sing-box/config.json
        echo ""
        echo "请检查以上配置，或提供错误信息以便修复"
        exit 1
    fi
    
    print_success "配置文件创建成功"
}

# 创建 systemd 服务
create_systemd_service() {
    print_info "创建 systemd 服务..."
    
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "systemd 服务创建完成"
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."
    
    # UFW
    if command -v ufw &> /dev/null; then
        ufw allow ${HY2_PORT}/udp comment "Hysteria 2" >/dev/null 2>&1
        ufw allow ${REALITY_PORT}/tcp comment "Reality" >/dev/null 2>&1
        ufw reload >/dev/null 2>&1 || true
        print_success "UFW 防火墙规则已添加"
    fi
    
    # firewalld
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=${HY2_PORT}/udp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${REALITY_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        print_success "firewalld 防火墙规则已添加"
    fi
}

# 启动服务
start_service() {
    print_info "启动 sing-box 服务..."
    
    systemctl enable sing-box >/dev/null 2>&1
    systemctl start sing-box
    
    sleep 3
    
    if systemctl is-active --quiet sing-box; then
        print_success "sing-box 服务启动成功"
    else
        print_error "sing-box 服务启动失败"
        print_error "查看日志: journalctl -u sing-box -n 50"
        journalctl -u sing-box -n 20 --no-pager
        exit 1
    fi
}

# 生成分享信息
generate_share_info() {
    print_info "生成分享信息..."
    
    # 生成 Hysteria 2 分享链接
    # 标准格式: hysteria2://password@server:port?insecure=0&sni=domain#remarks
    HY2_LINK="hysteria2://${HY2_PASSWORD}@${CERT_DOMAIN}:${HY2_PORT}/?insecure=0&sni=${CERT_DOMAIN}#${CERT_DOMAIN}"
    
    # 生成 VLESS Reality 分享链接

    VLESS_LINK_DOMAIN="vless://${REALITY_UUID}@${CERT_DOMAIN}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#${CERT_DOMAIN}"
    
    # 默认使用域名版本
    VLESS_LINK="$VLESS_LINK_DOMAIN"
    
    # 保存到文件
    cat > /root/sing-box-info.txt <<EOF
╔═══════════════════════════════════════════════════════════════╗
║                    Sing-box 配置信息                          ║
╚═══════════════════════════════════════════════════════════════╝

服务器信息:
  IP 地址: ${SERVER_IP}
  域名: ${CERT_DOMAIN}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Hysteria 2 配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

端口: ${HY2_PORT}
密码: ${HY2_PASSWORD}
服务器: ${CERT_DOMAIN}:${HY2_PORT}

客户端配置 (YAML):
---
server: ${CERT_DOMAIN}:${HY2_PORT}
auth: ${HY2_PASSWORD}
tls:
  sni: ${CERT_DOMAIN}
---

Hysteria 2 分享链接 (可直接导入):
${HY2_LINK}

注意: 请确保客户端支持 Hysteria 2 协议


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VLESS Reality 配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

地址: ${CERT_DOMAIN}
端口: ${REALITY_PORT}
UUID: ${REALITY_UUID}
Flow: xtls-rprx-vision
SNI: ${SNI}
Fingerprint: chrome
Public Key: ${REALITY_PUBLIC_KEY}
Short ID: ${REALITY_SHORT_ID}

VLESS 分享链接:
${VLESS_LINK}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
证书信息
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

域名: ${CERT_DOMAIN}
申请方式: Cloudflare DNS API
证书路径: /etc/sing-box/certs/cert.crt
私钥路径: /etc/sing-box/certs/private.key
自动续期: 已启用

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
文件位置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

配置文件: /etc/sing-box/config.json
证书目录: /etc/sing-box/certs/
配置信息: /root/sing-box-info.txt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
服务管理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

查看状态: systemctl status sing-box
启动服务: systemctl start sing-box
停止服务: systemctl stop sing-box
重启服务: systemctl restart sing-box
查看日志: journalctl -u sing-box -f
测试配置: sing-box check -c /etc/sing-box/config.json

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
客户端推荐
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Windows:  NekoRay / v2rayN
Android:  NekoBox / v2rayNG
iOS:      Shadowrocket / Stash
macOS:    NekoRay / Clash Verge

EOF

        
    echo "$VLESS_LINK" > /root/vless_link.txt
    echo "$HY2_LINK" > /root/hy2_link.txt
    
    # 保存所有链接到一个文件
    cat > /root/share_links.txt <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  分享链接汇总
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

=== Hysteria 2 分享链接 ===
${HY2_LINK}

=== VLESS Reality 分享链接 ===
${VLESS_LINK}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
使用说明
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Hysteria 2:
  - 直接复制链接导入客户端
  - 支持: NekoRay, NekoBox 等

VLESS Reality:
  - 使用域名连接: ${CERT_DOMAIN}:${REALITY_PORT}
  - 直接复制链接导入客户端

支持的客户端:
  - Windows:  NekoRay / v2rayN
  - Android:  NekoBox / v2rayNG
  - iOS:      Shadowrocket / Stash
  - macOS:    NekoRay / Clash Verge

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    
    # 生成二维码
    if command -v qrencode &> /dev/null; then
        qrencode -t ANSIUTF8 -o /root/vless_qr.txt "$VLESS_LINK" 2>/dev/null || true
        qrencode -t PNG -o /root/vless_qr.png "$VLESS_LINK" 2>/dev/null || true
        qrencode -t ANSIUTF8 -o /root/hy2_qr.txt "$HY2_LINK" 2>/dev/null || true
        qrencode -t PNG -o /root/hy2_qr.png "$HY2_LINK" 2>/dev/null || true
    fi
    
    print_success "配置信息已保存"
}

# 显示安装结果
show_result() {
    clear
    echo -e "${PURPLE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║                  🎉 安装完成！                                ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Hysteria 2 配置${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}服务器:${NC} ${CERT_DOMAIN}:${HY2_PORT}"
    echo -e "${CYAN}密码:${NC}   ${HY2_PASSWORD}"
    echo ""
    echo -e "${YELLOW}客户端配置 (YAML):${NC}"
    echo "---"
    echo "server: ${CERT_DOMAIN}:${HY2_PORT}"
    echo "auth: ${HY2_PASSWORD}"
    echo "tls:"
    echo "  sni: ${CERT_DOMAIN}"
    echo "---"
    echo ""
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  VLESS Reality 配置${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}地址:${NC}       ${CERT_DOMAIN}"
    echo -e "${CYAN}端口:${NC}       ${REALITY_PORT}"
    echo -e "${CYAN}UUID:${NC}       ${REALITY_UUID}"
    echo -e "${CYAN}Flow:${NC}       xtls-rprx-vision"
    echo -e "${CYAN}SNI:${NC}        ${SNI}"
    echo -e "${CYAN}Public Key:${NC} ${REALITY_PUBLIC_KEY}"
    echo -e "${CYAN}Short ID:${NC}   ${REALITY_SHORT_ID}"
    echo ""
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  分享链接 (可直接导入客户端)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Hysteria 2:${NC}"
    echo -e "${YELLOW}${HY2_LINK}${NC}"
    echo ""
    echo -e "${CYAN}VLESS Reality:${NC}"
    echo -e "${YELLOW}${VLESS_LINK}${NC}"
    echo ""
    
    # 显示二维码
    if [ -f /root/vless_qr.txt ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  Reality 二维码 (手机扫描)${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        cat /root/vless_qr.txt
        echo ""
    fi
    
    if [ -f /root/hy2_qr.txt ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  Hysteria 2 二维码 (手机扫描)${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        cat /root/hy2_qr.txt
        echo ""
    fi
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  重要信息${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}📁 配置文件位置:${NC}"
    echo "   /root/sing-box-info.txt    (完整配置信息)"
    echo ""
    echo -e "${YELLOW}🔧 客户端配置说明:${NC}"
    echo ""
    echo -e "${CYAN}Hysteria 2:${NC}"
    echo "   ✅ NekoRay (Windows/Linux) - 完美支持"
    echo "   ✅ NekoBox (Android) - 完美支持"
    echo "   ⚠️  v2rayN - 需要最新版本"
    echo "   ⚠️  如果链接无法导入，请手动配置"
    echo ""
    echo -e "${CYAN}VLESS Reality:${NC}"
    echo "   🌐 使用域名连接: ${CERT_DOMAIN}:${REALITY_PORT}"
    echo "   ✅ 支持所有主流客户端"
    echo "   ✅ 直接复制链接导入即可"
    echo ""
    echo -e "${YELLOW}服务管理:${NC}"
    echo "   systemctl status sing-box  (查看状态)"
    echo "   systemctl restart sing-box (重启服务)"
    echo "   journalctl -u sing-box -f  (查看日志)"
    echo ""
    echo -e "${YELLOW}📱 推荐客户端:${NC}"
    echo "   Windows:  NekoRay / v2rayN"
    echo "   Android:  NekoBox / v2rayNG"
    echo "   iOS:      Shadowrocket / Stash"
    echo "   macOS:    NekoRay"
    echo ""
    echo -e "${YELLOW}💡 使用提示:${NC}"
    echo "   1. 复制分享链接 → 客户端 → 从剪贴板导入"
    echo "   2. 或扫描对应的二维码"
    echo "   3. Hysteria 2: 高速下载、视频流畅"
    echo "   4. Reality: 稳定连接、抗封锁强"
    echo "   5. 证书自动续期，无需手动操作"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${PURPLE}感谢使用！祝您使用愉快！${NC}"
    echo ""
}

#####################################################################
# 主函数
#####################################################################

main() {
    check_root
    detect_os
    install_dependencies
    check_install_singbox
    interactive_config
    setup_certificate
    generate_config
    create_singbox_config
    create_systemd_service
    configure_firewall
    start_service
    generate_share_info
    show_result
}

# 运行主函数
main

#清理
rm vless*txt
rm hy2*txt
rm share*txt
rm *png
