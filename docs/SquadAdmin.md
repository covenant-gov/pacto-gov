# Squad Admin — delegated “app” permissions under the captain

## Why it exists

The **captain hat** is meant to be worn by a **person** or a **small multisig**, not by dozens of helper contracts. In practice, squads still want **on-chain modules** (bots, keepers, product-specific contracts) to do narrow jobs: flip a flag, poke a registry, trigger a bounded action.

**Squad Admin** is the **single contract** that wears the **squad-admin hat** in the Hats tree. Inside it, the **captain** maintains a roster of **executors** and **roles** (`bytes32` keys). Other contracts can ask “does this address have role X for this squad?” without minting a new hat per bot.

Think of it as **delegated admin under one hat**: one on-chain “desk,” many named keys, captain-controlled.

## What it does (v1)

### Executor roster

- **`enableExecutor(account, role)`** — Captain turns on a specific `bytes32` role for an address.
- **`disableExecutor(account, role)`** — Captain turns it off.
- **`enableFullPermission(account, enable)`** — Captain grants or clears a **full** sentinel (`bytes32("FULL")`): that executor is treated as having **every** role for `hasExecutorRole` checks until cleared.
- **`pauseExecutor(account, pause)`** — Captain sets a **pause** sentinel (`bytes32("PAUSE")`): while paused, `hasExecutorRole` returns **false** for every role for that executor (full flag may still be set in storage; pause wins for reads).

Integrations call **`hasExecutorRole(executor, role)`** to gate their own entrypoints. The app-defined role catalog is readable via `roles()` / `roleCount()` / `roleAt(index)` (excludes the `FULL` / `PAUSE` sentinels, which are the public constants `FULL_PERMISSION` and `PAUSE_PERMISSION`).

### Initialization and variants

- **`SquadAdmin`** (standard Nave Pirata path) — Clone is initialized with **`InitParams`**: `captainHatId` and `squadAdminHatId`. Only addresses that **wear the captain hat** may change the roster (`isAllowed` → captain check).
- **`SquadAdminExt`** — Standalone / extension deployments: first **`initialize(owner)`** with an **EOA or multisig owner**; **`postInitialize(InitParams)`** then wires hat ids and **clears** `owner`, after which the captain hat gates calls like the base contract.

`postInitialize` exists so governance can migrate from “owner bootstrap” to “captain-gated” in a controlled sequence.

## How it relates to other parts

| Piece | Relationship |
|--------|----------------|
| **Captain hat** | Gates roster changes on **`SquadAdmin`**; the squad-admin hat is a **child** of the captain branch in the Hats tree (see [technical/hats-tree-and-pointer-architecture.md](./technical/hats-tree-and-pointer-architecture.md)). |
| **Mutiny / Treasury / Quartermaster** | **No direct calls** in core governance contracts; Squad Admin is for **product and integration** access control keyed off the same hat tree. |
| **Upgrades** | Same **EIP-1167 clone** story as other role contracts: new logic → new master + new clone; moving the **squad-admin hat** to a new clone is the heavy path if bytecode must change. Day-to-day policy prefers **executor rows** over redeploys. |

## What it does *not* do

- It does **not** move Safe assets or replace **Treasury Authority**.
- It does **not** change crew roster (**Quartermaster**) or run mutinies (**Mutiny module**).
- It does **not** assign arbitrary hats in Hats Protocol; it only stores **which addresses map to which logical roles** for consumers that opt in to this pattern.

## Mental model

**One squad-admin hat on one contract; many fine-grained toggles inside**, all under **captain** control — so integrations can stay small and auditable without fragmenting the Hats tree into one hat per micro-role.
