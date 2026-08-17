// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAssetRescuer} from 'interfaces/utils/IAssetRescuer.sol';
import {IHatGated} from 'interfaces/utils/IHatGated.sol';
import {IQuiescent} from 'interfaces/utils/IQuiescent.sol';

/**
 * @title ITreasuryAuthority
 * @author Pacto
 * @notice Two-body Safe control: crew must pass the vote (snapshot majority or quorum-of-cast), captain must
 *         approve (`captainVote(true)`), then execute. Captain may `captainVote(false)` to veto
 *         before expiry. Sole module+owner on the Safe; param changes go through this role hat. `IAssetRescuer`
 *         sweeps stray balance to the Safe
 */
interface ITreasuryAuthority is IAssetRescuer, IQuiescent, IHatGated {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Crew vote counting mode.
   * @param MAJORITY_SNAPSHOT Proposal passes when yeas exceed 50% of the crew snapshot at proposal time.
   * @param QUORUM_OF_CAST Proposal passes when cast votes meet `quorumBps` of the snapshot AND yeas exceed nays.
   */
  enum CrewVoteMode {
    MAJORITY_SNAPSHOT,
    QUORUM_OF_CAST
  }

  /**
   * @notice Safe execution operation type.
   * @param CALL Standard external call.
   * @param DELEGATECALL Delegatecall via the Zodiac `Module` surface.
   */
  enum Operation {
    CALL,
    DELEGATECALL
  }

  /**
   * @notice Parameters required to initialize a TreasuryAuthority clone.
   * @param safe Squad Safe address. Set as both Zodiac `avatar` and `target`.
   * @param captainHatId Captain hat id used to gate `captainVote` and the propose surface.
   * @param crewHatId Crew hat id used to gate `crewVote` and the propose surface.
   * @param treasuryAuthorityRoleHatId Role hat worn by this live clone; gates parameter setters.
   * @param proposalExpiry Seconds from creation until a proposal expires.
   * @param crewVoteMode Crew vote counting mode.
   * @param quorumBps Quorum in basis points (applied only in `QUORUM_OF_CAST`).
   */
  struct InitParams {
    address safe;
    uint256 captainHatId;
    uint256 crewHatId;
    uint256 treasuryAuthorityRoleHatId;
    uint256 proposalExpiry;
    CrewVoteMode crewVoteMode;
    uint256 quorumBps;
  }

  /**
   * @notice Persisted proposal state. Laid out for compact slot packing.
   * @param proposer Proposer address. (slot 0: 20 bytes)
   * @param deadline Unix timestamp after which the proposal cannot execute. (slot 0: +8 bytes)
   * @param op Operation type (CALL / DELEGATECALL). (slot 0: +1 byte)
   * @param captainApproved Whether the captain has approved. (slot 0: +1 byte)
   * @param captainDefeated Whether the captain vetoed the proposal (cannot execute). (slot 0: +1 byte)
   * @param executed Whether the proposal has been finalized. (slot 0: +1 byte)
   * @param to Target address for the Safe call. (slot 1: 20 bytes)
   * @param snapshot Crew snapshot at creation time. (slot 1: +8 bytes)
   * @param yeas Yea vote count.
   * @param nays Nay vote count.
   * @param value ETH value.
   * @param data Calldata payload.
   */
  struct Proposal {
    address proposer;
    uint64 deadline;
    Operation op;
    bool captainApproved;
    bool captainDefeated;
    bool executed;
    address to;
    uint64 snapshot;
    uint64 yeas;
    uint64 nays;
    uint256 value;
    bytes data;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice A proposal was created.
   * @param _proposalId Proposal identifier.
   * @param _proposer Address that submitted the proposal (captain or crew wearer).
   * @param _to Target address the Safe will call.
   * @param _value ETH value in wei.
   * @param _op Operation type.
   * @param _data Calldata to forward.
   * @param _deadline Timestamp after which the proposal expires.
   * @param _snapshot Snapshot size of eligible crew at creation time.
   */
  event ProposalCreated(
    uint256 indexed _proposalId,
    address indexed _proposer,
    address indexed _to,
    uint256 _value,
    Operation _op,
    bytes _data,
    uint256 _deadline,
    uint256 _snapshot
  );

  /**
   * @notice A crew member cast a vote on a proposal.
   * @param _proposalId Proposal identifier.
   * @param _voter Crew voter.
   * @param _yea True to support the proposal.
   */
  event CrewVoted(uint256 indexed _proposalId, address indexed _voter, bool _yea);

  /**
   * @notice The captain cast their single vote on this proposal (approve or veto).
   * @param _proposalId Proposal identifier.
   * @param _captain Captain hat wearer.
   * @param _support True if approving, false if vetoing.
   */
  event CaptainVoted(uint256 indexed _proposalId, address indexed _captain, bool _support);

