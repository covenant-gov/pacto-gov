# Squad Admin — delegated “app” permissions under the captain

## Why it exists

The **captain hat** is meant to be worn by a **person** or a **small multisig**, not by dozens of helper contracts. In practice, squads still want **on-chain modules** (bots, keepers, product-specific contracts) to do narrow jobs: flip a flag, poke a registry, trigger a bounded action.

**Squad Admin** is the **single contract** that wears the **squad-admin hat** in the Hats tree. Inside it, the **captain** maintains a roster of **executors** and **roles** (`bytes32` keys). Other contracts can ask “does this address have role X for this squad?” without minting a new hat per bot.

Think of it as **delegated admin under one hat**: one on-chain “desk,” many named keys, captain-controlled.

## What it does (v1)

### Role catalog

App role ids are **opaque `bytes32` values**. The contract does not interpret permission bits or names; meaning for product privileges lives in the [client privilege encoding](#client-privilege-encoding-v1) below.

- **`createRole(role)`** — Captain registers a new app role id in the catalog. Reverts on `bytes32(0)`, on duplicate ids, and if the id is the `FULL` or `PAUSE` sentinel (`RoleAlreadyExists`). Sentinels are always valid for executor APIs without catalog registration.
- **`deleteRole(role)`** — Captain removes an id from the catalog (cannot delete `FULL` / `PAUSE`). Does **not** clear per-executor grants already stored for that id.

### Executor roster

- **`enableExecutor(account, role)`** — Captain turns on a specific `bytes32` role for an address (role must exist in the catalog, or be `FULL` / `PAUSE`).
- **`disableExecutor(account, role)`** — Captain turns it off.
- **`enableFullPermission(account, enable)`** — Captain grants or clears a **full** sentinel (`bytes32("FULL")`): that executor is treated as having **every** role for `hasExecutorRole` checks until cleared.
- **`pauseExecutor(account, pause)`** — Captain sets a **pause** sentinel (`bytes32("PAUSE")`): while paused, `hasExecutorRole` returns **false** for every role for that executor (full flag may still be set in storage; pause wins for reads).

Integrations call **`hasExecutorRole(executor, role)`** to gate their own entrypoints. The app-defined role catalog is readable via `roles()` / `roleCount()` / `roleAt(index)` (excludes the `FULL` / `PAUSE` sentinels, which are the public constants `FULL_PERMISSION` and `PAUSE_PERMISSION`).

Roster mutations (`createRole`, `deleteRole`, `enableExecutor`, `disableExecutor`, `enableFullPermission`, `pauseExecutor`) are **captain-gated** on `SquadAdmin` (and owner-then-captain on `SquadAdminExt`). There is **no ABI change and no redeploy** required for product privilege roles: clients pack action flags into the `bytes32` and register them with the existing APIs.

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
- It does **not** encode or decode action permissions on-chain; see the client convention below.

## Mental model

**One squad-admin hat on one contract; many fine-grained toggles inside**, all under **captain** control — so integrations can stay small and auditable without fragmenting the Hats tree into one hat per micro-role.

## Client privilege encoding (v1)

Product privileges for squads are a **client-side convention**: action permissions are packed into the role `bytes32` itself. Any conforming client can decode permissions from chain state alone — **no off-chain role registry** and **no SquadAdmin ABI change**.

Encode/decode and UI enforcement live in [covenant-gov/pacto-app#522](https://github.com/covenant-gov/pacto-app/issues/522). Captain FULL succession on captain change: [covenant-gov/pacto-gov#56](https://github.com/covenant-gov/pacto-gov/issues/56). Whether 1st Mates may mutate roles on-chain is undecided: [covenant-gov/pacto-gov#57](https://github.com/covenant-gov/pacto-gov/issues/57).

### Kept decisions

1. **Captain holds FULL.** The captain has `FULL_PERMISSION` on Squad Admin. FULL covers every action flag (including future ones once defined). Succession: [#56](https://github.com/covenant-gov/pacto-gov/issues/56).
2. **FULL semantics.** FULL ⇒ all action privileges via existing `hasExecutorRole` (PAUSE still overrides).
3. **Manual registration.** Roles are created through the governance dashboard with `createRole` as needed. No automatic migration or redeploy; existing squads bootstrap by creating packed role ids through the dashboard.
4. **Arrival-time receiver rule.** Receivers authorize privileged events at **local arrival/process time** against **current** on-chain privilege (trusted RPC / SquadAdmin). Do **not** use Nostr `created_at` / send-time. Reject if the sender has already lost the needed privilege at arrival, even if `created_at` predates revocation. Trade-off (accepted): delayed-but-legitimate events after revoke are dropped.
5. **Invite and accept join requests are one privilege** (single action flag).
6. **Custom combinable roles.** Clients combine any subset of action flags plus a short display name into one `bytes32`, `createRole` it, and assign members with `enableExecutor` / `disableExecutor`.
7. **1st Mate.** Reserved flag bit. Holders may assign/revoke **all roles except** roles that carry the 1st Mate flag; **only the Captain** may assign/revoke 1st Mate. Product role managers = Captain + 1st Mates. **Interim constraint:** on-chain `createRole` / `enableExecutor` / `disableExecutor` / `enableFullPermission` remain **captain-gated**. Until [#57](https://github.com/covenant-gov/pacto-gov/issues/57) is resolved, 1st Mates cannot execute those txs themselves; do not invent a shipping UX for 1st Mate–initiated on-chain writes here. The flag is still visible/decodable from chain state.

### Open: joint inbox holders

Exact meaning of the joint-inbox portion of `FLAG_MANAGE_NETWORK` (network / RPC / joint inbox) is **still open**. Do not invent Safe-owner or key-mutation behavior in clients until that is decided.

### `bytes32` layout (treat as `uint256`, low bits = flags)

| Field | Bits | Meaning |
| --- | --- | --- |
| Action flags | `0..15` (low 16 bits) | See flag table |
| Encoding version | `16..23` | `1` = this layout; unknown version ⇒ fail closed (grant nothing from that id) |
| Reserved | `24..31` | Must be `0` in v1; non-zero ⇒ fail closed for that id |
| Short role name | `32..255` (28 bytes) | UTF-8/ASCII display name, left-aligned in the high 28 bytes of `bytes32`, zero-padded; **not** used for authorization |

In `bytes32` big-endian byte order: bytes `[0..27]` = name, byte `[28]` = reserved, byte `[29]` = version, bytes `[30..31]` = flags.

### Action flags (v1)

| Bit | Symbol | Meaning |
| --- | --- | --- |
| 0 | `FLAG_INVITE_ACCEPT` | Invite members **and** accept join requests (one privilege) |
| 1 | `FLAG_CREATE_CHANNEL` | Create squad channels |
| 2 | `FLAG_BROADCAST` | User-initiated broadcast |
| 3 | `FLAG_MANAGE_NETWORK` | Set network / RPC / joint inbox holders (joint-inbox scope still open) |
| 4 | `FLAG_FIRST_MATE` | 1st Mate (role-manager; cannot grant/revoke 1st Mate) |
| 5..15 | — | Reserved for future actions. v1 encoders set to `0`. Decoders: do **not** grant unknown powers for those bits; known bits `0..4` may still be used |

Bump **encoding version** when the flag map or name placement changes incompatibly. Old ids remain readable if the version is known; unknown versions grant no permissions.

**Name field** is display-only. Two roles with the same flags but different names are different catalog entries.

v1 ids always set version `1` in bits `16..23`, so the low four bytes are non-zero and **never equal** `FULL_PERMISSION` (`bytes32("FULL")`) or `PAUSE_PERMISSION` (`bytes32("PAUSE")`).

### Authorization decode (client)

1. If the executor has FULL and is not paused → allow all actions (and treat as role-manager for UI / Captain path). Prefer `isExecutorFullPermission` / `isExecutorPaused`, or `hasExecutorRole` against any registered role.
2. Else enumerate catalog roles (`roles()` / `roleAt`) where `hasExecutorRole(executor, roleId)` is true; OR the decoded action flags across those roles (including 1st Mate if any role has bit 4).
3. For a protected action, require the corresponding flag bit (or FULL).
4. **Never** trust an off-chain map of name → permissions; permissions come only from decoded bits + FULL/PAUSE.

### Test vectors

Encode: `flags | (version << 16) | (reserved << 24)` in the low 32 bits; name in the high 28 bytes. Hex below is the full `bytes32`.

#### Round-trip (version = 1, reserved = 0)

| Label | Flags | Name | `bytes32` |
| --- | --- | --- | --- |
| Invite + `Moderator` | `0x0001` (bit 0) | `Moderator` | `0x4d6f64657261746f720000000000000000000000000000000000000000010001` |
| Invite \| Create channel + `Mod` | `0x0003` (bits 0\|1) | `Mod` | `0x4d6f640000000000000000000000000000000000000000000000000000010003` |
| Broadcast + empty name | `0x0004` (bit 2) | _(empty)_ | `0x0000000000000000000000000000000000000000000000000000000000010004` |
| Invite + 28-byte name | `0x0001` | `ABCDEFGHIJKLMNOPQRSTUVWXYZ12` | `0x4142434445464748494a4b4c4d4e4f505152535455565758595a313200010001` |
| Invite \| Create \| Broadcast + `Mate` | `0x0007` (bits 0\|1\|2) | `Mate` | `0x4d61746500000000000000000000000000000000000000000000000000010007` |
| All known flags + `Ops` | `0x001f` (bits 0..4) | `Ops` | `0x4f7073000000000000000000000000000000000000000000000000000001001f` |

Same flags, different names (distinct catalog ids):

| Label | Flags | Name | `bytes32` |
| --- | --- | --- | --- |
| Broadcast + `Alpha` | `0x0004` | `Alpha` | `0x416c706861000000000000000000000000000000000000000000000000010004` |
| Broadcast + `Beta` | `0x0004` | `Beta` | `0x4265746100000000000000000000000000000000000000000000000000010004` |

#### Fail-closed / reserved bits

| Label | Expected client decode | `bytes32` |
| --- | --- | --- |
| Version `0`, invite, name `X` | Fail closed (unknown version) | `0x5800000000000000000000000000000000000000000000000000000000000001` |
| Version `2`, invite, name `X` | Fail closed (unknown version) | `0x5800000000000000000000000000000000000000000000000000000000020001` |
| Reserved byte `0xab`, v1 invite, name `X` | Fail closed (reserved ≠ 0) | `0x58000000000000000000000000000000000000000000000000000000ab010001` |
| Invite \| bit 5, v1, name `X` | Grant bit 0 only; bit 5 grants nothing | `0x5800000000000000000000000000000000000000000000000000000000010021` |

#### Sentinels (not packed roles; do not `createRole`)

| Constant | `bytes32` |
| --- | --- |
| `FULL_PERMISSION` | `0x46554c4c00000000000000000000000000000000000000000000000000000000` |
| `PAUSE_PERMISSION` | `0x5041555345000000000000000000000000000000000000000000000000000000` |
