#!/bin/bash
# Moltbot Azure 全自动部署脚本
# 用法: ./deploy.sh -r RESOURCE_NAME -k API_KEY -d DEPLOYMENT_NAME

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
RESOURCE_GROUP="moltbot-rg"
VM_NAME="moltbot-vm"
LOCATION="eastus"
VM_SIZE="Standard_B4ms"
ADMIN_USER="azureuser"
GATEWAY_PORT="18789"

# Azure OpenAI 配置（通过参数传入）
AZURE_RESOURCE_NAME=""
AZURE_API_KEY=""
AZURE_DEPLOYMENT="gpt-5"

# 显示帮助
show_help() {
    echo -e "${BLUE}Moltbot Azure 全自动部署脚本${NC}"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "必需参数:"
    echo "  -r, --resource-name    Azure OpenAI 资源名"
    echo "  -k, --api-key          Azure OpenAI API Key"
    echo ""
    echo "可选参数:"
    echo "  -d, --deployment       模型部署名 (默认: gpt-5)"
    echo "  -g, --resource-group   Azure 资源组名 (默认: moltbot-rg)"
    echo "  -v, --vm-name          VM 名称 (默认: moltbot-vm)"
    echo "  -l, --location         Azure 区域 (默认: eastus)"
    echo "  -s, --vm-size          VM 规格 (默认: Standard_B4ms)"
    echo "  -h, --help             显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 -r my-openai-resource -k abc123xyz..."
    echo "  $0 -r my-openai-resource -k abc123xyz... -d gpt-5 -l westus2"
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--resource-name)
            AZURE_RESOURCE_NAME="$2"
            shift 2
            ;;
        -k|--api-key)
            AZURE_API_KEY="$2"
            shift 2
            ;;
        -d|--deployment)
            AZURE_DEPLOYMENT="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -v|--vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--vm-size)
            VM_SIZE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}错误: 未知参数 $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# 验证必需参数
if [[ -z "$AZURE_RESOURCE_NAME" || -z "$AZURE_API_KEY" ]]; then
    echo -e "${RED}错误: 必须提供 Azure OpenAI 资源名和 API Key${NC}"
    show_help
    exit 1
fi

# 生成随机 Gateway Token
GATEWAY_TOKEN=$(openssl rand -hex 32)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Moltbot Azure 全自动部署${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}配置信息:${NC}"
echo "  资源组: $RESOURCE_GROUP"
echo "  VM 名称: $VM_NAME"
echo "  区域: $LOCATION"
echo "  VM 规格: $VM_SIZE"
echo "  Azure OpenAI: $AZURE_RESOURCE_NAME"
echo "  模型部署: $AZURE_DEPLOYMENT"
echo ""

# 步骤 1: 检查 Azure CLI
echo -e "${BLUE}[步骤 1/8] 检查 Azure CLI...${NC}"
if ! command -v az &> /dev/null; then
    echo -e "${RED}错误: Azure CLI 未安装${NC}"
    echo "请先安装 Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# 检查登录状态
echo "检查 Azure 登录状态..."
az account show &> /dev/null || {
    echo -e "${YELLOW}需要登录 Azure...${NC}"
    az login
}

echo -e "${GREEN}✓ Azure CLI 就绪${NC}"
echo ""

# 步骤 2: 创建资源组
echo -e "${BLUE}[步骤 2/8] 创建资源组...${NC}"
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none
echo -e "${GREEN}✓ 资源组 $RESOURCE_GROUP 创建成功${NC}"
echo ""

# 步骤 3: 创建 VM
echo -e "${BLUE}[步骤 3/8] 创建 VM ($VM_SIZE)...${NC}"
echo "这可能需要 2-5 分钟..."

