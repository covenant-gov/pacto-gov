# Gas, proxies, and Hats integration

This note explains **why Nave Pirata deploys the way it does**: cheap per-squad contracts, **minimal proxies (EIP-1167)** for most roles, and **Hats-based “pointers”** for upgrades instead of the upgrade patterns Hats modules usually emphasize. It is a readable summary; storage packing and hot-path costs are reflected in the contracts and unit tests.

---

## Two ideas: address as logic vs hat as authority

**Safe-style governance** often treats a **contract address** as the long-lived anchor: the org points at one proxy, and **upgrading** means changing the implementation pointer behind that address (or migrating state). Gas is spent once on a heavier proxy; recurring calls hit one stable address.

**Hats Protocol** is different: the durable object is often a **hat id**. The **wearer** of that hat is who may act *right now*. EOAs and contracts are both valid wearers. That model does not require each “role contract” to be a UUPS proxy—because **authority can move by `transferHat`**, not only by `upgradeTo`.

Nave Pirata combines both worlds:

- **Squad Safe** — still a proxy-backed deployment (standard Safe stack).
- **Role contracts** (Quartermaster, MutinyModule, TreasuryAuthority, **SquadAdmin**) — **EIP-1167 minimal clones** of chain-wide master copies. **Changing role logic** uses the **Role-Hat Upgrader** path (new clone + `transferHat`) where applicable; SquadAdmin evolves via **fresh clones** when the master changes, relying on executor **roles** for in-contract policy without UUPS.

So: **proxies where the stack requires it (e.g. Safe)**; **clones + hat transfer / new clone** where each role wants a cheap instance and an auditable upgrade boundary.

---

## Why this is gas-efficient at deploy time

Per-squad bootstrap is dominated by **one-off** work, not by micro-optimizations inside pure validation:

- **Hats** — `mintTopHat`, `createHat`, eligibility wiring.
- **Safe** — proxy creation and module/owner wiring.
- **Four initializers** — Quartermaster, MutinyModule, TreasuryAuthority, SquadAdmin.
- **Registry write** and events.

Using **EIP-1167 clones** for the three core role contracts keeps **per-squad deployment bytecode tiny**: you pay for a minimal proxy plus `initialize`, not full duplicate implementation bytecode every time. **Governance hot paths** (Treasury votes, mutiny rounds, crew timelocks) are a **different** cost center; they are dominated by **Hats reads** (`supply`, `isWearerOfHat`, `transferHat`) and Safe execution, not by a few extra storage words in role contracts.

---

## Hats does not “usually” mean proxy-per-module

Many Hats **eligibility / toggle modules** are small, purpose-built contracts. They are not standardized around “every wearer is a UUPS proxy.” Nave Pirata leans into that:

- **Authority lives in the tree** — admin, eligibility, and immutability rules are set at hat creation.
- **Role contracts wear `maxSupply = 1` role hats** — “is this the live implementation?” collapses to “does `msg.sender` wear the role hat?”
- **Peer discovery** uses **Authority Lookup** — call into Hats to see who currently wears a role hat, rather than storing mutable peer addresses that would need updating on every upgrade.

That is **more Hats-native** than grafting OpenZeppelin UUPS onto every role: upgrades are **visible on-chain** as a hat movement plus an optional registry append, not a silent implementation slot change.
---

## Data layout: intentional, not accidental duplication

The gas review calls out several patterns worth preserving:

| Pattern | Why it exists |
|--------|----------------|
| **`Proposal` packing** in TreasuryAuthority | Keeps per-proposal storage disciplined (`proposer`, `deadline`, `op`, flags packed; counts sized for on-chain voting). |
| **`openProposalOf` + full `Proposal` store** | Enforces “at most one live proposal per proposer” without scanning; execution still needs full payload. |
| **`_maxDeadline` for `isQuiet()`** | Small denormalization so quiet-window checks stay **O(1)** instead of iterating proposals. |
| **Quartermaster pending maps + counters** | Same idea: **`isQuiet()`** without unbounded loops. |
| **Same hat ids on each clone** | Each module keeps squad hat ids locally to avoid an extra registry hop and to keep **`onlyHatWearer`** paths independently verifiable from a single contract address. |

**Snapshots** (crew size at proposal or mutiny start) are **not** redundant with live Hats supply: membership changes; governance is defined at **t0**.

---

## What not to sacrifice for gas

The following constraints are part of the security model:

- Do not drop **snapshots** or per-voter vote tracking to “recompute from Hats.”
- Do not strip **registry / deployment** fields without an indexer strategy—you move cost and trust off-chain.
- Do not merge unrelated values into opaque `uint256` packing without migration discipline.

---

## Where to read next

- **Plain-language modules** — [`../README.md`](../README.md) (guidebook index).
- **Hat tree and pointer upgrade story** — [`hats-tree-and-pointer-architecture.md`](./hats-tree-and-pointer-architecture.md).
