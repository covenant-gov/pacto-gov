// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IQuiescent} from 'interfaces/abstracts/IQuiescent.sol';

/**
 * @title ISquadAdmin
 * @author Pacto
 * @notice Captain-only product admin (executors + `isExecutor` v1). UUPS upgrades are captain-gated, not two-body.
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
   * @notice UUPS `upgradeToAndCall`; captain-only. `_data` optional post-upgrade call
   * @param _newImplementation New implementation
   * @param _data Optional call data after upgrade
   */
  function upgradeToAndCall(address _newImplementation, bytes memory _data) external payable;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice v1 gasless gate: enabled executors (more predicates later)
   * @param _executor Who to query
   * @return _enabled Whether enabled
   */
  function isExecutor(address _executor) external view returns (bool _enabled);

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
