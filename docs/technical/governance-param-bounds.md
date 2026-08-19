# Governance parameter bounds (for clients)

On-chain inclusive limits for Nave Pirata deploy UIs and later setters. Source: [`RangeValidator`](../../src/contracts/utils/RangeValidator.sol) (mixed into Treasury Authority, Quartermaster, and MutinyModule). `initialize` and setters revert `RangeValidator_OutOfRange` outside these ranges.

Do not invent tighter or looser limits in the client. War-game 5-minute clocks are a product default; they are valid because they sit at or above the 1-minute floor. This repo’s scripted defaults are 7 days, not 5 minutes (`script/Constants.sol`).

## Bounds

| Kind | Constant | Inclusive min | Inclusive max |
|------|----------|---------------|---------------|
| Delay / lifetime (seconds) | `MIN_GOV_DELAY` / `MAX_GOV_DELAY` | **60** (1 minute) | **5_184_000** (60 days) |
| Quorum (basis points) | `MIN_QUORUM_BPS` / `MAX_QUORUM_BPS` | **500** (5%) | **10_000** (100%) |

1 bp = 0.01%. Quorum bps is a `uint256` percent, not the vote-mode enum.

## `SquadParams` at factory deploy

[`INavePirataFactory.SquadParams`](../../src/interfaces/factory/INavePirataFactory.sol) is the deploy bundle. Each field is validated by the clone that stores it.

| Deploy field | Meaning | Seeds at factory init |
|--------------|---------|------------------------|
| `crewChangeDelay` | Captain add/remove **timelock** on Quartermaster (wait this long after request before execute). Delay range. | `Quartermaster.crewChangeDelay` only |
| `proposalExpiry` | Treasury Authority proposal **lifetime**. Execute as soon as votes pass; no extra delay. Delay range. | TA `proposalExpiry`, MutinyModule `mutinyExpiry`, Quartermaster `crewOffboardExpiry` |
| `crewVoteMode` | How TA scores **crew** votes. Solidity enum (`0` / `1`), not a percent. | TA `crewVoteMode` only |
| `quorumBps` | Turnout percent in bps. Quorum range. Unused by TA until mode is `QUORUM_OF_CAST`. | TA `quorumBps` **and** Quartermaster `crewOffboardQuorumBps` |

Scripted defaults: `crewChangeDelay` = 7 days, `proposalExpiry` = 7 days, `crewVoteMode` = `MAJORITY_SNAPSHOT`, `quorumBps` = **3000** (30%).

## `CrewVoteMode` (Treasury Authority only)

Either/or. Not AND.

- **`MAJORITY_SNAPSHOT` (`0`)** — pass if `2 * yeas > snapshot` (strictly more than half the crew snapshot). Non-voters count against. `quorumBps` is ignored.
- **`QUORUM_OF_CAST` (`1`)** — pass if turnout meets `quorumBps` of the snapshot **and** `yeas > nays`: `(yeas + nays) * 10_000 >= snapshot * quorumBps`.

## Not a `SquadParams` switch

- **Mutiny pass rule** — always 51% snapshot (`yeas * 2 > snapshot`). No nays. No quorum mode.
- **Crew-led offboard** — always quorum-of-cast on Quartermaster (`crewOffboardQuorumBps`), independent of TA `crewVoteMode`.

## Mutiny clock

No vote delay: execute as soon as 51% is met, while `block.timestamp < deadline`. `deadline = startedAt + mutinyExpiry` (delay range). After the deadline, permissionless `expireMutiny` clears the round and Quartermaster mutiny mode.

## After deploy

Parameter changes go through the Treasury Authority **role hat** (two-body proposal: crew pass + captain, unless the Safe wears the captain hat). Setters are **separate**:

- TA: `setProposalExpiry`, `setCrewVoteMode`, `setQuorumBps`
- MutinyModule: `setMutinyExpiry`
- Quartermaster: `setCrewChangeDelay`, `setCrewOffboardExpiry`, `setCrewOffboardQuorumBps`

Changing TA `proposalExpiry` or `quorumBps` later does **not** update MutinyModule or Quartermaster. A live TA proposal or live offboard is scored against the **current** stored mode/bps at execute, not the value at propose.
