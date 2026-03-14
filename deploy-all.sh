#!/usr/bin/env bash
set -euo pipefail

echo "=== MASTER DEPLOY: Starting full enterprise stack deployment ==="
echo "Timestamp: $(date -u)"

# Install Railway CLI
npm install -g @railway/cli 2>/dev/null || true

# Services to deploy (Railway project service names)
SERVICES=(
  "garcar-enterprise-production"
  "revenue-agent-system"
  "nwu-protocol"
  "tree-of-life-system"
  "mars-production"
  "apex-revenue-system"
  "garcar-autonomous-wealth-system"
  "autonomous-orchestrator-core"
  "enterprise-mlops-platform"
  "ai-powered-deal-desk"
  "customer-churn-predictor"
  "seo-content-factory"
  "defi-yield-aggregator"
  "smart-contract-auditor-ai"
  "lead-enrichment-engine"
  "automated-sales-outreach"
  "neural-mesh"
  "zero-human-governance-core"
  "ai-business-automation-tree"
  "autonomous-butler-core"
  "asynchronous-automation-framework"
  "all-in-one-auto-acquisition-system"
  "pocket-revenue-ai-deploy"
  "api-key-automaton"
  "tree-of-life-core"
)

SUCCESS=0
FAILED=0

for SERVICE in "${SERVICES[@]}"; do
  echo "--- Deploying: $SERVICE"
  if railway redeploy --service "$SERVICE" --yes 2>/dev/null; then
    echo "  OK: $SERVICE deployed"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  WARN: $SERVICE redeploy failed (may not exist yet)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "=== DEPLOY COMPLETE ==="
echo "Success: $SUCCESS | Failed/Skipped: $FAILED"
echo "Timestamp: $(date -u)"

# Health check loop
echo ""
echo "=== HEALTH CHECKS ==="
HEALTH_URLS=(
  "${GARCAR_URL:-}"
  "${REVENUE_AGENT_URL:-}"
  "${NWU_URL:-}"
  "${MARS_URL:-}"
  "${APEX_URL:-}"
)

for URL in "${HEALTH_URLS[@]}"; do
  if [ -n "$URL" ]; then
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL/health" --max-time 10 2>/dev/null || echo "000")
    echo "  $URL/health -> $STATUS"
  fi
done

echo ""
echo "All done. Enterprise stack deployment complete."
