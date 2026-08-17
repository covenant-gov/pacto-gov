// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetRescuer} from 'contracts/utils/AssetRescuer.sol';
import {HatGated} from 'contracts/utils/HatGated.sol';
import {RangeValidator} from 'contracts/utils/RangeValidator.sol';
import {ITreasuryAuthority} from 'interfaces/core/ITreasuryAuthority.sol';
import {IHatGated} from 'interfaces/utils/IHatGated.sol';
import {IQuiescent} from 'interfaces/utils/IQuiescent.sol';

import {Module} from '@gnosis-guild/zodiac/contracts/core/Module.sol';
import {FactoryFriendly} from '@gnosis-guild/zodiac/contracts/factory/FactoryFriendly.sol';
import {Enum} from '@gnosis.pm/safe-contracts/contracts/common/Enum.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title TreasuryAuthority
 * @author Pacto
 * @notice Zodiac + Safe owner: crew threshold plus captain consent (`captainVote(true)`), then `execute` → `avatar`.
 *         When `avatar` wears the captain hat, crew quorum alone suffices for `execute`. Captain may `captainVote(false)` to veto while a human wears the hat.
 *         `exec` from a wallet hits `AssetRescuer` (no ERC-1271)
 * @dev EIP-1167 master; `initialize` / `setUp` then `renounceOwnership` on `Module` so `avatar`/`target` are fixed. Param setters: TA role hat (via a passing proposal with `to` here). Rescue → Safe
 */
