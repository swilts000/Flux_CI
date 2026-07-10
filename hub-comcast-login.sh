#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

REGISTRY="hub.comcast.net"

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Docker Login to Atlus Registry${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Registry: $REGISTRY"
echo ""

read -p "Enter your username: " USERNAME
if [ -z "$USERNAME" ]; then
    echo -e "${RED}❌ Error: Username cannot be empty${NC}"
    exit 1
fi

read -sp "Enter your token: " TOKEN
echo ""

if [ -z "$TOKEN" ]; then
    echo -e "${RED}❌ Error: Token cannot be empty${NC}"
    exit 1
fi

echo ""
echo "Logging in to $REGISTRY..."

if docker login -u "$USERNAME" -p "$TOKEN" "$REGISTRY"; then
    echo ""
    echo -e "${GREEN}✅ Successfully logged in to $REGISTRY${NC}"
else
    echo ""
    echo -e "${RED}❌ Login failed${NC}"
    exit 1
fi
