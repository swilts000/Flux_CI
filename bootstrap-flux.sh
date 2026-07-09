#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pause() {
    echo ""
    read -p "Press Enter to continue to the next step..."
    echo ""
}

# ============================================================
# STEP 1: Configure Variables
# ============================================================
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}STEP 1: Configure Variables${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

export GITHUB_USER="swilts000"
export GITHUB_REPO="Flux_CI"
export GITHUB_BRANCH="main"
export FLUX_PATH="clusters/colima"

echo "GitHub User:   $GITHUB_USER"
echo "GitHub Repo:   $GITHUB_REPO"
echo "Branch:        $GITHUB_BRANCH"
echo "Flux Path:     $FLUX_PATH"

pause

# ============================================================
# STEP 2: Enter GitHub Token
# ============================================================
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}STEP 2: Enter GitHub Personal Access Token${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "Token needs 'repo' scope. Get one at: https://github.com/settings/tokens"
echo ""

read -sp "Enter your GitHub Personal Access Token: " GITHUB_TOKEN
echo ""
export GITHUB_TOKEN

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}❌ Error: Token cannot be empty${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Token received${NC}"

pause

# ============================================================
# STEP 3: Verify Kubernetes Connection
# ============================================================
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}STEP 3: Verify Kubernetes Connection${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo "Checking kubectl connection..."
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ Connected to Kubernetes cluster${NC}"
    kubectl cluster-info | head -2
else
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    echo "Make sure Colima is running: colima start --kubernetes"
    exit 1
fi

pause

# ============================================================
# STEP 4: Check Flux Prerequisites
# ============================================================
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}STEP 4: Check Flux Prerequisites${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo "Running flux check --pre..."
if flux check --pre; then
    echo -e "${GREEN}✓ All prerequisites passed${NC}"
else
    echo -e "${RED}❌ Prerequisites check failed${NC}"
    exit 1
fi

pause

# ============================================================
# STEP 5: Bootstrap Flux
# ============================================================
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}STEP 5: Bootstrap Flux${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo "This will:"
echo "  - Install Flux components in flux-system namespace"
echo "  - Create $FLUX_PATH directory in your repo"
echo "  - Configure Flux to sync from this path"
echo ""
read -p "Proceed with bootstrap? (y/n): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Bootstrapping Flux..."
flux bootstrap github \
  --owner="$GITHUB_USER" \
  --repository="$GITHUB_REPO" \
  --branch="$GITHUB_BRANCH" \
  --path="$FLUX_PATH" \
  --personal

pause

# ============================================================
# STEP 6: Verify Flux Installation
# ============================================================
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}STEP 6: Verify Flux Installation${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo "Running flux check..."
flux check

echo ""
echo "Flux pods:"
kubectl get pods -n flux-system

pause

# ============================================================
# STEP 7: Verify Git Source
# ============================================================
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}STEP 7: Verify Git Source${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo "Git sources:"
flux get sources git

echo ""
echo "Kustomizations:"
flux get kustomizations

# ============================================================
# COMPLETE
# ============================================================
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Flux Bootstrap Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo "  1. Pull the latest changes: git pull origin main"
echo "  2. Create todo-app kustomization in $FLUX_PATH/todo-app/"
echo "  3. Push changes and watch Flux reconcile"
echo ""
echo "Useful commands:"
echo "  flux get all                    - Show all Flux resources"
echo "  flux logs --follow              - Stream Flux logs"
echo "  flux reconcile kustomization flux-system --with-source"
