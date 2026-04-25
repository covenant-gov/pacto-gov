// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAssetRescuer} from 'interfaces/IAssetRescuer.sol';
import {IQuiescent} from 'interfaces/IQuiescent.sol';

/**
 * @title ITreasuryAuthority
 * @author Pacto
 * @notice Two-body Safe control: crew must pass the vote (snapshot majority or quorum-of-cast), captain must
 *         approve, then execute. Sole module+owner on the Safe; param changes go through this role hat. `IAssetRescuer`
 *         sweeps stray balance to the Safe
 */
interface ITreasuryAuthority is IAssetRescuer, IQuiescent {
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
   * @notice Captain approved (no rejection event; missing approval + deadline ends the proposal)
   * @param _proposalId Proposal id
   * @param _captain Approver
   */
  event CaptainApproved(uint256 indexed _proposalId, address indexed _captain);

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

  /// @notice The captain has already approved this proposal.
  error TreasuryAuthority_CaptainAlreadyApproved();
  /// @notice The proposal has already been executed.
  error TreasuryAuthority_AlreadyExecuted();
  /// @notice Crew vote has not passed under the current mode.
  error TreasuryAuthority_CrewVoteNotPassed();
  /// @notice Captain has not approved the proposal.
  error TreasuryAuthority_CaptainNotApproved();
  /// @notice The underlying Safe execution failed.
  error TreasuryAuthority_SafeExecutionFailed();

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
   * @param _proposalId Proposal identifier.
   * @param _yea True to support.
   */
  function crewVote(uint256 _proposalId, bool _yea) external;

  /**
   * @notice Record the captain's approval. Captain-hat-gated.
   * @dev There is no counterpart `captainReject`: a proposal the captain does not approve
   *      simply expires at its `deadline`. Silence is veto.
   * @param _proposalId Proposal identifier.
   */
  function captainApprove(uint256 _proposalId) external;

  /**
   * @notice Execute a proposal once the crew vote has passed and the captain has approved.
   * @dev Permissionless; uses Zodiac `Module.exec*` to act on the Safe.
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
                            VARIABLES
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
   * @return _captainApproved Whether the captain has approved (silence = veto).
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
  function CAPTAIN_HAT_ID() external view returns (uint256 _captainHatId);

  /**
   * @notice Crew hat id.
   * @return _crewHatId The crew hat id.
   */
  function CREW_HAT_ID() external view returns (uint256 _crewHatId);

  /**
   * @notice Role hat worn by the active TreasuryAuthority clone.
   * @return _treasuryAuthorityRoleHatId The role hat id.
   */
  function TREASURY_AUTHORITY_ROLE_HAT_ID() external view returns (uint256 _treasuryAuthorityRoleHatId);
}
