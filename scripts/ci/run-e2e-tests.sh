#!/usr/bin/env bash
# CI: workflow exposes MAINNET_RPC (and optional SEPOLIA_RPC); use GitHub Environment `e2e` for env-scoped vars/secrets.
# Locally: source .env when present.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  if [[ -z "${MAINNET_RPC:-}" ]]; then
    echo "::error::MAINNET_RPC is unset. Add it under the GitHub Environment that matches \`environment:\` in \`.github/workflows/tests.yml\` (or as a repository secret/variable)."
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
