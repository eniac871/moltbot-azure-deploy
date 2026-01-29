#!/bin/bash
# Moltbot Azure fully automated deployment script (includes Azure OpenAI creation)
# Usage: ./deploy-full-auto.sh [resource-group] [region] [model-name]

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="${1:-moltbot-rg}"
LOCATION="${2:-eastus}"
MODEL_NAME="${3:-gpt-5-mini}"  # Supported: gpt-5-mini, gpt-5-nano, gpt-4o, gpt-4o-mini, gpt-4, gpt-35-turbo
VM_NAME="moltbot-vm"
VM_SIZE="Standard_B4ms"
ADMIN_USER="azureuser"
GATEWAY_PORT="18789"
AOAI_RESOURCE_NAME="moltbot-openai"

# Model version mapping
declare -A MODEL_VERSIONS=(
    ["gpt-5-mini"]="2025-08-07"
    ["gpt-5-nano"]="2025-08-07"
    ["gpt-4o"]="2024-08-06"
    ["gpt-4o-mini"]="2024-07-18"
    ["gpt-4"]="0613"
    ["gpt-35-turbo"]="0125"
)

# Model SKU mapping
declare -A MODEL_SKUS=(
    ["gpt-5-mini"]="GlobalStandard"
    ["gpt-5-nano"]="GlobalStandard"
    ["gpt-4o"]="Standard"
    ["gpt-4o-mini"]="Standard"
    ["gpt-4"]="Standard"
    ["gpt-35-turbo"]="Standard"
)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Moltbot + Azure OpenAI Fully Automated Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Region: $LOCATION"
echo "  Model: $MODEL_NAME"
echo ""

# Validate model
if [[ -z "${MODEL_VERSIONS[$MODEL_NAME]}" ]]; then
    echo -e "${RED}Error: Unsupported model: $MODEL_NAME${NC}"
    echo "Supported models:"
    for model in "${!MODEL_VERSIONS[@]}"; do
        echo "  - $model"
    done
    exit 1
fi

MODEL_VERSION="${MODEL_VERSIONS[$MODEL_NAME]}"
MODEL_SKU="${MODEL_SKUS[$MODEL_NAME]}"

# Check Azure CLI
echo -e "${YELLOW}[Check] Azure CLI...${NC}"
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    exit 1
fi
az account show &> /dev/null || { echo -e "${RED}Please run first: az login${NC}"; exit 1; }
echo -e "${GREEN}✓ Azure CLI ready${NC}"

# Step 1: Create resource group
echo ""
echo -e "${YELLOW}[Step 1/9] Creating resource group: $RESOURCE_GROUP${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
echo -e "${GREEN}✓ Resource group created successfully${NC}"

# Step 2: Create Azure OpenAI resource
echo ""
echo -e "${YELLOW}[Step 2/9] Creating Azure OpenAI resource...${NC}"
echo "This may take 1-2 minutes..."
az cognitiveservices account create \
    --name "$AOAI_RESOURCE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --kind OpenAI \
    --sku s0 \
    --yes \
    --output none

echo -e "${GREEN}✓ Azure OpenAI resource created successfully${NC}"

