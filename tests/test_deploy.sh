#!/bin/bash
# Comprehensive bash test suite for the Master Deployment Auto-Deploy Revenue System
#
# Usage: ./tests/test_deploy.sh
# Exit code 0 = all tests passed, non-zero = at least one failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT_ORIG="${REPO_ROOT}"   # preserved so we can restore after _source_main_script
MAIN_SCRIPT="${REPO_ROOT}/scripts/autodeploy-revenue-systems.sh"
DEPLOY_ENTRY="${REPO_ROOT}/deploy.sh"

# ─────────────────────────────── Test harness ─────────────────────────────── #

PASS=0
FAIL=0
TESTS_RUN=0

pass() {
  local name="$1"
  PASS=$((PASS + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  ✅ PASS: ${name}"
}

fail() {
  local name="$1"
  local detail="${2:-}"
  FAIL=$((FAIL + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  ❌ FAIL: ${name}"
  [ -n "${detail}" ] && echo "         ${detail}"
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "${expected}" = "${actual}" ]; then
    pass "${name}"
  else
    fail "${name}" "expected='${expected}' actual='${actual}'"
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if echo "${haystack}" | grep -qF "${needle}"; then
    pass "${name}"
  else
    fail "${name}" "expected to find '${needle}' in output"
  fi
}

assert_file_exists() {
  local name="$1" file="$2"
  if [ -f "${file}" ]; then
    pass "${name}"
  else
    fail "${name}" "file not found: ${file}"
  fi
}

assert_executable() {
  local name="$1" file="$2"
  if [ -x "${file}" ]; then
    pass "${name}"
  else
    fail "${name}" "not executable: ${file}"
  fi
}

assert_exit_code() {
  local name="$1" expected="$2"
  shift 2
  local actual
  "$@" > /dev/null 2>&1
  actual=$?
  if [ "${actual}" -eq "${expected}" ]; then
    pass "${name}"
  else
    fail "${name}" "expected exit ${expected}, got ${actual} from: $*"
  fi
}

section() {
  echo ""
  echo "▶ $*"
}

summary() {
  echo ""
  echo "════════════════════════════════════════"
  echo "Test results: ${TESTS_RUN} run, ${PASS} passed, ${FAIL} failed"
  echo "════════════════════════════════════════"
  [ "${FAIL}" -eq 0 ]
}

# ─────────────────────────── Helper – source safely ───────────────────────── #

# Source the main script in a controlled way so we can unit-test its functions
# without executing main().  We stub out external CLI tools so no real network
# calls happen.
_source_main_script() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  # Stub external tools that the script might call
  for cmd in railway vercel helm kubectl curl git; do
    printf '#!/bin/bash\nexit 0\n' > "${tmpdir}/${cmd}"
    chmod +x "${tmpdir}/${cmd}"
  done

  # Prepend stubs to PATH and source the script with main() replaced by a no-op
  local patched
  patched="$(mktemp)"
  # Replace the final `main "$@"` call so sourcing doesn't execute the full flow
  sed 's/^main "\$@"$/: # main() call suppressed for testing/' \
    "${MAIN_SCRIPT}" > "${patched}"

  PATH="${tmpdir}:${PATH}" source "${patched}" 2>/dev/null
  rm -rf "${tmpdir}" "${patched}"

  # The main script derives REPO_ROOT from its temp file path which is wrong in
  # a sourced context.  Restore the correct values from the test's perspective.
  SCRIPT_DIR="${REPO_ROOT_ORIG}/scripts"
  REPO_ROOT="${REPO_ROOT_ORIG}"
}

# ═══════════════════════════════ Test sections ════════════════════════════════ #

section "1. File existence and permissions"

assert_file_exists "main script exists"  "${MAIN_SCRIPT}"
assert_file_exists "deploy.sh exists"    "${DEPLOY_ENTRY}"
assert_file_exists "workflow file exists" "${REPO_ROOT}/.github/workflows/deploy.yml"

chmod +x "${MAIN_SCRIPT}" "${DEPLOY_ENTRY}"
assert_executable "main script is executable" "${MAIN_SCRIPT}"
assert_executable "deploy.sh is executable"   "${DEPLOY_ENTRY}"

section "2. Bash syntax validation"

if bash -n "${MAIN_SCRIPT}" 2>/dev/null; then
  pass "autodeploy-revenue-systems.sh has valid bash syntax"
else
  fail "autodeploy-revenue-systems.sh has valid bash syntax" \
    "$(bash -n "${MAIN_SCRIPT}" 2>&1)"
fi

if bash -n "${DEPLOY_ENTRY}" 2>/dev/null; then
  pass "deploy.sh has valid bash syntax"
else
  fail "deploy.sh has valid bash syntax" \
    "$(bash -n "${DEPLOY_ENTRY}" 2>&1)"
fi

section "3. deploy.sh delegates to main script"

DEPLOY_CONTENT="$(cat "${DEPLOY_ENTRY}")"
assert_contains "deploy.sh references autodeploy-revenue-systems.sh" \
  "autodeploy-revenue-systems.sh" \
  "${DEPLOY_CONTENT}"

section "4. Revenue systems list"

_source_main_script
SYSTEMS_COUNT="${#REVENUE_SYSTEMS[@]}"

if [ "${SYSTEMS_COUNT}" -ge 1 ]; then
  pass "REVENUE_SYSTEMS is non-empty (${SYSTEMS_COUNT} entries)"
else
  fail "REVENUE_SYSTEMS is non-empty"
fi

for expected_repo in \
    "nwu-protocol" \
    "enterprise-unified-platform" \
    "tree-of-life-system" \
    "autonomous-orchestrator-core" \
    "ai-business-platform" \
    "systems-master-hub"; do
  repo_found=false
  for r in "${REVENUE_SYSTEMS[@]}"; do
    [ "${r}" = "${expected_repo}" ] && repo_found=true && break
  done
  if ${repo_found}; then
    pass "REVENUE_SYSTEMS contains '${expected_repo}'"
  else
    fail "REVENUE_SYSTEMS contains '${expected_repo}'"
  fi
done

section "5. write_status / read_status round-trip"

STATUS_DIR="$(mktemp -d)"
trap 'rm -rf "${STATUS_DIR}"' EXIT

write_status "nwu-protocol" "success"
assert_eq "read_status returns written value" \
  "success" "$(read_status "nwu-protocol")"

write_status "nwu-protocol" "failed"
assert_eq "read_status reflects update" \
  "failed" "$(read_status "nwu-protocol")"

assert_eq "read_status returns 'unknown' for missing repo" \
  "unknown" "$(read_status "no-such-repo")"

section "6. write_rollback_id / read_rollback_id round-trip"

write_rollback_id "enterprise-unified-platform" "deploy-abc123"
assert_eq "read_rollback_id returns written value" \
  "deploy-abc123" "$(read_rollback_id "enterprise-unified-platform")"

assert_eq "read_rollback_id returns empty string for unknown repo" \
  "" "$(read_rollback_id "no-such-repo")"

section "7. log() writes to stdout (and log file when LOG_DIR set)"

TMP_LOG_DIR="$(mktemp -d)"
DEPLOY_LOG="${TMP_LOG_DIR}/test.log"
LOG_DIR="${TMP_LOG_DIR}"

OUTPUT="$(log "hello test")"
assert_eq "log() produces stdout output" "hello test" "${OUTPUT}"

log "file line" > /dev/null
if [ -f "${DEPLOY_LOG}" ] && grep -q "file line" "${DEPLOY_LOG}"; then
  pass "log() appends to DEPLOY_LOG file"
else
  fail "log() appends to DEPLOY_LOG file"
fi

rm -rf "${TMP_LOG_DIR}"
unset DEPLOY_LOG LOG_DIR

section "8. send_notification – no-ops when webhook URLs are unset"

# Should complete without error when no webhook URLs are configured
unset SLACK_WEBHOOK_URL  2>/dev/null || true
unset DISCORD_WEBHOOK_URL 2>/dev/null || true

if send_notification "test" "hello" "good" 2>/dev/null; then
  pass "send_notification succeeds silently when no webhook URLs set"
else
  fail "send_notification succeeds silently when no webhook URLs set"
fi

section "9. health_check – skips gracefully when URL env var is absent"

unset HEALTH_CHECK_NWU_PROTOCOL 2>/dev/null || true

OUTPUT="$(health_check "nwu-protocol" 1 0 2>&1)"
EXIT=$?
assert_eq "health_check exits 0 when no URL configured" "0" "${EXIT}"
assert_contains "health_check reports skipping" "skipping" "${OUTPUT}"

section "10. health_check – passes on HTTP 200"

# Stub curl to return 200
_curl_stub_200() { echo "200"; }
curl() {
  # Only intercept the status-code check form
  if [[ "$*" == *'-w %{http_code}'* ]] || [[ "$*" == *"-w"*"%{http_code}"* ]]; then
    echo "200"
    return 0
  fi
  command curl "$@"
}
export -f curl

HEALTH_CHECK_NWU_PROTOCOL="http://localhost:9999/health"
OUTPUT="$(health_check "nwu-protocol" 3 0 2>&1)"
EXIT=$?
assert_eq "health_check exits 0 on HTTP 200" "0" "${EXIT}"
assert_contains "health_check reports passed on 200" "passed" "${OUTPUT}"
unset HEALTH_CHECK_NWU_PROTOCOL

section "11. health_check – fails after max retries on HTTP 503"

curl() {
  if [[ "$*" == *'-w %{http_code}'* ]] || [[ "$*" == *"-w"*"%{http_code}"* ]]; then
    echo "503"
    return 0
  fi
  command curl "$@"
}
export -f curl

HEALTH_CHECK_NWU_PROTOCOL="http://localhost:9999/health"
OUTPUT="$(health_check "nwu-protocol" 2 0 2>&1)"
EXIT=$?
assert_eq "health_check exits 1 after max retries on 503" "1" "${EXIT}"
assert_contains "health_check reports FAILED" "FAILED" "${OUTPUT}"
unset HEALTH_CHECK_NWU_PROTOCOL
unset -f curl

section "12. sync_env_railway – skips when no env file found"

OUTPUT="$(sync_env_railway "no-such-repo" 2>&1)"
EXIT=$?
assert_eq "sync_env_railway exits 0 with no env file" "0" "${EXIT}"
assert_contains "sync_env_railway reports skipping" "skipping" "${OUTPUT}"

section "13. sync_env_railway – reads and sets variables from .env file"

TMP_ENV_DIR="$(mktemp -d)"
TMP_RAILWAY_LOG="$(mktemp)"
# Temporarily redirect REPO_ROOT so the function finds our fake .env file
OLD_REPO_ROOT="${REPO_ROOT}"
REPO_ROOT="${TMP_ENV_DIR}"
mkdir -p "${TMP_ENV_DIR}/../no-such-repo"  # fake repo dir

# Create shared env file
cat > "${TMP_ENV_DIR}/.env.shared" <<'EOF'
# A comment
FOO=bar
BAZ=qux

EOF

# Write a railway stub that logs calls to a temp file (survives subshell boundary)
railway() {
  echo "$*" >> "${TMP_RAILWAY_LOG}"
}
export -f railway
export TMP_RAILWAY_LOG

STATUS_DIR="$(mktemp -d)"
sync_env_railway "no-such-repo" > /dev/null 2>&1

CALL_COUNT=$(wc -l < "${TMP_RAILWAY_LOG}" | tr -d ' ')

if [ "${CALL_COUNT}" -ge 2 ]; then
  pass "sync_env_railway called railway for each non-comment variable (${CALL_COUNT} calls)"
else
  fail "sync_env_railway called railway for each variable" \
    "got ${CALL_COUNT} calls, expected ≥2"
fi

REPO_ROOT="${OLD_REPO_ROOT}"
rm -rf "${TMP_ENV_DIR}" "${TMP_RAILWAY_LOG}"
unset -f railway
unset TMP_RAILWAY_LOG

section "14. verify_stripe – skips when STRIPE_SECRET_KEY unset"

unset STRIPE_SECRET_KEY 2>/dev/null || true
OUTPUT="$(verify_stripe "nwu-protocol" 2>&1)"
EXIT=$?
assert_eq "verify_stripe exits 0 when key unset" "0" "${EXIT}"
assert_contains "verify_stripe warns about missing key" "STRIPE_SECRET_KEY" "${OUTPUT}"

section "15. Workflow YAML – schedule trigger present"

WORKFLOW_CONTENT="$(cat "${REPO_ROOT}/.github/workflows/deploy.yml")"
assert_contains "workflow has cron schedule" "cron:" "${WORKFLOW_CONTENT}"
assert_contains "workflow triggers on push to main" "branches: [ main ]" "${WORKFLOW_CONTENT}"
assert_contains "workflow has workflow_dispatch" "workflow_dispatch:" "${WORKFLOW_CONTENT}"

section "16. Workflow YAML – only one deploy step (no unconditional multi-platform steps)"

RAILWAY_STEPS=$(echo "${WORKFLOW_CONTENT}" \
  | grep -c 'autodeploy-revenue-systems.sh railway' || true)
VERCEL_STEPS=$(echo "${WORKFLOW_CONTENT}" \
  | grep -c 'autodeploy-revenue-systems.sh vercel' || true)
K8S_STEPS=$(echo "${WORKFLOW_CONTENT}" \
  | grep -c 'autodeploy-revenue-systems.sh kubernetes' || true)

# The old bug: separate always-running steps for each platform.
# Fixed: single ./deploy.sh call.
DEPLOY_CALLS=$(echo "${WORKFLOW_CONTENT}" \
  | grep -c '\./deploy.sh' || true)

if [ "${DEPLOY_CALLS}" -ge 1 ]; then
  pass "workflow uses single deploy.sh invocation"
else
  fail "workflow uses single deploy.sh invocation" \
    "expected ≥1 ./deploy.sh call, found ${DEPLOY_CALLS}"
fi

if [ "${RAILWAY_STEPS}" -eq 0 ] && [ "${VERCEL_STEPS}" -eq 0 ] && [ "${K8S_STEPS}" -eq 0 ]; then
  pass "workflow has no separate unconditional platform-specific deploy steps"
else
  fail "workflow has no separate unconditional platform-specific deploy steps" \
    "railway=${RAILWAY_STEPS} vercel=${VERCEL_STEPS} k8s=${K8S_STEPS}"
fi

section "17. Workflow YAML – render platform option added"

assert_contains "workflow offers 'render' as deploy target option" "render" \
  "${WORKFLOW_CONTENT}"

section "18. Workflow YAML – artifact upload present"

assert_contains "workflow uploads deploy log artifact" \
  "upload-artifact" "${WORKFLOW_CONTENT}"

section "19. Workflow YAML – test job runs before deploy"

assert_contains "workflow has a test job" "test_deploy.sh" "${WORKFLOW_CONTENT}"

section "20. deploy_parallel – spawns background processes and collects results"

# Lightweight integration: run deploy_parallel with a stubbed deploy function
# and confirm all systems get a status entry.

STATUS_DIR="$(mktemp -d)"
DEPLOY_TARGET="railway"

# Override the actual deploy function with a fast no-op that writes success
deploy_railway() {
  write_status "$1" "success"
}
export -f deploy_railway

# Only test with a small subset to keep tests fast
REVENUE_SYSTEMS=("alpha-service" "beta-service")

deploy_parallel > /dev/null 2>&1 || true

for svc in "alpha-service" "beta-service"; do
  ST="$(read_status "${svc}")"
  assert_eq "deploy_parallel sets status for '${svc}'" "success" "${ST}"
done

# Restore
_source_main_script

# ─────────────────────────────── Final summary ────────────────────────────── #

summary