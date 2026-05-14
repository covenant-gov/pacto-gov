// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IQuiescent} from 'interfaces/abstracts/IQuiescent.sol';

/**
 * @title IMutinyModule
 * @author Pacto
 * @notice 51% of snapshot crew (yeas) to replace the captain, or `captainResign` if no open mutiny. Captain hat
 *         `IHatsEligibility`; no tunable params. Drives `transferHat` and QM for crew
 */
interface IMutinyModule is IQuiescent {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Parameters required to initialize a MutinyModule clone.
   * @param captainHatId Captain hat id administered by this clone (as MutinyRole wearer).
   * @param crewHatId Crew hat id (consulted for snapshot-gated voting checks).
   * @param mutinyRoleHatId MutinyRole hat id worn by this clone.
   * @param quartermasterRoleHatId QuartermasterRole hat id worn by the peer Quartermaster clone.
   * @param captain Initial captain-hat wearer (must be marked eligible before the factory mints the hat).
   * @param quartermaster Peer Quartermaster clone address (verified at every outbound call).
   */
  struct InitParams {
    uint256 captainHatId;
    uint256 crewHatId;
    uint256 mutinyRoleHatId;
    uint256 quartermasterRoleHatId;
    address captain;
    address quartermaster;
  }

  /**
   * @notice Persisted mutiny round state.
   * @param proposedNewCaptain Successor if the round passes.
   * @param fromCaptain Captain at the time the round opened (snapshot-locked).
   * @param startedAt Timestamp the round opened.
   * @param snapshot Size of the crew electorate at `startedAt`.
   * @param yeas Yea vote count.
   * @param executed Whether the round has been finalized.
   */
  struct MutinyRound {
    address proposedNewCaptain;
    address fromCaptain;
    uint64 startedAt;
    uint64 snapshot;
    uint64 yeas;
    bool executed;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice A mutiny round was opened.
   * @param _mutinyId Round identifier.
   * @param _proposer Crew member that opened the round.
   * @param _proposedNewCaptain Successor if the mutiny passes.
   * @param _snapshot Snapshot size of eligible crew when the round opened.
   */
  event MutinyStarted(
    uint256 indexed _mutinyId, address indexed _proposer, address indexed _proposedNewCaptain, uint256 _snapshot
  );

  /**
   * @notice Crew yea; pass requires yeas * 2 > snapshot (non-voters are not counted as nays)
   * @param _mutinyId Round id
   * @param _voter Voter
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
   * @notice The specified new captain already wears the captain hat or matches the current captain.
   * @param _target The rejected address.
   */
  error MutinyModule_SameCaptain(address _target);

  /**
   * @notice `quartermaster` no longer wears the quartermaster role hat (peer upgraded); upgrade this module before mutiny
   * @param _quartermaster Stale address
   */
  error MutinyModule_StaleQuartermaster(address _quartermaster);

  /**
   * @notice The cached captain address is no longer the captain-hat wearer (e.g. the captain
   *         renounced the hat directly via Hats). Safe recovery requires re-bootstrapping the
   *         module; this guard prevents mid-flight state divergence.
   * @param _captain The stale captain address.
   */
  error MutinyModule_StaleCaptain(address _captain);

  /**
   * @notice `startMutinyToArbitraryEoa` was called with an address that has contract code.
   * @param _proposedArbitraryEoa The rejected successor candidate.
   */
  error MutinyModule_NotEOA(address _proposedArbitraryEoa);

  /**
   * @notice `startMutinyToArbitraryContract` was called with an address that has no code, or `startMutinyToCommittee`.
   * @param _proposedArbitraryContract The rejected successor candidate.
   */
  error MutinyModule_NotContract(address _proposedArbitraryContract);

  /// @notice A mutiny round is already active.
  error MutinyModule_AlreadyActive();
  /// @notice No active mutiny exists for the requested id.
  error MutinyModule_NoActiveMutiny();
  /// @notice A required address argument was zero.
  error MutinyModule_ZeroAddress();

  /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice One-shot init: hat ids, `captain`, `quartermaster`. Eligibility for factory `mintHat` flows through `getWearerStatus` on the module.
   * @param _p Bootstrap parameters.
   */
  function initialize(InitParams calldata _p) external;

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Open a mutiny to a crew-hat successor. Crew-hat-gated; `_proposedCrewMember` must wear `crewHatId`.
   * @param _proposedCrewMember Address that wears `crewHatId`.
   */
  function startMutinyToCrewMember(address _proposedCrewMember) external;

  /**
   * @notice Open a mutiny to a Safe-style multisig (`getThreshold()` returns one word). Crew-hat-gated.
   * @param _proposedMultisigCommittee Address that is a Safe-style multisig.
   */
  function startMutinyToCommittee(address _proposedMultisigCommittee) external;

  /**
   * @notice Open a mutiny to an EOA successor (no contract code). Crew-hat-gated.
   * @param _proposedArbitraryEoa Address that is an EOA.
   */
  function startMutinyToArbitraryEoa(address _proposedArbitraryEoa) external;

  /**
   * @notice Open a mutiny to a contract successor (non-zero code length). Crew-hat-gated.
   * @param _proposedArbitraryContract Address that is a contract.
   */
  function startMutinyToArbitraryContract(address _proposedArbitraryContract) external;

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
                            VIEWS
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
  function captainHatId() external view returns (uint256 _captainHatId);

  /**
   * @notice Crew hat id.
   * @return _crewHatId The crew hat id.
   */
  function crewHatId() external view returns (uint256 _crewHatId);

  /**
   * @notice Role hat worn by the active MutinyModule clone.
   * @return _mutinyRoleHatId The MutinyRole hat id.
   */
  function mutinyRoleHatId() external view returns (uint256 _mutinyRoleHatId);

  /**
   * @notice Role hat worn by the active Quartermaster clone.
   * @return _quartermasterRoleHatId The QuartermasterRole hat id.
   */
  function quartermasterRoleHatId() external view returns (uint256 _quartermasterRoleHatId);

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
   * @dev Captured at `initialize`; verified to still wear `quartermasterRoleHatId` at every
   *      outbound peer call so a stale pointer (e.g. after a QuartermasterRole upgrade ceremony)
   *      reverts rather than silently calls the wrong contract. Re-deploying MutinyModule
   *      alongside a Quartermaster upgrade is the canonical recovery path.
   * @return _quartermaster Quartermaster peer address.
   */
  function quartermaster() external view returns (address _quartermaster);
}
