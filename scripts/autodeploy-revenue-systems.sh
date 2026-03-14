#!/bin/bash
# Master Deployment Auto-Deploy Revenue System
# One-command orchestrator for all revenue-generating enterprise systems
#
# Features:
#   - Parallel deployment to Railway / Render / Vercel / Kubernetes
#   - Health check loop with retry after each deploy
#   - Rollback to previous version when a health check fails
#   - Stripe revenue verification (active subscriptions check)
#   - Slack / Discord webhook notifications
#   - Environment variable sync across Railway services via Railway CLI
#
# Usage: ./deploy.sh [railway|render|vercel|kubernetes]

set -uo pipefail

# ───────────────────────────── Configuration ──────────────────────────────── #

DEPLOY_TARGET="${1:-railway}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${REPO_ROOT}/.deploy-logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DEPLOY_LOG="${LOG_DIR}/deploy_${TIMESTAMP}.log"
STATUS_DIR=""  # set in main() after mktemp

REVENUE_SYSTEMS=(
  "nwu-protocol"
  "enterprise-unified-platform"
  "tree-of-life-system"
  "autonomous-orchestrator-core"
  "ai-business-platform"
  "systems-master-hub"
)

# Health check retry configuration
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-10}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ───────────────────────────── Utility ────────────────────────────────────── #

log() {
  local msg="$1"
  if [ -n "${DEPLOY_LOG:-}" ] && [ -d "${LOG_DIR:-}" ]; then
    echo -e "$msg" | tee -a "${DEPLOY_LOG}"
  else
    echo -e "$msg"
  fi
}

# Send a notification to Slack and/or Discord.
# $1 – status label (starting|success|failure|warning)
# $2 – human-readable message
# $3 – Slack color (good/warning/danger or hex)
send_notification() {
  local status="$1"
  local message="$2"
  local color="${3:-good}"

  if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    local payload
    payload="{\"attachments\":[{\"color\":\"${color}\",\"text\":\"${message}\",\"footer\":\"Master Deploy | ${TIMESTAMP}\"}]}"
    curl -s -X POST "${SLACK_WEBHOOK_URL}" \
      -H 'Content-type: application/json' \
      -d "${payload}" > /dev/null \
      || log "${YELLOW}Warning: Slack notification failed${NC}"
  fi

  if [ -n "${DISCORD_WEBHOOK_URL:-}" ]; then
    local payload
    payload="{\"content\":\"${message}\"}"
    curl -s -X POST "${DISCORD_WEBHOOK_URL}" \
      -H 'Content-type: application/json' \
      -d "${payload}" > /dev/null \
      || log "${YELLOW}Warning: Discord notification failed${NC}"
  fi
}

# Write the deploy status for a repo to the shared status directory.
# $1 – repo name  $2 – status string (success|failed|skipped|health_failed)
write_status() {
  local repo="$1"
  local status="$2"
  if [ -n "${STATUS_DIR:-}" ]; then
    printf '%s' "${status}" > "${STATUS_DIR}/${repo}.status"
  fi
}

# Read the deploy status for a repo from the shared status directory.
# $1 – repo name
read_status() {
  local repo="$1"
  if [ -n "${STATUS_DIR:-}" ] && [ -f "${STATUS_DIR}/${repo}.status" ]; then
    cat "${STATUS_DIR}/${repo}.status"
  else
    echo "unknown"
  fi
}

# Write the previous deployment ID (for rollback) to the status directory.
write_rollback_id() {
  local repo="$1"
  local id="$2"
  if [ -n "${STATUS_DIR:-}" ]; then
    printf '%s' "${id}" > "${STATUS_DIR}/${repo}.rollback_id"
  fi
}

read_rollback_id() {
  local repo="$1"
  if [ -n "${STATUS_DIR:-}" ] && [ -f "${STATUS_DIR}/${repo}.rollback_id" ]; then
    cat "${STATUS_DIR}/${repo}.rollback_id"
  else
    echo ""
  fi
}

# ─────────────────────────── Environment Sync ─────────────────────────────── #

