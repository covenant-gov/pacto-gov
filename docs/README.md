# Pacto governance guidebook

Plain-language explainers for how key on-chain pieces of a **Nave Pirata** squad work together. These pages are for people who care about **governance outcomes** (who can spend treasury money, who can change the crew, how power can change hands) — not for reading Solidity.

## In this guide

- **[Mutiny module](./MutinyModule.md)** — How the crew can replace the captain (or how the captain can step down) using an on-chain vote — including a path that moves the captain hat to the **squad Safe** (“pause captain” mode).
- **[Quartermaster](./Quartermaster.md)** — How the captain adds and removes crew members, with a built-in waiting period.
- **[Treasury Authority](./TreasuryAuthority.md)** — How the squad agrees on **actions** that move money or change settings on the shared **Safe** (vault): crew vote plus captain approval for execution — with a **crew-only** execution path when the **Safe itself** wears the captain hat.
- **[Squad Admin](./SquadAdmin.md)** — Captain-gated **executor roles** under the squad-admin hat (integrations, bots, product modules).

## How the pieces fit

The **captain** leads, the **crew** participates. The **Quartermaster** is the “personnel office”: timelocked crew changes under the captain. The **mutiny module** is the “constitutional process” for changing who wears the captain hat when the crew revolts or the captain resigns — and while a mutiny is live, the Quartermaster **pauses** normal crew changes so the roster isn’t manipulated mid-crisis. A successful **pause-captain** mutiny moves the captain hat to the **Safe** (the same address the Treasury Authority uses as Zodiac **avatar**); treasury proposals can then pass on **crew quorum alone** until a later mutiny or resignation moves the hat back to a person. The **Treasury Authority** does not run the mutiny or crew roster itself — but the **same hats** anchor both lanes, so coordination off-chain still matters. **Squad Admin** sits beside that story: optional **delegated permissions** for other contracts, still ultimately under the captain hat for roster edits.