VM_RESULT=$(az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --image Ubuntu2204 \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USER" \
    --generate-ssh-keys \
    --public-ip-sku Standard \
    --query '{publicIpAddress:publicIpAddress, privateIpAddress:networkProfile.networkInterfaces[0].id}' \
    --output json)

VM_PUBLIC_IP=$(echo "$VM_RESULT" | jq -r '.publicIpAddress')

echo -e "${GREEN}✓ VM 创建成功${NC}"
echo "  公网 IP: $VM_PUBLIC_IP"
echo ""

# 步骤 4: 开放端口
echo -e "${BLUE}[步骤 4/8] 开放端口 $GATEWAY_PORT...${NC}"
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "${VM_NAME}NSG" \
    --name "AllowMoltbotGateway" \
    --protocol tcp \
    --priority 1010 \
    --destination-port-range "$GATEWAY_PORT" \
    --access allow \
    --output none

echo -e "${GREEN}✓ 端口 $GATEWAY_PORT 已开放${NC}"
echo ""

# 步骤 5: 生成 Moltbot 配置
echo -e "${BLUE}[步骤 5/8] 生成 Moltbot 配置...${NC}"

MOLTBOT_CONFIG=$(cat <<EOF
{
  "models": {
    "mode": "merge",
    "providers": {
      "azure": {
        "baseUrl": "https://${AZURE_RESOURCE_NAME}.openai.azure.com/openai/v1",
        "apiKey": "${AZURE_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "${AZURE_DEPLOYMENT}",
            "name": "Azure ${AZURE_DEPLOYMENT}",
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
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "azure/${AZURE_DEPLOYMENT}",
        "fallbacks": []
      },
      "workspace": "/home/${ADMIN_USER}/clawd",
      "sandbox": {
        "mode": "non-main"
      }
    }
  },
  "gateway": {
    "port": ${GATEWAY_PORT},
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
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
EOF
)

echo -e "${GREEN}✓ 配置生成成功${NC}"
echo ""

# 步骤 6: 安装 Node.js 和 Moltbot
echo -e "${BLUE}[步骤 6/8] 在 VM 上安装 Node.js 和 Moltbot...${NC}"
echo "这可能需要 3-5 分钟..."

# 创建安装脚本
INSTALL_SCRIPT=$(cat <<'ENDSCRIPT'
#!/bin/bash
set -e

# 更新系统
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

# 安装 Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - > /dev/null 2>&1
sudo apt-get install -y nodejs -qq

# 验证 Node.js
node --version
npm --version

# 配置 npm 全局路径
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.npm-global/bin:$PATH"

# 安装 Moltbot
curl -fsSL https://molt.bot/install.sh | bash

# 创建配置目录
mkdir -p ~/.clawdbot
mkdir -p ~/clawd

echo "安装完成!"
ENDSCRIPT
)

# 复制并执行安装脚本
echo "$INSTALL_SCRIPT" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i ~/.ssh/id_rsa \
    "${ADMIN_USER}@${VM_PUBLIC_IP}" \
    'bash -s' 2>/dev/null

echo -e "${GREEN}✓ Node.js 和 Moltbot 安装成功${NC}"
echo ""

# 步骤 7: 部署配置
echo -e "${BLUE}[步骤 7/8] 部署 Moltbot 配置...${NC}"

# 写入配置文件
echo "$MOLTBOT_CONFIG" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i ~/.ssh/id_rsa \
    "${ADMIN_USER}@${VM_PUBLIC_IP}" \
    "cat > ~/.clawdbot/clawdbot.json" 2>/dev/null

echo -e "${GREEN}✓ 配置已部署${NC}"
echo ""

# 步骤 8: 创建 systemd 服务并启动
echo -e "${BLUE}[步骤 8/8] 创建服务并启动 Moltbot...${NC}"

SERVICE_SCRIPT=$(cat <<EOF
#!/bin/bash
export PATH="\$HOME/.npm-global/bin:\$PATH"

# 创建 systemd 服务
sudo tee /etc/systemd/system/moltbot.service > /dev/null <<'EOFSERVICE'
[Unit]
Description=Moltbot Gateway
After=network.target

[Service]
Type=simple
User=${ADMIN_USER}
WorkingDirectory=/home/${ADMIN_USER}
Environment="PATH=/home/${ADMIN_USER}/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/home/${ADMIN_USER}/.npm-global/bin/clawdbot gateway --port ${GATEWAY_PORT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable moltbot
sudo systemctl start moltbot

# 等待服务启动
sleep 3

# 检查状态
if sudo systemctl is-active --quiet moltbot; then
    echo "服务启动成功!"
else
    echo "服务启动失败，查看日志:"
    sudo journalctl -u moltbot -n 20 --no-pager
    exit 1
fi
EOF
)

echo "$SERVICE_SCRIPT" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i ~/.ssh/id_rsa \
    "${ADMIN_USER}@${VM_PUBLIC_IP}" \
    'bash -s' 2>/dev/null

echo -e "${GREEN}✓ Moltbot 服务已启动${NC}"
echo ""

# 完成
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 Moltbot 部署完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}访问信息:${NC}"
echo "  VM IP: $VM_PUBLIC_IP"
echo "  Gateway URL: http://${VM_PUBLIC_IP}:${GATEWAY_PORT}"
echo "  Gateway Token: ${GATEWAY_TOKEN}"
echo ""
echo -e "${BLUE}SSH 连接:${NC}"
echo "  ssh ${ADMIN_USER}@${VM_PUBLIC_IP}"
echo ""
echo -e "${BLUE}管理服务:${NC}"
echo "  ssh ${ADMIN_USER}@${VM_PUBLIC_IP} 'sudo systemctl status moltbot'"
echo "  ssh ${ADMIN_USER}@${VM_PUBLIC_IP} 'sudo systemctl restart moltbot'"
echo ""
echo -e "${YELLOW}下一步:${NC}"
echo "  1. 访问 Dashboard: http://${VM_PUBLIC_IP}:${GATEWAY_PORT}"
echo "  2. 输入 Gateway Token 进行认证"
echo "  3. 配置 WhatsApp: moltbot channels login"
echo ""
echo -e "${YELLOW}费用提醒:${NC}"
echo "  VM $VM_SIZE: ~\$60/月"
echo "  Azure OpenAI GPT-5: 按用量计费"
echo "  总计: ~\$65-100/月"
echo ""
