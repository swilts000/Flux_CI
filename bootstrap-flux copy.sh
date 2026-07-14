set -e

export GITHUB_USER="SWilts000"
export GITHUB_REPO=""
export GITHUB_BRANCH="main"
export FLUX_PATH="clusters/local"

read -sp "Enter your GitHub Personal Access Token: " GITHUB_TOKEN
echo ""
export GITHUB_TOKEN

echo "Bootstrapping Flux..."

flux bootstrap github \
  --owner="$GITHUB_USER" \
  --repository="$GITHUB_REPO" \
  --branch="$GITHUB_BRANCH" \
  --path="$FLUX_PATH" \
  --personal

echo "✅ Flux bootstrap complete!"
echo ""
echo "Verify with:"
echo "  flux check"
echo "  flux get sources git"
echo "  flux get kustomizations"
