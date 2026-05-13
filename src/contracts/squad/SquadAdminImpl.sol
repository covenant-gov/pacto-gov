// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {IQuiescent} from 'interfaces/abstracts/IQuiescent.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title SquadAdminImpl
 * @author Pacto
 * @notice v1: captain-gated per-role executors, `bytes32("FULL")`, and `bytes32("PAUSE")` kill-switch. More surface later via UUPS
 * @dev ERC-7201 `pacto.squadadmin.v1` layout; UUPS is captain-only (not two-body)
 */
contract SquadAdminImpl is ISquadAdmin, HatGated, Initializable, UUPSUpgradeable {
  /*///////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Full permission role.
  bytes32 internal constant _FULL_PERMISSION = bytes32('FULL');

  /// @notice When enabled for an executor, `hasExecutorRole` is false for every `_role` until cleared.
  bytes32 internal constant _PAUSE_PERMISSION = bytes32('PAUSE');

  /**
   * @notice ERC-7201 slot for `SquadAdminStorageV1`.
   * @dev Computed as `keccak256(abi.encode(uint256(keccak256("pacto.squadadmin.v1")) - 1)) & ~bytes32(uint256(0xff))`.
   */
  bytes32 private constant _SQUAD_ADMIN_STORAGE_V1 = 0xbc98e12076e749742801736ca484b4a7be0cea42f395e3487d1ecb57f6c45400;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/
  /// @notice Runs the body only if `msg.sender` wears the captain hat.
  modifier isCaptain() {
    _requireCaptain();
    _;
  }

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Master-copy constructor; bakes the Hats singleton into implementation runtime code
   *         and locks direct initialization of the implementation.
   * @param hats_ Hats Protocol address for this chain.
   */
  constructor(IHats hats_) HatGated(hats_) {
    _disableInitializers();
  }

  /// @inheritdoc ISquadAdmin
  function initialize(InitParams calldata _p) external override initializer {
    // OZ v5 UUPSUpgradeable is stateless; no initializer needs to run.
    SquadAdminStorageV1 storage _s = _getStorage();
    _s.captainHatId = _p.captainHatId;
    _s.squadAdminHatId = _p.squadAdminHatId;
  }

  /*///////////////////////////////////////////////////////////////
                            CAPTAIN-GATED LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  function enableExecutor(address _executor, bytes32 _role) external override isCaptain {
    if (_executor == address(0)) revert SquadAdmin_ZeroAddress();
    SquadAdminStorageV1 storage _s = _getStorage();
    _s.executors[_executor][_role] = true;
    emit ExecutorEnabled(_executor, _role);
  }

  /// @inheritdoc ISquadAdmin
  function enableFullPermission(address _executor, bool _enable) external override isCaptain {
    SquadAdminStorageV1 storage _s = _getStorage();
    _s.executors[_executor][_FULL_PERMISSION] = _enable;
    emit FullPermissionEnabled(_executor, _enable);
  }

  /// @inheritdoc ISquadAdmin
  function disableExecutor(address _executor, bytes32 _role) external override isCaptain {
    SquadAdminStorageV1 storage _s = _getStorage();
    _s.executors[_executor][_role] = false;
    emit ExecutorDisabled(_executor, _role);
  }

  /// @inheritdoc ISquadAdmin
  function pauseExecutor(address _executor, bool _pause) external override isCaptain {
    SquadAdminStorageV1 storage _s = _getStorage();
    _s.executors[_executor][_PAUSE_PERMISSION] = _pause;
    emit ExecutorPaused(_executor, _pause);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  function hasExecutorRole(address _executor, bytes32 _role) external view override returns (bool _enabled) {
    SquadAdminStorageV1 storage _s = _getStorage();
    if (_isExecutorPaused(_executor)) _enabled = false;
    else _enabled = _isExecutorFullPermission(_executor) || _s.executors[_executor][_role];
  }

  /// @inheritdoc ISquadAdmin
  function isExecutorFullPermission(address _executor) external view override returns (bool _fullPermission) {
    _fullPermission = _isExecutorFullPermission(_executor);
  }

  /// @inheritdoc ISquadAdmin
  function isExecutorPaused(address _executor) external view override returns (bool _paused) {
    _paused = _isExecutorPaused(_executor);
  }

  /// @inheritdoc ISquadAdmin
  function captainHatId() external view override returns (uint256 _captainHatId) {
    _captainHatId = _getStorage().captainHatId;
  }

  /// @inheritdoc ISquadAdmin
  function squadAdminHatId() external view override returns (uint256 _squadAdminHatId) {
    _squadAdminHatId = _getStorage().squadAdminHatId;
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external pure override returns (bool _quiet) {
    // v1 has no timelocked, pending, or in-flight state; always quiet. Future implementations with
    // asynchronous flows (e.g. EIP-712 nonces with windows, scheduled policy changes) should tighten this.
    _quiet = true;
  }

  /*///////////////////////////////////////////////////////////////
                            UUPS UPGRADE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  function upgradeToAndCall(
    address _newImplementation,
    bytes memory _data
  ) public payable override(ISquadAdmin, UUPSUpgradeable) {
    super.upgradeToAndCall(_newImplementation, _data);
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice UUPS upgrade authorisation hook. Captain-hat-gated — SquadAdmin changes bypass the
   *         two-body vote by design.
   * @param _newImplementation Address of the proposed new implementation.
   */
  function _authorizeUpgrade(address _newImplementation) internal view override {
    _requireCaptain();
    if (_newImplementation == address(0)) revert SquadAdmin_ZeroAddress();
  }

  /**
   * @notice Reverts with `SquadAdmin_NotCaptain` if `msg.sender` does not wear the captain hat.
   * @dev Uses the v1-specific error surface instead of `HatGated_NotHatWearer` to match the
   *      `ISquadAdmin` contract and keep captain-gated reverts uniform across the product surface.
   */
  function _requireCaptain() internal view {
    uint256 _captainHatId = _getStorage().captainHatId;
    if (!_HATS.isWearerOfHat(msg.sender, _captainHatId)) revert SquadAdmin_NotCaptain();
  }

  /**
   * @notice Reads the pause sentinel for `_executor`.
   * @param _executor Account queried.
   * @return _paused Whether `_PAUSE_PERMISSION` is enabled in storage.
   */
  function _isExecutorPaused(address _executor) internal view returns (bool _paused) {
    _paused = _getStorage().executors[_executor][_PAUSE_PERMISSION];
  }

  /**
   * @notice Reads the full-permission sentinel for `_executor`.
   * @param _executor Account queried.
   * @return _fullPermission Whether `_FULL_PERMISSION` is enabled in storage.
   */
  function _isExecutorFullPermission(address _executor) internal view returns (bool _fullPermission) {
    _fullPermission = _getStorage().executors[_executor][_FULL_PERMISSION];
  }

  /**
   * @notice Returns a pointer to the ERC-7201 `SquadAdminStorageV1` struct.
   * @return _s Storage-pointer to the v1 namespaced storage.
   */
  function _getStorage() internal pure returns (SquadAdminStorageV1 storage _s) {
    bytes32 _slot = _SQUAD_ADMIN_STORAGE_V1;
    assembly {
      _s.slot := _slot
    }
  }
}
