# Mutiny module — changing who is captain

## Why it exists

On-chain squads need a **clear, verifiable rule** for who is allowed to wear the **captain** role. In the real world, crews sometimes lose trust in their leader. This module encodes a **mutiny**: a formal process where **crew members** can vote to install a **new captain**, if enough of them agree under fixed rules.

It also supports **captain resignation**: the current captain can voluntarily hand the role to someone else **when no mutiny is already running**, without going through a crew vote.

Together, this makes **leadership change** something the chain can enforce, instead of only social agreement.

## What it does (in plain terms)

1. **Start a mutiny**  
   A crew member proposes an address that should become the new captain. The system records who the current captain was at that moment and takes a **snapshot** of crew size (how many crew hats exist). Only **one** mutiny can be active at a time for this squad.

2. **Crew vote**  
   Crew members who agree cast a vote. Each can vote once per mutiny.

3. **Execute the mutiny**  
   If **yes** votes pass a **majority-of-snapshot** threshold (more than half of the snapshot crew count), anyone can finalize the process. The **captain hat** is transferred from the old captain to the proposed new captain on **Hats Protocol** (the hat system this squad uses).

4. **While a mutiny is active**  
   The module tells the **Quartermaster** to turn on **“mutiny mode.”** That **freezes** the captain’s normal “hire and fire crew” flows so the roster can’t be changed casually during the vote. When the mutiny finishes, mutiny mode is turned off.

5. **After the captain changes (human ex-captains)**  
   If the old captain was a **person’s wallet** (not a smart contract), the module may ask the Quartermaster to **seat the former captain as crew** again — either by minting them a crew hat or by **handing off** an existing crew hat from the new captain, depending on whether the new captain was already crew.

   If the old captain was a **contract**, this automatic “welcome back as crew” step is **skipped** by design.

## How it relates to other parts

| Piece | Relationship |
|--------|----------------|
| **Quartermaster** | The mutiny module **calls** the Quartermaster to flip mutiny mode on/off and, when needed, to adjust crew membership after a successful mutiny. |
| **Hats Protocol** | Captain and crew membership live in **hats**. The module is wired as **eligibility** for the captain hat so transfers stay consistent with stored captain state. |
| **Treasury Authority** | There is **no direct link in code**. In practice the same squad still coordinates: a mutiny doesn’t automatically cancel treasury proposals, but **who** is captain for approvals **can** change if a mutiny succeeds. |
| **“Quiet” checks elsewhere** | While a mutiny is active, this module reports the squad as **not quiet**, which other processes (like safe contract upgrades) may use to avoid risky changes during turmoil. |

## What this module does *not* do

- It does **not** move money from the Safe by itself.
- It does **not** replace the Quartermaster for day-to-day crew onboarding — it only **overrides** normal rules during mutiny and uses special **mutiny-only** crew paths when appropriate.
- It does **not** allow two overlapping mutinies; a round must finish (successfully or not — note: failed mutinies may still require governance/product clarity on how the round ends) before another starts in the current design.

## Mental model

Think of the mutiny module as the squad’s **written constitution for removing or replacing the captain**, enforced by code — with a **pause** on normal HR (Quartermaster) while the vote is live.