  /**
   * @notice The proposal was executed against the Safe via the Zodiac module surface.
   * @param _proposalId Proposal identifier.
   * @param _success Whether the underlying Safe execution succeeded.
   */
  event ProposalExecuted(uint256 indexed _proposalId, bool _success);

  /**
   * @notice The proposal expired without execution.
   * @param _proposalId Proposal identifier.
   */
  event ProposalExpired(uint256 indexed _proposalId);

  /**
   * @notice Proposal expiry parameter updated.
   * @param _oldValue Previous value in seconds.
   * @param _newValue New value in seconds.
   */
  event ProposalExpiryUpdated(uint256 _oldValue, uint256 _newValue);

  /**
   * @notice Crew vote mode parameter updated.
   * @param _oldValue Previous mode.
   * @param _newValue New mode.
   */
  event CrewVoteModeUpdated(CrewVoteMode _oldValue, CrewVoteMode _newValue);

  /**
   * @notice Quorum bps parameter updated.
   * @param _oldValue Previous bps.
   * @param _newValue New bps.
   */
  event QuorumBpsUpdated(uint256 _oldValue, uint256 _newValue);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Caller is neither the captain nor a crew member.
   * @param _caller Caller that failed the gate check.
   */
  error TreasuryAuthority_NotCaptainOrCrew(address _caller);

  /**
   * @notice Proposer already has an open proposal (one-open-per-proposer invariant).
   * @param _proposer The proposer at fault.
   * @param _openProposalId The currently open proposal.
   */
  error TreasuryAuthority_ProposerHasOpenProposal(address _proposer, uint256 _openProposalId);

  /**
   * @notice No proposal exists with that id.
   * @param _proposalId The missing proposal id.
   */
  error TreasuryAuthority_ProposalDoesNotExist(uint256 _proposalId);

  /**
   * @notice The proposal has expired.
   * @param _proposalId The expired proposal id.
   */
  error TreasuryAuthority_ProposalExpired(uint256 _proposalId);

  /**
   * @notice Voter has already voted on this proposal.
   * @param _voter Address that attempted a duplicate vote.
   */
  error TreasuryAuthority_AlreadyVoted(address _voter);

  /**
   * @notice The captain may only vote once per proposal.
   * @param _captain Captain that attempted a second vote.
   */
  error TreasuryAuthority_CaptainAlreadyVoted(address _captain);

  /**
   * @notice The proposal cannot be executed yet (captain vetoed, crew threshold not met, or captain has not
   *         approved), or crew cannot vote because the captain vetoed. Inspect `proposal(_id)` on-chain for why.
   * @param _proposalId The proposal that cannot be executed or voted on by crew.
   */
  error TreasuryAuthority_NotExecutable(uint256 _proposalId);

  /// @notice The proposal has already been executed.
  error TreasuryAuthority_AlreadyExecuted();
  /// @notice The underlying Safe execution failed.
  error TreasuryAuthority_SafeExecutionFailed();
  /// @notice `block.timestamp + proposalExpiry` exceeds `type(uint64).max` (proposal `deadline` storage width).
  error TreasuryAuthority_DeadlineOverflow();

  /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Per-clone initializer with a typed parameter struct. Preferred entry point for Pacto factories.
   * @param _p Bootstrap parameters.
   */
  function initialize(InitParams calldata _p) external;

  /**
   * @notice Zodiac `FactoryFriendly` / `Module` init shim: ABI-encoded `InitParams` for `ModuleProxyFactory` compatibility.
   * @param _initializeParams ABI-encoded `InitParams`.
   */
  function setUp(bytes memory _initializeParams) external;

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Create a proposal to execute `(to, value, data, op)` against the Safe.
   * @dev Gated to the captain or current crew members. One open proposal per proposer.
   * @param _to Target address.
   * @param _value ETH value in wei.
   * @param _data Calldata to forward.
   * @param _op Operation type (CALL / DELEGATECALL).
   * @return _proposalId Identifier of the new proposal.
   */
  function propose(
    address _to,
    uint256 _value,
    bytes calldata _data,
    Operation _op
  ) external returns (uint256 _proposalId);

  /**
   * @notice Cast one crew vote on a proposal. Crew-hat-gated and snapshot-constrained.
   * @dev Reverts `NotExecutable` if the captain vetoed this proposal.
   * @param _proposalId Proposal identifier.
   * @param _support True to vote in favor; false to vote against.
   */
  function crewVote(uint256 _proposalId, bool _support) external;

  /**
   * @notice Captain casts their single vote: `true` approves; `false` vetoes (defeats the proposal,
   *         clears the proposer's open slot, blocks execution). Cannot be called twice on the same proposal.
   * @param _proposalId Proposal identifier.
   * @param _support True to approve; false to veto.
   */
  function captainVote(uint256 _proposalId, bool _support) external;

