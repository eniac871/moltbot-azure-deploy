#!/bin/bash
# Install Moltbot and dependencies on Ubuntu
# This script runs on the Azure VM

set -e

echo "📦 Updating packages..."
sudo apt-get update
sudo apt-get upgrade -y

echo "🟢 Installing Node.js 22+..."
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "✅ Node version: $(node --version)"
echo "✅ NPM version: $(npm --version)"

echo "🤖 Installing Moltbot..."
curl -fsSL https://molt.bot/install.sh | bash

# Alternative: npm install
# npm install -g moltbot@latest

echo "📁 Creating Moltbot config directory..."
mkdir -p ~/.clawdbot

echo "🔧 Moltbot installed successfully!"
echo "Version: $(moltbot --version 2>/dev/null || echo 'Check with: moltbot status')"
