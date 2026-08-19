# Quartermaster — crew roster and timelocks

## Why it exists

A squad needs a **fair, predictable way** to grow and shrink the **crew**: who is allowed to wear the **crew hat** in Hats Protocol. Letting the captain add or remove people **instantly** can feel arbitrary or abusive. The Quartermaster adds **time**: proposed changes become real only **after a delay**, so everyone can see what’s coming and react (socially or through other governance).

It also connects to **mutiny**: when the crew is voting to replace the captain, you don’t want the captain to **quietly reshuffle the crew** in the same block. So the Quartermaster can enter **mutiny mode**, which **blocks** those normal add/remove paths until the mutiny is resolved.

Crew can also **offboard** a fellow crew member **without the captain**, one person at a time. That vote uses the same **quorum-of-cast** rule as Treasury Authority’s optional quorum mode (default **30%** of the crew snapshot must vote, and yeas must beat nays). Inactive hats do not count as votes; they only enlarge the snapshot.

## What it does

### Normal operation (captain-driven)

1. **Add crew**  
   The **captain** requests that a candidate be given the crew hat. Nothing happens immediately: a **timestamp** is recorded, and after the squad’s **crew change delay** elapses, **anyone** can run the final step that actually **mints** the crew hat (through Hats).

2. **Remove crew**  
   Same pattern: captain **requests** removal, wait **delay**, then **anyone** can execute the removal. The system updates internal eligibility so Hats can enforce standing.

3. **Cancel**  
   The captain can cancel a pending add or remove before it executes.

The product API for “what is pending” is on-chain views, not events: `pendingAdds()` / `pendingRemoves()` (or `pendingAddAt` / `pendingRemoveAt` plus the counts). `pendingCrewAddAt(address)` / `pendingCrewRemoveAt(address)` remain the point-check for a known address. Immediate paths (`bootstrapCrew`, mutiny mint / handoff) never appear in those lists.

### Crew-led offboard

1. **Propose**  
   A **crew** member opens an offboard against another crew member (not themselves, not the captain). Only **one** offboard can be live at a time. The vote window is **`crewOffboardExpiry`** (initialized from the same squad `proposalExpiry` as Treasury Authority).

2. **Vote**  
   Crew members vote yea or nay once. Pass requires turnout of at least **`crewOffboardQuorumBps`** of the snapshot **and** more yeas than nays.

3. **Execute or expire**  
   If the vote passes before the deadline, **anyone** can execute: eligibility is cleared and Hats re-checks the wearer. If the deadline passes first, **anyone** can expire the vote so another offboard can start.

While an offboard is live, captain add/remove request and execute are **frozen** (same idea as mutiny mode). A captain **pending remove** on the same address blocks opening an offboard on that address. Mutiny and offboard cannot overlap.

### During a mutiny

- **Mutiny mode** is turned **on** by the **mutiny module** (only that module’s role can flip the switch).
- While mutiny mode is on, the captain **cannot** use the normal request/execute paths for adding or removing crew — they revert. Crew-led offboard also cannot start.
- The **mutiny module** may still call **special** Quartermaster functions reserved for mutiny (for example, seating a former human captain as crew after a successful mutiny).

### Parameters

- The length of the **crew change delay**, the **offboard voting window**, and the **offboard quorum** can be updated by whoever wears the **Treasury Authority role hat** — typically after a proper treasury governance process, not by the captain alone. Changing Treasury Authority `proposalExpiry` later does **not** automatically change Quartermaster `crewOffboardExpiry` or MutinyModule `mutinyExpiry`.

### Background: eligibility

The Quartermaster is also the **eligibility reference** for the **crew hat** in Hats. In practice that means: the chain asks this contract whether an address **should** be treated as eligible crew, aligned with the squad’s internal bookkeeping.

## How it relates to other parts

| Piece | Relationship |
|--------|----------------|
| **Mutiny module** | **Calls into** the Quartermaster to set mutiny mode and, when needed, to mint or hand off crew hats after a captain change. |
| **Hats Protocol** | All real “who holds the crew hat” operations go through **Hats** (mint, transfer, status checks). The Quartermaster does not talk to the Treasury Authority or Safe directly. |
| **Treasury Authority** | No direct code link. The **Treasury Authority role** hat gates **delay changes** on the Quartermaster, so treasury governance can tune how patient crew changes must be. |
| **Captain & crew** | The **captain** drives normal roster proposals; **crew** vote on **crew-led offboard** (no captain required). Mutiny still lives on the mutiny module. If the **Safe** wears the captain hat (pause-captain mutiny), roster actions still require **captain** checks: the Safe must call **as itself** (e.g. via a Safe transaction) for `onlyHatWearer(captainHatId)` paths to succeed. |

## Mental model

Think of the Quartermaster as **HR with a waiting period**, a **crew-only offboard vote** for removing inactive members, plus a **“lock the doors”** switch during a mutiny or live offboard so normal hiring/firing pauses.
