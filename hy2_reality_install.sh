#!/bin/bash

#####################################################################
# Sing-box 管理脚本
# 协议: Hysteria 2 + VLESS Reality Vision
# 功能: 安装、卸载、灵活证书配置
# 作者: Chaconne
# 版本: 3.0
#####################################################################

trap 'rm -f /root/hy2*txt /root/vless*txt /root/hy2*png /root/vless*png /root/share*' EXIT


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
USE_ACME=false
DNS_PROVIDER="standalone"

#####################################################################
# 通用函数
#####################################################################

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

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "无法检测操作系统"
        exit 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

#####################################################################
# 主菜单
#####################################################################

show_main_menu() {
    clear
    echo -e "${PURPLE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║       Sing-box 管理脚本 v3.0                      ║
║                                                   ║
║   Hysteria 2 + VLESS Reality Vision               ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${CYAN}请选择操作:${NC}"
    echo ""
    echo "  1)安装 Sing-box (Hysteria 2 + Reality)"
    echo "  2)卸载 Sing-box"
    echo "  3)查看配置信息"
    echo "  4)退出"
    echo ""
    
    read -p "请输入选项 [1-4]: " menu_choice
    
    case $menu_choice in
        1)
            install_singbox_menu
            ;;
        2)
            uninstall_singbox_menu
            ;;
        3)
            show_config_menu
            ;;
        4)
            echo -e "${GREEN}再见！${NC}"
            exit 0
            ;;
        *)
            print_error "无效选项"
            sleep 2
            show_main_menu
            ;;
    esac
}

#####################################################################
# 查看配置菜单
#####################################################################

show_config_menu() {
    if [ ! -f /root/sing-box-info.txt ]; then
        print_error "未找到配置信息，请先安装 Sing-box"
        sleep 3
        show_main_menu
        return
    fi
    
    clear
    cat /root/sing-box-info.txt
    echo ""
    echo -e "${YELLOW}按任意键返回主菜单...${NC}"
    read -n 1
    show_main_menu
}

#####################################################################
# 卸载功能
#####################################################################

