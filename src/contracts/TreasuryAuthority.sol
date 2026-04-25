// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetRescuer} from 'contracts/abstracts/AssetRescuer.sol';
import {GovernanceParams} from 'contracts/abstracts/GovernanceParams.sol';
import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {IQuiescent} from 'interfaces/IQuiescent.sol';
import {ITreasuryAuthority} from 'interfaces/ITreasuryAuthority.sol';

import {Module} from '@gnosis-guild/zodiac/contracts/core/Module.sol';
import {Enum} from '@gnosis.pm/safe-contracts/contracts/common/Enum.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title TreasuryAuthority
 * @author Pacto
 * @notice Zodiac + Safe owner: crew threshold + `captainApproved`, then `execute` → `avatar`. `exec` from a wallet hits `AssetRescuer` (no ERC-1271)
 * @dev EIP-1167 master; `initialize` / `setUp` then `renounceOwnership` on `Module` so `avatar`/`target` are fixed. Param setters: TA role hat (via a passing proposal with `to` here). Rescue → Safe
 */
contract TreasuryAuthority is ITreasuryAuthority, Module, HatGated, GovernanceParams, AssetRescuer {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  uint256 public override CAPTAIN_HAT_ID;
  /// @inheritdoc ITreasuryAuthority
  uint256 public override CREW_HAT_ID;
  /// @inheritdoc ITreasuryAuthority
  uint256 public override TREASURY_AUTHORITY_ROLE_HAT_ID;
  /// @inheritdoc ITreasuryAuthority
  uint256 public override proposalExpiry;
  /// @inheritdoc ITreasuryAuthority
  CrewVoteMode public override crewVoteMode;
  /// @inheritdoc ITreasuryAuthority
  uint256 public override quorumBps;

  /// @inheritdoc ITreasuryAuthority
  mapping(address _proposer => uint256 _openProposalId) public override openProposalOf;
  /// @notice Proposal store indexed by id. Id `0` is reserved as the sentinel "no proposal".
  mapping(uint256 _proposalId => Proposal _proposal) internal _proposals;
  /// @notice Per-proposal vote registry; `true` iff `_voter` has cast a vote on `_proposalId`.
  mapping(uint256 _proposalId => mapping(address _voter => bool _voted)) internal _voted;

  /// @notice Monotonically increasing id counter. First issued id is `1`.
  uint256 internal _nextProposalId;

  /**
   * @notice Maximum deadline ever assigned by `propose`. Used by `isQuiet` as a cheap
   *         over-approximation of "some proposal could still execute". Once
   *         `block.timestamp >= _maxDeadline`, every ever-created proposal is past its
   *         deadline and therefore can no longer transition to `executed`.
   */
  uint256 internal _maxDeadline;

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
  function initialize(InitParams calldata _p) external override initializer {
    _applyInit(_p);
  }

  /*///////////////////////////////////////////////////////////////
                            GOVERNANCE: PROPOSE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  function propose(
    address _to,
    uint256 _value,
    bytes calldata _data,
    Operation _op
  ) external override returns (uint256 _proposalId) {
    _requireCaptainOrCrew(msg.sender);

    uint256 _prior = openProposalOf[msg.sender];
    if (_prior != 0) {
      Proposal storage _p = _proposals[_prior];
      if (!_p.executed && block.timestamp < _p.deadline) {
        revert TreasuryAuthority_ProposerHasOpenProposal(msg.sender, _prior);
      }
    }

    uint64 _snapshot = _HATS.hatSupply(CREW_HAT_ID);
    uint64 _deadline = uint64(block.timestamp + proposalExpiry);

    _proposalId = ++_nextProposalId;

    Proposal storage _np = _proposals[_proposalId];
    _np.proposer = msg.sender;
    _np.deadline = _deadline;
    _np.op = _op;
    _np.to = _to;
    _np.snapshot = _snapshot;
    _np.value = _value;
    _np.data = _data;

    openProposalOf[msg.sender] = _proposalId;
    if (_deadline > _maxDeadline) _maxDeadline = _deadline;

    emit ProposalCreated(_proposalId, msg.sender, _to, _value, _op, _data, _deadline, _snapshot);
  }

  /*///////////////////////////////////////////////////////////////
                            GOVERNANCE: VOTE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  function crewVote(uint256 _proposalId, bool _yea) external override onlyHatWearer(CREW_HAT_ID) {
    Proposal storage _p = _requireAlive(_proposalId);
    if (_voted[_proposalId][msg.sender]) revert TreasuryAuthority_AlreadyVoted(msg.sender);

    _voted[_proposalId][msg.sender] = true;
    unchecked {
      if (_yea) _p.yeas += 1;
      else _p.nays += 1;
    }
    emit CrewVoted(_proposalId, msg.sender, _yea);
  }

  /// @inheritdoc ITreasuryAuthority
  function captainApprove(uint256 _proposalId) external override onlyHatWearer(CAPTAIN_HAT_ID) {
    Proposal storage _p = _requireAlive(_proposalId);
    if (_p.captainApproved) revert TreasuryAuthority_CaptainAlreadyApproved();

    _p.captainApproved = true;
    emit CaptainApproved(_proposalId, msg.sender);
  }

  /*///////////////////////////////////////////////////////////////
                            GOVERNANCE: EXECUTE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ITreasuryAuthority
  function execute(uint256 _proposalId) external override {
    Proposal storage _p = _requireAlive(_proposalId);
    if (!_crewVotePassed(_p)) revert TreasuryAuthority_CrewVoteNotPassed();
    if (!_p.captainApproved) revert TreasuryAuthority_CaptainNotApproved();

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
  function setProposalExpiry(uint256 _newValue) external override onlyHatWearer(TREASURY_AUTHORITY_ROLE_HAT_ID) {
    _validateDelay(_newValue);
    uint256 _old = proposalExpiry;
    proposalExpiry = _newValue;
    emit ProposalExpiryUpdated(_old, _newValue);
  }

  /// @inheritdoc ITreasuryAuthority
  function setCrewVoteMode(CrewVoteMode _newValue) external override onlyHatWearer(TREASURY_AUTHORITY_ROLE_HAT_ID) {
    CrewVoteMode _old = crewVoteMode;
    crewVoteMode = _newValue;
    emit CrewVoteModeUpdated(_old, _newValue);
  }

  /// @inheritdoc ITreasuryAuthority
  function setQuorumBps(uint256 _newValue) external override onlyHatWearer(TREASURY_AUTHORITY_ROLE_HAT_ID) {
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
    override
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
    )
  {
    Proposal storage _p = _proposals[_id];
    return (
      _p.proposer,
      _p.to,
      _p.value,
      _p.op,
      _p.data,
      _p.deadline,
      _p.snapshot,
      _p.yeas,
      _p.nays,
      _p.captainApproved,
      _p.executed
    );
  }

  /// @inheritdoc ITreasuryAuthority
  function hasVoted(uint256 _proposalId, address _voter) external view override returns (bool) {
    return _voted[_proposalId][_voter];
  }

  /// @inheritdoc ITreasuryAuthority
  function SAFE() external view override returns (address) {
    return avatar;
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view override returns (bool) {
    return block.timestamp >= _maxDeadline;
  }

  /*///////////////////////////////////////////////////////////////
                            ZODIAC FACTORY SHIM
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Zodiac `FactoryFriendly.setUp` shim. Decodes `InitParams` and runs the same
   *         initialization path as `initialize`. Satisfies the `FactoryFriendly` abstract
   *         surface so this module is compatible with Zodiac's `ModuleProxyFactory`, even
   *         though Pacto itself bootstraps via `Clones` + `initialize`.
   * @param _initializeParams ABI-encoded `InitParams`.
   */
  function setUp(bytes memory _initializeParams) public override initializer {
    _applyInit(abi.decode(_initializeParams, (InitParams)));
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

    CAPTAIN_HAT_ID = _p.captainHatId;
    CREW_HAT_ID = _p.crewHatId;
    TREASURY_AUTHORITY_ROLE_HAT_ID = _p.treasuryAuthorityRoleHatId;
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
   * @notice Caller-gate that admits both the captain-hat wearer and any crew-hat wearer.
   * @param _caller Address to gate-check.
   */
  function _requireCaptainOrCrew(address _caller) internal view {
    if (_HATS.isWearerOfHat(_caller, CAPTAIN_HAT_ID)) return;
    if (_HATS.isWearerOfHat(_caller, CREW_HAT_ID)) return;
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
   * @notice Evaluates the crew-vote pass condition under the current `crewVoteMode`.
   * @dev `MAJORITY_SNAPSHOT`: yeas strictly greater than half the snapshot (`2*yeas > snapshot`).
   *      `QUORUM_OF_CAST`: cast-total reaches `quorumBps` of snapshot AND yeas strictly greater
   *      than nays.
   * @param _p Proposal being evaluated.
   * @return _passed True iff the crew vote passes under the configured mode.
   */
  function _crewVotePassed(Proposal storage _p) internal view returns (bool _passed) {
    uint256 _yeas = _p.yeas;
    if (crewVoteMode == CrewVoteMode.MAJORITY_SNAPSHOT) {
      return _yeas * 2 > _p.snapshot;
    }

    uint256 _cast = _yeas + _p.nays;
    if (_cast * 10_000 < uint256(_p.snapshot) * quorumBps) return false;
    return _yeas > _p.nays;
  }

  /// @inheritdoc AssetRescuer
  function _rescueDestination() internal view override returns (address) {
    return avatar;
  }
}
