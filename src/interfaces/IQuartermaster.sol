// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IQuiescent} from 'interfaces/IQuiescent.sol';

/**
 * @title IQuartermaster
 * @author Pacto
 * @notice Timelocked crew onboarding and offboarding; administers the crew hat in Hats Protocol.
 * @dev Captain-gated request / cancel pattern with permissionless execution after the configured
 *      `crewChangeDelay`. While `mutinyActive`, onboarding is frozen and the MutinyModule drives
 *      crew mint / hand-off paths directly. Parameter setters are gated by the Treasury Authority
 *      role hat so governance changes always flow through the two-body vote.
 */
interface IQuartermaster is IQuiescent {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A crew add was scheduled by the captain.
   * @param _candidate Address that may receive the crew hat after the delay.
   * @param _executableAt Timestamp when `executeAddCrew` becomes valid.
   */
  event CrewAddRequested(address indexed _candidate, uint256 _executableAt);

  /**
   * @notice A scheduled crew add was executed.
   * @param _candidate Address that received the crew hat.
   */
  event CrewAddExecuted(address indexed _candidate);

  /**
   * @notice A scheduled crew add was cancelled by the captain.
   * @param _candidate Address whose pending add was cleared.
   */
  event CrewAddCancelled(address indexed _candidate);

  /**
   * @notice A crew removal was scheduled by the captain.
   * @param _crew Address whose crew hat may be revoked after the delay.
   * @param _executableAt Timestamp when `executeRemoveCrew` becomes valid.
   */
  event CrewRemoveRequested(address indexed _crew, uint256 _executableAt);

  /**
   * @notice A scheduled crew removal was executed.
   * @param _crew Address that lost the crew hat.
   */
  event CrewRemoveExecuted(address indexed _crew);

  /**
   * @notice A scheduled crew removal was cancelled by the captain.
   * @param _crew Address whose pending removal was cleared.
   */
  event CrewRemoveCancelled(address indexed _crew);

  /**
   * @notice The MutinyModule minted a crew hat to a former captain after a successful mutiny.
   * @param _formerCaptain Address that received the crew hat.
   */
  event CrewMintedFromMutiny(address indexed _formerCaptain);

  /**
   * @notice The MutinyModule handed the new captain's existing crew hat to the former captain.
   * @param _formerCaptain Address that received the crew hat.
   * @param _newCaptain Address whose crew hat was transferred.
   */
  event CrewHandoffForMutiny(address indexed _formerCaptain, address indexed _newCaptain);

  /**
   * @notice Mutiny mode toggled (disables captain-driven onboarding while active).
   * @param _active True when a mutiny is in progress.
   */
  event MutinyActiveSet(bool _active);

  /**
   * @notice The crew change delay parameter was updated via a Treasury Authority proposal.
   * @param _oldValue Previous delay, in seconds.
   * @param _newValue New delay, in seconds.
   */
  event CrewChangeDelayUpdated(uint256 _oldValue, uint256 _newValue);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Crew onboarding is blocked while a mutiny is active.
  error Quartermaster_MutinyActive();

  /**
   * @notice No pending operation exists for the target.
   * @param _target Address whose pending entry was expected but missing.
   */
  error Quartermaster_NotPending(address _target);

  /**
   * @notice The scheduled delay has not yet elapsed for the target.
   * @param _target Address whose pending entry is still locked.
   * @param _executableAt Timestamp after which execution becomes valid.
   */
  error Quartermaster_StillLocked(address _target, uint256 _executableAt);

  /**
   * @notice The target already wears the crew hat.
   * @param _target Address that already holds the crew hat.
   */
  error Quartermaster_AlreadyCrew(address _target);

  /**
   * @notice The candidate currently wears the captain hat (captain ∩ crew = ∅ invariant).
   * @param _target Address that wears the captain hat.
   */
  error Quartermaster_CandidateIsCaptain(address _target);

  /**
   * @notice The target does not wear the crew hat.
   * @param _target Address expected to wear the crew hat.
   */
  error Quartermaster_NotCrew(address _target);

  /// @notice The crew hat has reached its max supply cap.
  error Quartermaster_CrewFull();

  /// @notice A required address argument was zero.
  error Quartermaster_ZeroAddress();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Schedule minting the crew hat to `_candidate` after `crewChangeDelay`. Captain-gated.
   * @dev Reverts if a mutiny is active or the candidate already wears crew / is the captain.
   * @param _candidate Address to receive the crew hat.
   */
  function requestAddCrew(address _candidate) external;

