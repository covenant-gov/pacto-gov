// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IQuiescent} from 'interfaces/abstracts/IQuiescent.sol';

/**
 * @title ISquadAdmin
 * @author Pacto
 * @notice Captain-only product admin (executors + role `hasExecutorRole`, FULL / PAUSE sentinels). UUPS upgrades are captain-gated, not two-body.
 *         More predicates / signed actions come in later versions
 */
interface ISquadAdmin is IQuiescent {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Parameters required to initialize a SquadAdmin proxy.
   * @param captainHatId Captain hat id that gates executor management and UUPS upgrades.
   * @param squadAdminHatId Squad-admin hat id worn by this proxy (informational for v1; reserved for richer app-level checks later).
   */
  struct InitParams {
    uint256 captainHatId;
    uint256 squadAdminHatId;
  }

  /**
   * @notice ERC-7201 namespaced storage layout for SquadAdmin v1.
   * @dev New fields may be appended in later implementation versions; never reordered or
   *      removed, so existing proxies upgrade-in-place without state migration. Kept on the
   *      implementation because Solidity interface structs cannot contain mappings.
   * @param captainHatId Captain hat id used for gate checks.
   * @param squadAdminHatId Squad-admin hat id worn by this proxy.
   * @param executors Mapping of address → role → enabled-flag for v1's single predicate.
   * @note `bytes32("FULL")` grants every role in `hasExecutorRole`. `bytes32("PAUSE")` freezes an
   *      executor: `hasExecutorRole` is false for every role until pause is cleared, without revoking each slot.
   * @custom:storage-location erc7201:pacto.squadadmin.v1
   */
  struct SquadAdminStorageV1 {
    uint256 captainHatId;
    uint256 squadAdminHatId;
    mapping(address _executor => mapping(bytes32 role => bool _enabled)) executors;
  }

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
   * @notice An executor lost an application-level role.
   * @param _executor Address that lost this `_role`.
   * @param _role App-defined role id that was cleared.
   */
  event ExecutorDisabled(address indexed _executor, bytes32 indexed _role);

  /**
   * @notice The UUPS implementation was upgraded.
   * @param _newImplementation New logic contract address.
   */
  event Upgraded(address indexed _newImplementation);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Caller is not the current captain.
  error SquadAdmin_NotCaptain();
  /// @notice The executor does not have this role enabled.
  error SquadAdmin_NotExecutor();
  /// @notice The executor already has this role enabled.
  error SquadAdmin_AlreadyExecutor();
  /// @notice A required address argument was zero.
  error SquadAdmin_ZeroAddress();

  /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice One-shot proxy initializer; seeds the captain and squad-admin hat ids.
   * @param _p Bootstrap parameters.
   */
  function initialize(InitParams calldata _p) external;

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Enable an executor for an app role. Captain-hat-gated.
   * @param _executor Address to enable.
   * @param _role App role id from the product; `bytes32("FULL")` for all roles; `bytes32("PAUSE")` for captain kill-switch.
   */
  function enableExecutor(address _executor, bytes32 _role) external;

  /**
   * @notice Disable an executor for a specific app role. Captain-hat-gated.
   * @param _executor Address to update.
   * @param _role Role to revoke (including `bytes32("PAUSE")` to lift a global freeze).
   */
  function disableExecutor(address _executor, bytes32 _role) external;

  /**
   * @notice UUPS `upgradeToAndCall`; captain-only. `_data` optional post-upgrade call
   * @param _newImplementation New implementation
   * @param _data Optional call data after upgrade
   */
  function upgradeToAndCall(address _newImplementation, bytes memory _data) external payable;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
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
   * @notice Captain hat id
   * @return _captainHatId Hat id
   */
  function captainHatId() external view returns (uint256 _captainHatId);

  /**
   * @notice Squad admin hat id (this proxy wears it)
   * @return _squadAdminHatId Hat id
   */
  function squadAdminHatId() external view returns (uint256 _squadAdminHatId);
}
