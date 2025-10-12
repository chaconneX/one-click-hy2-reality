# one-click-hy2-reality
hy2 &amp; reality一键安装脚本

# 🚀 hy2 + reality 一键安装脚本

## 📖 简介
本项目提供一个 **一键安装脚本**，用于在 Linux 服务器上快速部署 **hysteria2 (hy2)** 与 **reality**。  
脚本会自动完成以下任务：  

- ✅ 安装依赖与服务  
- ✅ 部署 hy2 与 reality  
- ✅ 配置域名并启用 TLS  
- ✅ 使用 **Cloudflare API** 自动添加 DNS 解析记录  

---

## ✨ 功能特点
- 🖱️ 一键安装，零手动配置  
- 🌐 自动对接 **Cloudflare DNS**  
- 🔒 自动生成 **Reality 配置**  
- 📜 自动申请证书 / DNS 验证  
- ⚡ 开箱即用，输出客户端参数  

---

## 📌 前置条件
在运行脚本前，请准备以下内容：

1. **域名**  
   - 已注册的域名  
   - 已托管到 **Cloudflare**（NS 需指向 Cloudflare 提供的地址）  

2. **Cloudflare API Token**  
   - 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)  
   - 创建 **API Token**（需 `Zone.DNS 编辑` 权限）  
   - 保存该 Token，稍后脚本会用到  

3. **服务器**  
   - Linux 系统 
   - 已开放 **80/443** 端口  

---

## ⚙️ 安装方法
```bash
wget -N --no-check-certificate  https://raw.githubusercontent.com/chaconneX/one-click-hy2-reality/main/hy2_reality_install.sh && chmod +x hy2_reality_install.sh && bash hy2_reality_install.sh
```
运行过程中会提示输入：

🌍 你的域名（例如：example.com）

🔑 Cloudflare API Token


## ⚙️ 输出信息：

hy2 配置信息

reality 配置信息

客户端连接参数

⚠️ 声明

本项目仅用于学习与研究，请勿用于任何非法用途。
作者不对使用过程中的后果负责。
