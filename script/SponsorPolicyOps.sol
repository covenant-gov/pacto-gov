// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISponsorPolicyRegistry} from 'interfaces/external/ISponsorPolicyRegistry.sol';

/**
 * @title SponsorPolicyOps
 * @author Pacto
 * @notice Shared helpers for wiring `NavePirataFactory` and `RoleHatUpgrader` on username-nft
 *         `SponsorPolicyRegistry`.
 */
library SponsorPolicyOps {
  /// @notice Outcome of a factory (and optional upgrader) wire.
  struct WireResult {
    bool registrarAuthorized;
    bool targetRegistered;
    bool upgraderRegistrarAuthorized;
  }

  /// @notice `upgrader` was the zero address; role-upgrade reindex needs a registrar.
  error SponsorPolicyOps_ZeroUpgrader();

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

  /// @notice Authorizes `registrar` when it is not already an authorized registrar.
  function authorizeRegistrar(
    ISponsorPolicyRegistry registry,
    address registrar
  ) internal returns (bool authorizedNow) {
    if (!registry.authorizedRegistrars(registrar)) {
      registry.setAuthorizedRegistrar(registrar, true);
      authorizedNow = true;
    }
  }

  /// @notice Wires the factory as registrar + target, then authorizes the upgrader as registrar only.
  /// @dev The upgrader is not a deploy target; it only needs `registerModulesForTopHat` / `deregisterModules`.
  function wireFactoryAndUpgrader(
    ISponsorPolicyRegistry registry,
    address factory,
    address upgrader
  ) internal returns (WireResult memory result) {
    if (upgrader == address(0)) revert SponsorPolicyOps_ZeroUpgrader();
    result = wireFactory(registry, factory);
    result.upgraderRegistrarAuthorized = authorizeRegistrar(registry, upgrader);
  }
}