contract TreasuryAuthority is ITreasuryAuthority, Module, HatGated, RangeValidator, AssetRescuer {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  uint256 public captainHatId;
  /// @inheritdoc ITreasuryAuthority
  uint256 public crewHatId;
  /// @inheritdoc ITreasuryAuthority
  uint256 public treasuryAuthorityRoleHatId;
  /// @inheritdoc ITreasuryAuthority
  uint256 public proposalExpiry;
  /// @inheritdoc ITreasuryAuthority
  CrewVoteMode public crewVoteMode;
  /// @inheritdoc ITreasuryAuthority
  uint256 public quorumBps;

  /// @inheritdoc ITreasuryAuthority
  mapping(address _proposer => uint256 _openProposalId) public openProposalOf;
  /// @notice Proposal store indexed by id. Id `0` is reserved as the sentinel "no proposal".
  mapping(uint256 _proposalId => Proposal _proposal) internal _proposals;
  /// @notice Per-proposal vote registry; `true` iff `_voter` has cast a vote on `_proposalId`.
  mapping(uint256 _proposalId => mapping(address _voter => bool _voted)) internal _voted;

  /// @inheritdoc ITreasuryAuthority
  uint256 public proposalCount;

  /// @inheritdoc ITreasuryAuthority
  uint256 public maxDeadline;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Master-copy constructor; bakes the Hats singleton into runtime code shared by all
   *         clones and disables direct initialization of the master copy itself.
   * @param hats_ Hats Protocol address for this chain.
   */
  constructor(IHats hats_) HatGated(hats_) {
    _disableInitializers();
  }

  /// @inheritdoc ITreasuryAuthority
  function initialize(InitParams calldata _p) external initializer {
    _applyInit(_p);
  }

  /*///////////////////////////////////////////////////////////////
                            GOVERNANCE LOGIC: PROPOSE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  function propose(
    address _to,
    uint256 _value,
    bytes calldata _data,
    Operation _op
  ) external returns (uint256 _proposalId) {
    _requireCaptainOrCrew(msg.sender);

    uint256 _prior = openProposalOf[msg.sender];
    if (_prior != 0) {
      Proposal storage _p = _proposals[_prior];
      if (!_p.executed && block.timestamp < _p.deadline) {
        revert TreasuryAuthority_ProposerHasOpenProposal(msg.sender, _prior);
      }
    }

    uint64 _snapshot = _HATS.hatSupply(crewHatId);
    uint256 _deadline256 = block.timestamp + proposalExpiry;
    if (_deadline256 > type(uint64).max) revert TreasuryAuthority_DeadlineOverflow();
    // casting to 'uint64' is safe because `_deadline256` is checked against `type(uint64).max` above.
    // forge-lint: disable-next-line(unsafe-typecast)
    uint64 _deadline = uint64(_deadline256);

    _proposalId = ++proposalCount;

    Proposal storage _np = _proposals[_proposalId];
    _np.proposer = msg.sender;
    _np.deadline = _deadline;
    _np.op = _op;
    _np.to = _to;
    _np.snapshot = _snapshot;
    _np.value = _value;
    _np.data = _data;

    openProposalOf[msg.sender] = _proposalId;
    if (_deadline > maxDeadline) maxDeadline = _deadline;
    emit ProposalCreated(_proposalId, msg.sender, _to, _value, _op, _data, _deadline, _snapshot);
  }

  /*///////////////////////////////////////////////////////////////
                            GOVERNANCE LOGIC: VOTE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  function crewVote(uint256 _proposalId, bool _support) external onlyHatWearer(crewHatId) {
    Proposal storage _p = _requireAlive(_proposalId);
    _rejectIfCaptainVetoed(_proposalId, _p);
    if (_voted[_proposalId][msg.sender]) revert TreasuryAuthority_AlreadyVoted(msg.sender);

    _voted[_proposalId][msg.sender] = true;
    unchecked {
      if (_support) _p.yeas += 1;
      else _p.nays += 1;
    }
    emit CrewVoted(_proposalId, msg.sender, _support);
  }

  /// @inheritdoc ITreasuryAuthority
  function captainVote(uint256 _proposalId, bool _support) external onlyHatWearer(captainHatId) {
    _captainVote(_proposalId, _support);
  }

  /*///////////////////////////////////////////////////////////////
                            GOVERNANCE LOGIC: EXECUTE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  function execute(uint256 _proposalId) external {
    Proposal storage _p = _requireAlive(_proposalId);
    _rejectIfCaptainVetoed(_proposalId, _p);
    bool _captainOk = _p.captainApproved || _HATS.isWearerOfHat(avatar, captainHatId);
    if (!_crewVotePassed(_p) || !_captainOk) revert TreasuryAuthority_NotExecutable(_proposalId);

    _p.executed = true;
    delete openProposalOf[_p.proposer];

    bool _ok =
      exec(_p.to, _p.value, _p.data, _p.op == Operation.CALL ? Enum.Operation.Call : Enum.Operation.DelegateCall);
    if (!_ok) revert TreasuryAuthority_SafeExecutionFailed();

    emit ProposalExecuted(_proposalId, _ok);
  }

  /*///////////////////////////////////////////////////////////////
                            PARAMETER SETTERS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  function setProposalExpiry(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateDelay(_newValue);
    uint256 _old = proposalExpiry;
    proposalExpiry = _newValue;
    emit ProposalExpiryUpdated(_old, _newValue);
  }

  /// @inheritdoc ITreasuryAuthority
  function setCrewVoteMode(CrewVoteMode _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    CrewVoteMode _old = crewVoteMode;
    crewVoteMode = _newValue;
    emit CrewVoteModeUpdated(_old, _newValue);
  }

  /// @inheritdoc ITreasuryAuthority
  function setQuorumBps(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateQuorumBps(_newValue);
    uint256 _old = quorumBps;
    quorumBps = _newValue;
    emit QuorumBpsUpdated(_old, _newValue);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
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
    )
  {
    Proposal storage _p = _proposals[_id];
    _proposer = _p.proposer;
    _to = _p.to;
    _value = _p.value;
    _op = _p.op;
    _data = _p.data;
    _deadline = _p.deadline;
    _snapshot = _p.snapshot;
    _yeas = _p.yeas;
    _nays = _p.nays;
    _captainApproved = _p.captainApproved;
    _captainDefeated = _p.captainDefeated;
    _executed = _p.executed;
  }

  /// @inheritdoc ITreasuryAuthority
  function hasVoted(uint256 _proposalId, address _voter) external view returns (bool __voted) {
    __voted = _voted[_proposalId][_voter];
  }

  /// @inheritdoc ITreasuryAuthority
  function SAFE() external view returns (address _safe) {
    _safe = avatar;
  }

  /// @inheritdoc ITreasuryAuthority
  function crewVotePassed(uint256 _id) external view returns (bool _passed) {
    Proposal storage _p = _proposals[_id];
    if (_p.proposer == address(0)) return false;
    _passed = _crewVotePassed(_p);
  }

  /// @inheritdoc ITreasuryAuthority
  function isExecutable(uint256 _id) external view returns (bool _executable) {
    Proposal storage _p = _proposals[_id];
    if (_p.proposer == address(0) || _p.executed || block.timestamp >= _p.deadline || _p.captainDefeated) {
      return false;
    }
    bool _captainOk = _p.captainApproved || _HATS.isWearerOfHat(avatar, captainHatId);
    _executable = _crewVotePassed(_p) && _captainOk;
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view returns (bool _quiet) {
    _quiet = block.timestamp >= maxDeadline;
  }

  /*///////////////////////////////////////////////////////////////
                            ZODIAC FACTORY SHIM
  //////////////////////////////////////////////////////////////*/
  /**
   * @inheritdoc ITreasuryAuthority
   * @dev Also satisfies the Zodiac `Module` / `FactoryFriendly` `setUp` surface for `ModuleProxyFactory`.
   * @param _initializeParams ABI-encoded `InitParams`.
   */
  function setUp(bytes memory _initializeParams) public override(ITreasuryAuthority, FactoryFriendly) initializer {
    _applyInit(abi.decode(_initializeParams, (InitParams)));
  }

  /// @inheritdoc IHatGated
  function hats() public view override(IHatGated, HatGated) returns (IHats _hats) {
    _hats = _HATS;
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Single initialization routine shared by both typed `initialize` and the Zodiac
   *         `setUp` shim. Validates params, seeds state, wires `avatar`/`target` to the Safe,
   *         and renounces base-module ownership so `setAvatar` / `setTarget` are inert for
   *         the clone's lifetime.
   * @param _p Bootstrap parameters.
   */
  function _applyInit(InitParams memory _p) internal {
    if (_p.safe == address(0)) revert TreasuryAuthority_NotCaptainOrCrew(address(0));
    _validateDelay(_p.proposalExpiry);
    _validateQuorumBps(_p.quorumBps);

    __Ownable_init(msg.sender);

    captainHatId = _p.captainHatId;
    crewHatId = _p.crewHatId;
    treasuryAuthorityRoleHatId = _p.treasuryAuthorityRoleHatId;
    proposalExpiry = _p.proposalExpiry;
    crewVoteMode = _p.crewVoteMode;
    quorumBps = _p.quorumBps;

    setAvatar(_p.safe);
    setTarget(_p.safe);

    renounceOwnership();

    emit ProposalExpiryUpdated(0, _p.proposalExpiry);
    emit CrewVoteModeUpdated(CrewVoteMode.MAJORITY_SNAPSHOT, _p.crewVoteMode);
    emit QuorumBpsUpdated(0, _p.quorumBps);
  }

  /**
   * @notice Captain votes once per proposal; veto clears `openProposalOf` for a new proposal from proposer.
   * @param _proposalId Proposal id.
   * @param _support True to approve, false to veto.
   */
  function _captainVote(uint256 _proposalId, bool _support) internal {
    Proposal storage _p = _requireAlive(_proposalId);
    if (_p.captainApproved || _p.captainDefeated) revert TreasuryAuthority_CaptainAlreadyVoted(msg.sender);
    if (_support) {
      _p.captainApproved = true;
    } else {
      _p.captainDefeated = true;
      delete openProposalOf[_p.proposer];
    }
    emit CaptainVoted(_proposalId, msg.sender, _support);
  }

  /**
   * @notice Caller-gate that admits both the captain-hat wearer and any crew-hat wearer.
   * @param _caller Address to gate-check.
   */
  function _requireCaptainOrCrew(address _caller) internal view {
    if (_HATS.isWearerOfHat(_caller, captainHatId)) return;
    if (_HATS.isWearerOfHat(_caller, crewHatId)) return;
    revert TreasuryAuthority_NotCaptainOrCrew(_caller);
  }

  /**
   * @notice Resolves the proposal by id and reverts with the appropriate error if it is
   *         missing, already executed, or past its deadline.
   * @param _proposalId Proposal id.
   * @return _p Storage pointer to the proposal.
   */
  function _requireAlive(uint256 _proposalId) internal view returns (Proposal storage _p) {
    _p = _proposals[_proposalId];
    if (_p.proposer == address(0)) revert TreasuryAuthority_ProposalDoesNotExist(_proposalId);
    if (_p.executed) revert TreasuryAuthority_AlreadyExecuted();
    if (block.timestamp >= _p.deadline) revert TreasuryAuthority_ProposalExpired(_proposalId);
  }

  /**
   * @notice Reverts if the captain vetoed; used by `crewVote` and `execute` only.
   * @param _proposalId Proposal id (for revert payload).
   * @param _p Proposal storage from `_requireAlive`.
   */
  function _rejectIfCaptainVetoed(uint256 _proposalId, Proposal storage _p) internal view {
    if (_p.captainDefeated) revert TreasuryAuthority_NotExecutable(_proposalId);
  }

  /**
   * @notice Evaluates the crew-vote pass condition under the current `crewVoteMode`.
   * @dev `MAJORITY_SNAPSHOT`: yeas strictly greater than half the snapshot (`2*yeas > snapshot`).
   *      `QUORUM_OF_CAST`: cast-total reaches `quorumBps` of snapshot AND yeas strictly greater than nays.
   * @param _p Proposal being evaluated.
   * @return _passed True iff the crew vote passes under the configured mode.
   */
  function _crewVotePassed(Proposal storage _p) internal view returns (bool _passed) {
    uint256 _yeas = _p.yeas;
    if (crewVoteMode == CrewVoteMode.MAJORITY_SNAPSHOT) {
      _passed = _yeas * 2 > _p.snapshot;
    } else {
      uint256 _cast = _yeas + _p.nays;
      if (_cast * 10_000 < uint256(_p.snapshot) * quorumBps) _passed = false;
      else _passed = _yeas > _p.nays;
    }
  }

  /// @inheritdoc AssetRescuer
  function _rescueDestination() internal view override returns (address _destination) {
    _destination = avatar;
  }
}
