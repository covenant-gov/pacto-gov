#!/usr/bin/env bash
# Runs forked E2E tests with RPC retries; re-runs only when the provider rate-limits (HTTP 429).
set -euo pipefail

MAX_ATTEMPTS="${FOUNDRY_INTEGRATION_ATTEMPTS:-3}"
BACKOFF_SEC="${FOUNDRY_INTEGRATION_RETRY_SLEEP:-45}"

FORGE_ARGS=(
  test
  --match-contract
  E2E
  --fork-url
  mainnet
  --fork-retries
  10
  --fork-retry-backoff
  2000
  -j
  1
  -vvv
)

is_rpc_rate_limit_failure() {
  local _log=$1
  grep -E -q '429|Too Many Requests|Max retries exceeded|failed to get (account|storage) for' <<<"$_log"
}

attempt=1
while true; do
  set +e
  _output="$(forge "${FORGE_ARGS[@]}" 2>&1)"
  _exit=$?
  set -e

  printf '%s\n' "$_output"

  if [[ $_exit -eq 0 ]]; then
    exit 0
  fi

  if ! is_rpc_rate_limit_failure "$_output"; then
    exit "$_exit"
  fi

  if [[ $attempt -ge $MAX_ATTEMPTS ]]; then
    echo "Integration tests hit RPC rate limits through ${MAX_ATTEMPTS} attempts; failing."
    exit "$_exit"
  fi

  echo "RPC rate limit detected (attempt ${attempt}/${MAX_ATTEMPTS}); retrying in ${BACKOFF_SEC}s..."
  sleep "$BACKOFF_SEC"
  attempt=$((attempt + 1))
  BACKOFF_SEC=$((BACKOFF_SEC * 2))
done
