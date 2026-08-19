# Pacto Gov — Nave Pirata

Governance contracts for Pacto squads. Each squad deploys a "Nave Pirata" (pirate ship) — a hat-governed mesh of role contracts sitting on top of a Safe — via a one-shot factory call.

## Why this repo exists

Healthy organizations eventually have to answer the same questions: **who decides**, **who can spend**, **who can join or leave**, and **how leadership can change** without a crisis. That is as true for [open-source projects that outgrow informal maintainership](https://opensource.guide/leadership-and-governance/#understanding-governance-for-your-growing-project) as it is for campaigns, cooperatives, and unions. Informal norms work until they don’t; ambiguity favors the loudest voice in the room.

**Pacto Gov** is our attempt to make those answers **legible and enforceable** where it matters most: **shared treasuries** and **role-based authority**. We use familiar language — think **maintainer** and **contributor** — but on-chain: a **captain** (which can be a person, a multisig, or another contract) and **crew** with real procedural weight. The crew can replace the captain through a **mutiny** process; roster changes get **timelocks** so membership shifts aren’t snuck through overnight. The chain doesn’t replace culture or trust, but it can **bound** betrayal: the Safe won’t move unless the rules you published have been satisfied.

### Two-body treasury democracy

Spending and other **Treasury Authority** actions use a deliberate **two-body** rule: **crew** must meet the configured vote threshold, and the **captain** must approve (or may veto early). Neither body alone can authorize execution through the module, so the vault is not a single-key toy. Details and the exceptional case where the **captain hat sits on the Safe** (crew-only execution path) are in **[Treasury Authority](./docs/TreasuryAuthority.md)**.

### Why app admin and roles belong on-chain

**Nostr** and relays are excellent for **coordination**: announcements, debate, and human-readable history that does not need to pay gas. Relays are not, however, a substitute for **anti-fragile, canonical authority**: operators change, policies differ, and a squad may **migrate relays** or lose access to spaces where records lived only off-chain. If “who may run this integration” or “what role did we grant” lived **only** in relay-scoped logs, a relay break-up could feel like an organizational **amnesia** event.

Putting **permissions, roles, and governance outcomes** on-chain (treasury votes, hat transfers, **SquadAdmin** executor rows) stores the **durable structure of the org** in a replicated ledger: the same rules and wearers remain queryable after social layers move. The **immutability** that matters here is not mysticism—it is **tamper-evident, replayable commitments** anyone can verify without trusting a single relay operator. The unlikely-but-real case of **changing Nostr relays** and **losing relay-persisted artifacts** then does not erase **who the squad agreed could act**—that story stays anchored in contracts the squad chose to deploy.

We are building this **first for ourselves** as open-source contributors who want governance we can point to, not only argue about. The same pattern — transparent membership, staged spending, accountable leadership — is also relevant to **activists** and **labor unions** (and similar orgs) that hold funds collectively and need procedures that members can **audit** and **replicate**. This stack is not a fit for every repository or every fight; it is aimed at groups that already want **cryptographic enforcement** for a defined slice of decisions.

For a non-technical overview of the main modules, see the **[docs guidebook](./docs/README.md)**.

## Nave Pirata contracts

The system is built around **Hats-Pointer Upgradeability**: authority is a Hats Protocol hat, and upgrading a role contract is a `transferHat` call rather than a proxy migration. Implementation detail lives under `src/contracts/` and `src/interfaces/` (each with `core/`, `squad/`, `factory/`, and `abstracts/` where applicable) and in tests; governance behavior is summarized in the **Docs** list below.

**Docs** (governance contracts — plain language):
- **[Guidebook](./docs/README.md)** — how Mutiny, Quartermaster, Treasury Authority, and Squad Admin fit together.
- **[Quartermaster](./docs/Quartermaster.md)** — crew roster and timelocks.
- **[Mutiny module](./docs/MutinyModule.md)** — replacing or resigning the captain (including pause-captain → Safe).
- **[Treasury Authority](./docs/TreasuryAuthority.md)** — Safe actions: two-body democracy, execution, captain veto.
- **[Squad Admin](./docs/SquadAdmin.md)** — captain-gated on-chain executor roles for integrations.
- **[Governance parameter bounds](./docs/technical/governance-param-bounds.md)** — `RangeValidator` delay/quorum limits and `SquadParams` for client UIs.

**Contracts (v1)**:
- `Quartermaster` — timelocked crew roster, admin of the crew hat.
- `MutinyModule` — 51%-of-snapshot captain accountability, admin of the captain hat; also supports voluntary captain resignation.
- `TreasuryAuthority` — **two-body democracy** (crew vote + captain approval for execution through the module; see docs for the Safe-wears-captain-hat case) over the squad's Safe. Both the Safe's sole owner *and* its sole Zodiac module. Inherits `AssetRescuer`.
- `SquadAdmin` — EIP-1167 clone of application-level executor predicates; evolves via roles and new clones, not upgrades.
- `NavePirataFactory` — one-shot bootstrap that atomically deploys the Safe, creates the hat tree, deploys clones, wires the Safe, and registers the deployment (`stackKind`: Production → `NavePirataRegistry`, WarGame → `WarGameRegistry`).
- `NavePirataRegistry`, `WarGameRegistry`, `RoleHatClonesFactory`, `RoleHatUpgrader` — infra for discovery (real-gov vs throwaway war-game stacks) and upgrade ceremonies.
- `AssetRescuer` (abstract) — shared primitive; permissionless sweep of accidentally-received ETH / ERC-20 / ERC-721 / ERC-1155 to a fixed destination.
