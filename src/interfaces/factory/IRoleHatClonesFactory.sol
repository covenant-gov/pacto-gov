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
  /// @notice Parallel `createClones` array lengths do not match.
  error RoleHatClonesFactory_LengthMismatch();

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
   * @notice Batch CREATE2 clones; one external CALL for several role clones.
   * @param _masterCopies Master implementations (parallel).
   * @param _initDatas Encoded `initialize(...)` calldata per clone (parallel).
   * @param _salts CREATE2 salts (parallel).
   * @return _clones New clone addresses in input order.
   */
  function createClones(
    address[] calldata _masterCopies,
    bytes[] calldata _initDatas,
    bytes32[] calldata _salts
  ) external returns (address[] memory _clones);

  /**
   * @notice Deterministic address for `(masterCopy, salt, this factory)`
   * @param _masterCopy Master implementation
   * @param _salt CREATE2 salt
   * @return _predicted Predicted clone
   */
  function predictCloneAddress(address _masterCopy, bytes32 _salt) external view returns (address _predicted);
}
