# Hats tree and pointer architecture (Nave Pirata)

This document is a **technical summary** of how Pacto’s on-chain squad is shaped in **Hats Protocol**: the **hat tree**, **who admins whom**, and **Hats-Pointer upgradeability** (upgrades via `transferHat` to a new contract, not only via proxy `upgradeTo`). For step-by-step product behavior of Treasury, Mutiny, and Quartermaster, see the [guidebook](../README.md).

---

## Product shape (on-chain)

A **squad** has two social bodies and one app-scoped role:

| Role | On-chain meaning (v1) |
|------|------------------------|
| **Captain** | Wearer of the captain hat (`maxSupply = 1`). Executive; half of Treasury two-body approval; can propose Quartermaster crew changes. |
| **Crew** | Wearers of the crew hat. Mutiny electorate; other half of Treasury approval. |
| **Squad Admin** | **One** contract wears the squad-admin hat; multiple human “admins” can live inside that contract’s roster. |

**Hats treats EOAs and contracts as first-class wearers.** Authority in this system is **a hat**, not an address baked immutably into a single proxy.

---

## Core idea: Hats-Pointer upgradeability

In a classic **proxy** story, the **address** stays fixed and **implementation** changes. In Nave Pirata’s **role contracts** (Quartermaster, MutinyModule, TreasuryAuthority), the preferred upgrade story is:

1. Deploy a **new** minimal-proxy **clone** (new address).
2. Initialize it and verify **`isQuiet()`** on the outgoing clone (quiet-window invariant).
3. **`transferHat(roleHatId, oldClone, newClone)`**.

The **hat** is the pointer to “the live logic.” The old clone keeps existing bytecode but **loses the hat**, so hat-gated entrypoints **revert**. No proxy migration on the same address is required for those roles.

**SquadAdmin** matches the same **EIP-1167 clone** pattern: cheap per-squad bytecode, fixed logic behind each clone address. Product evolution prefers **executor roles** inside the contract over swapping implementations in place; changing the master + minting a **new** clone (and moving the squad-admin hat) is the heavy-duty path if bytecode must change.

Together with **CREATE2 / EIP-1167** clones per squad, you get **cheap deploys**, **decoupling of authority from contract identity**, and **auditable** upgrades (new address + hat transfer + registry events).

---

## Named patterns (vocabulary)

| Pattern | Meaning |
|---------|---------|
| **Hats-Pointer upgradeability** | Authority is a hat; upgrade ≈ `transferHat` to a new instance. |
| **Bedrock-and-joints** | Tophat, captain, crew foundation is fixed after bootstrap; **role hats** are the evolvable joints. |
| **Authority lookup** | Resolve peer contracts via **who wears** a role hat at call time, not a stored peer address. |
| **Role-Hat Upgrader** | Ceremony contract: deploy new clone, **`isQuiet()`** check, `transferHat`, registry log. |
| **Quiet-window invariant** | No role-hat transfer while the outgoing contract reports pending work (`isQuiet() == false`). |
| **Two-body democracy** | Treasury: crew vote + captain approval; neither alone is enough. |
| **Accountability mesh** | Each power has a defined counterparty (mutiny, timelocks, two-body Treasury). |

---

## Hat tree

```
Tophat (Safe — acts on-chain via TreasuryAuthority)
├── MutinyRole hat              (maxSupply 1 → MutinyModule clone)
│   └── Captain hat             (maxSupply 1 → current captain)
│         └── Squad-admin hat   (maxSupply 1 → SquadAdmin clone)
├── QuartermasterRole hat       (maxSupply 1 → Quartermaster clone)
│   └── Crew hat                (maxSupply 10_000)
└── TreasuryAuthorityRole hat   (maxSupply 1 → TreasuryAuthority clone)
```

**Rationale (structural):**

- **Captain under MutinyRole** — MutinyModule wears MutinyRole and is **admin** of the captain hat, so mutiny execution can `transferHat` on captain.
- **Crew under QuartermasterRole** — Quartermaster wears QuartermasterRole and admins **crew** mints and eligibility revocations; captain does **not** admin crew directly (mitigates purge-style attacks).
- **Squad-admin under Captain** — product policy sits under the captain branch; squad-admin is not crew and does not vote in mutiny/Treasury as crew.
- **TreasuryAuthorityRole under Tophat** — sibling to other role hats; wearer is sole **Zodiac module** and **owner** of the squad Safe (by design).

---

## Hats primitives per hat

