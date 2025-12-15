#!/bin/bash

#####################################################################
# Sing-box 管理脚本
# 协议: Hysteria 2 + VLESS Reality Vision + VLESS WS TLS
# 功能: 安装、卸载、灵活证书配置、中转服务器支持
# 作者: Chaconne
# 版本: 6.0
#####################################################################

trap 'rm -f /root/hy2*txt /root/vless*txt /root/vless_ws*txt /root/hy2*png /root/vless*png /root/vless_ws*png /root/share*' EXIT


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
VLESS_WS_PORT=""
HY2_PASSWORD=""
REALITY_UUID=""
VLESS_WS_UUID=""
VLESS_WS_PATH=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""
REALITY_SHORT_ID=""
CERT_DOMAIN=""
CF_API_TOKEN=""
SNI=""
SERVER_IP=""
USE_ACME=false
DNS_PROVIDER="standalone"

# 中转服务器配置
SERVER_TYPE="landing"  # landing=落地服务器, relay=中转服务器
RELAY_BACKEND_TYPE=""  # hy2, vless 或 vless-ws
RELAY_BACKEND_ADDR=""  # 落地服务器地址
RELAY_BACKEND_HY2_PORT=""
RELAY_BACKEND_HY2_PASSWORD=""
RELAY_BACKEND_VLESS_PORT=""
RELAY_BACKEND_VLESS_UUID=""
RELAY_BACKEND_VLESS_FLOW=""
RELAY_BACKEND_VLESS_SNI=""
RELAY_BACKEND_VLESS_PUBLIC_KEY=""
RELAY_BACKEND_VLESS_SHORT_ID=""
RELAY_BACKEND_VLESS_WS_PORT=""
RELAY_BACKEND_VLESS_WS_UUID=""
RELAY_BACKEND_VLESS_WS_PATH=""
RELAY_BACKEND_VLESS_WS_HOST=""

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
║       Sing-box 管理脚本 v6.0                      ║
║                                                   ║
║   Hysteria 2 + VLESS Reality + VLESS WS TLS       ║
║   支持中转服务器模式 + VPS调优                    ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo -e "${CYAN}请选择操作:${NC}"
    echo ""
    echo "  1) 安装 Sing-box (Hy2 + Reality + WS)"
    echo "  2) 卸载 Sing-box"
    echo "  3) 查看配置信息"
    echo "  4) VPS 系统调优 (BBR + TCP优化)"
    echo "  5) 退出"
    echo ""

    read -p "请输入选项 [1-5]: " menu_choice

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
            show_optimize_menu
            ;;
        5)
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
# VPS 调优功能
#####################################################################

# 检查当前BBR状态
check_bbr_status() {
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
    local bbr_module=$(lsmod | grep -c bbr)

    echo -e "${CYAN}当前TCP拥塞控制算法: ${NC}${current_cc}"
    echo -e "${CYAN}可用算法: ${NC}${available_cc}"

    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${GREEN}✓ BBR 已启用${NC}"
        return 0
    else
        echo -e "${YELLOW}✗ BBR 未启用${NC}"
        return 1
    fi
}

# 检查系统优化状态
check_optimization_status() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  当前系统状态${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # BBR状态
    check_bbr_status
    echo ""

    # 文件描述符限制
    local current_nofile=$(ulimit -n)
    echo -e "${CYAN}文件描述符限制: ${NC}${current_nofile}"

    # TCP快速打开
    local tfo=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
    if [[ "$tfo" -ge 3 ]]; then
        echo -e "${GREEN}✓ TCP Fast Open 已启用 (值: $tfo)${NC}"
    else
        echo -e "${YELLOW}✗ TCP Fast Open 未完全启用 (值: $tfo)${NC}"
    fi

    # 内核版本
    echo -e "${CYAN}内核版本: ${NC}$(uname -r)"
    echo ""
}

