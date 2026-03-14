# Add Your Railway Token — 60 Seconds

## Step 1: Get Your Railway Token
Go to: https://railway.app/account/tokens
- Click **New Token**
- Name: `github-actions`
- Copy the token

## Step 2: Run the Auto-Add Workflow
Go to: https://github.com/Garrettc123/master-deployment-auto-deploy-revenue/actions/workflows/auto-add-railway-token.yml
- Click **Run workflow**
- Paste your Railway token in the input box
- Click **Run workflow**

That's it. The workflow will:
1. Automatically encrypt and save your token as `RAILWAY_TOKEN` secret
2. Immediately trigger Railway auto-provision for all 25+ services
3. Every future deploy is fully automatic — no more manual steps

## After Setup
- Every Copilot PR merge → auto-deploys to Railway
- Every 15 minutes → new repos auto-provisioned
- Every 6 hours → all services redeployed