# Sync .env variables to a Railway service using the Railway CLI.
# Looks for ${REPO_ROOT}/.env.<repo> first, then ${REPO_ROOT}/.env.shared.
sync_env_railway() {
  local repo="$1"
  local env_file="${REPO_ROOT}/.env.${repo}"

  if [ ! -f "${env_file}" ]; then
    env_file="${REPO_ROOT}/.env.shared"
  fi

  if [ ! -f "${env_file}" ]; then
    log "${YELLOW}  [${repo}] No env file found, skipping Railway env sync${NC}"
    return 0
  fi

  log "${YELLOW}  [${repo}] Syncing environment variables from ${env_file}...${NC}"

  while IFS= read -r line || [ -n "${line}" ]; do
    # Skip comments and blank lines
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"

    if [ -n "${key}" ]; then
      (cd "${REPO_ROOT}/../${repo}" \
        && railway variables set "${key}=${value}" 2>/dev/null) \
        || log "${YELLOW}    Warning: Could not set ${key} for ${repo}${NC}"
    fi
  done < "${env_file}"

  log "${GREEN}  [${repo}] ✓ Environment synced${NC}"
}

# ───────────────────────────── Health Checks ──────────────────────────────── #

# Check that a deployed service is responding with HTTP 2xx/3xx.
# The health-check URL is resolved (in order of precedence) from:
#   1. Env var HEALTH_CHECK_<REPO_SLUG_UPPERCASE>  e.g. HEALTH_CHECK_NWU_PROTOCOL
#   2. Falls back gracefully if not set.
health_check() {
  local repo="$1"
  local max_retries="${2:-${HEALTH_CHECK_RETRIES}}"
  local retry_interval="${3:-${HEALTH_CHECK_INTERVAL}}"

  # Convert repo name to env-var key: nwu-protocol → NWU_PROTOCOL
  local url_key
  url_key="HEALTH_CHECK_$(echo "${repo}" | tr '[:lower:]-' '[:upper:]_')"
  local url="${!url_key:-}"

  if [ -z "${url}" ]; then
    log "${YELLOW}  [${repo}] No health check URL configured (set ${url_key}), skipping${NC}"
    return 0
  fi

  log "${YELLOW}  [${repo}] Health checking at ${url} (up to ${max_retries} attempts)...${NC}"

  local i
  for i in $(seq 1 "${max_retries}"); do
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${url}" 2>/dev/null \
      || echo "000")

    if [ "${http_code}" -ge 200 ] 2>/dev/null && [ "${http_code}" -lt 400 ] 2>/dev/null; then
      log "${GREEN}  [${repo}] ✓ Health check passed (HTTP ${http_code})${NC}"
      return 0
    fi

    log "${YELLOW}  [${repo}] Attempt ${i}/${max_retries}: HTTP ${http_code}, retrying in ${retry_interval}s...${NC}"
    sleep "${retry_interval}"
  done

  log "${RED}  [${repo}] ✗ Health check FAILED after ${max_retries} attempts${NC}"
  return 1
}

# ─────────────────────────────── Rollback ─────────────────────────────────── #

rollback_railway() {
  local repo="$1"
  local prev_id
  prev_id="$(read_rollback_id "${repo}")"
  log "${YELLOW}  [${repo}] Rolling back on Railway...${NC}"

  if [ -n "${prev_id}" ]; then
    (cd "${REPO_ROOT}/../${repo}" && railway rollback "${prev_id}") \
      || log "${RED}  [${repo}] Rollback failed${NC}"
  else
    (cd "${REPO_ROOT}/../${repo}" && railway rollback) \
      || log "${RED}  [${repo}] Rollback failed${NC}"
  fi

  log "${GREEN}  [${repo}] ✓ Rolled back${NC}"
}

rollback_vercel() {
  local repo="$1"
  local prev_id
  prev_id="$(read_rollback_id "${repo}")"
  log "${YELLOW}  [${repo}] Rolling back on Vercel...${NC}"

  if [ -n "${prev_id}" ]; then
    (cd "${REPO_ROOT}/../${repo}" \
      && vercel rollback "${prev_id}" --token "${VERCEL_TOKEN:-}" --yes) \
      || log "${RED}  [${repo}] Rollback failed${NC}"
  else
    log "${YELLOW}  [${repo}] No previous deployment ID available, cannot rollback${NC}"
  fi
}

# ──────────────────────── Stripe / Revenue Verification ───────────────────── #

