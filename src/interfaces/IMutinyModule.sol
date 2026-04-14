// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IMutinyModule
 * @author Pacto
 * @notice Crew-driven mutiny: snapshot electorate, one vote per crew member, strict majority to replace the captain hat wearer.
 * @dev Orchestrates `Hats.transferHat` on the captain hat and calls `IQuartermaster` for crew mint/burn/handoff. Eligibility and exact
 *      vote counting are implementation-defined; parameters (threshold, snapshot, etc.) are fixed per deployment.
 */
interface IMutinyModule {
  /*///////////////////////////////////////////////////////////////
                            STRUCTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Persistent fields for one mutiny round (storage layout is implementation-defined beyond this shape)
   * @param proposedNewCaptain Successor if the mutiny passes
   * @param snapshotBlock Block number recorded when the round opened
   * @param eligibleCrewCount Crew supply / electorate size fixed for majority math
   * @param open True while voting may proceed
   * @param executed True after `executeMutiny` succeeds
   */
  struct Round {
    address proposedNewCaptain;
    uint256 snapshotBlock;
    uint256 eligibleCrewCount;
    bool open;
    bool executed;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice A mutiny round was opened
   * @param _mutinyId Round identifier
   * @param _proposedNewCaptain Address that will receive the captain hat if the mutiny passes
   * @param _snapshotBlock Block number fixed for crew electorate
   */
  event MutinyStarted(uint256 indexed _mutinyId, address indexed _proposedNewCaptain, uint256 _snapshotBlock);

  /**
   * @notice A crew member cast a vote
   * @param _mutinyId Round identifier
   * @param _voter Crew voter
   * @param _yea True for mutiny / new captain, false against
   */
  event VoteCast(uint256 indexed _mutinyId, address indexed _voter, bool _yea);

  /**
   * @notice Mutiny succeeded and on-chain actions were performed
   * @param _mutinyId Round identifier
   * @param _newCaptain Final wearer of the captain hat
   */
  event MutinyExecuted(uint256 indexed _mutinyId, address indexed _newCaptain);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Caller is not eligible crew (at snapshot or current rules)
   */
  error MutinyModule_NotEligibleCrew();

  /**
   * @notice Mutiny is not open for this id or wrong phase
   */
  error MutinyModule_InvalidMutiny();

  /**
   * @notice Vote already recorded for this voter and round
   */
  error MutinyModule_AlreadyVoted();

  /**
   * @notice Threshold not met or mutiny already executed
   */
  error MutinyModule_NotExecutable();

  /**
   * @notice Proposed captain is zero or otherwise invalid
   */
  error MutinyModule_InvalidSuccessor();

  /**
   * @notice A mutiny is already active
   */
  error MutinyModule_MutinyAlreadyActive();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Open a mutiny round fixing electorate and proposed new captain
   * @dev Must set Quartermaster mutiny active per product rules
   * @param _proposedNewCaptain Non-zero successor (EOA or contract) for the captain hat
   */
  function startMutiny(address _proposedNewCaptain) external;

  /**
   * @notice Cast one vote per crew member for an open round
   * @param _mutinyId The active mutiny id
   * @param _yea True to support mutiny and install `proposedNewCaptain`
   */
  function castVote(uint256 _mutinyId, bool _yea) external;

  /**
   * @notice If strict majority is met, transfer captain hat, run crew handoff/mint per successor type, clear mutiny active
   * @param _mutinyId Round to finalize
   */
  function executeMutiny(uint256 _mutinyId) external;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Linked Quartermaster
   * @return _quartermaster The Quartermaster contract
   */
  function QUARTERMASTER() external view returns (address _quartermaster);

  /**
   * @notice Hats Protocol singleton
   * @return _hats The Hats contract address
   */
  function HATS() external view returns (address _hats);

  /**
   * @notice Captain hat id used for transfers and wearer reads
   * @return _captainHatId The captain hat id
   */
  function CAPTAIN_HAT_ID() external view returns (uint256 _captainHatId);

  /**
   * @notice Crew hat id used for electorate checks
   * @return _crewHatId The crew hat id
   */
  function CREW_HAT_ID() external view returns (uint256 _crewHatId);

  /**
   * @notice Monotonic mutiny counter (next id = currentOpen + 1 pattern is implementation detail)
   * @return _id The latest started mutiny id
   */
  function latestMutinyId() external view returns (uint256 _id);

  /**
   * @notice Whether a mutiny round is open for voting
   * @param _mutinyId Round to query
   * @return _open True if voting is open
   */
  function isMutinyOpen(uint256 _mutinyId) external view returns (bool _open);

  /**
   * @notice Round state for `_mutinyId` (unset id returns zeroed fields)
   * @param _mutinyId Round to query
   */
  function rounds(uint256 _mutinyId)
    external
    view
    returns (address proposedNewCaptain, uint256 snapshotBlock, uint256 eligibleCrewCount, bool open, bool executed);

  /**
   * @notice Yea votes tallied for the round
   * @param _mutinyId Round to query
   * @return _yeas Vote count
   */
  function yeaVotes(uint256 _mutinyId) external view returns (uint256 _yeas);

  /**
   * @notice Whether `_voter` already voted in `_mutinyId`
   * @param _mutinyId Round to query
   * @param _voter Voter address
   * @return _voted True if voted
   */
  function hasVoted(uint256 _mutinyId, address _voter) external view returns (bool _voted);
}
