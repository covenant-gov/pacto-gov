// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title DeployTypes
 * @author Pacto
 * @notice Shared structs for deployment scripts and the integration harness (see tech spec §11 P9).
 */
library DeployTypes {
  /// @notice Chain singletons required by `NavePirataFactory` and master-copy constructors.
  struct ExternalAddresses {
    address hats;
    address safeProxyFactory;
    address safeSingleton;
  }

  /// @notice EIP-1167 master copies deployed once per chain.
  struct MasterCopyAddresses {
    address quartermaster;
    address mutinyModule;
    address treasuryAuthority;
    address squadAdminImpl;
  }

  /// @notice Pacto infra wired after masters exist.
  struct InfraAddresses {
    address clonesFactory;
    address registry;
    address upgrader;
    address navePirataFactory;
  }
}
