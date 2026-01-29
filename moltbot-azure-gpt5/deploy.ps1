# Moltbot Azure Auto Deploy - PowerShell Version
param(
    [string]$ResourceGroup = "moltbot-rg",
    [string]$Location = "eastus",
    [string]$ModelName = "gpt-5-mini"
)

$ErrorActionPreference = "Stop"
$AzPath = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

function Write-Color($Text, $Color = "White") {
    Write-Host $Text -ForegroundColor $Color
}

Write-Color "========================================" "Blue"
Write-Color "  Moltbot + Azure OpenAI Deployment" "Blue"
Write-Color "========================================" "Blue"
Write-Host ""
Write-Color "Config:" "Yellow"
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  Location: $Location"
Write-Host "  Model: $ModelName"
Write-Host ""

# Check Azure CLI
Write-Color "[Step 1/10] Checking Azure CLI..." "Yellow"
if (-not (Test-Path $AzPath)) {
    Write-Color "Error: Azure CLI not found" "Red"
    exit 1
}
& $AzPath account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Color "Please run: az login" "Red"
    exit 1
}
Write-Color "OK - Azure CLI ready" "Green"

# Step 1: Create Resource Group
Write-Host ""
Write-Color "[Step 2/10] Creating Resource Group: $ResourceGroup" "Yellow"
& $AzPath group create --name $ResourceGroup --location $Location --output none
Write-Color "OK - Resource Group created" "Green"

# Step 2: Create Azure OpenAI
Write-Host ""
Write-Color "[Step 3/10] Creating Azure OpenAI resource..." "Yellow"
Write-Host "This may take 1-2 minutes..."
& $AzPath cognitiveservices account create --name "moltbot-openai" --resource-group $ResourceGroup --location $Location --kind OpenAI --sku s0 --yes --output none
Write-Color "OK - Azure OpenAI created" "Green"

# Step 3: Get API Key
Write-Host ""
Write-Color "[Step 4/10] Getting API Key..." "Yellow"
$AOAI_KEY = & $AzPath cognitiveservices account keys list --name "moltbot-openai" --resource-group $ResourceGroup --query key1 --output tsv
Write-Color "OK - API Key retrieved" "Green"

# Step 4: Deploy Model
Write-Host ""
Write-Color "[Step 5/10] Deploying model: $ModelName..." "Yellow"
$ModelVersions = @{
    "gpt-5-mini" = "2025-08-07"
    "gpt-5-nano" = "2025-08-07"
    "gpt-4o" = "2024-08-06"
    "gpt-4o-mini" = "2024-07-18"
    "gpt-4" = "0613"
    "gpt-35-turbo" = "0125"
}
$ModelSKUs = @{
    "gpt-5-mini" = "GlobalStandard"
    "gpt-5-nano" = "GlobalStandard"
    "gpt-4o" = "Standard"
    "gpt-4o-mini" = "Standard"
    "gpt-4" = "Standard"
    "gpt-35-turbo" = "Standard"
}
if (-not $ModelVersions.ContainsKey($ModelName)) {
    Write-Color "Error: Unsupported model: $ModelName" "Red"
    exit 1
}
$ModelVersion = $ModelVersions[$ModelName]
$ModelSKU = $ModelSKUs[$ModelName]
& $AzPath cognitiveservices account deployment create --name "moltbot-openai" --resource-group $ResourceGroup --deployment-name $ModelName --model-name $ModelName --model-version $ModelVersion --model-format OpenAI --sku-capacity 1 --sku-name $ModelSKU --output none 2>$null
Write-Color "OK - Model deployed" "Green"

# Step 5: Create VM
Write-Host ""
Write-Color "[Step 6/10] Creating VM (Standard_B4ms)..." "Yellow"
Write-Host "This may take 3-5 minutes..."
$VM_RESULT = & $AzPath vm create --resource-group $ResourceGroup --name "moltbot-vm" --image Ubuntu2204 --size Standard_B4ms --admin-username azureuser --generate-ssh-keys --public-ip-sku Standard --query "{publicIpAddress:publicIpAddress}" --output json | ConvertFrom-Json
$VM_PUBLIC_IP = $VM_RESULT.publicIpAddress
Write-Color "OK - VM created: $VM_PUBLIC_IP" "Green"

# Step 6: Open Ports
Write-Host ""
Write-Color "[Step 7/10] Opening ports..." "Yellow"
& $AzPath network nsg rule create --resource-group $ResourceGroup --nsg-name "moltbot-vmNSG" --name "AllowMoltbot" --protocol tcp --priority 1010 --destination-port-range 80 443 18789 --access allow --output none 2>$null
Write-Color "OK - Ports opened" "Green"

