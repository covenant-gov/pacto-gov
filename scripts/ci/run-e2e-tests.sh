#!/usr/bin/env bash
# CI: job must set `environment:` for env-scoped Variables/Secrets and pass:
#   _GHA_MAINNET_RPC_SECRET / _GHA_MAINNET_RPC_VAR (and optional Sepolia analogs).
# Locally: source .env when present.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  if [[ -z "${MAINNET_RPC:-}" ]]; then
    if [[ -n "${_GHA_MAINNET_RPC_SECRET:-}" ]]; then
      export MAINNET_RPC="$_GHA_MAINNET_RPC_SECRET"
    elif [[ -n "${_GHA_MAINNET_RPC_VAR:-}" ]]; then
      export MAINNET_RPC="$_GHA_MAINNET_RPC_VAR"
    fi
  fi
  if [[ -z "${SEPOLIA_RPC:-}" ]]; then
    if [[ -n "${_GHA_SEPOLIA_RPC_SECRET:-}" ]]; then
      export SEPOLIA_RPC="$_GHA_SEPOLIA_RPC_SECRET"
    elif [[ -n "${_GHA_SEPOLIA_RPC_VAR:-}" ]]; then
      export SEPOLIA_RPC="$_GHA_SEPOLIA_RPC_VAR"
    fi
  fi
  if [[ -z "${MAINNET_RPC:-}" ]]; then
    echo "::error::MAINNET_RPC is unset. Add it as an Environment Variable or Secret for the job's \`environment:\` slug, or repository-level secret/variable. This script reads _GHA_MAINNET_RPC_SECRET then _GHA_MAINNET_RPC_VAR (set them in the workflow from \`secrets\` / \`vars\`)."
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
