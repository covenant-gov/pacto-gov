// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
  CHAIN_ID_ANVIL,
  CHAIN_ID_ARBITRUM_ONE,
  CHAIN_ID_BASE,
  CHAIN_ID_ETHEREUM,
  CHAIN_ID_OPTIMISM,
  CHAIN_ID_SEPOLIA,
  SPONSOR_POLICY_REGISTRY_SEPOLIA
} from 'script/Constants.sol';

/**
 * @title SponsorPolicyPins
 * @author Pacto
 * @notice Chain pins for pacto-username-nft `SponsorPolicyRegistry` wiring scripts.
 * @dev Update `NAVE_PIRATA_FACTORY_SEPOLIA` after each infra redeploy on Sepolia.
 */
library SponsorPolicyPins {
  /// @notice No sponsor-policy pins for `chainId` (extend this library when a chain is wired).
  error SponsorPolicyPins_UnsupportedChain(uint256 chainId);

  /// @notice `navePirataFactory` pin is unset for this chain.
  error SponsorPolicyPins_UnsetFactory(uint256 chainId);

  /// @dev pacto-gov `NavePirataFactory` on Sepolia; set after `pnpm deploy:infra:sepolia`.
  address internal constant NAVE_PIRATA_FACTORY_SEPOLIA = address(0);

  /// @notice Resolves the username-nft policy registry for `chainId`.
  function sponsorPolicyRegistry(uint256 chainId) internal pure returns (address registry) {
    if (chainId == CHAIN_ID_SEPOLIA) return SPONSOR_POLICY_REGISTRY_SEPOLIA;
    if (
      chainId == CHAIN_ID_ETHEREUM || chainId == CHAIN_ID_OPTIMISM || chainId == CHAIN_ID_BASE
        || chainId == CHAIN_ID_ARBITRUM_ONE || chainId == CHAIN_ID_ANVIL
    ) {
      return address(0);
    }
    revert SponsorPolicyPins_UnsupportedChain(chainId);
  }

  /// @notice Resolves the wired `NavePirataFactory` pin for `chainId`.
  function navePirataFactory(uint256 chainId) internal pure returns (address factory) {
    if (chainId == CHAIN_ID_SEPOLIA) {
      factory = NAVE_PIRATA_FACTORY_SEPOLIA;
      if (factory == address(0)) revert SponsorPolicyPins_UnsetFactory(chainId);
      return factory;
    }
    if (
      chainId == CHAIN_ID_ETHEREUM || chainId == CHAIN_ID_OPTIMISM || chainId == CHAIN_ID_BASE
        || chainId == CHAIN_ID_ARBITRUM_ONE || chainId == CHAIN_ID_ANVIL
    ) {
      revert SponsorPolicyPins_UnsetFactory(chainId);
    }
    revert SponsorPolicyPins_UnsupportedChain(chainId);
  }
}