# 开启BBR
enable_bbr() {
    print_info "正在启用 BBR..."

    # 检查内核版本是否支持BBR (4.9+)
    local kernel_version=$(uname -r | cut -d. -f1,2)
    local kernel_major=$(echo $kernel_version | cut -d. -f1)
    local kernel_minor=$(echo $kernel_version | cut -d. -f2)

    if [[ $kernel_major -lt 4 ]] || [[ $kernel_major -eq 4 && $kernel_minor -lt 9 ]]; then
        print_error "内核版本 $(uname -r) 不支持BBR，需要 4.9 或更高版本"
        print_info "建议升级内核或使用其他拥塞控制算法"
        return 1
    fi

    # 加载BBR模块
    modprobe tcp_bbr 2>/dev/null || true

    # 配置BBR
    cat >> /etc/sysctl.conf <<'SYSCTL_BBR'

# BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL_BBR

    # 移除重复配置
    sort -u /etc/sysctl.conf | grep -v '^$' > /tmp/sysctl.tmp
    mv /tmp/sysctl.tmp /etc/sysctl.conf

    sysctl -p >/dev/null 2>&1

    # 验证
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [[ "$current_cc" == "bbr" ]]; then
        print_success "BBR 已成功启用"
        return 0
    else
        print_error "BBR 启用失败"
        return 1
    fi
}

# TCP优化
optimize_tcp() {
    print_info "正在优化 TCP 参数..."

    # 备份原配置
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

    cat >> /etc/sysctl.conf <<'SYSCTL_TCP'

# =============================================
# TCP 优化配置 - 降低延迟、提高吞吐量
# =============================================

# --- 网络缓冲区优化 ---
# 增大套接字缓冲区，提高大流量传输性能
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216

# 网络设备队列长度
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535

# --- TCP 连接优化 ---
# TCP Fast Open - 减少握手延迟
net.ipv4.tcp_fastopen = 3

# 启用TCP窗口缩放，支持大于64K的窗口
net.ipv4.tcp_window_scaling = 1

# MTU探测，优化路径MTU
net.ipv4.tcp_mtu_probing = 1

# 启用SACK和DSACK，改善丢包恢复
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1

# 启用时间戳，提高RTT计算精度
net.ipv4.tcp_timestamps = 1

# 禁用慢启动重启，保持传输速度
net.ipv4.tcp_slow_start_after_idle = 0

# --- TCP 超时和重试优化 ---
# 减少FIN-WAIT-2超时时间
net.ipv4.tcp_fin_timeout = 15

# 减少TIME-WAIT套接字数量
net.ipv4.tcp_max_tw_buckets = 65536
net.ipv4.tcp_tw_reuse = 1

# 减少SYN重试次数，加快连接失败检测
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# --- TCP Keepalive 优化 ---
# 更快检测断开的连接
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# 孤儿连接处理
net.ipv4.tcp_max_orphans = 65536

# SYN队列长度
net.ipv4.tcp_max_syn_backlog = 65536

# --- 内存管理 ---
net.ipv4.tcp_mem = 786432 1048576 1572864
SYSCTL_TCP

    # 移除重复配置
    awk '!seen[$0]++' /etc/sysctl.conf > /tmp/sysctl.tmp
    mv /tmp/sysctl.tmp /etc/sysctl.conf

    sysctl -p >/dev/null 2>&1

    print_success "TCP 参数优化完成"
}

# UDP/QUIC优化 (对Hysteria 2特别有效)
optimize_udp() {
    print_info "正在优化 UDP/QUIC 参数 (Hysteria 2 加速)..."

    cat >> /etc/sysctl.conf <<'SYSCTL_UDP'

# =============================================
# UDP/QUIC 优化配置 - Hysteria 2 加速
# =============================================

# 增大UDP缓冲区
net.core.rmem_default = 26214400
net.core.rmem_max = 26214400
net.core.wmem_default = 26214400
net.core.wmem_max = 26214400

# 增大UDP接收缓冲区队列
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 20000

# 允许更多的数据包排队等待
net.core.netdev_max_backlog = 65536
SYSCTL_UDP

    # 移除重复配置
    awk '!seen[$0]++' /etc/sysctl.conf > /tmp/sysctl.tmp
    mv /tmp/sysctl.tmp /etc/sysctl.conf

    sysctl -p >/dev/null 2>&1

    print_success "UDP/QUIC 参数优化完成"
}

