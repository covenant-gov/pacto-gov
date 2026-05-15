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

  /// @notice Mapping of role → enabled flag.
  mapping(bytes32 role => bool enabled) internal _enabledRoles;

  /// @notice list of all roles that can be enabled
  bytes32[] internal _roles;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Runs the body only if `_role` exists.
   * @param _role Role id that must be registered (or sentinel `FULL` / `PAUSE`).
   */
  modifier roleExists(bytes32 _role) {
    if (!_roleExists(_role)) revert SquadAdminBase_RoleDoesNotExist();
    _;
  }

  /// @notice Runs the body only if `msg.sender` wears the captain hat.
  modifier isAllowed() {
    _requireAllowed();
    _;
  }

  /*///////////////////////////////////////////////////////////////
                            ACCESS-GATED LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdminBase
  function createRole(bytes32 _role) external isAllowed {
    if (_role == bytes32(0)) revert SquadAdminBase_ZeroAddress();
    if (_role == _FULL_PERMISSION || _role == _PAUSE_PERMISSION) revert SquadAdminBase_RoleAlreadyExists();
    if (_roleExists(_role)) revert SquadAdminBase_RoleAlreadyExists();
    _enabledRoles[_role] = true;
    _roles.push(_role);
  }

  /// @inheritdoc ISquadAdminBase
  function deleteRole(bytes32 _role) external isAllowed roleExists(_role) {
    if (_role == _FULL_PERMISSION || _role == _PAUSE_PERMISSION) revert SquadAdminBase_ReservedRole();
    _enabledRoles[_role] = false;
    uint256 _len = _roles.length;
    for (uint256 i = 0; i < _len; ++i) {
      if (_roles[i] == _role) {
        _roles[i] = _roles[_len - 1];
        _roles.pop();
        break;
      }
    }
  }

  /// @inheritdoc ISquadAdminBase
  function enableExecutor(address _executor, bytes32 _role) external isAllowed roleExists(_role) {
    if (_executor == address(0)) revert SquadAdminBase_ZeroAddress();
    _executors[_executor][_role] = true;
    emit ExecutorEnabled(_executor, _role);
  }

  /// @inheritdoc ISquadAdminBase
  function enableFullPermission(address _executor, bool _enable) external isAllowed {
    _executors[_executor][_FULL_PERMISSION] = _enable;
    emit FullPermissionEnabled(_executor, _enable);
  }

  /// @inheritdoc ISquadAdminBase
  function disableExecutor(address _executor, bytes32 _role) external isAllowed roleExists(_role) {
    _executors[_executor][_role] = false;
    emit ExecutorDisabled(_executor, _role);
  }

  /// @inheritdoc ISquadAdminBase
  function pauseExecutor(address _executor, bool _pause) external isAllowed {
    _executors[_executor][_PAUSE_PERMISSION] = _pause;
    emit ExecutorPaused(_executor, _pause);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdminBase
  function hasExecutorRole(address _executor, bytes32 _role) external view roleExists(_role) returns (bool _enabled) {
    if (_isExecutorPaused(_executor)) _enabled = false;
    else _enabled = _isExecutorFullPermission(_executor) || _executors[_executor][_role];
  }

  /// @inheritdoc ISquadAdminBase
  function isExecutorFullPermission(address _executor) external view returns (bool _fullPermission) {
    _fullPermission = _isExecutorFullPermission(_executor);
  }

  /// @inheritdoc ISquadAdminBase
  function isExecutorPaused(address _executor) external view returns (bool _paused) {
    _paused = _isExecutorPaused(_executor);
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/
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

  /**
   * @notice Checks if a role exists.
   * @param _role Role to check.
   * @return _exists Whether the role exists.
   */
  function _roleExists(bytes32 _role) internal view returns (bool _exists) {
    if (_role == _FULL_PERMISSION || _role == _PAUSE_PERMISSION) return true;
    _exists = _enabledRoles[_role];
  }

  /// @notice Hook for access control on `isAllowed`; implementations revert when denied (e.g. `HatGated_NotHatWearer` or `SquadAdminExt_NotAllowed`).
  function _requireAllowed() internal view virtual;
}
