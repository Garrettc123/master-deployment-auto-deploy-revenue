# Railway Auto-Deploy Setup

## One-Time Setup (2 minutes)

### Step 1: Get Railway Token
1. Go to https://railway.app/account/tokens
2. Click **New Token**
3. Name it `github-actions-deploy`
4. Copy the token

### Step 2: Add to GitHub Secrets
1. Go to https://github.com/Garrettc123/master-deployment-auto-deploy-revenue/settings/secrets/actions
2. Click **New repository secret**
3. Name: `RAILWAY_TOKEN`
4. Value: paste your Railway token
5. Click **Add secret**

### Step 3: Done
Railway will now auto-deploy all 25 services:
- On every push to main
- Every 6 hours automatically
- Manually via Actions tab → Railway Auto-Deploy → Run workflow

## Services Deployed
- garcar-enterprise-production
- revenue-agent-system
- nwu-protocol
- tree-of-life-system
- mars-production
- apex-revenue-system
- garcar-autonomous-wealth-system
- autonomous-orchestrator-core
- enterprise-mlops-platform
- ai-powered-deal-desk
- customer-churn-predictor
- seo-content-factory
- defi-yield-aggregator
- smart-contract-auditor-ai
- lead-enrichment-engine
- automated-sales-outreach
- neural-mesh
- zero-human-governance-core
- ai-business-automation-tree
- autonomous-butler-core
- asynchronous-automation-framework
- all-in-one-auto-acquisition-system
- pocket-revenue-ai-deploy
- api-key-automaton
- tree-of-life-core
