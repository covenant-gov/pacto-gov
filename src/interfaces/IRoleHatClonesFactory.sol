// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IRoleHatClonesFactory
 * @author Pacto
 * @notice Permissionless CREATE2 EIP-1167 role clones. Clone address = f(master, salt, this); master-copy
 *         allow-list is on `RoleHatUpgrader` / call policy, not here
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
   * @notice CREATE2 clone of `_masterCopy`, then `_initData` on the new proxy
   * @param _masterCopy Master implementation
   * @param _initData Encoded `initialize(...)` for the clone
   * @param _salt CREATE2 salt
   * @return _clone New clone
   */
  function createClone(address _masterCopy, bytes calldata _initData, bytes32 _salt) external returns (address _clone);

  /**
   * @notice Deterministic address for `(masterCopy, salt, this factory)`
   * @param _masterCopy Master implementation
   * @param _salt CREATE2 salt
   * @return _predicted Predicted clone
   */
  function predictCloneAddress(address _masterCopy, bytes32 _salt) external view returns (address _predicted);
}
