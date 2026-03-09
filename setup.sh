#!/bin/sh
set -eu

REPO="https://raw.githubusercontent.com/catflyflyfly/personal-mail-agent/main"

echo "Setting up Personal Mail Agent..."

mkdir -p config/spamassassin

echo "Downloading files..."
curl -fsSL "$REPO/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO/config/agent.lua.example" -o config/agent.lua
curl -fsSL "$REPO/config/spamassassin/custom.cf.example" -o config/spamassassin/custom.cf
curl -fsSL "$REPO/config/spamassassin/local.cf" -o config/spamassassin/local.cf

echo ""
echo "Done! Next steps:"
echo "  1. Edit config/agent.lua with your IMAP credentials"
echo "  2. Run: docker compose up -d"
