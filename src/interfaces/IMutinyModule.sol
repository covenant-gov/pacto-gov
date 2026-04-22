// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IQuiescent} from 'interfaces/IQuiescent.sol';

/**
 * @title IMutinyModule
 * @author Pacto
 * @notice Crew-driven mutiny module: snapshot electorate, one vote per crew member, strict 51%
 *         majority of the snapshot to replace the captain hat wearer.
 * @dev Orchestrates `Hats.transferHat` on the captain hat and calls `IQuartermaster` for crew
 *      mint / burn / hand-off during succession. The 51% threshold is hard-coded — there are no
 *      governance-mutable parameters on this module. A captain may also resign voluntarily via
 *      `captainResign` (bypassing the vote entirely), but not while a mutiny is already active.
 */
interface IMutinyModule is IQuiescent {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A mutiny round was opened.
   * @param _mutinyId Round identifier.
   * @param _proposer Crew member that opened the round.
   * @param _proposedNewCaptain Successor if the mutiny passes.
   * @param _snapshot Snapshot size of eligible crew at `startMutiny` time.
   */
  event MutinyStarted(
    uint256 indexed _mutinyId, address indexed _proposer, address indexed _proposedNewCaptain, uint256 _snapshot
  );

  /**
   * @notice A crew member cast a yea vote.
   * @dev A "nay" is simply the absence of a vote; mutiny uses a strict 51%-of-snapshot yea threshold.
   * @param _mutinyId Round identifier.
   * @param _voter Crew voter.
   */
  event MutinyVoteCast(uint256 indexed _mutinyId, address indexed _voter);

  /**
   * @notice Mutiny succeeded and the captain hat was transferred.
   * @param _mutinyId Round identifier.
   * @param _formerCaptain Previous captain wearer.
   * @param _newCaptain Final wearer of the captain hat.
   */
  event MutinyExecuted(uint256 indexed _mutinyId, address indexed _formerCaptain, address indexed _newCaptain);

  /**
   * @notice The captain voluntarily handed the captain hat to a new wearer.
   * @param _formerCaptain Address that held the captain hat.
   * @param _newCaptain Address that received the captain hat.
   */
  event CaptainResigned(address indexed _formerCaptain, address indexed _newCaptain);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A mutiny round is already active.
   */
  error MutinyModule_AlreadyActive();

  /**
   * @notice No active mutiny exists for the requested id.
   */
  error MutinyModule_NoActiveMutiny();

  /**
   * @notice Voter has already voted in this round.
   * @param _voter Address that attempted a duplicate vote.
   */
  error MutinyModule_AlreadyVoted(address _voter);

  /**
   * @notice Voter was not in the snapshot electorate for this round.
   * @param _voter Address that failed the snapshot check.
   */
  error MutinyModule_NotInSnapshot(address _voter);

  /**
   * @notice The 51% threshold has not yet been reached.
   * @param _yeas Current yea count.
   * @param _snapshot Snapshot size fixed when the round opened.
   */
  error MutinyModule_ThresholdNotReached(uint256 _yeas, uint256 _snapshot);

  /**
   * @notice A required address argument was zero.
   */
  error MutinyModule_ZeroAddress();

  /**
   * @notice The specified new captain already wears the captain hat or matches the current captain.
   * @param _target The rejected address.
   */
  error MutinyModule_SameCaptain(address _target);

  /**
   * @notice The cached Quartermaster peer no longer wears `QUARTERMASTER_ROLE_HAT_ID`; a role-hat
   *         upgrade has invalidated this clone's view of its peer and this clone must itself be
   *         upgraded via the ceremony before further mutiny operations can proceed.
   * @param _quartermaster The stale peer address.
   */
  error MutinyModule_StaleQuartermaster(address _quartermaster);

