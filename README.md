# one-click-hy2-reality-ws
hy2 &amp; reality &amp; vless-ws 一键安装脚本

# 🚀 Hysteria 2 + VLESS Reality + VLESS WS TLS 一键安装脚本

## 📖 简介
本项目提供一个 **一键安装脚本**，用于在 Linux 服务器上快速部署 **Hysteria 2 (Hy2)**、**VLESS Reality** 和 **VLESS WS TLS**。

你可以根据情况选择：
- ✅ 使用 **域名 + Cloudflare API** 自动配置
- ✅ 使用 **域名 + Let's Encrypt** 证书（Standalone 模式）
- ✅ **无域名**，使用 IP + 自签证书

---

## ✨ 功能
- 一键安装，无需手动繁琐配置
- 支持三种协议：**Hysteria 2**、**VLESS Reality**、**VLESS WS TLS**
- 支持 **自签证书**，无需购买域名也可使用
- 可选 **Cloudflare API 自动解析**，省去手动添加 DNS
- 可选 **Let's Encrypt Standalone** 模式申请证书
- 自动输出客户端配置参数和分享链接
- 自动生成二维码，方便手机扫码导入
- **支持中转服务器模式**，可配置中转VPS → 落地VPS架构
- **VPS 系统调优**，一键开启 BBR、TCP/UDP优化、降低延迟

---

## 📋 协议说明

| 协议 | 传输层 | 默认端口 | 特点 |
|------|--------|----------|------|
| Hysteria 2 | UDP/QUIC | 443 | 高速、抗丢包、适合不稳定网络 |
| VLESS Reality | TCP | 8443 | 高度伪装、防探测、无需证书 |
| VLESS WS TLS | TCP/WebSocket | 2053 | 兼容性好、支持CDN、适合受限网络 |

---

## 📌 前置条件
在运行脚本前，请准备以下内容：

1. **服务器（必备）**
   - Linux 系统（推荐 Ubuntu 20.04 / 22.04 / Debian 11+）
   - 已开放相应端口（UDP 443, TCP 8443, TCP 2053）

2. **域名（可选）**
   - 如果使用域名，需要将域名解析到服务器IP
   - 使用 Cloudflare DNS API 时，需要将 NS 指向 **Cloudflare**

3. **Cloudflare API Token（可选）**
   - 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)
   - 创建一个 API Token，权限需包含 `Zone.DNS 编辑`

---

## ⚙️ 安装方法
```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/chaconneX/one-click-hy2-reality/main/hy2_reality_install.sh && chmod +x hy2_reality_install.sh && bash hy2_reality_install.sh
```

## 📝 安装选项说明

### 证书配置
- **自签名证书** → 快速安装，客户端需设置 insecure: true
- **Let's Encrypt (Standalone)** → 需要 80 端口，域名可托管在任何 DNS
- **Let's Encrypt (Cloudflare API)** → 无需 80 端口，域名必须在 Cloudflare

### 端口配置
- **Hysteria 2**: 默认 443 (UDP)
- **Reality**: 默认 8443 (TCP)
- **VLESS WS TLS**: 默认 2053 (TCP)

### 其他配置
- **Reality SNI**: 可选 Microsoft、Apple、Cloudflare 等
- **WebSocket 路径**: 默认 /ws，可自定义

---

## 🔀 中转服务器模式

脚本支持 **中转VPS → 落地VPS** 架构，可以通过中转服务器转发流量到落地服务器。

### 使用场景
- 落地VPS线路好但直连不稳定
- 需要隐藏落地VPS的真实IP
- 使用多个中转服务器共享一个落地服务器

### 部署步骤

#### 1. 先部署落地服务器
在落地VPS上运行脚本，选择 **"落地服务器"** 模式：
```bash
bash hy2_reality_install.sh
# 选择 1) 落地服务器 (直接出口)
```

安装完成后，记录以下信息（根据你选择的协议）：
- **Hysteria 2**: 服务器地址、端口、密码
- **VLESS Reality**: 服务器地址、端口、UUID、Public Key、Short ID、SNI
- **VLESS WS TLS**: 服务器地址、端口、UUID、路径