uninstall_singbox_menu() {
    clear
    echo -e "${RED}"
    cat << "EOF"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║       卸载 Sing-box                               ║
║                                                   ║
║   ⚠️  警告: 将删除所有配置和证书！                ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo ""
    echo -e "${YELLOW}此操作将删除:${NC}"
    echo "  • sing-box 程序"
    echo "  • 所有配置文件"
    echo "  • SSL 证书"
    echo "  • systemd 服务"
    echo "  • 防火墙规则"
    echo "  • 生成的分享链接和二维码"
    echo ""
    
    read -p "确认要卸载吗? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_warning "已取消卸载"
        sleep 2
        show_main_menu
        return
    fi
    
    echo ""
    print_info "开始卸载..."
    
    # 停止服务
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    print_success "服务已停止"
    
    # 删除文件
    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload
    rm -f /usr/local/bin/sing-box
    rm -rf /etc/sing-box
    rm -f /root/sing-box-info.txt
    rm -f /root/share_links.txt
    rm -f /root/hy2_link.txt
    rm -f /root/vless_link.txt
    rm -f /root/*_qr.png
    rm -f /root/*_qr.txt
    print_success "文件已删除"
    
    # 防火墙规则
    if command -v ufw &> /dev/null; then
        ufw status numbered 2>/dev/null | grep -i "hysteria\|reality" | awk '{print $1}' | sed 's/\[//g' | sed 's/\]//g' | sort -rn | while read rule_num; do
            echo "y" | ufw delete $rule_num 2>/dev/null || true
        done
        ufw reload 2>/dev/null || true
    fi
    
    echo ""
    echo -e "${GREEN}✅ Sing-box 已完全卸载！${NC}"
    echo ""
    read -p "是否同时删除 acme.sh? (y/n) [n]: " remove_acme
    if [[ "$remove_acme" =~ ^[Yy]$ ]]; then
        rm -rf ~/.acme.sh
        crontab -l 2>/dev/null | grep -v '.acme.sh' | crontab - 2>/dev/null || true
        print_success "acme.sh 已删除"
    fi
    
    echo ""
    echo -e "${YELLOW}按任意键返回主菜单...${NC}"
    read -n 1
    show_main_menu
}

#####################################################################
# 安装功能
#####################################################################

install_singbox_menu() {
    clear
    echo -e "${GREEN}开始安装 Sing-box...${NC}"
    echo ""
    
    detect_os
    print_success "系统: $OS $VERSION"
    
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
    
    echo ""
    echo -e "${YELLOW}按任意键返回主菜单...${NC}"
    read -n 1
    show_main_menu
}

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
    
    install_singbox_binary
}

install_singbox_binary() {
    print_info "正在安装 sing-box..."
    
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/v//')
    
    if [ -z "$LATEST_VERSION" ]; then
        print_error "无法获取 sing-box 最新版本"
        exit 1
    fi
    
    print_info "最新版本: v${LATEST_VERSION}"
    
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
    
    DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
    
    wget -q --show-progress -O /tmp/sing-box.tar.gz "$DOWNLOAD_URL"
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/
    cp /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    rm -rf /tmp/sing-box*
    
    if command -v sing-box &> /dev/null; then
        print_success "sing-box 安装成功 (v${LATEST_VERSION})"
    else
        print_error "sing-box 安装失败"
        exit 1
    fi
}

interactive_config() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  配置向导${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 获取服务器 IP
    print_info "正在获取服务器 IP..."
    SERVER_IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me || curl -s icanhazip.com)
    if [ -z "$SERVER_IP" ]; then
        read -p "无法自动获取 IP，请手动输入服务器 IP: " SERVER_IP
    fi
    print_success "服务器 IP: $SERVER_IP"
    echo ""
    
    # 证书配置
    echo -e "${YELLOW}━━━ 证书配置 ━━━${NC}"
    echo "  1) 自签名证书 (快速安装，客户端需设置 insecure: true)"
    echo "  2) Let's Encrypt 证书 (需要域名，更安全)"
    read -p "请选择 [默认: 2]: " cert_choice
    cert_choice=${cert_choice:-2}
    
    if [ "$cert_choice" = "2" ]; then
        while true; do
            read -p "请输入你的域名 (例: proxy.example.com): " CERT_DOMAIN
            if [ -z "$CERT_DOMAIN" ]; then
                print_error "域名不能为空"
                continue
            fi
            
            if [[ ! "$CERT_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
                print_error "域名格式不正确"
                continue
            fi
            
            break
        done
        
        USE_ACME=true
        
        echo ""
        echo -e "${YELLOW}━━━ 证书申请方式 ━━━${NC}"
        echo "  1) Standalone 模式 (推荐)"
        echo "     - 需要 80 端口"
        echo "     - 域名可托管在任何 DNS 服务商"
        echo "     - 适合新手和测试"
        echo ""
        echo "  2) Cloudflare DNS API (高级)"
        echo "     - 不需要 80 端口"
        echo "     - 域名必须在 Cloudflare 托管"
        echo "     - 需要 API Token"
        echo "     - 续期更可靠，支持泛域名"
        echo ""
        read -p "请选择 [默认: 1]: " dns_choice
        dns_choice=${dns_choice:-1}
        
        if [ "$dns_choice" = "2" ]; then
            DNS_PROVIDER="cloudflare"
            echo ""
            print_warning "域名必须已在 Cloudflare 并解析到: ${SERVER_IP}"
            echo ""
            echo -e "${BLUE}获取 Cloudflare API Token:${NC}"
            echo "  1. 访问: https://dash.cloudflare.com/profile/api-tokens"
            echo "  2. Create Token → Edit zone DNS"
            echo "  3. Zone Resources: 选择你的域名"
            echo "  4. 复制生成的 Token"
            echo ""
            read -p "请输入 Cloudflare API Token: " CF_API_TOKEN
        else
            DNS_PROVIDER="standalone"
            print_info "将使用 Standalone 模式 (需要 80 端口)"
            echo ""
            print_warning "请确保域名 ${CERT_DOMAIN} 已解析到: ${SERVER_IP}"
            read -p "域名是否已正确解析? (y/n): " dns_ready
            if [[ ! "$dns_ready" =~ ^[Yy]$ ]]; then
                print_error "请先配置 DNS 解析后再运行此脚本"
                exit 1
            fi
        fi
    else
        USE_ACME=false
        print_info "将使用自签名证书"
    fi
    
    echo ""
    
    # 端口配置
    echo -e "${YELLOW}━━━ 端口配置 ━━━${NC}"
    read -p "Hysteria 2 端口 [默认: 443]: " input_hy2_port
    HY2_PORT=${input_hy2_port:-443}
    
    read -p "Reality 端口 [默认: 8443]: " input_reality_port
    REALITY_PORT=${input_reality_port:-8443}
    
    echo ""
    
    # SNI 配置
    echo -e "${YELLOW}━━━ Reality SNI 配置 ━━━${NC}"
    echo "推荐的 SNI 域名:"
    echo "  1) www.microsoft.com (推荐)"
    echo "  2) www.apple.com"
    echo "  3) www.cloudflare.com"
    echo "  4) www.bing.com"
    echo "  5) 自定义"
    
    read -p "请选择 [默认: 1]: " sni_choice
    sni_choice=${sni_choice:-1}
    
    case $sni_choice in
        1) SNI="www.microsoft.com" ;;
        2) SNI="www.apple.com" ;;
        3) SNI="www.cloudflare.com" ;;
        4) SNI="www.bing.com" ;;
        5)
            read -p "请输入自定义 SNI 域名: " custom_sni
            SNI=${custom_sni:-www.microsoft.com}
            ;;
        *) SNI="www.microsoft.com" ;;
    esac
    
    echo ""
    
    # 配置确认
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  配置确认${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}服务器 IP:${NC}      $SERVER_IP"
    if [ "$USE_ACME" = true ]; then
        echo -e "${GREEN}域名:${NC}           $CERT_DOMAIN"
        echo -e "${GREEN}证书申请:${NC}       $DNS_PROVIDER"
    else
        echo -e "${GREEN}证书:${NC}           自签名证书"
    fi
    echo -e "${GREEN}Hysteria 2 端口:${NC} $HY2_PORT"
    echo -e "${GREEN}Reality 端口:${NC}    $REALITY_PORT"
    echo -e "${GREEN}Reality SNI:${NC}     $SNI"
    echo ""
    
    read -p "确认以上配置并开始安装? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "安装已取消"
        sleep 2
        show_main_menu
        exit 0
    fi
    
    echo ""
}

setup_certificate() {
    if [ "$USE_ACME" != true ]; then
        print_info "生成自签名证书..."
        mkdir -p /etc/sing-box/certs
        openssl ecparam -name prime256v1 -out /tmp/ecparam.pem
        openssl req -x509 -nodes -newkey ec:/tmp/ecparam.pem \
            -keyout /etc/sing-box/certs/private.key \
            -out /etc/sing-box/certs/cert.crt \
            -subj "/CN=bing.com" \
            -days 36500
        rm -f /tmp/ecparam.pem
        chmod 644 /etc/sing-box/certs/cert.crt
        chmod 600 /etc/sing-box/certs/private.key
        print_success "自签名证书生成完成"
        return
    fi
    
    print_info "配置证书申请..."
    
    if [ ! -d "$HOME/.acme.sh" ]; then
        print_info "安装 acme.sh..."
        curl -s https://get.acme.sh | sh -s email=admin@${CERT_DOMAIN} >/dev/null 2>&1
        source ~/.bashrc 2>/dev/null || true
    fi
    
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    
    mkdir -p /etc/sing-box/certs
    
    if [ "$DNS_PROVIDER" = "cloudflare" ]; then
        print_info "使用 Cloudflare DNS API 申请证书..."
        export CF_Token="$CF_API_TOKEN"
        
        ~/.acme.sh/acme.sh --issue \
            --dns dns_cf \
            -d ${CERT_DOMAIN} \
            --keylength ec-256 \
            --force 2>&1 | grep -E "success|error|failed" || true
    else
        print_info "使用 Standalone 模式申请证书..."
        ~/.acme.sh/acme.sh --issue \
            -d ${CERT_DOMAIN} \
            --standalone \
            --keylength ec-256 \
            --force 2>&1 | grep -E "success|error|failed" || true
    fi
    
    ~/.acme.sh/acme.sh --install-cert \
        -d ${CERT_DOMAIN} \
        --ecc \
        --key-file /etc/sing-box/certs/private.key \
        --fullchain-file /etc/sing-box/certs/cert.crt \
        --reloadcmd "systemctl reload sing-box 2>/dev/null || true" \
        >/dev/null 2>&1
    
    if [ -f "/etc/sing-box/certs/cert.crt" ] && [ -f "/etc/sing-box/certs/private.key" ]; then
        chmod 644 /etc/sing-box/certs/cert.crt
        chmod 600 /etc/sing-box/certs/private.key
        print_success "证书申请成功"
        CERT_EXPIRE=$(openssl x509 -in /etc/sing-box/certs/cert.crt -noout -enddate | cut -d= -f2)
        print_info "证书有效期至: $CERT_EXPIRE"
    else
        print_error "证书申请失败"
        print_error "请检查域名解析和 API Token (如果使用)"
        exit 1
    fi
}

generate_config() {
    print_info "生成配置参数..."
    
    HY2_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    REALITY_UUID=$(cat /proc/sys/kernel/random/uuid)
    
    REALITY_KEYS=$(sing-box generate reality-keypair)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep "PrivateKey:" | awk '{print $2}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep "PublicKey:" | awk '{print $2}')
    
    REALITY_SHORT_ID=$(openssl rand -hex 8)
    
    print_success "配置参数生成完成"
}

create_singbox_config() {
    print_info "创建 sing-box 配置文件..."
    
    mkdir -p /etc/sing-box
    
    # 确定服务器名称
    if [ "$USE_ACME" = true ]; then
        SERVER_NAME="$CERT_DOMAIN"
    else
        SERVER_NAME="bing.com"
    fi
    
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
        "server_name": "${SERVER_NAME}",
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
    
    if ! sing-box check -c /etc/sing-box/config.json; then
        print_error "配置文件验证失败"
        cat /etc/sing-box/config.json
        exit 1
    fi
    
    print_success "配置文件创建成功"
}

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

configure_firewall() {
    print_info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        ufw allow ${HY2_PORT}/udp comment "Hysteria 2" >/dev/null 2>&1
        ufw allow ${REALITY_PORT}/tcp comment "Reality" >/dev/null 2>&1
        ufw reload >/dev/null 2>&1 || true
        print_success "UFW 防火墙规则已添加"
    fi
    
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=${HY2_PORT}/udp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${REALITY_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        print_success "firewalld 防火墙规则已添加"
    fi
}

start_service() {
    print_info "启动 sing-box 服务..."
    
    systemctl enable sing-box >/dev/null 2>&1
    systemctl start sing-box
    
    sleep 3
    
    if systemctl is-active --quiet sing-box; then
        print_success "sing-box 服务启动成功"
    else
        print_error "sing-box 服务启动失败"
        journalctl -u sing-box -n 20 --no-pager
        exit 1
    fi
}

generate_share_info() {
    print_info "生成分享信息..."
    
    # 确定连接地址
    if [ "$USE_ACME" = true ]; then
        CONNECT_ADDR="$CERT_DOMAIN"
        HY2_LINK="hysteria2://${HY2_PASSWORD}@${CERT_DOMAIN}:${HY2_PORT}/?insecure=0&sni=${CERT_DOMAIN}#${CERT_DOMAIN}"
    else
        CONNECT_ADDR="$SERVER_IP"
        HY2_LINK="hysteria2://${HY2_PASSWORD}@${SERVER_IP}:${HY2_PORT}/?insecure=1#Hysteria2-${SERVER_IP}"
    fi
    
    VLESS_LINK="vless://${REALITY_UUID}@${CONNECT_ADDR}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#Reality-${CONNECT_ADDR}"
    
    # 生成配置文件
    cat > /root/sing-box-info.txt <<EOF
╔═══════════════════════════════════════════════════════════════╗
║                    Sing-box 配置信息                          ║
╚═══════════════════════════════════════════════════════════════╝

服务器信息:
  IP 地址: ${SERVER_IP}
$([ "$USE_ACME" = true ] && echo "  域名: ${CERT_DOMAIN}")
$([ "$USE_ACME" = true ] && echo "  证书: Let's Encrypt ($DNS_PROVIDER)" || echo "  证书: 自签名证书")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Hysteria 2 配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

端口: ${HY2_PORT}
密码: ${HY2_PASSWORD}
连接: ${CONNECT_ADDR}:${HY2_PORT}

客户端配置 (YAML):
---
server: ${CONNECT_ADDR}:${HY2_PORT}
auth: ${HY2_PASSWORD}
$([ "$USE_ACME" = true ] && echo "tls:" || echo "tls:")
$([ "$USE_ACME" = true ] && echo "  sni: ${CERT_DOMAIN}" || echo "  insecure: true")
---

Hysteria 2 分享链接:
${HY2_LINK}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VLESS Reality 配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

地址: ${CONNECT_ADDR}
端口: ${REALITY_PORT}
UUID: ${REALITY_UUID}
Flow: xtls-rprx-vision
SNI: ${SNI}
Public Key: ${REALITY_PUBLIC_KEY}
Short ID: ${REALITY_SHORT_ID}

VLESS 分享链接:
${VLESS_LINK}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
文件位置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

配置: /etc/sing-box/config.json
证书: /etc/sing-box/certs/
信息: /root/sing-box-info.txt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    echo "$HY2_LINK" > /root/hy2_link.txt
    echo "$VLESS_LINK" > /root/vless_link.txt
    
    cat > /root/share_links.txt <<EOF
Hysteria 2: ${HY2_LINK}

VLESS Reality: ${VLESS_LINK}
EOF
    
    if command -v qrencode &> /dev/null; then
        qrencode -t ANSIUTF8 -o /root/hy2_qr.txt "$HY2_LINK" 2>/dev/null || true
        qrencode -t PNG -o /root/hy2_qr.png "$HY2_LINK" 2>/dev/null || true
        qrencode -t ANSIUTF8 -o /root/vless_qr.txt "$VLESS_LINK" 2>/dev/null || true
        qrencode -t PNG -o /root/vless_qr.png "$VLESS_LINK" 2>/dev/null || true
    fi
    
    print_success "配置信息已保存"
}

show_result() {
    clear
    echo -e "${PURPLE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                  🎉 安装完成！                                ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Hysteria 2 配置${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [ "$USE_ACME" = true ]; then
        echo -e "${CYAN}连接: ${CERT_DOMAIN}:${HY2_PORT}${NC}"
    else
        echo -e "${CYAN}连接: ${SERVER_IP}:${HY2_PORT}${NC}"
        echo -e "${YELLOW}注意: 客户端需设置 insecure: true${NC}"
    fi
    echo -e "${CYAN}密码: ${HY2_PASSWORD}${NC}"
    echo ""
    echo -e "${YELLOW}分享链接:${NC}"
    echo "${HY2_LINK}"
    echo ""

    if [ -f /root/hy2_qr.txt ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  二维码${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        cat /root/hy2_qr.txt 2>/dev/null || true
        echo ""
    fi
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  VLESS Reality 配置${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [ "$USE_ACME" = true ]; then
        echo -e "${CYAN}连接: ${CERT_DOMAIN}:${REALITY_PORT}${NC}"
    else
        echo -e "${CYAN}连接: ${SERVER_IP}:${REALITY_PORT}${NC}"
    fi
    echo -e "${CYAN}UUID: ${REALITY_UUID}${NC}"
    echo -e "${CYAN}SNI: ${SNI}${NC}"
    echo ""
    echo -e "${YELLOW}分享链接:${NC}"
    echo "${VLESS_LINK}"
    echo ""
    
    if [ -f /root/vless_qr.txt ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  二维码${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        cat /root/vless_qr.txt 2>/dev/null || true
        echo ""
    fi
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}💡 重要信息${NC}"
    echo ""
    echo "  📁 配置已保存到: /root/sing-box-info.txt"
    echo ""
    echo "  🔧 服务管理:"
    echo "     systemctl status sing-box"
    echo "     systemctl restart sing-box"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}


#####################################################################
# 主程序
#####################################################################

main() {
    check_root
    show_main_menu

}

main



