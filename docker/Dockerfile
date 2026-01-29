FROM node:22-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Moltbot
RUN curl -fsSL https://molt.bot/install.sh | bash

# Create workspace
WORKDIR /root/clawd
RUN mkdir -p /root/.clawdbot

# Expose Moltbot Gateway port
EXPOSE 18789

# Default command
CMD ["moltbot", "gateway", "--port", "18789", "--verbose"]
