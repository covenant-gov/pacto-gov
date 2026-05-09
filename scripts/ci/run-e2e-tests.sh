#!/usr/bin/env bash
# E2E entrypoint: CI injects MAINNET_RPC / SEPOLIA_RPC via GitHub Actions (secrets and/or repository variables).
# Locally, source .env when present so `forge test` matches `foundry.toml` `${MAINNET_RPC}` expansion.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  if [[ -z "${MAINNET_RPC:-}" ]]; then
    echo "::error::MAINNET_RPC is unset. In GitHub: add repository or environment secret MAINNET_RPC, or a repository Variable MAINNET_RPC (public RPC only). Environment-scoped values require \`environment:\` on the job. Workflow should pass \`secrets.MAINNET_RPC || vars.MAINNET_RPC\`."
    exit 1
  fi
else
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
fi

exec forge test --match-contract E2E -vvv "$@"
