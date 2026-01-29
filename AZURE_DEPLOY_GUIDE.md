# Moltbot Azure 部署指南

## 📋 部署概览

- **VM 规格**: B4ms (4vCPU/16GB)
- **AI 模型**: Azure OpenAI GPT-5
- **预估费用**: $65-100/月
- **部署方式**: Azure CLI 或手动

---

## 第一步：安装 Azure CLI

### Windows
```powershell
# 方式1: Winget (推荐)
winget install Microsoft.AzureCLI

# 方式2: 手动下载
# 访问 https://aka.ms/installazurecliwindows 下载 MSI 安装
```

### 验证安装
```bash
az --version
```

---

## 第二步：登录 Azure

```bash
az login
```

浏览器会弹出，选择你的 Azure 账户登录。

验证登录：
```bash
az account show
```

---

## 第三步：创建资源组

```bash
az group create \
  --name moltbot-rg \
  --location eastus
```

可选区域: `eastus`, `westus2`, `westeurope`, `southeastasia`

---

## 第四步：创建 VM (B4ms)

```bash
az vm create \
  --resource-group moltbot-rg \
  --name moltbot-vm \
  --image Ubuntu2204 \
  --size Standard_B4ms \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard
```

**输出示例**:
```
"publicIpAddress": "20.XXX.XXX.XXX"
```

记下这个 IP 地址！

---

## 第五步：开放端口

```bash
# 开放 Moltbot Gateway 端口 (18789)
az network nsg rule create \
  --resource-group moltbot-rg \
  --nsg-name moltbot-vmNSG \
  --name AllowMoltbotGateway \
  --protocol tcp \
  --priority 1000 \
  --destination-port-range 18789 \
  --access allow

# 开放 HTTPS (443) - 可选
az network nsg rule create \
  --resource-group moltbot-rg \
  --nsg-name moltbot-vmNSG \
  --name AllowHTTPS \
  --protocol tcp \
  --priority 1001 \
  --destination-port-range 443 \
  --access allow
```

---

## 第六步：SSH 进入 VM

```bash
ssh azureuser@<VM_PUBLIC_IP>
```

---

## 第七步：在 VM 上安装 Moltbot

```bash
# 更新系统
sudo apt-get update
sudo apt-get upgrade -y

# 安装 Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# 验证 Node.js
node --version  # v22.x.x
npm --version   # 10.x.x

# 安装 Moltbot
curl -fsSL https://molt.bot/install.sh | bash

# 或 npm 安装
npm install -g moltbot@latest
```

---

## 第八步：配置 Moltbot

### 8.1 创建配置目录
```bash
mkdir -p ~/.clawdbot
```

### 8.2 编辑配置文件
```bash
nano ~/.clawdbot/clawdbot.json
```

### 8.3 填入以下配置（替换 YOUR_* 部分）

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "azure": {
        "baseUrl": "https://YOUR_RESOURCE_NAME.openai.azure.com/openai/v1",
        "apiKey": "YOUR_AZURE_API_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "gpt-5",
            "name": "Azure GPT-5",
            "reasoning": true,
            "input": ["text", "image"],
            "cost": {
              "input": 1.25,
              "output": 10.0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 128000,
            "maxTokens": 8192
          },
          {
            "id": "gpt-4o",
            "name": "Azure GPT-4o",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": {
              "input": 5.0,
              "output": 15.0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 128000,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "azure/gpt-5",
        "fallbacks": ["azure/gpt-4o"]
      },
      "workspace": "/home/azureuser/clawd",
      "sandbox": {
        "mode": "non-main"
      }
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "GENERATE_A_RANDOM_TOKEN_HERE"
    }
  },
  "channels": {
    "whatsapp": {
      "dmPolicy": "allowlist",
      "selfChatMode": true,
      "allowFrom": [],
      "groupPolicy": "allowlist",
      "mediaMaxMb": 50
    }
  }
}
```

### 8.4 获取 Azure OpenAI 信息

在 Azure Portal 中:
1. 进入你的 Azure OpenAI 资源
2. **密钥和终结点** → 复制 **终结点** 和 **密钥**
3. **模型部署** → 确认已部署 `gpt-5`

---

## 第九步：启动 Moltbot

### 前台运行（测试）
```bash
moltbot gateway --port 18789 --verbose
```

### 后台运行（生产）
```bash
# 使用 systemd
sudo tee /etc/systemd/system/moltbot.service > /dev/null << 'EOF'
[Unit]
Description=Moltbot Gateway
After=network.target

[Service]
Type=simple
User=azureuser
WorkingDirectory=/home/azureuser
ExecStart=/usr/bin/moltbot gateway --port 18789
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable moltbot
sudo systemctl start moltbot
```

---

## 第十步：验证部署

### 检查状态
```bash
moltbot status
moltbot health
```

### 访问 Dashboard
打开浏览器访问:
```
http://<VM_PUBLIC_IP>:18789
```

---

## 📱 配置 WhatsApp（可选）

```bash
moltbot channels login
```

用 WhatsApp 扫描二维码完成配对。

---

## 🔐 安全建议

### 1. 使用强 Token
生成随机 token:
```bash
openssl rand -base64 32
```

### 2. 配置防火墙
仅允许特定 IP 访问:
```bash
az network nsg rule update \
  --resource-group moltbot-rg \
  --nsg-name moltbot-vmNSG \
  --name AllowMoltbotGateway \
  --source-address-prefixes YOUR_IP/32
```

### 3. 启用 HTTPS（高级）
使用 Nginx + Let's Encrypt 或 Azure Application Gateway

---

## 💰 费用明细

| 项目 | 月费用 |
|------|--------|
| VM B4ms | ~$60 |
| 64GB SSD | ~$5 |
| 公网 IP | ~$3 |
| GPT-5 API | $5-40（按用量）|
| **总计** | **$73-108** |

---

## 🆘 常见问题

### Q: VM 创建失败
A: 检查订阅配额，或尝试其他区域
```bash
az vm list-sizes --location eastus --output table
```

### Q: 端口不通
A: 检查 NSG 规则
```bash
az network nsg rule list --resource-group moltbot-rg --nsg-name moltbot-vmNSG --output table
```

### Q: Moltbot 启动失败
A: 检查日志
```bash
moltbot gateway --port 18789 --verbose
```

---

## 📚 参考链接

- [Moltbot 文档](https://docs.molt.bot)
- [Azure OpenAI 定价](https://azure.microsoft.com/pricing/details/azure-openai/)
- [GitHub Repo](https://github.com/eniac871/moltbot-azure-deploy)

---

**部署完成！** 🎉
