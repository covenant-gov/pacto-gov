// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IQuiescent} from 'interfaces/IQuiescent.sol';

/**
 * @title ISquadAdmin
 * @author Pacto
 * @notice Captain-controlled application-level admin surface for a squad. v1 ships a minimal
 *         executor allow-list and gasless governance predicates.
 * @dev UUPS-upgradeable implementation: `upgradeToAndCall` is captain-hat-gated. The captain
 *      alone authorises SquadAdmin upgrades — SquadAdmin changes do not flow through the
 *      two-body vote, by design. Phase 11 expands this interface with EIP-712 Signed App Actions,
 *      per-channel policies, and richer predicates.
 */
interface ISquadAdmin is IQuiescent {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice An executor was granted application-level powers.
   * @param _executor Address newly allowed to execute.
   */
  event ExecutorEnabled(address indexed _executor);

  /**
   * @notice An executor's application-level powers were revoked.
   * @param _executor Address that lost executor status.
   */
  event ExecutorDisabled(address indexed _executor);

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

  /// @notice Caller is not an enabled executor.
  error SquadAdmin_NotExecutor();

  /// @notice The target is already an enabled executor.
  error SquadAdmin_AlreadyExecutor();

  /// @notice A required address argument was zero.
  error SquadAdmin_ZeroAddress();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Enable an executor. Captain-hat-gated.
   * @param _executor Address to enable.
   */
  function enableExecutor(address _executor) external;

  /**
   * @notice Disable an executor. Captain-hat-gated.
   * @param _executor Address to disable.
   */
  function disableExecutor(address _executor) external;

  /**
   * @notice UUPS upgrade. Captain-hat-gated.
   * @dev Standard UUPS `upgradeToAndCall` semantics; data location matches OpenZeppelin's
   *      `UUPSUpgradeable.upgradeToAndCall(address,bytes memory)` so this interface can be
   *      satisfied by a single overriding function.
   * @param _newImplementation New logic contract address.
   * @param _data Optional initializer calldata; pass empty bytes for no call.
   */
  function upgradeToAndCall(address _newImplementation, bytes memory _data) external payable;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Whether an address is currently an enabled executor.
   * @dev Single gasless governance predicate for v1. Phase 11 expands to richer role / channel predicates.
   * @param _executor Address to query.
   * @return _enabled True if enabled.
   */
  function isExecutor(address _executor) external view returns (bool _enabled);

  /**
   * @notice Captain hat id.
   * @return _captainHatId The captain hat id.
   */
  function CAPTAIN_HAT_ID() external view returns (uint256 _captainHatId);

  /**
   * @notice Squad-admin hat id.
   * @return _squadAdminHatId The squad-admin hat id worn by this proxy.
   */
  function SQUAD_ADMIN_HAT_ID() external view returns (uint256 _squadAdminHatId);
}