verify_stripe() {
  local repo="$1"
  log "${YELLOW}  [${repo}] Verifying Stripe configuration...${NC}"

  if [ -z "${STRIPE_SECRET_KEY:-}" ]; then
    log "${YELLOW}  [${repo}] Warning: STRIPE_SECRET_KEY not set, skipping Stripe check${NC}"
    return 0
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${STRIPE_SECRET_KEY}" \
    "https://api.stripe.com/v1/account" 2>/dev/null || echo "000")

  if [ "${http_code}" = "200" ]; then
    log "${GREEN}  [${repo}] ✓ Stripe account verified${NC}"

    # Check for at least one active subscription
    local subs_json
    subs_json=$(curl -s \
      -H "Authorization: Bearer ${STRIPE_SECRET_KEY}" \
      "https://api.stripe.com/v1/subscriptions?status=active&limit=1" 2>/dev/null || echo "{}")

    if echo "${subs_json}" | grep -q '"id":"sub_'; then
      log "${GREEN}  [${repo}] ✓ Active subscriptions found${NC}"
    else
      log "${YELLOW}  [${repo}] Warning: No active subscriptions found${NC}"
    fi
  else
    log "${YELLOW}  [${repo}] Warning: Stripe API returned HTTP ${http_code}${NC}"
  fi
}

# ────────────────────────── Platform Deploy Functions ─────────────────────── #

# Clone the repo if it doesn't exist, or pull latest changes.
_ensure_repo() {
  local repo="$1"
  local repo_dir="${REPO_ROOT}/../${repo}"

  if [ ! -d "${repo_dir}" ]; then
    log "${YELLOW}  [${repo}] Cloning...${NC}"
    git clone "https://github.com/Garrettc123/${repo}.git" "${repo_dir}" \
      >> "${DEPLOY_LOG}" 2>&1 \
      || { log "${RED}  [${repo}] Clone failed${NC}"; return 1; }
  else
    log "${YELLOW}  [${repo}] Pulling latest...${NC}"
    git -C "${repo_dir}" pull origin main >> "${DEPLOY_LOG}" 2>&1 \
      || log "${YELLOW}  [${repo}] Warning: git pull failed, using existing code${NC}"
  fi
}

deploy_railway() {
  local repo="$1"

  _ensure_repo "${repo}" || { write_status "${repo}" "failed"; return 1; }

  local repo_dir="${REPO_ROOT}/../${repo}"

  # Capture previous deployment ID for rollback
  local prev_id
  prev_id=$(cd "${repo_dir}" \
    && railway status --json 2>/dev/null \
    | grep -o '"deploymentId":"[^"]*"' \
    | head -1 \
    | cut -d'"' -f4 2>/dev/null \
    || echo "")
  write_rollback_id "${repo}" "${prev_id}"

  sync_env_railway "${repo}"

  log "${YELLOW}  [${repo}] Deploying to Railway...${NC}"
  if (cd "${repo_dir}" && railway up --detach >> "${DEPLOY_LOG}" 2>&1); then
    write_status "${repo}" "success"
    log "${GREEN}  [${repo}] ✓ Deployed to Railway${NC}"
    return 0
  else
    write_status "${repo}" "failed"
    log "${RED}  [${repo}] ✗ Railway deploy FAILED${NC}"
    return 1
  fi
}

