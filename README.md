# Moltbot Azure GPT-5 Deployment

Azure deployment scripts and configurations for running Moltbot (formerly Clawdbot) with Azure OpenAI GPT-5.

## 📋 Overview

This repository contains:
- Azure VM deployment scripts
- Moltbot configuration for Azure OpenAI GPT-5
- Docker deployment option
- Terraform infrastructure-as-code

## 💰 Cost Estimation

| Component | Monthly Cost |
|-----------|-------------|
| Azure VM (B4ms) | ~$60 |
| Azure OpenAI GPT-5 | $5-40 (usage-based) |
| **Total** | **$65-100** |

## 🚀 Quick Start

### Option 1: Azure CLI Deployment

```bash
# Run the deployment script
./scripts/deploy-azure-vm.sh
```

### Option 2: Terraform Deployment

```bash
cd terraform
terraform init
terraform apply
```

### Option 3: Docker Deployment

```bash
docker-compose up -d
```

## 📁 Repository Structure

```
.
├── README.md
├── config/
│   └── moltbot.json.example       # Moltbot configuration template
├── scripts/
│   ├── deploy-azure-vm.sh         # Azure VM deployment script
│   ├── install-moltbot.sh         # Moltbot installation script
│   └── configure-aoai.sh          # Azure OpenAI configuration
├── terraform/
│   ├── main.tf                    # Terraform main configuration
│   ├── variables.tf               # Terraform variables
│   └── outputs.tf                 # Terraform outputs
└── docker/
    ├── Dockerfile
    └── docker-compose.yml
```

## 🔧 Configuration

1. Copy the example configuration:
   ```bash
   cp config/moltbot.json.example ~/.clawdbot/clawdbot.json
   ```

2. Edit the configuration with your Azure OpenAI credentials:
   - `AZURE_RESOURCE_NAME`: Your Azure OpenAI resource name
   - `AZURE_API_KEY`: Your Azure OpenAI API key
   - `AZURE_ENDPOINT`: Your Azure OpenAI endpoint URL

## 📖 Documentation

- [Moltbot Documentation](https://docs.molt.bot)
- [Azure OpenAI Service](https://azure.microsoft.com/en-us/products/ai-services/openai-service)

## 📄 License

MIT