  /**
   * @notice Execute a proposal once the crew vote has passed, the proposal was not vetoed, and either the captain
   *         approved or the Safe (`avatar`) wears the captain hat (paused captain / crew-only path).
   * @dev Permissionless; uses Zodiac `Module.exec*` to act on the Safe. Reverts `NotExecutable` if any precondition fails.
   * @param _proposalId Proposal identifier.
   */
  function execute(uint256 _proposalId) external;

  /*///////////////////////////////////////////////////////////////
                            PARAMETER SETTERS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Update the proposal expiry. TreasuryAuthorityRole-gated (self-gated).
   * @param _newValue New expiry in seconds.
   */
  function setProposalExpiry(uint256 _newValue) external;

  /**
   * @notice Update the crew vote mode. TreasuryAuthorityRole-gated (self-gated).
   * @param _newValue New crew vote mode.
   */
  function setCrewVoteMode(CrewVoteMode _newValue) external;

  /**
   * @notice Update the quorum bps (only meaningful in `QUORUM_OF_CAST` mode). TreasuryAuthorityRole-gated.
   * @param _newValue New quorum in basis points.
   */
  function setQuorumBps(uint256 _newValue) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Current proposal expiry in seconds.
   * @return _expiry The expiry value.
   */
  function proposalExpiry() external view returns (uint256 _expiry);

  /**
   * @notice Current crew vote mode.
   * @return _mode The vote mode.
   */
  function crewVoteMode() external view returns (CrewVoteMode _mode);

  /**
   * @notice Current quorum in basis points (only applied in `QUORUM_OF_CAST` mode).
   * @return _bps The quorum value.
   */
  function quorumBps() external view returns (uint256 _bps);

  /**
   * @notice Id of the open proposal submitted by `_proposer`, or zero if none.
   * @param _proposer The proposer address.
   * @return _openProposalId The open proposal id, or zero.
   */
  function openProposalOf(address _proposer) external view returns (uint256 _openProposalId);

  /**
   * @notice Read the stored state of a proposal.
   * @param _id Proposal identifier.
   * @return _proposer Address that created the proposal.
   * @return _to Target address.
   * @return _value ETH value.
   * @return _op Operation type.
   * @return _data Calldata to forward.
   * @return _deadline Unix timestamp after which the proposal expires.
   * @return _snapshot Snapshot size of eligible crew at creation time.
   * @return _yeas Yea vote count.
   * @return _nays Nay vote count.
   * @return _captainApproved Whether the captain has approved.
   * @return _captainDefeated Whether the captain vetoed (`captainVote` with false).
   * @return _executed Whether the proposal has been executed.
   */
  function proposal(uint256 _id)
    external
    view
    returns (
      address _proposer,
      address _to,
      uint256 _value,
      Operation _op,
      bytes memory _data,
      uint64 _deadline,
      uint64 _snapshot,
      uint64 _yeas,
      uint64 _nays,
      bool _captainApproved,
      bool _captainDefeated,
      bool _executed
    );

  /**
   * @notice Whether `_voter` has cast a vote on `_proposalId`.
   * @param _proposalId Proposal identifier.
   * @param _voter Voter address.
   * @return _voted True if the voter has voted.
   */
  function hasVoted(uint256 _proposalId, address _voter) external view returns (bool _voted);

  /**
   * @notice The squad Safe governed by this authority.
   * @return _safe The Safe address.
   */
  function SAFE() external view returns (address _safe);

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
   * @notice Role hat worn by the active TreasuryAuthority clone.
   * @return _treasuryAuthorityRoleHatId The role hat id.
   */
  function treasuryAuthorityRoleHatId() external view returns (uint256 _treasuryAuthorityRoleHatId);

  /**
   * @notice Highest proposal id ever issued (`0` before the first `propose`).
   * @return _count Last issued id; clients iterate `1..=_count`.
   */
  function proposalCount() external view returns (uint256 _count);

  /**
   * @notice Latest proposal deadline ever assigned. Used by `isQuiet`.
   * @return _deadline Unix timestamp.
   */
  function maxDeadline() external view returns (uint256 _deadline);

  /**
   * @notice Whether crew support on `_id` meets the configured vote mode.
   * @param _id Proposal identifier.
   * @return _passed False if the proposal is missing.
   */
  function crewVotePassed(uint256 _id) external view returns (bool _passed);

  /**
   * @notice Whether `_id` can be executed now (alive, not vetoed, crew passed, captain path satisfied).
   * @param _id Proposal identifier.
   * @return _executable False if missing, expired, executed, vetoed, or thresholds unmet.
   */
  function isExecutable(uint256 _id) external view returns (bool _executable);
}
