# Pacto Gov — Nave Pirata

Governance contracts for Pacto squads. Each squad deploys a "Nave Pirata" (pirate ship) — a hat-governed mesh of role contracts sitting on top of a Safe — via a one-shot factory call.

## Why this repo exists

Healthy organizations eventually have to answer the same questions: **who decides**, **who can spend**, **who can join or leave**, and **how leadership can change** without a crisis. That is as true for [open-source projects that outgrow informal maintainership](https://opensource.guide/leadership-and-governance/#understanding-governance-for-your-growing-project) as it is for campaigns, cooperatives, and unions. Informal norms work until they don’t; ambiguity favors the loudest voice in the room.

**Pacto Gov** is our attempt to make those answers **legible and enforceable** where it matters most: **shared treasuries** and **role-based authority**. We use familiar language — think **maintainer** and **contributor** — but on-chain: a **captain** (which can be a person, a multisig, or another contract) and **crew** with real procedural weight. Crew and captain both participate in treasury actions; the crew can replace the captain through a **mutiny** process; roster changes get **timelocks** so membership shifts aren’t snuck through overnight. The chain doesn’t replace culture or trust, but it can **bound** betrayal: the Safe won’t move unless the rules you published have been satisfied.

We are building this **first for ourselves** as open-source contributors who want governance we can point to, not only argue about. The same pattern — transparent membership, staged spending, accountable leadership — is also relevant to **activists** and **labor unions** (and similar orgs) that hold funds collectively and need procedures that members can **audit** and **replicate**. This stack is not a fit for every repository or every fight; it is aimed at groups that already want **cryptographic enforcement** for a defined slice of decisions.

For a non-technical overview of the main modules, see the **[docs guidebook](./docs/README.md)**.

## Nave Pirata contracts

The system is built around **Hats-Pointer Upgradeability**: authority is a Hats Protocol hat, and upgrading a role contract is a `transferHat` call rather than a proxy migration. Implementation detail lives under `src/contracts/` and `src/interfaces/` (each with `core/`, `squad/`, `factory/`, and `abstracts/` where applicable) and in tests; governance behavior is summarized in the **Docs** list below.

**Docs** (governance contracts — plain language):
- **[Guidebook](./docs/README.md)** — how Mutiny, Quartermaster, and Treasury Authority fit together.
- **[Quartermaster](./docs/Quartermaster.md)** — crew roster and timelocks.
- **[Mutiny module](./docs/MutinyModule.md)** — replacing or resigning the captain.
- **[Treasury Authority](./docs/TreasuryAuthority.md)** — Safe actions: crew vote, captain approval, execution.

**Contracts (v1)**:
- `Quartermaster` — timelocked crew roster, admin of the crew hat.
- `MutinyModule` — 51%-of-snapshot captain accountability, admin of the captain hat; also supports voluntary captain resignation.
- `TreasuryAuthority` — two-body democracy (crew majority + captain approval) over the squad's Safe. Both the Safe's sole owner *and* its sole Zodiac module. Inherits `AssetRescuer`.
- `SquadAdmin` — EIP-1167 clone of application-level executor predicates; evolves via roles and new clones, not upgrades.
- `NavePirataFactory` — one-shot bootstrap that atomically deploys the Safe, creates the hat tree, deploys clones, wires the Safe, and registers the deployment.
- `NavePirataRegistry`, `RoleHatClonesFactory`, `RoleHatUpgrader` — infra for discovery and upgrade ceremonies.
- `AssetRescuer` (abstract) — shared primitive; permissionless sweep of accidentally-received ETH / ERC-20 / ERC-721 / ERC-1155 to a fixed destination.