  /**
   * @notice The cached captain address is no longer the captain-hat wearer (e.g. the captain
   *         renounced the hat directly via Hats). Safe recovery requires re-bootstrapping the
   *         module; this guard prevents mid-flight state divergence.
   * @param _captain The stale captain address.
   */
  error MutinyModule_StaleCaptain(address _captain);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Open a mutiny round. Crew-hat-gated.
   * @dev Fixes the snapshot electorate to the current crew supply and toggles Quartermaster mutiny mode.
   * @param _proposedNewCaptain Non-zero successor for the captain hat.
   */
  function startMutiny(address _proposedNewCaptain) external;

  /**
   * @notice Cast a yea vote in the active mutiny. Crew-hat-gated and snapshot-constrained.
   * @dev No "nay" path; abstention = opposition under the 51% snapshot rule.
   * @param _mutinyId Active mutiny id.
   */
  function castVote(uint256 _mutinyId) external;

  /**
   * @notice Finalize the mutiny if the 51% threshold is met. Permissionless.
   * @param _mutinyId Round to execute.
   */
  function executeMutiny(uint256 _mutinyId) external;

  /**
   * @notice Captain's voluntary succession — transfers the captain hat to `_newCaptain`. Captain-hat-gated.
   * @dev Reverts if a mutiny is active; `_newCaptain` must be non-zero.
   * @param _newCaptain Address that receives the captain hat.
   */
  function captainResign(address _newCaptain) external;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Id of the currently active mutiny, or zero if none.
   * @return _id The active mutiny id.
   */
  function activeMutinyId() external view returns (uint256 _id);

  /**
   * @notice Read the state of a mutiny round.
   * @param _id Round identifier.
   * @return _proposedNewCaptain Successor if the round succeeds.
   * @return _startedAt Timestamp the round opened.
   * @return _snapshot Snapshot size of eligible crew.
   * @return _yeas Yea vote count.
   * @return _executed Whether the round has already been executed.
   */
  function mutiny(uint256 _id)
    external
    view
    returns (address _proposedNewCaptain, uint64 _startedAt, uint64 _snapshot, uint64 _yeas, bool _executed);

  /**
   * @notice Whether `_voter` has cast a vote in `_mutinyId`.
   * @param _mutinyId Round identifier.
   * @param _voter Voter address.
   * @return _voted True if the voter has voted in this round.
   */
  function hasVoted(uint256 _mutinyId, address _voter) external view returns (bool _voted);

  /**
   * @notice Whether `_voter` was part of the snapshot electorate for `_mutinyId`.
   * @param _mutinyId Round identifier.
   * @param _voter Voter address.
   * @return _inSnapshot True if in the snapshot.
   */
  function isInSnapshot(uint256 _mutinyId, address _voter) external view returns (bool _inSnapshot);

  /**
   * @notice Captain hat id.
   * @return _captainHatId The captain hat id.
   */
  function CAPTAIN_HAT_ID() external view returns (uint256 _captainHatId);

  /**
   * @notice Crew hat id.
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
   * @notice Current captain-hat wearer as tracked by this module.
   * @dev Updated by `captainResign` and `executeMutiny`. MutinyModule is the only admin of the
   *      captain hat under the Nave Pirata hat tree, so all legitimate captain transitions flow
   *      through this module and keep the cache authoritative.
   * @return _captain Current captain address.
   */
  function captain() external view returns (address _captain);

  /**
   * @notice Quartermaster clone address used for mutiny-driven crew mint / hand-off calls.
   * @dev Captured at `initialize`; verified to still wear `QUARTERMASTER_ROLE_HAT_ID` at every
   *      outbound peer call so a stale pointer (e.g. after a QuartermasterRole upgrade ceremony)
   *      reverts rather than silently calls the wrong contract. Re-deploying MutinyModule
   *      alongside a Quartermaster upgrade is the canonical recovery path.
   * @return _quartermaster Quartermaster peer address.
   */
  function quartermaster() external view returns (address _quartermaster);
}
