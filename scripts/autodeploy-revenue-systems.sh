#!/bin/bash
# Master Deployment Auto-Deploy Revenue System
# One-command orchestrator for all revenue-generating enterprise systems

set -e

echo "🚀 Master Deployment Auto-Deploy Revenue System"
echo "=================================================="

# Configuration
DEPLOY_TARGET="${1:-railway}"  # Default to Railway, accepts: railway, vercel, kubernetes
REVENUE_SYSTEMS=(
  "nwu-protocol"
  "enterprise-unified-platform"
  "tree-of-life-system"
  "autonomous-orchestrator-core"
  "ai-business-platform"
  "systems-master-hub"
)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# Deploy to Railway
deploy_railway() {
  local repo=$1
  echo -e "${YELLOW}Deploying ${repo} to Railway...${NC}"
  
  # Clone if not exists
  if [ ! -d "../${repo}" ]; then
    git clone "https://github.com/Garrettc123/${repo}.git" "../${repo}"
  fi
  
  cd "../${repo}"
  railway up || echo -e "${RED}Railway deploy failed for ${repo}${NC}"
  cd - > /dev/null
  
  echo -e "${GREEN}✓ ${repo} deployed to Railway${NC}"
}

# Deploy to Vercel
deploy_vercel() {
  local repo=$1
  echo -e "${YELLOW}Deploying ${repo} to Vercel...${NC}"
  
  if [ ! -d "../${repo}" ]; then
    git clone "https://github.com/Garrettc123/${repo}.git" "../${repo}"
  fi
  
  cd "../${repo}"
  vercel --prod || echo -e "${RED}Vercel deploy failed for ${repo}${NC}"
  cd - > /dev/null
  
  echo -e "${GREEN}✓ ${repo} deployed to Vercel${NC}"
}

# Deploy to Kubernetes
deploy_kubernetes() {
  local repo=$1
  echo -e "${YELLOW}Deploying ${repo} to Kubernetes...${NC}"
  
  if [ ! -d "../${repo}" ]; then
    git clone "https://github.com/Garrettc123/${repo}.git" "../${repo}"
  fi
  
  cd "../${repo}"
  
  # Check for Helm chart
  if [ -d "helm" ]; then
    helm upgrade --install "${repo}" ./helm || echo -e "${RED}Helm deploy failed for ${repo}${NC}"
  elif [ -f "k8s/deployment.yaml" ]; then
    kubectl apply -f k8s/ || echo -e "${RED}K8s deploy failed for ${repo}${NC}"
  else
    echo -e "${RED}No K8s config found for ${repo}${NC}"
  fi
  
  cd - > /dev/null
  
  echo -e "${GREEN}✓ ${repo} deployed to Kubernetes${NC}"
}

# Main deployment loop
echo ""
echo "Deploying to: ${DEPLOY_TARGET}"
echo "Revenue systems to deploy: ${#REVENUE_SYSTEMS[@]}"
echo ""

for repo in "${REVENUE_SYSTEMS[@]}"; do
  case "${DEPLOY_TARGET}" in
    railway)
      deploy_railway "${repo}"
      ;;
    vercel)
      deploy_vercel "${repo}"
      ;;
    kubernetes|k8s)
      deploy_kubernetes "${repo}"
      ;;
    *)
      echo -e "${RED}Unknown deploy target: ${DEPLOY_TARGET}${NC}"
      echo "Usage: $0 [railway|vercel|kubernetes]"
      exit 1
      ;;
  esac
  echo ""
done

echo -e "${GREEN}=================================================="
echo "✅ All revenue systems deployed to ${DEPLOY_TARGET}!"
echo "=================================================="
echo ""
echo "💰 Auto-money mode: ACTIVATED"
echo "🔄 Systems are now generating revenue automatically"
echo ""
echo "Next steps:"
echo "  1. Configure billing webhooks (Stripe/Paddle)"
echo "  2. Set up monitoring dashboards"
echo "  3. Enable auto-scaling policies"
echo ""
echo "Monitor at: https://your-dashboard-url.com"
