# Pacto governance guidebook

Plain-language explainers for how key on-chain pieces of a **Nave Pirata** squad work together. These pages are for people who care about **governance outcomes** (who can spend treasury money, who can change the crew, how power can change hands) — not for reading Solidity.

## In this guide

- **[Mutiny module](./MutinyModule.md)** — How the crew can replace the captain (or how the captain can step down) using an on-chain vote.
- **[Quartermaster](./Quartermaster.md)** — How the captain adds and removes crew members, with a built-in waiting period.
- **[Treasury Authority](./TreasuryAuthority.md)** — How the squad agrees on **actions** that move money or change settings on the shared **Safe** (vault): crew vote + captain + execution.

## How the pieces fit (one paragraph)

The **captain** leads, the **crew** participates. The **Quartermaster** is the “personnel office”: timelocked crew changes under the captain. The **mutiny module** is the “constitutional process” for changing who wears the captain hat when the crew revolts or the captain resigns — and while a mutiny is live, the Quartermaster **pauses** normal crew changes so the roster isn’t manipulated mid-crisis. The **Treasury Authority** is separate: it governs **what the Safe is allowed to do** (transactions), using crew support and captain approval, and does not run the mutiny or crew roster itself — but the **same people** (wearing the same hats) usually interact with all of them, so coordination off-chain still matters.

## Possible next chapters

- **Nave Pirata Registry** — The on-chain index of deployed squads and upgrade history (good for explorers and auditors).
- **Nave Pirata Factory** — How a new squad is born in one deployment flow.
- **Role hat upgrader** — How implementation contracts can be swapped safely when the squad is “quiet.”
- **Squad Admin & Safe** — How the module relates to the Safe as owner.
- A **glossary** (Safe, Hats, proposal, snapshot, timelock, veto).

If you want a specific audience (e.g. only captains, only legal/compliance), say so and these pages can be retuned.
