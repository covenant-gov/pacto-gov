// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ITreasuryAuthority} from 'interfaces/ITreasuryAuthority.sol';

/// @dev Default `Quartermaster.crewChangeDelay` / `INavePirataFactory.SquadParams.crewChangeDelay` for scripted deploys.
uint256 constant CREW_CHANGE_DELAY = 7 days;
/// @dev Default `TreasuryAuthority.proposalExpiry` / `INavePirataFactory.SquadParams.proposalExpiry` for scripted deploys.
uint256 constant PROPOSAL_EXPIRY = 7 days;
/// @dev Default `INavePirataFactory.SquadParams.quorumBps` (basis points; used with `QUORUM_OF_CAST` on-chain).
uint256 constant SQUAD_QUORUM_BPS = 3000;
/// @dev Default `INavePirataFactory.SquadParams.crewVoteMode` for scripted deploys.
ITreasuryAuthority.CrewVoteMode constant DEFAULT_CREW_VOTE_MODE = ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT;

/// @dev Chain ids referenced by deploy scripts and integration harnesses.
uint256 constant CHAIN_ID_ETHEREUM = 1;
uint256 constant CHAIN_ID_OPTIMISM = 10;
uint256 constant CHAIN_ID_BASE = 8453;
uint256 constant CHAIN_ID_ARBITRUM_ONE = 42_161;
uint256 constant CHAIN_ID_SEPOLIA = 11_155_111;
uint256 constant CHAIN_ID_ANVIL = 31_337;

/// @dev Hats Protocol v1 — same address on every chain where it is deployed ([Hats docs](https://docs.hatsprotocol.xyz/using-hats/hats-protocol-supported-chains)).
address constant HATS_PROTOCOL_V1 = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

/// @dev Safe v1.4.1 `SafeProxyFactory` — canonical cross-chain deployment ([Safe deployments](https://docs.safe.global/advanced/smart-account-supported-networks)).
address constant SAFE_PROXY_FACTORY_141 = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;

/// @dev Safe v1.4.1 `Safe` singleton (master copy).
address constant SAFE_SINGLETON_141 = 0x41675c099f32341bf84bFC6712a922029b8dFc80;