deploy_render() {
  local repo="$1"

  _ensure_repo "${repo}" || { write_status "${repo}" "failed"; return 1; }

  # Resolve service ID: repo-specific env var takes priority over global
  local env_key
  env_key="RENDER_SERVICE_ID_$(echo "${repo}" | tr '[:lower:]-' '[:upper:]_')"
  local service_id="${!env_key:-${RENDER_SERVICE_ID:-}}"

  if [ -z "${service_id}" ] || [ -z "${RENDER_API_KEY:-}" ]; then
    log "${YELLOW}  [${repo}] RENDER_API_KEY or service ID not set, skipping${NC}"
    write_status "${repo}" "skipped"
    return 0
  fi

  log "${YELLOW}  [${repo}] Triggering Render deploy...${NC}"
  local response
  response=$(curl -s -X POST \
    "https://api.render.com/v1/services/${service_id}/deploys" \
    -H "Authorization: Bearer ${RENDER_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"clearCache":"do_not_clear"}' 2>/dev/null || echo "{}")

  if echo "${response}" | grep -q '"id"'; then
    write_status "${repo}" "success"
    log "${GREEN}  [${repo}] ✓ Render deploy triggered${NC}"
    return 0
  else
    write_status "${repo}" "failed"
    log "${RED}  [${repo}] ✗ Render deploy failed: ${response}${NC}"
    return 1
  fi
}

deploy_vercel() {
  local repo="$1"

  _ensure_repo "${repo}" || { write_status "${repo}" "failed"; return 1; }

  local repo_dir="${REPO_ROOT}/../${repo}"

  # Capture latest deployment URL for rollback
  local prev_id
  prev_id=$(cd "${repo_dir}" \
    && vercel list --token "${VERCEL_TOKEN:-}" 2>/dev/null \
    | grep "● " | head -1 | awk '{print $2}' \
    || echo "")
  write_rollback_id "${repo}" "${prev_id}"

  log "${YELLOW}  [${repo}] Deploying to Vercel...${NC}"
  if (cd "${repo_dir}" \
      && vercel --prod --token "${VERCEL_TOKEN:-}" --yes >> "${DEPLOY_LOG}" 2>&1); then
    write_status "${repo}" "success"
    log "${GREEN}  [${repo}] ✓ Deployed to Vercel${NC}"
    return 0
  else
    write_status "${repo}" "failed"
    log "${RED}  [${repo}] ✗ Vercel deploy FAILED${NC}"
    return 1
  fi
}

deploy_kubernetes() {
  local repo="$1"

  _ensure_repo "${repo}" || { write_status "${repo}" "failed"; return 1; }

  local repo_dir="${REPO_ROOT}/../${repo}"
  log "${YELLOW}  [${repo}] Deploying to Kubernetes...${NC}"

  local deployed=0
  if [ -d "${repo_dir}/helm" ]; then
    if (cd "${repo_dir}" \
        && helm upgrade --install "${repo}" ./helm \
          --wait --timeout 5m >> "${DEPLOY_LOG}" 2>&1); then
      deployed=1
    fi
  elif [ -f "${repo_dir}/k8s/deployment.yaml" ]; then
    if (cd "${repo_dir}" && kubectl apply -f k8s/ >> "${DEPLOY_LOG}" 2>&1) \
        && (cd "${repo_dir}" \
          && kubectl rollout status "deployment/${repo}" \
            --timeout=5m >> "${DEPLOY_LOG}" 2>&1); then
      deployed=1
    fi
  else
    log "${RED}  [${repo}] No Helm chart or k8s/ manifests found${NC}"
    write_status "${repo}" "failed"
    return 1
  fi

  if [ "${deployed}" -eq 1 ]; then
    write_status "${repo}" "success"
    log "${GREEN}  [${repo}] ✓ Deployed to Kubernetes${NC}"
    return 0
  else
    write_status "${repo}" "failed"
    log "${RED}  [${repo}] ✗ Kubernetes deploy FAILED${NC}"
    return 1
  fi
}

# ─────────────────────── Parallel Deploy Orchestrator ─────────────────────── #

deploy_parallel() {
  log "${BLUE}Starting parallel deployment of ${#REVENUE_SYSTEMS[@]} systems to ${DEPLOY_TARGET}...${NC}"
  log ""

  local pids=()

  for repo in "${REVENUE_SYSTEMS[@]}"; do
    case "${DEPLOY_TARGET}" in
      railway)        deploy_railway    "${repo}" & ;;
      render)         deploy_render     "${repo}" & ;;
      vercel)         deploy_vercel     "${repo}" & ;;
      kubernetes|k8s) deploy_kubernetes "${repo}" & ;;
      *)
        log "${RED}Unknown deploy target: ${DEPLOY_TARGET}${NC}"
        log "Usage: $0 [railway|render|vercel|kubernetes]"
        exit 1
        ;;
    esac
    pids+=($!)
  done

  # Wait for all background jobs and collect exit codes
  local failures=0
  local i
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      failures=$((failures + 1))
    fi
  done

  log ""
  log "${BLUE}Deploy phase complete. Failures: ${failures}/${#REVENUE_SYSTEMS[@]}${NC}"
  return "${failures}"
}

# ─────────────────────────── Health Check Loop ────────────────────────────── #

run_health_checks() {
  log ""
  log "${BLUE}Running post-deploy health checks...${NC}"

  local failed=()
  local repo
  for repo in "${REVENUE_SYSTEMS[@]}"; do
    local status
    status="$(read_status "${repo}")"
    if [ "${status}" = "success" ]; then
      if ! health_check "${repo}"; then
        write_status "${repo}" "health_failed"
        failed+=("${repo}")
      fi
    fi
  done

  if [ "${#failed[@]}" -gt 0 ]; then
    log "${RED}Health checks failed for: ${failed[*]}${NC}"
    return 1
  fi

  log "${GREEN}All health checks passed!${NC}"
  return 0
}

# ──────────────────────── Revenue / Stripe Verification ───────────────────── #

