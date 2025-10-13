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


## ⚙️ 输出信息：

hy2 配置信息

reality 配置信息

客户端连接参数

⚠️ 声明

本项目仅用于学习与研究，请勿用于任何非法用途。
作者不对使用过程中的后果负责。