# 系统限制优化
optimize_system_limits() {
    print_info "正在优化系统限制..."

    # 优化文件描述符限制
    cat > /etc/security/limits.d/99-proxy-optimize.conf <<'LIMITS'
# 代理服务器优化 - 增大文件描述符限制
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 65535
root hard nproc 65535
LIMITS

    # 确保PAM读取limits
    if ! grep -q "pam_limits.so" /etc/pam.d/common-session 2>/dev/null; then
        echo "session required pam_limits.so" >> /etc/pam.d/common-session 2>/dev/null || true
    fi

    # 系统级文件描述符限制
    cat >> /etc/sysctl.conf <<'SYSCTL_FS'

# =============================================
# 系统限制优化
# =============================================

# 增大系统文件描述符限制
fs.file-max = 2097152
fs.nr_open = 2097152

# 增大inotify限制
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
SYSCTL_FS

    # 移除重复配置
    awk '!seen[$0]++' /etc/sysctl.conf > /tmp/sysctl.tmp
    mv /tmp/sysctl.tmp /etc/sysctl.conf

    sysctl -p >/dev/null 2>&1

    print_success "系统限制优化完成"
}

# 网络延迟优化
optimize_latency() {
    print_info "正在应用低延迟优化..."

    cat >> /etc/sysctl.conf <<'SYSCTL_LATENCY'

# =============================================
# 低延迟优化配置
# =============================================

# 禁用IPv6 (如果不需要)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# 启用IP转发 (中转服务器需要)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# 减少路由缓存刷新时间
net.ipv4.route.gc_timeout = 100

# 本地端口范围扩大
net.ipv4.ip_local_port_range = 1024 65535

# 允许TIME-WAIT socket重用
net.ipv4.tcp_tw_reuse = 1

# 减少ICMP限制，加快路径MTU发现
net.ipv4.icmp_ratelimit = 100
net.ipv4.icmp_ratemask = 88089

# ARP缓存优化
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh3 = 8192
SYSCTL_LATENCY

    # 移除重复配置
    awk '!seen[$0]++' /etc/sysctl.conf > /tmp/sysctl.tmp
    mv /tmp/sysctl.tmp /etc/sysctl.conf

    sysctl -p >/dev/null 2>&1

    print_success "低延迟优化完成"
}

# 一键全面优化
full_optimization() {
    echo ""
    print_info "开始全面系统优化..."
    echo ""

    enable_bbr
    echo ""
    optimize_tcp
    echo ""
    optimize_udp
    echo ""
    optimize_system_limits
    echo ""
    optimize_latency
    echo ""

    # 重启sing-box服务以应用新的限制
    if systemctl is-active --quiet sing-box 2>/dev/null; then
        print_info "重启 sing-box 服务..."
        systemctl restart sing-box
        print_success "sing-box 服务已重启"
    fi

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ 系统优化完成！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}优化内容:${NC}"
    echo "  • BBR 拥塞控制算法"
    echo "  • TCP 缓冲区和超时优化"
    echo "  • UDP/QUIC 缓冲区优化 (Hysteria 2)"
    echo "  • 系统文件描述符限制提升"
    echo "  • 低延迟网络参数调优"
    echo ""
    echo -e "${YELLOW}提示:${NC}"
    echo "  • 某些优化可能需要重启系统才能完全生效"
    echo "  • 配置已备份到 /etc/sysctl.conf.bak.*"
    echo ""
}

# 恢复默认配置
restore_defaults() {
    print_warning "此操作将恢复系统默认网络配置"
    read -p "确认要恢复吗? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "已取消恢复操作"
        return
    fi

    print_info "正在恢复默认配置..."

    # 查找最近的备份
    local backup_file=$(ls -t /etc/sysctl.conf.bak.* 2>/dev/null | head -1)

    if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
        cp "$backup_file" /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
        print_success "已恢复到备份: $backup_file"
    else
        # 创建最小化的sysctl配置
        cat > /etc/sysctl.conf <<'DEFAULT_SYSCTL'
# 系统默认配置
net.ipv4.ip_forward = 0
net.ipv4.tcp_congestion_control = cubic
DEFAULT_SYSCTL
        sysctl -p >/dev/null 2>&1
        print_success "已恢复系统默认配置"
    fi

    # 删除limits配置
    rm -f /etc/security/limits.d/99-proxy-optimize.conf

    print_success "恢复完成"
}

