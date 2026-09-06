// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISponsorPolicyRegistry} from 'interfaces/external/ISponsorPolicyRegistry.sol';

/**
 * @title SponsorPolicyOps
 * @author Pacto
 * @notice Shared helpers for wiring `NavePirataFactory` on username-nft `SponsorPolicyRegistry`.
 */
library SponsorPolicyOps {
  /// @notice Outcome of `_wireFactory`.
  struct WireResult {
    bool registrarAuthorized;
    bool targetRegistered;
  }

  /// @notice Authorizes `factory` as registrar and registers it as a deploy target when not already set.
  function wireFactory(ISponsorPolicyRegistry registry, address factory) internal returns (WireResult memory result) {
    if (!registry.authorizedRegistrars(factory)) {
      registry.setAuthorizedRegistrar(factory, true);
      result.registrarAuthorized = true;
    }
    if (!registry.isContractAllowed(factory)) {
      registry.registerTarget(factory);
      result.targetRegistered = true;
    }
  }
}
