// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ISquadAdminBase
 * @author Pacto
 * @notice Executor roster, FULL / PAUSE sentinels, and role queries shared by squad-admin implementations.
 */
interface ISquadAdminBase {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice An executor was granted an application-level role.
   * @param _executor Address newly allowed for this `_role`.
   * @param _role App-defined role id; `bytes32("FULL")` grants every role; `bytes32("PAUSE")` suspends all.
   */
  event ExecutorEnabled(address indexed _executor, bytes32 indexed _role);

  /**
   * @notice An executor was granted full permission.
   * @param _executor Address that was granted full permission.
   * @param _enable Whether the executor was granted full permission.
   */
  event FullPermissionEnabled(address indexed _executor, bool _enable);

  /**
   * @notice An executor lost an application-level role.
   * @param _executor Address that lost this `_role`.
   * @param _role App-defined role id that was cleared.
   */
  event ExecutorDisabled(address indexed _executor, bytes32 indexed _role);

  /**
   * @notice An executor was paused.
   * @param _executor Address that was paused.
   * @param _pause Whether the executor was paused.
   */
  event ExecutorPaused(address indexed _executor, bool _pause);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice A required address argument was zero.
  error SquadAdminBase_ZeroAddress();
  /// @notice A required role argument does not exist.
  error SquadAdminBase_RoleDoesNotExist();
  /// @notice A required role argument already exists.
  error SquadAdminBase_RoleAlreadyExists();
  /// @notice `bytes32("FULL")` / `bytes32("PAUSE")` cannot be removed from the catalog.
  error SquadAdminBase_ReservedRole();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Register an app-defined role before it may be used with `enableExecutor` / `hasExecutorRole`.
   * @param _role Non-zero role id; must not duplicate an existing registration.
   */
  function createRole(bytes32 _role) external;

  /**
   * @notice Remove a registered role from the catalog (does not clear per-executor flags in `_executors`).
   * @param _role Role id previously registered via `createRole`.
   */
  function deleteRole(bytes32 _role) external;

  /**
   * @notice Enable an executor for an app role. Access-gated by the implementation.
   * @param _executor Address to enable.
   * @param _role App role id from the product; `bytes32("FULL")` for all roles; `bytes32("PAUSE")` for captain kill-switch.
   */
  function enableExecutor(address _executor, bytes32 _role) external;

  /**
   * @notice Enable full permission for an executor. Access-gated by the implementation.
   * @param _executor Address to enable.
   * @param _enable Whether to enable full permission.
   */
  function enableFullPermission(address _executor, bool _enable) external;

  /**
   * @notice Disable an executor for a specific app role. Access-gated by the implementation.
   * @param _executor Address to update.
   * @param _role Role to revoke (including `bytes32("PAUSE")` to lift a global freeze).
   */
  function disableExecutor(address _executor, bytes32 _role) external;

  /**
   * @notice Pause an executor. Access-gated by the implementation.
   * @param _executor Address to pause.
   * @param _pause Whether to pause the executor.
   */
  function pauseExecutor(address _executor, bool _pause) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Whether `_executor` may act under `_role` for app gating.
   * @dev False while `isExecutorPaused` is true. Otherwise true if `isExecutorFullPermission` is true or
   *      `_role` is explicitly enabled.
   * @param _executor Account queried for executor permissions.
   * @param _role App role id to check.
   * @return _enabled Whether that account may act under `_role` under those rules.
   */
  function hasExecutorRole(address _executor, bytes32 _role) external view returns (bool _enabled);

  /**
   * @notice Whether `bytes32("FULL")` is enabled for `_executor` (superseded by pause for `hasExecutorRole`).
   * @param _executor Account queried.
   * @return _fullPermission Whether the full-permission sentinel is set.
   */
  function isExecutorFullPermission(address _executor) external view returns (bool _fullPermission);

  /**
   * @notice Whether `bytes32("PAUSE")` is set for `_executor` (captain kill-switch).
   * @param _executor Account queried.
   * @return _paused Whether the pause sentinel is set.
   */
  function isExecutorPaused(address _executor) external view returns (bool _paused);

  /**
   * @notice Sentinel role id that grants every registered role for `hasExecutorRole`.
   * @return _full `bytes32("FULL")`.
   */
  function FULL_PERMISSION() external view returns (bytes32 _full);

  /**
   * @notice Sentinel role id that pauses an executor for every `hasExecutorRole` check.
   * @return _pause `bytes32("PAUSE")`.
   */
  function PAUSE_PERMISSION() external view returns (bytes32 _pause);

  /**
   * @notice Number of app-defined roles in the catalog (excludes `FULL` / `PAUSE`).
   * @return _count Catalog length.
   */
  function roleCount() external view returns (uint256 _count);

  /**
   * @notice Role id at catalog index `_index`. Reverts if `_index >= roleCount()`.
   * @param _index Zero-based index.
   * @return _role Registered role id.
   */
  function roleAt(uint256 _index) external view returns (bytes32 _role);

  /**
   * @notice Full app-defined role catalog (excludes `FULL` / `PAUSE`).
   * @return _roles Registered role ids.
   */
  function roles() external view returns (bytes32[] memory _roles);
}
