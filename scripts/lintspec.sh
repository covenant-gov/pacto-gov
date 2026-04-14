#!/usr/bin/env bash
# Resolve lintspec from Cargo's bin dir (Husky / GUI apps often have a minimal PATH).
set -euo pipefail
export PATH="${HOME}/.cargo/bin:${PATH}"
if ! command -v lintspec >/dev/null 2>&1; then
  echo "warning: lintspec not found. Install: cargo install lintspec" >&2
  exit 0
fi
if [ "$#" -eq 0 ]; then
  exec lintspec src script test
else
  exec lintspec "$@"
fi
