# CI and supply-chain hardening

Protective controls for dependency installs and GitHub Actions in this
repository. This document does **not** claim the repository is free of
compromise or fully safe — it records what was hardened in-tree and what still
depends on owner-side settings.

## Goals (in-tree)

| Control | Where |
|--------|--------|
| Disposable hosted CI workers | Jobs use GitHub-hosted `ubuntu-latest`. |
| Minimal default `GITHUB_TOKEN` permissions | Workflow `permissions:` default to `contents: read`; coverage comment job adds `pull-requests: write` only. |
| No checkout credential persistence | Every `actions/checkout` uses `persist-credentials: false` (no trusted push steps in these workflows). |
| Third-party Actions pinned to full commit SHAs | All `uses:` refs are 40-char SHAs with version comments; `scripts/check-actions-pinned.mjs` + CI `workflow-policy` job enforce it. |
| Frozen install without lifecycle scripts | Composite `.github/actions/install-tools` runs `pnpm install --frozen-lockfile --ignore-scripts` (skips husky `prepare`). |
| Explicit dependency build-script policy | `pnpm-workspace.yaml` `allowBuilds` + `strictDepBuilds` + `minimumReleaseAge: 1440` for local/add paths. |
| RPC secrets off install | `MAINNET_RPC` / `SEPOLIA_RPC` are step-scoped on the E2E test step only, after install. |
| PR vs release trust separation | Canary / production release jobs stay `if: false`; `NPM_TOKEN` remains publish-step-only and is never injected into CI test jobs. |

## Foundry / tool install trust

`foundry-rs/foundry-toolchain` is SHA-pinned and installs Foundry `v1.4.1` via
the Action's own installer (`foundryup`). This repository does **not** vendor
Foundry binary checksums; treat the pinned Action + pinned Foundry version as
the trust boundary. Do not replace that with an unverified remote install
script in workflows.

## Workflow review ownership

CODEOWNERS for `.github/workflows/` lists people with verified write-or-higher
access on this repository:

| Handle | Access check |
|--------|--------------|
| `@logicminds` | permission API: admin |
| `@daopunk` | permission API: admin |

This document does not grant or change repository access.

## Editor / agent surfaces (review only)

| Path | Role |
|------|------|
| `.husky/pre-commit` / `.husky/commit-msg` | Local git hooks (build + lint-staged; commitlint). Skipped in CI via `--ignore-scripts`. |
| `.cursor/rules/*.mdc` | Agent policy text; not executable CI. |

No MCP / Codex / Beads hook configs are present in this repository.

## Fork / contributor behavior preserved

- Push CI and pull_request coverage/natspec continue with read-only default
  contents permission.
- Coverage PR comments still require same-repo PRs (fork PRs skip the comment
  step as before).
- Disabled canary / production NPM publish jobs stay disabled (no cost or
  publishing widening).

## Owner-side prerequisites (YAML alone does not enforce)

Not verified from this environment. An admin should confirm as appropriate:

1. **Branch protection / rulesets on `dev`** — require PR, require status checks
   (including `Workflow policy` if desired), and CODEOWNERS review for
   `.github/workflows/**` when that policy is wanted.
2. **`e2e` environment** — keep `MAINNET_RPC` (and optional `SEPOLIA_RPC`) on
   the environment or repository secrets/vars used by the E2E job; do not add
   publish tokens there.
3. **Secret hygiene** — `NPM_TOKEN` only if/when publish jobs are intentionally
   enabled; never add it to unit/lint/coverage workflows.
4. **Actions fork defaults** — keep fork PR workflows on read-only tokens.

## What this hardening is not

- Not evidence of an active infection or compromise in this repository.
- Not a substitute for dependency review or Foundry/Solidity audit.
- Not enabling releases, deploys, or previously disabled publish jobs.
- Not an unrelated dependency or compiler upgrade.
