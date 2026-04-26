# Treasury Authority — spending and Safe actions

## Why it exists

Many squads keep assets in a **Gnosis Safe** (a shared multisig-style vault). The Treasury Authority is the on-chain rulebook for **what the Safe is allowed to do** when acting through this module: things like **sending tokens**, **calling other contracts**, or **updating parameters** on squad contracts — without giving any single person a blank check.

The design is intentionally **two-key**:

1. **Crew** must show enough support (votes are counted in one of two configurable modes: majority of a snapshot, or quorum-of-votes with a yes/no tally).
2. **Captain** must **approve** the same proposal (or explicitly **veto** it early).

Only then can the proposal **execute** as a transaction **from the Safe** through the module.

## What it does

### Proposals

- **Who can propose:** the **captain** or any **crew member** (same hat gates as elsewhere in the squad).
- **What a proposal contains:** where to call, how much value to send, what data to send, and whether it’s a normal call or a delegate call (technical detail: the Safe still executes it; readers can think “what action on-chain”).  
- **One open proposal per address:** if you already have a live proposal you haven’t finished or that hasn’t expired, you can’t open another until that situation clears (execute, captain veto, or expiry).

### Crew vote

- Crew members vote **for** or **against** the proposal.
- Each crew member votes **once** per proposal.

### Captain vote

- The captain gets **one** vote per proposal: **approve** (yes to executing, if crew passes) or **veto** (no — the proposal is dead for execution, and the proposer’s “open slot” is freed so they can propose something else).
- A veto does **not** require waiting until the proposal’s deadline; it’s an early **off-ramp**.

### Execution

- After the deadline logic and checks, if crew support and captain approval are satisfied, **anyone** can trigger **execute**. The module asks the Safe to perform the agreed action.

### Expiry

- Proposals have a **lifetime**. If time runs out without enough support and captain approval, the proposal simply **cannot** be executed anymore (even though the record may still exist on-chain for transparency).

## How it relates to other parts

| Piece | Relationship |
|--------|----------------|
| **Mutiny module** | **No direct link in code.** If a mutiny **changes the captain**, **who** must approve treasury proposals changes with the new captain hat wearer. |
| **Quartermaster** | **No direct link in code.** Treasury governance can still **change** things that affect the Quartermaster (for example, crew change delay) **if** a proposal’s target is set to that contract and passes crew + captain. |
| **Safe** | The Treasury Authority is a **module** wired to the squad Safe; execution is **Safe execution** under the hood. |
| **Hats** | Proposing, crew voting, captain voting, and some parameter updates are **hat-gated** (captain hat, crew hat, or a dedicated treasury role hat depending on the function). |

## Mental model

Think of the Treasury Authority as **“crew + captain sign-off before the vault acts.”** It is **not** the crew roster and **not** the mutiny process — it’s the **spending and admin action** lane, with a captain **veto** so leadership can stop a bad transaction without waiting for the clock to run out.

## Note for readers

Exact vote math (majority vs quorum) and timing are **parameters** set for each deployment. For precise numbers, your squad’s deployment docs or on-chain readouts are the source of truth; this page is the **shape** of the rules, not every constant.