# VPS调优菜单
show_optimize_menu() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║       VPS 系统调优                                ║
║                                                   ║
║   BBR + TCP优化 + UDP/QUIC优化                    ║
║   降低延迟 · 提高速度 · 优化Hysteria 2            ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    check_optimization_status

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  调优选项${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  1) 一键全面优化 (推荐)"
    echo "  2) 仅开启 BBR"
    echo "  3) 仅优化 TCP 参数"
    echo "  4) 仅优化 UDP/QUIC (Hysteria 2)"
    echo "  5) 仅优化系统限制"
    echo "  6) 仅优化低延迟参数"
    echo "  7) 恢复默认配置"
    echo "  8) 返回主菜单"
    echo ""

    read -p "请选择 [1-8]: " opt_choice

    case $opt_choice in
        1)
            full_optimization
            ;;
        2)
            echo ""
            enable_bbr
            ;;
        3)
            echo ""
            optimize_tcp
            ;;
        4)
            echo ""
            optimize_udp
            ;;
        5)
            echo ""
            optimize_system_limits
            ;;
        6)
            echo ""
            optimize_latency
            ;;
        7)
            echo ""
            restore_defaults
            ;;
        8)
            show_main_menu
            return
            ;;
        *)
            print_error "无效选项"
            sleep 2
            show_optimize_menu
            return
            ;;
    esac

    echo ""
    echo -e "${YELLOW}按任意键返回调优菜单...${NC}"
    read -n 1
    show_optimize_menu
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
    rm -f /root/vless_ws_link.txt
    rm -f /root/*_qr.png
    rm -f /root/*_qr.txt
    print_success "文件已删除"
    
    # 防火墙规则
    if command -v ufw &> /dev/null; then
        ufw status numbered 2>/dev/null | grep -iE "hysteria|reality|vless.ws" | awk '{print $1}' | sed 's/\[//g' | sed 's/\]//g' | sort -rn | while read rule_num; do
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

    # 服务器类型选择
    echo -e "${YELLOW}━━━ 服务器类型 ━━━${NC}"
    echo "  1) 落地服务器 (直接出口)"
    echo "  2) 中转服务器 (转发到落地VPS)"
    echo ""
    read -p "请选择服务器类型 [默认: 1]: " server_type_choice
    server_type_choice=${server_type_choice:-1}

    if [ "$server_type_choice" = "2" ]; then
        SERVER_TYPE="relay"
        print_info "配置为中转服务器模式"
    else
        SERVER_TYPE="landing"
        print_info "配置为落地服务器模式"
    fi
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

    read -p "VLESS WS TLS 端口 [默认: 2053]: " input_vless_ws_port
    VLESS_WS_PORT=${input_vless_ws_port:-2053}

    echo ""
    echo -e "${YELLOW}━━━ VLESS WS 路径配置 ━━━${NC}"
    read -p "WebSocket 路径 [默认: /ws]: " input_ws_path
    VLESS_WS_PATH=${input_ws_path:-/ws}

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

    # 中转服务器配置
    if [ "$SERVER_TYPE" = "relay" ]; then
        echo -e "${YELLOW}━━━ 落地服务器配置 ━━━${NC}"
        echo "请输入落地服务器的配置信息"
        echo ""

        read -p "落地服务器地址 (IP或域名): " RELAY_BACKEND_ADDR
        if [ -z "$RELAY_BACKEND_ADDR" ]; then
            print_error "落地服务器地址不能为空"
            exit 1
        fi

        echo ""
        echo "选择连接落地服务器的协议:"
        echo "  1) Hysteria 2"
        echo "  2) VLESS Reality"
        echo "  3) VLESS WS TLS"
        read -p "请选择 [默认: 1]: " backend_type_choice
        backend_type_choice=${backend_type_choice:-1}

        if [ "$backend_type_choice" = "2" ]; then
            RELAY_BACKEND_TYPE="vless"
            echo ""
            echo -e "${YELLOW}━━━ VLESS Reality 落地服务器配置 ━━━${NC}"
            read -p "落地服务器端口 [默认: 8443]: " input_backend_port
            RELAY_BACKEND_VLESS_PORT=${input_backend_port:-8443}

            read -p "UUID: " RELAY_BACKEND_VLESS_UUID
            if [ -z "$RELAY_BACKEND_VLESS_UUID" ]; then
                print_error "UUID不能为空"
                exit 1
            fi

            read -p "Flow [默认: xtls-rprx-vision]: " input_flow
            RELAY_BACKEND_VLESS_FLOW=${input_flow:-xtls-rprx-vision}

            read -p "SNI [默认: www.microsoft.com]: " input_sni
            RELAY_BACKEND_VLESS_SNI=${input_sni:-www.microsoft.com}

            read -p "Public Key: " RELAY_BACKEND_VLESS_PUBLIC_KEY
            if [ -z "$RELAY_BACKEND_VLESS_PUBLIC_KEY" ]; then
                print_error "Public Key不能为空"
                exit 1
            fi

            read -p "Short ID: " RELAY_BACKEND_VLESS_SHORT_ID
            if [ -z "$RELAY_BACKEND_VLESS_SHORT_ID" ]; then
                print_error "Short ID不能为空"
                exit 1
            fi
        elif [ "$backend_type_choice" = "3" ]; then
            RELAY_BACKEND_TYPE="vless-ws"
            echo ""
            echo -e "${YELLOW}━━━ VLESS WS TLS 落地服务器配置 ━━━${NC}"
            read -p "落地服务器端口 [默认: 2053]: " input_backend_port
            RELAY_BACKEND_VLESS_WS_PORT=${input_backend_port:-2053}

            read -p "UUID: " RELAY_BACKEND_VLESS_WS_UUID
            if [ -z "$RELAY_BACKEND_VLESS_WS_UUID" ]; then
                print_error "UUID不能为空"
                exit 1
            fi

            read -p "WebSocket 路径 [默认: /ws]: " input_ws_path
            RELAY_BACKEND_VLESS_WS_PATH=${input_ws_path:-/ws}

            read -p "Host/SNI [默认: 落地服务器地址]: " input_ws_host
            RELAY_BACKEND_VLESS_WS_HOST=${input_ws_host:-$RELAY_BACKEND_ADDR}
        else
            RELAY_BACKEND_TYPE="hy2"
            echo ""
            echo -e "${YELLOW}━━━ Hysteria 2 落地服务器配置 ━━━${NC}"
            read -p "落地服务器端口 [默认: 443]: " input_backend_port
            RELAY_BACKEND_HY2_PORT=${input_backend_port:-443}

            read -p "密码: " RELAY_BACKEND_HY2_PASSWORD
            if [ -z "$RELAY_BACKEND_HY2_PASSWORD" ]; then
                print_error "密码不能为空"
                exit 1
            fi
        fi

        echo ""
    fi

    # 配置确认
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  配置确认${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}服务器类型:${NC}     $([ "$SERVER_TYPE" = "relay" ] && echo "中转服务器" || echo "落地服务器")"
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
    echo -e "${GREEN}VLESS WS 端口:${NC}   $VLESS_WS_PORT"
    echo -e "${GREEN}VLESS WS 路径:${NC}   $VLESS_WS_PATH"

    if [ "$SERVER_TYPE" = "relay" ]; then
        echo ""
        echo -e "${YELLOW}落地服务器:${NC}"
        echo -e "${GREEN}  地址:${NC}         $RELAY_BACKEND_ADDR"
        case "$RELAY_BACKEND_TYPE" in
            hy2) echo -e "${GREEN}  协议:${NC}         Hysteria 2" ;;
            vless) echo -e "${GREEN}  协议:${NC}         VLESS Reality" ;;
            vless-ws) echo -e "${GREEN}  协议:${NC}         VLESS WS TLS" ;;
        esac
        if [ "$RELAY_BACKEND_TYPE" = "hy2" ]; then
            echo -e "${GREEN}  端口:${NC}         $RELAY_BACKEND_HY2_PORT"
        elif [ "$RELAY_BACKEND_TYPE" = "vless" ]; then
            echo -e "${GREEN}  端口:${NC}         $RELAY_BACKEND_VLESS_PORT"
        else
            echo -e "${GREEN}  端口:${NC}         $RELAY_BACKEND_VLESS_WS_PORT"
            echo -e "${GREEN}  路径:${NC}         $RELAY_BACKEND_VLESS_WS_PATH"
        fi
    fi
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
    VLESS_WS_UUID=$(cat /proc/sys/kernel/random/uuid)

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

    # 生成outbounds配置
    if [ "$SERVER_TYPE" = "relay" ]; then
        # 中转服务器模式：outbound连接到落地服务器
        if [ "$RELAY_BACKEND_TYPE" = "hy2" ]; then
            # Hysteria 2 后端
            OUTBOUND_CONFIG=$(cat <<OUTBOUND_EOF
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "backend",
      "server": "${RELAY_BACKEND_ADDR}",
      "server_port": ${RELAY_BACKEND_HY2_PORT},
      "password": "${RELAY_BACKEND_HY2_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${RELAY_BACKEND_ADDR}",
        "insecure": true
      }
    }
  ]
OUTBOUND_EOF
)
        elif [ "$RELAY_BACKEND_TYPE" = "vless" ]; then
            # VLESS Reality 后端
            OUTBOUND_CONFIG=$(cat <<OUTBOUND_EOF
  "outbounds": [
    {
      "type": "vless",
      "tag": "backend",
      "server": "${RELAY_BACKEND_ADDR}",
      "server_port": ${RELAY_BACKEND_VLESS_PORT},
      "uuid": "${RELAY_BACKEND_VLESS_UUID}",
      "flow": "${RELAY_BACKEND_VLESS_FLOW}",
      "tls": {
        "enabled": true,
        "server_name": "${RELAY_BACKEND_VLESS_SNI}",
        "reality": {
          "enabled": true,
          "public_key": "${RELAY_BACKEND_VLESS_PUBLIC_KEY}",
          "short_id": "${RELAY_BACKEND_VLESS_SHORT_ID}"
        }
      }
    }
  ]
OUTBOUND_EOF
)
        else
            # VLESS WS TLS 后端
            OUTBOUND_CONFIG=$(cat <<OUTBOUND_EOF
  "outbounds": [
    {
      "type": "vless",
      "tag": "backend",
      "server": "${RELAY_BACKEND_ADDR}",
      "server_port": ${RELAY_BACKEND_VLESS_WS_PORT},
      "uuid": "${RELAY_BACKEND_VLESS_WS_UUID}",
      "tls": {
        "enabled": true,
        "server_name": "${RELAY_BACKEND_VLESS_WS_HOST}",
        "insecure": true
      },
      "transport": {
        "type": "ws",
        "path": "${RELAY_BACKEND_VLESS_WS_PATH}",
        "headers": {
          "Host": "${RELAY_BACKEND_VLESS_WS_HOST}"
        }
      }
    }
  ]
OUTBOUND_EOF
)
        fi
    else
        # 落地服务器模式：direct出口
        OUTBOUND_CONFIG=$(cat <<OUTBOUND_EOF
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
OUTBOUND_EOF
)
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
    },
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "::",
      "listen_port": ${VLESS_WS_PORT},
      "users": [
        {
          "uuid": "${VLESS_WS_UUID}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SERVER_NAME}",
        "key_path": "/etc/sing-box/certs/private.key",
        "certificate_path": "/etc/sing-box/certs/cert.crt"
      },
      "transport": {
        "type": "ws",
        "path": "${VLESS_WS_PATH}"
      }
    }
  ],
${OUTBOUND_CONFIG}
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
        ufw allow ${VLESS_WS_PORT}/tcp comment "VLESS WS" >/dev/null 2>&1
        ufw reload >/dev/null 2>&1 || true
        print_success "UFW 防火墙规则已添加"
    fi

    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=${HY2_PORT}/udp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${REALITY_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${VLESS_WS_PORT}/tcp >/dev/null 2>&1
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
        VLESS_WS_LINK="vless://${VLESS_WS_UUID}@${CERT_DOMAIN}:${VLESS_WS_PORT}?encryption=none&security=tls&sni=${CERT_DOMAIN}&type=ws&host=${CERT_DOMAIN}&path=$(echo ${VLESS_WS_PATH} | sed 's/\//%2F/g')#VLESS-WS-${CERT_DOMAIN}"
    else
        CONNECT_ADDR="$SERVER_IP"
        HY2_LINK="hysteria2://${HY2_PASSWORD}@${SERVER_IP}:${HY2_PORT}/?insecure=1#Hysteria2-${SERVER_IP}"
        VLESS_WS_LINK="vless://${VLESS_WS_UUID}@${SERVER_IP}:${VLESS_WS_PORT}?encryption=none&security=tls&sni=${SERVER_IP}&type=ws&host=${SERVER_IP}&path=$(echo ${VLESS_WS_PATH} | sed 's/\//%2F/g')&allowInsecure=1#VLESS-WS-${SERVER_IP}"
    fi

    VLESS_LINK="vless://${REALITY_UUID}@${CONNECT_ADDR}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#Reality-${CONNECT_ADDR}"
    
    # 生成配置文件
    cat > /root/sing-box-info.txt <<EOF
╔═══════════════════════════════════════════════════════════════╗
║                    Sing-box 配置信息                          ║
╚═══════════════════════════════════════════════════════════════╝

服务器信息:
  类型: $([ "$SERVER_TYPE" = "relay" ] && echo "中转服务器" || echo "落地服务器")
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
VLESS WS TLS 配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

地址: ${CONNECT_ADDR}
端口: ${VLESS_WS_PORT}
UUID: ${VLESS_WS_UUID}
传输: WebSocket
路径: ${VLESS_WS_PATH}
TLS: 启用
$([ "$USE_ACME" != true ] && echo "注意: 使用自签名证书，客户端需允许不安全连接")

VLESS WS 分享链接:
${VLESS_WS_LINK}

$([ "$SERVER_TYPE" = "relay" ] && cat <<RELAY_INFO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
落地服务器配置 (中转模式)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  注意: 此服务器为中转服务器，流量将转发到以下落地服务器

落地服务器地址: ${RELAY_BACKEND_ADDR}
$(case "$RELAY_BACKEND_TYPE" in
    hy2) echo "协议类型: Hysteria 2
端口: ${RELAY_BACKEND_HY2_PORT}
密码: ${RELAY_BACKEND_HY2_PASSWORD}" ;;
    vless) echo "协议类型: VLESS Reality
端口: ${RELAY_BACKEND_VLESS_PORT}
UUID: ${RELAY_BACKEND_VLESS_UUID}" ;;
    vless-ws) echo "协议类型: VLESS WS TLS
端口: ${RELAY_BACKEND_VLESS_WS_PORT}
UUID: ${RELAY_BACKEND_VLESS_WS_UUID}
路径: ${RELAY_BACKEND_VLESS_WS_PATH}" ;;
esac)

RELAY_INFO
)
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
    echo "$VLESS_WS_LINK" > /root/vless_ws_link.txt

    cat > /root/share_links.txt <<EOF
Hysteria 2: ${HY2_LINK}

VLESS Reality: ${VLESS_LINK}

VLESS WS TLS: ${VLESS_WS_LINK}
EOF

    if command -v qrencode &> /dev/null; then
        qrencode -t ANSIUTF8 -o /root/hy2_qr.txt "$HY2_LINK" 2>/dev/null || true
        qrencode -t PNG -o /root/hy2_qr.png "$HY2_LINK" 2>/dev/null || true
        qrencode -t ANSIUTF8 -o /root/vless_qr.txt "$VLESS_LINK" 2>/dev/null || true
        qrencode -t PNG -o /root/vless_qr.png "$VLESS_LINK" 2>/dev/null || true
        qrencode -t ANSIUTF8 -o /root/vless_ws_qr.txt "$VLESS_WS_LINK" 2>/dev/null || true
        qrencode -t PNG -o /root/vless_ws_qr.png "$VLESS_WS_LINK" 2>/dev/null || true
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
    echo -e "${GREEN}  VLESS WS TLS 配置${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [ "$USE_ACME" = true ]; then
        echo -e "${CYAN}连接: ${CERT_DOMAIN}:${VLESS_WS_PORT}${NC}"
    else
        echo -e "${CYAN}连接: ${SERVER_IP}:${VLESS_WS_PORT}${NC}"
        echo -e "${YELLOW}注意: 客户端需允许不安全连接${NC}"
    fi
    echo -e "${CYAN}UUID: ${VLESS_WS_UUID}${NC}"
    echo -e "${CYAN}路径: ${VLESS_WS_PATH}${NC}"
    echo ""
    echo -e "${YELLOW}分享链接:${NC}"
    echo "${VLESS_WS_LINK}"
    echo ""

    if [ -f /root/vless_ws_qr.txt ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  二维码${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        cat /root/vless_ws_qr.txt 2>/dev/null || true
        echo ""
    fi

    # 中转服务器模式提示
    if [ "$SERVER_TYPE" = "relay" ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}⚠️  中转服务器模式${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${CYAN}落地服务器: ${RELAY_BACKEND_ADDR}${NC}"
        case "$RELAY_BACKEND_TYPE" in
            hy2) echo -e "${CYAN}协议: Hysteria 2${NC}" ;;
            vless) echo -e "${CYAN}协议: VLESS Reality${NC}" ;;
            vless-ws) echo -e "${CYAN}协议: VLESS WS TLS${NC}" ;;
        esac
        echo ""
        echo -e "${YELLOW}提示: 客户端连接到本服务器(${CONNECT_ADDR})，流量将自动转发到落地服务器${NC}"
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