Each hat uses **admin**, **eligibility**, and **toggle** deliberately ([Hats: admins & hatters](https://docs.hatsprotocol.xyz/for-developers/hats-protocol-for-developers/hat-admins-and-hatter-contracts#hatter-contracts), [eligibility](https://docs.hatsprotocol.xyz/for-developers/hats-protocol-for-developers/eligibility-modules), [toggles](https://docs.hatsprotocol.xyz/for-developers/hats-protocol-for-developers/toggle-modules)):

| Hat | Admin (transitive) | Eligibility | Toggle |
|-----|-------------------|-------------|--------|
| Tophat | (root) | Neutral / immutable | Neutral / immutable |
| MutinyRole | Tophat | Role-Hat Upgrader (quiet-window gated) | Immutable after bootstrap |
| Captain | MutinyRole | MutinyModule (succession rules) | Immutable |
| Squad-admin | Captain | Squad policy / immutable | Immutable |
| QuartermasterRole | Tophat | Role-Hat Upgrader | Immutable |
| Crew | QuartermasterRole | Quartermaster (timelock + mutiny hooks) | Immutable |
| TreasuryAuthorityRole | Tophat | Role-Hat Upgrader | Immutable |

**Toggle discipline:** nothing that could **turn off** the crew hat as a weapon is given to the captain. After bootstrap, critical toggles are **immutable**.

---

## Foundational invariants (short list)

These are enforced in contracts and tests; full prose lives in the [authoritative architecture draft](../../ai-docs/nave-pirata-hats-pointer-architecture.md).

1. **Captain ∩ Crew = ∅** — no one wears both captain and crew hats.
2. **Structural `maxSupply`** — captain and role hats **1**; crew **10_000**; squad-admin **1**.
3. **Captain does not admin crew** — tree shape enforces this.
4. **Authority-bearing hats must not transfer to `address(0)`** (with crew hat exempt for legitimate revocation paths where allowed).
5. **Crew onboarding blocked during active mutiny** — electorate frozen for that round.
6. **One crew, one vote** — snapshot-based mutiny and Treasury crew votes.
7. **Privileged cross-module calls are hat-gated** — no “peer contract” address as source of truth for authority.
8. **Outgoing role clone must be quiet before hat upgrade** — quiet-window invariant.
9. **Mutiny threshold** — hard-coded majority of snapshot (constitutional; not Treasury-tunable).
10. **Critical toggles immutable** after bootstrap.

---

## Governance parameters (Treasury-tunable)

Timing and voting mode for Treasury and Quartermaster are **mutable** via **TreasuryAuthority** proposals (two-body vote), with **sanity bounds** on setters. **Mutiny** threshold is **not** in that bucket—it is fixed in code.

Defaults and bounds are described in the [architecture draft](../../ai-docs/nave-pirata-hats-pointer-architecture.md#governance-parameters-per-squad-mutable-via-treasury-authority). On-chain names may use enums such as `CrewVoteMode` (`MAJORITY_SNAPSHOT`, `QUORUM_OF_CAST`) in `ITreasuryAuthority`.

---

## TreasuryAuthority and the Safe

- **Sole module** on the Safe and **sole owner** (`threshold = 1`) — the two-body process *is* the Safe’s authority.
- **Functional path** is **`execute` → `execTransactionFromModule`**; the contract does not implement ERC-1271 for owner signatures, so stray `execTransaction` owner flows are not the steady-state.
- **Upgrading TreasuryAuthority** is a **ceremony**: Safe txs to swap module/owner, then **`transferHat`** on TreasuryAuthorityRole via Role-Hat Upgrader (with **`isQuiet()`** on the old clone).

Captain approval in code is **`captainVote(proposalId, true)`**; explicit veto is **`captainVote(proposalId, false)`**. Silence until deadline means the proposal cannot execute.

---

## Access control: no mutable peer pointers

- Contracts **do not** store another module’s address as the authority source.
- They check **`IHats.isWearerOfHat(msg.sender, ROLE_HAT_ID)`** (or equivalent).
- **`maxSupply = 1`** on role hats makes “the” live instance identifiable at call time.
- **Authority lookup** for cross-calls (e.g. MutinyModule → Quartermaster) reads the **current** QuartermasterRole wearer from Hats so upgrades do not require reconfiguring stored addresses.

---

## Upgrade paths (summary)

| Target | Who authorizes | Mechanism |
|--------|----------------|-----------|
| Captain (forced) | Crew via MutinyModule | `transferHat(captain, …)` after vote |
| Captain (voluntary) | Captain | `captainResign` / equivalent succession on MutinyModule |
| Crew roster | Captain proposes → Quartermaster | Timelocked add/remove; mutiny hooks hat-gated |
| Params (delays, quorum, vote mode) | Two-body Treasury | Proposals targeting role contracts’ setters |
| Quartermaster / Mutiny / Treasury **logic** | Two-body Treasury | Role-Hat Upgrader on respective role hat |
| SquadAdmin **logic** | Captain | New clone + squad-admin `transferHat` if bytecode changes; in-contract policy via executor roles |
---

## References

- [Hats Protocol — core concepts](https://docs.hatsprotocol.xyz/)
- [Zodiac modules](https://github.com/gnosisguild/zodiac)
- [Safe contracts](https://github.com/safe-global/safe-contracts)
- Deep-dive draft (longer, includes factory steps, security list, conventions): [`ai-docs/nave-pirata-hats-pointer-architecture.md`](../../ai-docs/nave-pirata-hats-pointer-architecture.md)
