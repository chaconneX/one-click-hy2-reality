# one-click-hy2-reality
hy2 &amp; reality一键安装脚本

# 🚀 hy2 + reality 一键安装脚本

## 📖 简介
本项目提供一个 **一键安装脚本**，用于在 Linux 服务器上快速部署 **hysteria2 (hy2)** 与 **reality**。  

你可以根据情况选择：  
- ✅ 使用 **域名 + Cloudflare API** 自动配置  
- ✅ 使用 **域名 + 自签证书**（无需 Cloudflare API）  
- ✅ **无域名**，使用 IP + 自签证书  

---

## ✨ 功能
- 一键安装，无需手动繁琐配置
- 支持 **自签证书**，无需购买域名也可使用
- 可选 **Cloudflare API 自动解析**，省去手动添加 DNS
- 自动输出客户端配置参数
- **支持中转服务器模式**，可配置中转VPS → 落地VPS架构

---

## 📌 前置条件
在运行脚本前，请准备以下内容：

1. **服务器（必备）**  
   - Linux 系统（推荐 Ubuntu 20.04 / 22.04）  
   - 已开放 80 和 443 端口  

2. **域名（可选）**  
   - 如果使用域名，需要将 NS 指向 **Cloudflare**  

3. **Cloudflare API Token（可选）**  
   - 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)  
   - 创建一个 API Token，权限需包含 `Zone.DNS 编辑`  

---

## ⚙️ 安装方法
```bash
wget -N --no-check-certificate  https://raw.githubusercontent.com/chaconneX/one-click-hy2-reality/main/hy2_reality_install.sh && chmod +x hy2_reality_install.sh && bash hy2_reality_install.sh
```
## 根据提示选择安装方式

不输入域名 → 使用 IP + 自签证书

输入域名但不提供 API Token → 使用自签证书

输入域名 + Cloudflare API Token → 自动解析并配置证书

---

## 🔀 中转服务器模式

脚本现在支持 **中转VPS → 落地VPS** 架构，可以通过中转服务器转发流量到落地服务器。

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

#### 2. 再部署中转服务器
在中转VPS上运行脚本，选择 **"中转服务器"** 模式：
```bash
bash hy2_reality_install.sh
# 选择 2) 中转服务器 (转发到落地VPS)
```

配置时需要输入落地服务器的信息：
- 落地服务器地址（IP或域名）
- 落地服务器协议类型（Hysteria 2 或 VLESS Reality）
- 落地服务器的连接参数

#### 3. 客户端连接
客户端使用中转服务器的连接信息（IP、端口、密码等），流量会自动转发到落地服务器。

### 架构示意
```
客户端 → 中转VPS (Hy2/Reality入口) → 落地VPS (Hy2/Reality出口) → 互联网
```

### 注意事项
- 中转服务器和落地服务器都需要运行本脚本
- 中转服务器可以使用与落地服务器不同的协议（如中转用Reality，落地用Hy2）
- 确保落地服务器的端口在防火墙中已开放
- 中转服务器需要能够连接到落地服务器

---

## ⚙️ 输出信息：

hy2 配置信息

reality 配置信息

客户端连接参数

⚠️ 声明

本项目仅用于学习与研究，请勿用于任何非法用途。
作者不对使用过程中的后果负责。
