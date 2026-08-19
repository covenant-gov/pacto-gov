// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ITreasuryAuthority} from 'interfaces/core/ITreasuryAuthority.sol';

/// @dev Default `Quartermaster.crewChangeDelay` / `INavePirataFactory.SquadParams.crewChangeDelay` for scripted deploys.
uint256 constant CREW_CHANGE_DELAY = 7 days;
/// @dev Default `TreasuryAuthority.proposalExpiry` / `INavePirataFactory.SquadParams.proposalExpiry` for scripted deploys.
///      Also seeds `MutinyModule.mutinyExpiry` and `Quartermaster.crewOffboardExpiry` at factory init.
uint256 constant PROPOSAL_EXPIRY = 7 days;
/// @dev Default `INavePirataFactory.SquadParams.quorumBps` (basis points; TA `QUORUM_OF_CAST` and Quartermaster crew-led offboard).
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

/// @dev Safe v1.4.1 `Safe` singleton (canonical cross-chain deployment; matches `safe-global/safe-deployments` v1.4.1).
address constant SAFE_SINGLETON_141 = 0x41675C099F32341bf84BFc5382aF534df5C7461a;

/// @dev EIP-1167 master copies for `INavePirataFactory.deployNavePirata` and standalone squad-admin helpers. Replace
///      with addresses from the same chain’s bootstrap (`DeployMasterCopies` / `master-copies.json`) before production;
///      `address(0)` is unset (standalone scripts may read implementation from env instead).
address constant MASTER_COPY_QUARTERMASTER = address(0);
address constant MASTER_COPY_MUTINY_MODULE = address(0);
address constant MASTER_COPY_TREASURY_AUTHORITY = address(0);
address constant MASTER_COPY_SQUAD_ADMIN_IMPL = address(0);
address constant MASTER_COPY_SQUAD_ADMIN_EXT_IMPL = address(0);

/// @dev Salt passed to `DeployParams.saltNonce` for Safe + clone determinism; increment per new squad if needed.
uint256 constant DEPLOY_NAV_PIRATA_SALT_NONCE = 1;

/// @dev Default block pin for `vm.createSelectFork` / `vm.rollFork` when `MAINNET_RPC` is set (stable Safe singleton).
uint256 constant DEFAULT_MAINNET_FORK_BLOCK = 22_900_000;