#### 2. 再部署中转服务器
在中转VPS上运行脚本，选择 **"中转服务器"** 模式：
```bash
bash hy2_reality_install.sh
# 选择 2) 中转服务器 (转发到落地VPS)
```

配置时需要输入落地服务器的信息：
- 落地服务器地址（IP或域名）
- 落地服务器协议类型（Hysteria 2 / VLESS Reality / VLESS WS TLS）
- 落地服务器的连接参数

#### 3. 客户端连接
客户端使用中转服务器的连接信息（IP、端口、密码等），流量会自动转发到落地服务器。

### 架构示意
```
客户端 → 中转VPS (Hy2/Reality/WS入口) → 落地VPS (Hy2/Reality/WS出口) → 互联网
```

### 注意事项
- 中转服务器和落地服务器都需要运行本脚本
- 中转服务器可以使用与落地服务器不同的协议（如中转用Reality，落地用Hy2）
- 确保落地服务器的端口在防火墙中已开放
- 中转服务器需要能够连接到落地服务器

---

## ⚡ VPS 系统调优

脚本内置 VPS 调优功能，可以显著提升代理性能、降低延迟。

### 调优内容

| 优化项 | 说明 | 效果 |
|--------|------|------|
| **BBR** | Google TCP 拥塞控制算法 | 显著提升带宽利用率，减少丢包影响 |
| **TCP 优化** | 缓冲区、超时、Fast Open 等 | 加快连接速度，降低延迟 |
| **UDP/QUIC 优化** | 增大 UDP 缓冲区 | 提升 Hysteria 2 性能 |
| **系统限制** | 文件描述符、进程数 | 支持更多并发连接 |
| **低延迟参数** | 端口范围、ARP缓存等 | 整体降低网络延迟 |

### 使用方法

运行脚本后选择 **"4) VPS 系统调优"**：

```bash
bash hy2_reality_install.sh
# 选择 4) VPS 系统调优 (BBR + TCP优化)
```

### 调优选项

- **一键全面优化（推荐）** - 应用所有优化项
- **仅开启 BBR** - 只启用 BBR 拥塞控制
- **仅优化 TCP 参数** - TCP 缓冲区和超时优化
- **仅优化 UDP/QUIC** - 针对 Hysteria 2 的 UDP 优化
- **仅优化系统限制** - 增大文件描述符限制
- **仅优化低延迟参数** - 网络延迟相关优化
- **恢复默认配置** - 回滚到优化前的状态

### 系统要求

- **BBR**: 需要 Linux 内核 4.9 或更高版本
- 大多数现代 VPS（Ubuntu 18.04+、Debian 10+、CentOS 8+）默认满足要求

### 查看当前状态

调优菜单会自动显示当前系统状态：
- 当前 TCP 拥塞控制算法
- BBR 是否启用
- TCP Fast Open 状态
- 文件描述符限制
- 内核版本

---

## 📂 文件位置

| 文件 | 路径 |
|------|------|
| 配置文件 | `/etc/sing-box/config.json` |
| 证书目录 | `/etc/sing-box/certs/` |
| 配置信息 | `/root/sing-box-info.txt` |
| 分享链接 | `/root/share_links.txt` |

---

## 🔧 服务管理

```bash
# 查看服务状态
systemctl status sing-box

# 重启服务
systemctl restart sing-box

# 停止服务
systemctl stop sing-box

# 查看日志
journalctl -u sing-box -f
```

---

## ⚙️ 输出信息

安装完成后，脚本会输出：
- Hysteria 2 配置信息和分享链接
- VLESS Reality 配置信息和分享链接
- VLESS WS TLS 配置信息和分享链接
- 客户端连接参数
- 二维码（支持手机扫码导入）

---

## 📱 客户端推荐

| 平台 | 推荐客户端 |
|------|-----------|
| Windows | v2rayN, Clash Verge, NekoRay |
| macOS | ClashX Pro, V2rayU, NekoRay |
| iOS | Shadowrocket, Quantumult X, Stash |
| Android | v2rayNG, Clash for Android, NekoBox |

---

## ⚠️ 声明

本项目仅用于学习与研究，请勿用于任何非法用途。
作者不对使用过程中的后果负责。
