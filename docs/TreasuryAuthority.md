# Treasury Authority — spending and Safe actions

## Why it exists

Many squads keep assets in a **Gnosis Safe** (a shared multisig-style vault). The Treasury Authority is the on-chain rulebook for **what the Safe is allowed to do** when acting through this module: things like **sending tokens**, **calling other contracts**, or **updating parameters** on squad contracts — without giving any single person a blank check.

The default design is **two-key**:

1. **Crew** must show enough support (votes are counted in one of two configurable modes: majority of a snapshot, or quorum-of-votes with a yes/no tally).
2. **Captain** must **approve** the same proposal (or explicitly **veto** it early).

**Exception:** if the squad **Safe** (the module’s Zodiac **avatar**) **wears the captain hat** — for example after a successful **pause-captain** mutiny — then **crew support alone** is enough to **execute**; there is no separate `captainVote(true)` step because no human holds that hat. The captain’s **veto** path still applies when a **human** wears the captain hat; once the hat sits on the Safe, veto semantics align with “no human captain on the hat.”

Only when the rule above is satisfied can the proposal **execute** as a transaction **from the Safe** through the module.

## What it does

### Proposals

- **Who can propose:** the **captain** or any **crew member** (same hat gates as elsewhere in the squad).
- **What a proposal contains:** where to call, how much value to send, what data to send, and whether it’s a normal call or a delegate call (technical detail: the Safe still executes it; readers can think “what action on-chain”).  
- **One open proposal per address:** if you already have a live proposal you haven’t finished or that hasn’t expired, you can’t open another until that situation clears (execute, captain veto, or expiry).
- **Listing:** `nextProposalId` is the next unused id (1 when none exist). Clients loop `for (id = 1; id < nextProposalId(); id++)` and read `proposal(id)` / `isExecutable(id)` / `crewVotePassed(id)`. `maxDeadline` is the latest deadline ever assigned (used by `isQuiet`).

### Crew vote

- Crew members vote **for** or **against** the proposal.
- Each crew member votes **once** per proposal.

### Captain vote

- When a **human** or non-avatar **smart contract** (any non–Safe wearer) holds the captain hat, the captain gets **one** vote per proposal: **approve** (yes to executing, if crew passes) or **veto** (no — the proposal is dead for execution, and the proposer’s “open slot” is freed so they can propose something else).
- A veto does **not** require waiting until the proposal’s deadline; it’s an early **off-ramp**.
- When the **Safe** wears the captain hat, **`captainVote(true)` is not required** for `execute`; crew threshold still applies. Product-wise, treat that window as **crew-led execution** for passed proposals.

### Execution

- After the deadline logic and checks, if crew support and captain approval are satisfied, **anyone** can trigger **execute**. The module asks the Safe to perform the agreed action.

### Expiry

- Proposals have a **lifetime**. If time runs out without enough crew support (and, when required, captain approval), the proposal **cannot** be executed anymore (even though the record may still exist on-chain for transparency).

## How it relates to other parts

| Piece | Relationship |
|--------|----------------|
| **Mutiny module** | **No direct calls.** If a mutiny moves the captain hat to the **Safe** (pause captain), treasury **execute** no longer requires a human `captainVote(true)`; other mutiny or resignation outcomes change the human captain as before. |
| **Quartermaster** | **No direct link in code.** Treasury governance can still **change** things that affect the Quartermaster (for example, crew change delay) **if** a proposal’s target is set to that contract and passes crew + captain. |
| **Safe** | The Treasury Authority is a **module** wired to the squad Safe; execution is **Safe execution** under the hood. |
| **Hats** | Proposing, crew voting, captain voting, and some parameter updates are **hat-gated** (captain hat, crew hat, or a dedicated treasury role hat depending on the function). |

## Mental model

Think of the Treasury Authority as **“crew sign-off before the vault acts,”** plus **captain sign-off** — with a captain **veto** in that mode so leadership can stop a bad transaction without waiting for the clock to run out. When the **Safe** wears the captain hat, the mental model is **“crew quorum unlocks execution”** for the same proposal object.

## Note for readers

Exact vote math (majority vs quorum) and timing are **parameters** set for each deployment. For precise numbers, your squad’s deployment docs or on-chain readouts are the source of truth; this page is the **shape** of the rules, not every constant.