verify_revenue_systems() {
  log ""
  log "${BLUE}Verifying revenue activation (Stripe)...${NC}"

  local repo
  for repo in "${REVENUE_SYSTEMS[@]}"; do
    verify_stripe "${repo}"
  done

  log "${GREEN}Revenue verification complete${NC}"
}

# ────────────────────────────── Rollback Handler ──────────────────────────── #

rollback_failed_services() {
  local repos=("$@")
  [ "${#repos[@]}" -eq 0 ] && return 0

  log ""
  log "${RED}Initiating rollback for ${#repos[@]} service(s): ${repos[*]}${NC}"
  send_notification "warning" \
    "⚠️ Rolling back failed services: ${repos[*]}" \
    "warning"

  local repo
  for repo in "${repos[@]}"; do
    case "${DEPLOY_TARGET}" in
      railway)  rollback_railway "${repo}" ;;
      vercel)   rollback_vercel  "${repo}" ;;
      *)        log "${YELLOW}  [${repo}] Rollback not implemented for ${DEPLOY_TARGET}${NC}" ;;
    esac
  done
}

# ──────────────────────────────── Main ────────────────────────────────────── #

main() {
  mkdir -p "${LOG_DIR}"
  STATUS_DIR="$(mktemp -d)"
  trap 'rm -rf "${STATUS_DIR}"' EXIT

  log "🚀 Master Deployment Auto-Deploy Revenue System"
  log "=================================================="
  log "Deploy target : ${DEPLOY_TARGET}"
  log "Systems       : ${#REVENUE_SYSTEMS[@]}"
  log "Timestamp     : ${TIMESTAMP}"
  log "Log file      : ${DEPLOY_LOG}"
  log ""

  send_notification "starting" \
    "🚀 Starting master deploy to ${DEPLOY_TARGET} — ${#REVENUE_SYSTEMS[@]} systems" \
    "#36a64f"

  # ── Phase 1: Deploy all systems in parallel ──────────────────────────────
  deploy_parallel || true

  # ── Phase 2: Health check every successfully deployed service ────────────
  run_health_checks || true

  # ── Phase 3: Rollback services that failed deploy or health check ─────────
  local failed_repos=()
  local repo
  for repo in "${REVENUE_SYSTEMS[@]}"; do
    local st
    st="$(read_status "${repo}")"
    if [ "${st}" = "failed" ] || [ "${st}" = "health_failed" ]; then
      failed_repos+=("${repo}")
    fi
  done
  rollback_failed_services "${failed_repos[@]+"${failed_repos[@]}"}"

  # ── Phase 4: Stripe / revenue verification ────────────────────────────────
  verify_revenue_systems

  # ── Phase 5: Summary and notifications ───────────────────────────────────
  local success_count=0
  local fail_count=0
  local summary=""

  for repo in "${REVENUE_SYSTEMS[@]}"; do
    local st
    st="$(read_status "${repo}")"
    case "${st}" in
      success)
        success_count=$((success_count + 1))
        summary+="✅ ${repo}"$'\n'
        ;;
      skipped)
        success_count=$((success_count + 1))
        summary+="⏭️  ${repo} (skipped)"$'\n'
        ;;
      *)
        fail_count=$((fail_count + 1))
        summary+="❌ ${repo} (${st})"$'\n'
        ;;
    esac
  done

  log ""
  log "${BLUE}=================================================="
  log "DEPLOYMENT SUMMARY"
  log "=================================================="
  log "Target   : ${DEPLOY_TARGET}"
  log "Success  : ${success_count}/${#REVENUE_SYSTEMS[@]}"
  log "Failed   : ${fail_count}/${#REVENUE_SYSTEMS[@]}"
  log "Log      : ${DEPLOY_LOG}"
  log ""
  echo -e "${summary}"
  log "==================================================${NC}"

  if [ "${fail_count}" -eq 0 ]; then
    log "${GREEN}✅ All revenue systems deployed successfully!${NC}"
    log "${GREEN}💰 Auto-money mode: ACTIVATED${NC}"
    send_notification "success" \
      "✅ Master deploy SUCCESS to ${DEPLOY_TARGET} — ${success_count}/${#REVENUE_SYSTEMS[@]} systems online\n${summary}" \
      "good"
    exit 0
  else
    log "${RED}⚠️  Deploy completed with ${fail_count} failure(s). Rollback applied where supported.${NC}"
    send_notification "failure" \
      "❌ Master deploy PARTIAL FAILURE to ${DEPLOY_TARGET} — ${fail_count} failure(s)\n${summary}" \
      "danger"
    exit 1
  fi
}

main "$@"
