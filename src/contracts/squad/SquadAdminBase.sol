// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISquadAdminBase} from 'interfaces/squad/ISquadAdminBase.sol';

abstract contract SquadAdminBase is ISquadAdminBase {
  /*///////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdminBase
  // forge-lint: disable-next-line(unsafe-typecast) — ASCII labels fit in `bytes32` (Solidity left-padding).
  bytes32 public constant FULL_PERMISSION = bytes32('FULL');

  /// @inheritdoc ISquadAdminBase
  // forge-lint: disable-next-line(unsafe-typecast) — ASCII labels fit in `bytes32` (Solidity left-padding).
  bytes32 public constant PAUSE_PERMISSION = bytes32('PAUSE');

  /// @notice Bit 0 of `_executorFlags`: `FULL_PERMISSION`.
  uint8 internal constant _FLAG_FULL = 1;
  /// @notice Bit 1 of `_executorFlags`: `PAUSE_PERMISSION`.
  uint8 internal constant _FLAG_PAUSE = 2;

  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @notice Mapping of executor address → app role → enabled flag (sentinels use `_executorFlags`).
  mapping(address account => mapping(bytes32 role => bool enabled)) internal _executors;

  /// @notice Packed PAUSE/FULL bits per executor (`_FLAG_PAUSE` / `_FLAG_FULL`).
  mapping(address account => uint8 flags) internal _executorFlags;

  /// @notice 1-based index into `_roles` (0 = not in catalog).
  mapping(bytes32 role => uint256 index) internal _roleIndex;

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
    _enforceRoleExists(_role);
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
    if (_role == FULL_PERMISSION || _role == PAUSE_PERMISSION) revert SquadAdminBase_RoleAlreadyExists();
    if (_roleExists(_role)) revert SquadAdminBase_RoleAlreadyExists();
    _roles.push(_role);
    _roleIndex[_role] = _roles.length;
  }

  /// @inheritdoc ISquadAdminBase
  function deleteRole(bytes32 _role) external isAllowed roleExists(_role) {
    if (_role == FULL_PERMISSION || _role == PAUSE_PERMISSION) revert SquadAdminBase_ReservedRole();

    uint256 _idx1 = _roleIndex[_role];
    uint256 _idx = _idx1 - 1;
    uint256 _last = _roles.length - 1;
    if (_idx != _last) {
      bytes32 _moved = _roles[_last];
      _roles[_idx] = _moved;
      _roleIndex[_moved] = _idx1;
    }
    _roles.pop();
    delete _roleIndex[_role];
  }

  /// @inheritdoc ISquadAdminBase
  function enableExecutor(address _executor, bytes32 _role) external isAllowed roleExists(_role) {
    if (_executor == address(0)) revert SquadAdminBase_ZeroAddress();
    if (_role == FULL_PERMISSION) {
      if (!_setExecutorFlag(_executor, _FLAG_FULL, true)) return;
    } else if (_role == PAUSE_PERMISSION) {
      if (!_setExecutorFlag(_executor, _FLAG_PAUSE, true)) return;
    } else {
      if (_executors[_executor][_role]) return;
      _executors[_executor][_role] = true;
    }
    emit ExecutorEnabled(_executor, _role);
  }

  /// @inheritdoc ISquadAdminBase
  function enableFullPermission(address _executor, bool _enable) external isAllowed {
    if (!_setExecutorFlag(_executor, _FLAG_FULL, _enable)) return;
    emit FullPermissionEnabled(_executor, _enable);
  }

  /// @inheritdoc ISquadAdminBase
  function disableExecutor(address _executor, bytes32 _role) external isAllowed roleExists(_role) {
    if (_role == FULL_PERMISSION) {
      if (!_setExecutorFlag(_executor, _FLAG_FULL, false)) return;
    } else if (_role == PAUSE_PERMISSION) {
      if (!_setExecutorFlag(_executor, _FLAG_PAUSE, false)) return;
    } else {
      if (!_executors[_executor][_role]) return;
      _executors[_executor][_role] = false;
    }
    emit ExecutorDisabled(_executor, _role);
  }

  /// @inheritdoc ISquadAdminBase
  function pauseExecutor(address _executor, bool _pause) external isAllowed {
    if (!_setExecutorFlag(_executor, _FLAG_PAUSE, _pause)) return;
    emit ExecutorPaused(_executor, _pause);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdminBase
  function hasExecutorRole(address _executor, bytes32 _role) external view roleExists(_role) returns (bool _enabled) {
    uint8 _flags = _executorFlags[_executor];
    if ((_flags & _FLAG_PAUSE) != 0) _enabled = false;
    else _enabled = ((_flags & _FLAG_FULL) != 0) || _executors[_executor][_role];
  }

  /// @inheritdoc ISquadAdminBase
  function isExecutorFullPermission(address _executor) external view returns (bool _fullPermission) {
    uint8 _flags = _executorFlags[_executor];
    if ((_flags & _FLAG_PAUSE) != 0) _fullPermission = false;
    else _fullPermission = (_flags & _FLAG_FULL) != 0;
  }

  /// @inheritdoc ISquadAdminBase
  function isExecutorPaused(address _executor) external view returns (bool _paused) {
    _paused = (_executorFlags[_executor] & _FLAG_PAUSE) != 0;
  }

  /// @inheritdoc ISquadAdminBase
  function roleCount() external view returns (uint256 _count) {
    _count = _roles.length;
  }

  /// @inheritdoc ISquadAdminBase
  function roleAt(uint256 _index) external view returns (bytes32 _role) {
    _role = _roles[_index];
  }

  /// @inheritdoc ISquadAdminBase
  function roles() external view returns (bytes32[] memory _catalog) {
    _catalog = _roles;
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Sets or clears a bit in `_executorFlags`.
   * @param _executor Account to update.
   * @param _flag `_FLAG_FULL` or `_FLAG_PAUSE`.
   * @param _enable True to set the bit; false to clear it.
   * @return _changed Whether storage changed.
   */
  function _setExecutorFlag(address _executor, uint8 _flag, bool _enable) internal returns (bool _changed) {
    uint8 _flags = _executorFlags[_executor];
    uint8 _next = _enable ? uint8(_flags | _flag) : uint8(_flags & ~_flag);
    if (_next == _flags) return false;
    _executorFlags[_executor] = _next;
    _changed = true;
  }

  /**
   * @notice Checks if a role exists.
   * @param _role Role to check.
   * @return _exists Whether the role exists.
   */
  function _roleExists(bytes32 _role) internal view returns (bool _exists) {
    if (_role == FULL_PERMISSION || _role == PAUSE_PERMISSION) return true;
    _exists = _roleIndex[_role] != 0;
  }

  /**
   * @notice Reverts if a role does not exist.
   * @param _role Role to check.
   */
  function _enforceRoleExists(bytes32 _role) internal view {
    if (!_roleExists(_role)) revert SquadAdminBase_RoleDoesNotExist();
  }

  /// @notice Hook for access control on `isAllowed`; implementations revert when denied (e.g. `HatGated_NotHatWearer` or `SquadAdminExt_NotAllowed`).
  function _requireAllowed() internal view virtual;
}
