#!/bin/bash
# Moltbot Azure fully automated deployment script
# Usage: ./deploy.sh -r RESOURCE_NAME -k API_KEY -d DEPLOYMENT_NAME

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
RESOURCE_GROUP="moltbot-rg"
VM_NAME="moltbot-vm"
LOCATION="eastus"
VM_SIZE="Standard_B4ms"
ADMIN_USER="azureuser"
GATEWAY_PORT="18789"

# Azure OpenAI configuration (passed via parameters)
AZURE_RESOURCE_NAME=""
AZURE_API_KEY=""
AZURE_DEPLOYMENT="gpt-5"

# Show help
show_help() {
    echo -e "${BLUE}Moltbot Azure Fully Automated Deployment Script${NC}"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Required parameters:"
    echo "  -r, --resource-name    Azure OpenAI resource name"
    echo "  -k, --api-key          Azure OpenAI API Key"
    echo ""
    echo "Optional parameters:"
    echo "  -d, --deployment       Model deployment name (default: gpt-5)"
    echo "  -g, --resource-group   Azure resource group name (default: moltbot-rg)"
    echo "  -v, --vm-name          VM name (default: moltbot-vm)"
    echo "  -l, --location         Azure region (default: eastus)"
    echo "  -s, --vm-size          VM size (default: Standard_B4ms)"
    echo "  -h, --help             Show help"
    echo ""
    echo "Examples:"
    echo "  $0 -r my-openai-resource -k abc123xyz..."
    echo "  $0 -r my-openai-resource -k abc123xyz... -d gpt-5 -l westus2"
}

# Parse parameters
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
            echo -e "${RED}Error: Unknown parameter $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$AZURE_RESOURCE_NAME" || -z "$AZURE_API_KEY" ]]; then
    echo -e "${RED}Error: Azure OpenAI resource name and API Key are required${NC}"
    show_help
    exit 1
fi

# Generate random Gateway Token
GATEWAY_TOKEN=$(openssl rand -hex 32)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Moltbot Azure Fully Automated Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  VM Name: $VM_NAME"
echo "  Region: $LOCATION"
echo "  VM Size: $VM_SIZE"
echo "  Azure OpenAI: $AZURE_RESOURCE_NAME"
echo "  Model Deployment: $AZURE_DEPLOYMENT"
echo ""

# Step 1: Check Azure CLI
echo -e "${BLUE}[Step 1/8] Checking Azure CLI...${NC}"
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI first: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check login status
echo "Checking Azure login status..."
az account show &> /dev/null || {
    echo -e "${YELLOW}Azure login required...${NC}"
    az login
}

echo -e "${GREEN}✓ Azure CLI ready${NC}"
echo ""

# Step 2: Create resource group
echo -e "${BLUE}[Step 2/8] Creating resource group...${NC}"
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none
echo -e "${GREEN}✓ Resource group $RESOURCE_GROUP created successfully${NC}"
echo ""

# Step 3: Create VM
echo -e "${BLUE}[Step 3/8] Creating VM ($VM_SIZE)...${NC}"
echo "This may take 2-5 minutes..."

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

echo -e "${GREEN}✓ VM created successfully${NC}"
echo "  Public IP: $VM_PUBLIC_IP"
echo ""

# Step 4: Open port
echo -e "${BLUE}[Step 4/8] Opening port $GATEWAY_PORT...${NC}"
az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "${VM_NAME}NSG" \
    --name "AllowMoltbotGateway" \
    --protocol tcp \
    --priority 1010 \
    --destination-port-range "$GATEWAY_PORT" \
    --access allow \
    --output none

echo -e "${GREEN}✓ Port $GATEWAY_PORT opened${NC}"
echo ""

# Step 5: Generate Moltbot configuration
echo -e "${BLUE}[Step 5/8] Generating Moltbot configuration...${NC}"

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