# Get API Key
echo ""
echo -e "${YELLOW}[Step 3/9] Retrieving API Key...${NC}"
AOAI_KEY=$(az cognitiveservices account keys list \
    --name "$AOAI_RESOURCE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query key1 --output tsv)
echo -e "${GREEN}✓ API Key retrieved successfully${NC}"

# Step 4: Deploy model
echo ""
echo -e "${YELLOW}[Step 4/9] Deploying model: $MODEL_NAME (version: $MODEL_VERSION, SKU: $MODEL_SKU)...${NC}"

# Attempt deployment; skip if it fails (may already exist or require approval)
if az cognitiveservices account deployment create \
    --name "$AOAI_RESOURCE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name "$MODEL_NAME" \
    --model-name "$MODEL_NAME" \
    --model-version "$MODEL_VERSION" \
    --model-format OpenAI \
    --sku-capacity 1 \
    --sku-name "$MODEL_SKU" \
    --output none 2>/dev/null; then
    echo -e "${GREEN}✓ Model deployed successfully${NC}"
else
    echo -e "${YELLOW}⚠ Model deployment failed or already exists, continuing...${NC}"
    # Check available models
    echo -e "${YELLOW}Available models:${NC}"
    az cognitiveservices account list-models \
        --name "$AOAI_RESOURCE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'gpt')].{name:name, version:version}" \
        -o table 2>/dev/null || echo "Unable to retrieve model list"
fi

# Step 5: Create VM
echo ""
echo -e "${YELLOW}[Step 5/9] Creating VM ($VM_SIZE)...${NC}"
echo "This may take 3-5 minutes..."

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
echo -e "${GREEN}✓ VM created successfully: $VM_PUBLIC_IP${NC}"

# Step 6: Open port
echo ""
echo -e "${YELLOW}[Step 6/9] Opening port...${NC}"
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "${VM_NAME}NSG" \
    --name "AllowMoltbot" \
    --protocol tcp \
    --priority 1010 \
    --destination-port-range "$GATEWAY_PORT" \
    --access allow \
    --output none 2>/dev/null || echo -e "${YELLOW}⚠ Rule may already exist${NC}"
echo -e "${GREEN}✓ Port $GATEWAY_PORT opened${NC}"

# Generate Gateway Token
GATEWAY_TOKEN=$(openssl rand -hex 16)

# Create Moltbot configuration
echo ""
echo -e "${YELLOW}[Step 7/9] Creating Moltbot configuration...${NC}"

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
            "id": "${MODEL_NAME}",
            "name": "Azure ${MODEL_NAME}",
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
        "primary": "azure/${MODEL_NAME}"
      },
      "workspace": "/home/${ADMIN_USER}/clawd"
    }
  },
  "gateway": {
    "mode": "local",
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

echo -e "${GREEN}✓ Configuration generated${NC}"

# Step 8: Install Moltbot
echo ""
echo -e "${YELLOW}[Step 8/9] Installing Moltbot on VM...${NC}"
echo "This may take 3-5 minutes..."

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
echo "Installation complete"
INSTALL
)

echo "$INSTALL_CMD" | ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${ADMIN_USER}@${VM_PUBLIC_IP}" 'bash -s' 2>/dev/null
echo -e "${GREEN}✓ Moltbot installed successfully${NC}"

# Step 9: Deploy configuration and start
echo ""
echo -e "${YELLOW}[Step 9/9] Deploying configuration and starting...${NC}"

# Write configuration
echo "$MOLTBOT_CONFIG" | ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${ADMIN_USER}@${VM_PUBLIC_IP}" 'cat > ~/.clawdbot/clawdbot.json'

# Create and start service
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
sudo systemctl is-active --quiet moltbot && echo "Service is running"
EOF
)

echo "$START_CMD" | ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${ADMIN_USER}@${VM_PUBLIC_IP}" 'bash -s' 2>/dev/null
echo -e "${GREEN}✓ Moltbot started${NC}"

# Final output
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 Fully Automated Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Access Information:${NC}"
echo "  VM IP: $VM_PUBLIC_IP"
echo "  Gateway URL: http://${VM_PUBLIC_IP}:${GATEWAY_PORT}"
echo "  Gateway Token: ${GATEWAY_TOKEN}"
echo "  SSH: ssh ${ADMIN_USER}@${VM_PUBLIC_IP}"
echo ""
echo -e "${BLUE}Azure OpenAI:${NC}"
echo "  Resource Name: $AOAI_RESOURCE_NAME"
echo "  Model: $MODEL_NAME"
echo "  Endpoint: https://${AOAI_RESOURCE_NAME}.openai.azure.com"
echo ""
echo -e "${YELLOW}Cost Estimate:${NC}"
echo "  VM B4ms: ~\$60/month"
echo "  Azure OpenAI: Pay-per-use"
echo "  Total: ~\$65-100/month"
echo ""