  /**
   * @notice Cancel a previously requested crew add. Captain-gated.
   * @param _candidate Address whose pending add should be cleared.
   */
  function cancelAddCrew(address _candidate) external;

  /**
   * @notice Execute a scheduled crew add after the delay. Permissionless.
   * @param _candidate Address to receive the crew hat.
   */
  function executeAddCrew(address _candidate) external;

  /**
   * @notice Schedule burning the crew hat from `_crew` after `crewChangeDelay`. Captain-gated.
   * @dev Reverts if a mutiny is active or the target does not wear the crew hat.
   * @param _crew Address to remove from crew.
   */
  function requestRemoveCrew(address _crew) external;

  /**
   * @notice Cancel a previously requested crew removal. Captain-gated.
   * @param _crew Address whose pending removal should be cleared.
   */
  function cancelRemoveCrew(address _crew) external;

  /**
   * @notice Execute a scheduled crew removal after the delay. Permissionless.
   * @param _crew Address to remove from crew.
   */
  function executeRemoveCrew(address _crew) external;

  /**
   * @notice Mint one crew hat to `_formerCaptain` with no delay (mutiny / succession path).
   * @dev Only callable by the MutinyRole hat wearer; used to seat a deposed human captain as crew.
   * @param _formerCaptain Recipient of the crew hat.
   */
  function mintCrewFromMutiny(address _formerCaptain) external;

  /**
   * @notice Hand the existing crew hat from the elected successor to the former captain in one step.
   * @dev Only callable by the MutinyRole hat wearer. Used when the new captain was already crew.
   * @param _formerCaptain Previous captain (receives crew).
   * @param _newCaptain New captain (must not retain the crew hat after execution).
   */
  function crewHandoffForMutiny(address _formerCaptain, address _newCaptain) external;

  /**
   * @notice Toggle mutiny mode to guard captain-driven onboarding.
   * @dev Only callable by the MutinyRole hat wearer.
   * @param _active True to block captain onboarding while a mutiny runs.
   */
  function setMutinyActive(bool _active) external;

  /**
   * @notice Update the crew change delay. TreasuryAuthorityRole-gated.
   * @dev Must fall within the `GovernanceParams` bounds.
   * @param _newValue New delay in seconds.
   */
  function setCrewChangeDelay(uint256 _newValue) external;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Seconds between scheduling and executing a crew add / remove.
   * @return _delay The current delay value.
   */
  function crewChangeDelay() external view returns (uint256 _delay);

  /**
   * @notice Whether a mutiny is currently active.
   * @return _active True if mutiny is active.
   */
  function mutinyActive() external view returns (bool _active);

  /**
   * @notice Timestamp after which `executeAddCrew` succeeds, or zero if none.
   * @param _candidate Candidate address.
   * @return _executableAt Unix timestamp, or zero.
   */
  function pendingCrewAddAt(address _candidate) external view returns (uint256 _executableAt);

  /**
   * @notice Timestamp after which `executeRemoveCrew` succeeds, or zero if none.
   * @param _crew Crew address.
   * @return _executableAt Unix timestamp, or zero.
   */
  function pendingCrewRemoveAt(address _crew) external view returns (uint256 _executableAt);

  /**
   * @notice Captain hat id for access-control checks.
   * @return _captainHatId The captain hat id.
   */
  function CAPTAIN_HAT_ID() external view returns (uint256 _captainHatId);

  /**
   * @notice Crew hat id administered by this contract.
   * @return _crewHatId The crew hat id.
   */
  function CREW_HAT_ID() external view returns (uint256 _crewHatId);

  /**
   * @notice Role hat worn by the active MutinyModule clone.
   * @return _mutinyRoleHatId The MutinyRole hat id.
   */
  function MUTINY_ROLE_HAT_ID() external view returns (uint256 _mutinyRoleHatId);

  /**
   * @notice Role hat worn by the active Quartermaster clone.
   * @return _quartermasterRoleHatId The QuartermasterRole hat id.
   */
  function QUARTERMASTER_ROLE_HAT_ID() external view returns (uint256 _quartermasterRoleHatId);

  /**
   * @notice Role hat worn by the active TreasuryAuthority clone.
   * @return _treasuryAuthorityRoleHatId The TreasuryAuthorityRole hat id.
   */
  function TREASURY_AUTHORITY_ROLE_HAT_ID() external view returns (uint256 _treasuryAuthorityRoleHatId);
}