# Step 7: Install Node.js and Moltbot
Write-Host ""
Write-Color "[Step 8/10] Installing Node.js and Moltbot..." "Yellow"
Write-Host "This may take 3-5 minutes..."
$SSH_KEY = "$env:USERPROFILE\.ssh\id_rsa"
$INSTALL_CMD = @'
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
'@
$INSTALL_CMD | ssh -o StrictHostKeyChecking=no -i $SSH_KEY "azureuser@$VM_PUBLIC_IP" 'bash -s' 2>$null
Write-Color "OK - Moltbot installed" "Green"

# Step 8: Configure Moltbot
Write-Host ""
Write-Color "[Step 9/10] Configuring Moltbot..." "Yellow"
$MOLTBOT_CONFIG = @"
{
  "models": {
    "mode": "merge",
    "providers": {
      "azure": {
        "baseUrl": "https://moltbot-openai.openai.azure.com/openai/v1",
        "apiKey": "$AOAI_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "$ModelName",
            "name": "Azure $ModelName",
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
        "primary": "azure/$ModelName"
      },
      "workspace": "/home/azureuser/clawd"
    }
  },
  "gateway": {
    "mode": "local",
    "port": 18789
  }
}
"@
$MOLTBOT_CONFIG | ssh -o StrictHostKeyChecking=no -i $SSH_KEY "azureuser@$VM_PUBLIC_IP" 'cat > ~/.clawdbot/clawdbot.json'
Write-Color "OK - Moltbot configured" "Green"

# Step 9: Install Nginx
Write-Host ""
Write-Color "[Step 10/10] Installing Nginx..." "Yellow"
$NGINX_CMD = @'
sudo apt-get install -y nginx
sudo tee /etc/nginx/sites-available/moltbot > /dev/null <<'EOF'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
sudo ln -sf /etc/nginx/sites-available/moltbot /etc/nginx/sites-enabled/moltbot
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
'@
$NGINX_CMD | ssh -o StrictHostKeyChecking=no -i $SSH_KEY "azureuser@$VM_PUBLIC_IP" 'bash -s' 2>$null
Write-Color "OK - Nginx configured" "Green"

# Step 10: Start Moltbot
Write-Host ""
Write-Color "[Step 10/10] Starting Moltbot service..." "Yellow"
$START_CMD = @'
export PATH="$HOME/.npm-global/bin:$PATH"
sudo tee /etc/systemd/system/moltbot.service > /dev/null <<'EOF'
[Unit]
Description=Moltbot Gateway
After=network.target
[Service]
Type=simple
User=azureuser
Environment="PATH=/home/azureuser/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=/home/azureuser/.npm-global/bin/clawdbot gateway --port 18789
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable moltbot
sudo systemctl start moltbot
sleep 3
sudo systemctl is-active --quiet moltbot && echo "Service running"
'@
$START_CMD | ssh -o StrictHostKeyChecking=no -i $SSH_KEY "azureuser@$VM_PUBLIC_IP" 'bash -s' 2>$null
Write-Color "OK - Moltbot started" "Green"

# Output
Write-Host ""
Write-Color "========================================" "Green"
Write-Color "  Deployment Complete!" "Green"
Write-Color "========================================" "Green"
Write-Host ""
Write-Color "Access Info:" "Blue"
Write-Host "  VM IP: $VM_PUBLIC_IP"
Write-Host "  HTTP URL: http://$VM_PUBLIC_IP"
Write-Host "  Direct URL: http://$VM_PUBLIC_IP:18789"
Write-Host "  SSH: ssh azureuser@$VM_PUBLIC_IP"
Write-Host ""
Write-Color "SSH Tunnel (recommended):" "Blue"
Write-Host "  ssh -L 18789:localhost:18789 azureuser@$VM_PUBLIC_IP"
Write-Host "  Then access: http://localhost:18789"
Write-Host ""
Write-Color "Azure OpenAI:" "Blue"
Write-Host "  Resource: moltbot-openai"
Write-Host "  Model: $ModelName"
Write-Host "  Endpoint: https://moltbot-openai.openai.azure.com"
Write-Host ""
Write-Color "Cost Estimate:" "Yellow"
Write-Host "  VM B4ms: ~$60/month"
Write-Host "  Azure OpenAI: pay-per-use"
Write-Host "  Total: ~$65-100/month"
Write-Host ""
