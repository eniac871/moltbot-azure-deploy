#!/bin/bash
# Deploy Moltbot on Azure VM with B4ms instance
# Usage: ./deploy-azure-vm.sh <resource-group> <vm-name> <location>

set -e

RESOURCE_GROUP=${1:-moltbot-rg}
VM_NAME=${2:-moltbot-vm}
LOCATION=${3:-eastus}
ADMIN_USER="azureuser"

echo "🚀 Deploying Moltbot on Azure..."
echo "Resource Group: $RESOURCE_GROUP"
echo "VM Name: $VM_NAME"
echo "Location: $LOCATION"

# Create resource group
echo "📦 Creating resource group..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

# Create VM with B4ms size
echo "🖥️  Creating Azure VM (B4ms - 4vCPU/16GB)..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --image Ubuntu2204 \
  --size Standard_B4ms \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --public-ip-sku Standard

# Get public IP
VM_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --show-details \
  --query "publicIps" \
  --output tsv)

echo "✅ VM created with IP: $VM_IP"

# Open port 18789 for Moltbot Gateway
echo "🔓 Opening port 18789..."
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "${VM_NAME}NSG" \
  --name AllowMoltbotGateway \
  --protocol tcp \
  --priority 1000 \
  --destination-port-range 18789 \
  --access allow \
  --direction inbound

# Open port 443 for HTTPS (optional)
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "${VM_NAME}NSG" \
  --name AllowHTTPS \
  --protocol tcp \
  --priority 1001 \
  --destination-port-range 443 \
  --access allow \
  --direction inbound

echo "🔧 Installing Moltbot on VM..."
# Copy install script to VM and execute
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts @scripts/install-moltbot.sh

echo ""
echo "🎉 Deployment complete!"
echo "VM IP: $VM_IP"
echo "SSH: ssh $ADMIN_USER@$VM_IP"
echo ""
echo "Next steps:"
echo "1. SSH into the VM: ssh $ADMIN_USER@$VM_IP"
echo "2. Configure Azure OpenAI credentials in ~/.clawdbot/clawdbot.json"
echo "3. Start Moltbot: moltbot gateway --port 18789"
echo "4. Access dashboard: http://$VM_IP:18789"
