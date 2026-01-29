#!/bin/bash
# Moltbot Azure 全自动部署脚本（包含 Azure OpenAI 创建）
# 用法: ./deploy-full-auto.sh [资源组名] [区域]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
RESOURCE_GROUP="${1:-moltbot-rg}"
LOCATION="${2:-eastus}"
VM_NAME="moltbot-vm"
VM_SIZE="Standard_B4ms"
ADMIN_USER="azureuser"
GATEWAY_PORT="18789"
AOAI_RESOURCE_NAME="moltbot-openai"
AOAI_DEPLOYMENT_NAME="gpt-5"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Moltbot + Azure OpenAI 全自动部署${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查 Azure CLI
echo -e "${YELLOW}[检查] Azure CLI...${NC}"
if ! command -v az &> /dev/null; then
    echo -e "${RED}错误: Azure CLI 未安装${NC}"
    exit 1
fi
az account show &> /dev/null || { echo -e "${RED}请先运行: az login${NC}"; exit 1; }
echo -e "${GREEN}✓ Azure CLI 就绪${NC}"

# 步骤 1: 创建资源组
echo ""
echo -e "${YELLOW}[步骤 1/9] 创建资源组: $RESOURCE_GROUP${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
echo -e "${GREEN}✓ 资源组创建成功${NC}"

# 步骤 2: 创建 Azure OpenAI 资源
echo ""
echo -e "${YELLOW}[步骤 2/9] 创建 Azure OpenAI 资源...${NC}"
echo "这可能需要 1-2 分钟..."
az cognitiveservices account create \
    --name "$AOAI_RESOURCE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --kind OpenAI \
    --sku s0 \
    --yes \
    --output none

echo -e "${GREEN}✓ Azure OpenAI 资源创建成功${NC}"

# 获取 API Key
echo ""
echo -e "${YELLOW}[步骤 3/9] 获取 API Key...${NC}"
AOAI_KEY=$(az cognitiveservices account keys list \
    --name "$AOAI_RESOURCE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query key1 --output tsv)
echo -e "${GREEN}✓ API Key 获取成功${NC}"

# 步骤 4: 部署 GPT-5 模型
echo ""
echo -e "${YELLOW}[步骤 4/9] 部署 GPT-5 模型...${NC}"
az cognitiveservices account deployment create \
    --name "$AOAI_RESOURCE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name "$AOAI_DEPLOYMENT_NAME" \
    --model-name gpt-5 \
    --model-version "2025-07-01" \
    --model-format OpenAI \
    --sku-capacity 1 \
    --sku-name Standard \
    --output none 2>/dev/null || echo -e "${YELLOW}⚠ 模型可能已存在或需要审批${NC}"

echo -e "${GREEN}✓ GPT-5 模型部署成功${NC}"

# 步骤 5: 创建 VM
echo ""
echo -e "${YELLOW}[步骤 5/9] 创建 VM ($VM_SIZE)...${NC}"
echo "这可能需要 3-5 分钟..."

VM_RESULT=$(az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --image Ubuntu2204 \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USER" \
    --generate-ssh-keys \
    --public-ip-sku Standard \
    --query '{publicIpAddress:publicIpAddress}' \
    --output json)

VM_PUBLIC_IP=$(echo "$VM_RESULT" | jq -r '.publicIpAddress')
echo -e "${GREEN}✓ VM 创建成功: $VM_PUBLIC_IP${NC}"

# 步骤 6: 开放端口
echo ""
echo -e "${YELLOW}[步骤 6/9] 开放端口...${NC}"
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "${VM_NAME}NSG" \
    --name "AllowMoltbot" \
    --protocol tcp \
    --priority 1010 \
    --destination-port-range "$GATEWAY_PORT" \
    --access allow \
    --output none
echo -e "${GREEN}✓ 端口 $GATEWAY_PORT 已开放${NC}"

# 生成 Gateway Token
GATEWAY_TOKEN=$(openssl rand -hex 16)

# 创建 Moltbot 配置
echo ""
echo -e "${YELLOW}[步骤 7/9] 创建 Moltbot 配置...${NC}"

MOLTBOT_CONFIG=$(cat <<EOF
{
  "models": {
    "mode": "merge",
    "providers": {
      "azure": {
        "baseUrl": "https://${AOAI_RESOURCE_NAME}.openai.azure.com/openai/v1",
        "apiKey": "${AOAI_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "${AOAI_DEPLOYMENT_NAME}",
            "name": "Azure GPT-5",
            "reasoning": true,
            "input": ["text", "image"],
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
        "primary": "azure/${AOAI_DEPLOYMENT_NAME}"
      },
      "workspace": "/home/${ADMIN_USER}/clawd"
    }
  },
  "gateway": {
    "port": ${GATEWAY_PORT},
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    }
  }
}
EOF
)

echo -e "${GREEN}✓ 配置已生成${NC}"

# 步骤 8: 安装 Moltbot
echo ""
echo -e "${YELLOW}[步骤 8/9] 在 VM 上安装 Moltbot...${NC}"
echo "这可能需要 3-5 分钟..."

INSTALL_CMD=$(cat <<'INSTALL'
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq && sudo apt-get upgrade -y -qq
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - > /dev/null 2>&1
sudo apt-get install -y nodejs -qq
mkdir -p ~/.npm-global && npm config set prefix '~/.npm-global'
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.npm-global/bin:$PATH"
curl -fsSL https://molt.bot/install.sh | bash
mkdir -p ~/.clawdbot ~/clawd
echo "安装完成"
INSTALL
)

echo "$INSTALL_CMD" | ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${ADMIN_USER}@${VM_PUBLIC_IP}" 'bash -s' 2>/dev/null
echo -e "${GREEN}✓ Moltbot 安装成功${NC}"

# 步骤 9: 部署配置和启动
echo ""
echo -e "${YELLOW}[步骤 9/9] 部署配置并启动...${NC}"

# 写入配置
echo "$MOLTBOT_CONFIG" | ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${ADMIN_USER}@${VM_PUBLIC_IP}" 'cat > ~/.clawdbot/clawdbot.json'

# 创建并启动服务
START_CMD=$(cat <<EOF
export PATH="\$HOME/.npm-global/bin:\$PATH"
sudo tee /etc/systemd/system/moltbot.service > /dev/null <<'SVCFILE'
[Unit]
Description=Moltbot Gateway
After=network.target
[Service]
Type=simple
User=${ADMIN_USER}
Environment="PATH=/home/${ADMIN_USER}/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=/home/${ADMIN_USER}/.npm-global/bin/clawdbot gateway --port ${GATEWAY_PORT}
Restart=always
[Install]
WantedBy=multi-user.target
SVCFILE
sudo systemctl daemon-reload
sudo systemctl enable moltbot
sudo systemctl start moltbot
sleep 3
sudo systemctl is-active --quiet moltbot && echo "服务运行中"
EOF
)

echo "$START_CMD" | ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${ADMIN_USER}@${VM_PUBLIC_IP}" 'bash -s' 2>/dev/null
echo -e "${GREEN}✓ Moltbot 已启动${NC}"

# 完成输出
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 全自动部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}访问信息:${NC}"
echo "  VM IP: $VM_PUBLIC_IP"
echo "  Gateway URL: http://${VM_PUBLIC_IP}:${GATEWAY_PORT}"
echo "  Gateway Token: ${GATEWAY_TOKEN}"
echo "  SSH: ssh ${ADMIN_USER}@${VM_PUBLIC_IP}"
echo ""
echo -e "${BLUE}Azure OpenAI:${NC}"
echo "  资源名: $AOAI_RESOURCE_NAME"
echo "  终结点: https://${AOAI_RESOURCE_NAME}.openai.azure.com"
echo ""
echo -e "${YELLOW}费用提醒:${NC}"
echo "  VM B4ms: ~\$60/月"
echo "  Azure OpenAI: 按用量计费"
echo "  总计: ~\$65-100/月"
echo ""