echo -e "${GREEN}✓ Configuration generated successfully${NC}"
echo ""

# Step 6: Install Node.js and Moltbot
echo -e "${BLUE}[Step 6/8] Installing Node.js and Moltbot on VM...${NC}"
echo "This may take 3-5 minutes..."

# Create install script
INSTALL_SCRIPT=$(cat <<'ENDSCRIPT'
#!/bin/bash
set -e

# Update system
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

# Install Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - > /dev/null 2>&1
sudo apt-get install -y nodejs -qq

# Verify Node.js
node --version
npm --version

# Configure npm global path
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.npm-global/bin:$PATH"

# Install Moltbot
curl -fsSL https://molt.bot/install.sh | bash

# Create config directories
mkdir -p ~/.clawdbot
mkdir -p ~/clawd

echo "Installation complete!"
ENDSCRIPT
)

# Copy and execute install script
echo "$INSTALL_SCRIPT" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i ~/.ssh/id_rsa \
    "${ADMIN_USER}@${VM_PUBLIC_IP}" \
    'bash -s' 2>/dev/null

echo -e "${GREEN}✓ Node.js and Moltbot installed successfully${NC}"
echo ""

# Step 7: Deploy configuration
echo -e "${BLUE}[Step 7/8] Deploying Moltbot configuration...${NC}"

# Write config file
echo "$MOLTBOT_CONFIG" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i ~/.ssh/id_rsa \
    "${ADMIN_USER}@${VM_PUBLIC_IP}" \
    "cat > ~/.clawdbot/clawdbot.json" 2>/dev/null

echo -e "${GREEN}✓ Configuration deployed${NC}"
echo ""

# Step 8: Create systemd service and start
echo -e "${BLUE}[Step 8/8] Creating service and starting Moltbot...${NC}"

SERVICE_SCRIPT=$(cat <<EOF
#!/bin/bash
export PATH="\$HOME/.npm-global/bin:\$PATH"

# Create systemd service
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

# Start service
sudo systemctl daemon-reload
sudo systemctl enable moltbot
sudo systemctl start moltbot

# Wait for service to start
sleep 3

# Check status
if sudo systemctl is-active --quiet moltbot; then
    echo "Service started successfully!"
else
    echo "Service failed to start, checking logs:"
    sudo journalctl -u moltbot -n 20 --no-pager
    exit 1
fi
EOF
)

echo "$SERVICE_SCRIPT" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i ~/.ssh/id_rsa \
    "${ADMIN_USER}@${VM_PUBLIC_IP}" \
    'bash -s' 2>/dev/null

echo -e "${GREEN}✓ Moltbot service started${NC}"
echo ""

# Done
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 Moltbot Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Access Information:${NC}"
echo "  VM IP: $VM_PUBLIC_IP"
echo "  Gateway URL: http://${VM_PUBLIC_IP}:${GATEWAY_PORT}"
echo "  Gateway Token: ${GATEWAY_TOKEN}"
echo ""
echo -e "${BLUE}SSH Connection:${NC}"
echo "  ssh ${ADMIN_USER}@${VM_PUBLIC_IP}"
echo ""
echo -e "${BLUE}Manage Service:${NC}"
echo "  ssh ${ADMIN_USER}@${VM_PUBLIC_IP} 'sudo systemctl status moltbot'"
echo "  ssh ${ADMIN_USER}@${VM_PUBLIC_IP} 'sudo systemctl restart moltbot'"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Access Dashboard: http://${VM_PUBLIC_IP}:${GATEWAY_PORT}"
echo "  2. Enter Gateway Token for authentication"
echo "  3. Configure WhatsApp: moltbot channels login"
echo ""
echo -e "${YELLOW}Cost Estimate:${NC}"
echo "  VM $VM_SIZE: ~\$60/month"
echo "  Azure OpenAI GPT-5: Pay-per-use"
echo "  Total: ~\$65-100/month"
echo ""
