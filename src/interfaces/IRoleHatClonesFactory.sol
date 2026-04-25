// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IRoleHatClonesFactory
 * @author Pacto
 * @notice Generic EIP-1167 minimal-proxy factory for Nave Pirata role contracts.
 * @dev Permissionless: anyone may clone an approved master copy. Trust flows from the caller
 *      — typically `NavePirataFactory` (one-shot bootstrap) or `RoleHatUpgrader` (upgrade
 *      ceremony). The factory itself does not enforce a master-copy allow-list; that is the
 *      responsibility of `RoleHatUpgrader`.
 */
interface IRoleHatClonesFactory {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A new clone was created.
   * @param _masterCopy Implementation cloned via EIP-1167.
   * @param _clone The deployed clone address.
   * @param _salt The CREATE2 salt used.
   * @param _deployer Address that triggered the clone.
   */
  event CloneCreated(address indexed _masterCopy, address indexed _clone, bytes32 _salt, address indexed _deployer);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice The clone's initializer call reverted.
  error RoleHatClonesFactory_InitializationFailed();
  /// @notice Master copy address is zero.
  error RoleHatClonesFactory_ZeroMasterCopy();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy an EIP-1167 clone of `_masterCopy` via CREATE2, then invoke `_initData` on it.
   * @dev The clone's address is deterministic in `(masterCopy, salt, factory)`.
   * @param _masterCopy Implementation address.
   * @param _initData Encoded `initialize(...)` calldata to invoke on the fresh clone.
   * @param _salt CREATE2 salt.
   * @return _clone Address of the newly deployed clone.
   */
  function createClone(address _masterCopy, bytes calldata _initData, bytes32 _salt) external returns (address _clone);

  /**
   * @notice Predict the address of a clone for `(masterCopy, salt)`.
   * @param _masterCopy Implementation address.
   * @param _salt CREATE2 salt.
   * @return _predicted Deterministic address of the would-be clone.
   */
  function predictCloneAddress(address _masterCopy, bytes32 _salt) external view returns (address _predicted);
}
