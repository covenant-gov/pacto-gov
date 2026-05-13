// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISquadAdminBase} from 'interfaces/squad/ISquadAdminBase.sol';

abstract contract SquadAdminBase is ISquadAdminBase {
  /*///////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Full permission role.
  // forge-lint: disable-next-line(unsafe-typecast) — ASCII labels fit in `bytes32` (Solidity left-padding).
  bytes32 internal constant _FULL_PERMISSION = bytes32('FULL');

  /// @notice When enabled for an executor, `hasExecutorRole` is false for every `_role` until cleared.
  // forge-lint: disable-next-line(unsafe-typecast) — ASCII labels fit in `bytes32` (Solidity left-padding).
  bytes32 internal constant _PAUSE_PERMISSION = bytes32('PAUSE');

  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @notice Mapping of executor address → role → enabled flag.
  mapping(address account => mapping(bytes32 role => bool enabled)) internal _executors;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/
  /// @notice Runs the body only if `msg.sender` wears the captain hat.
  modifier isAllowed() {
    _requireAllowed();
    _;
  }

  /*///////////////////////////////////////////////////////////////
                            ACCESS-GATED LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdminBase
  function enableExecutor(address _executor, bytes32 _role) external override isAllowed {
    if (_executor == address(0)) revert SquadAdminBase_ZeroAddress();
    _executors[_executor][_role] = true;
    emit ExecutorEnabled(_executor, _role);
  }

  /// @inheritdoc ISquadAdminBase
  function enableFullPermission(address _executor, bool _enable) external override isAllowed {
    _executors[_executor][_FULL_PERMISSION] = _enable;
    emit FullPermissionEnabled(_executor, _enable);
  }

  /// @inheritdoc ISquadAdminBase
  function disableExecutor(address _executor, bytes32 _role) external override isAllowed {
    _executors[_executor][_role] = false;
    emit ExecutorDisabled(_executor, _role);
  }

  /// @inheritdoc ISquadAdminBase
  function pauseExecutor(address _executor, bool _pause) external override isAllowed {
    _executors[_executor][_PAUSE_PERMISSION] = _pause;
    emit ExecutorPaused(_executor, _pause);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdminBase
  function hasExecutorRole(address _executor, bytes32 _role) external view override returns (bool _enabled) {
    if (_isExecutorPaused(_executor)) _enabled = false;
    else _enabled = _isExecutorFullPermission(_executor) || _executors[_executor][_role];
  }

  /// @inheritdoc ISquadAdminBase
  function isExecutorFullPermission(address _executor) external view override returns (bool _fullPermission) {
    _fullPermission = _isExecutorFullPermission(_executor);
  }

  /// @inheritdoc ISquadAdminBase
  function isExecutorPaused(address _executor) external view override returns (bool _paused) {
    _paused = _isExecutorPaused(_executor);
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/

  /// @notice Hook for access control on `isAllowed`; implementations revert when denied (e.g. `HatGated_NotHatWearer` or `SquadAdminExt_NotAllowed`).
  function _requireAllowed() internal view virtual;

  /**
   * @notice Reads the pause sentinel for `_executor`.
   * @param _executor Account queried.
   * @return _paused Whether `_PAUSE_PERMISSION` is enabled in storage.
   */
  function _isExecutorPaused(address _executor) internal view returns (bool _paused) {
    _paused = _executors[_executor][_PAUSE_PERMISSION];
  }

  /**
   * @notice Reads the full-permission sentinel for `_executor`.
   * @param _executor Account queried.
   * @return _fullPermission Whether `_FULL_PERMISSION` is enabled in storage.
   */
  function _isExecutorFullPermission(address _executor) internal view returns (bool _fullPermission) {
    _fullPermission = _executors[_executor][_FULL_PERMISSION];
  }
}
