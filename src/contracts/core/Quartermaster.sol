// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeadlineLib} from 'contracts/libraries/DeadlineLib.sol';
import {PendingQueueLib} from 'contracts/libraries/PendingQueueLib.sol';
import {VoteThresholdLib} from 'contracts/libraries/VoteThresholdLib.sol';
import {HatGated} from 'contracts/utils/HatGated.sol';
import {RangeValidator} from 'contracts/utils/RangeValidator.sol';
import {IMutinyModule} from 'interfaces/core/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';
import {IHatGated} from 'interfaces/utils/IHatGated.sol';
import {IQuiescent} from 'interfaces/utils/IQuiescent.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IHatsEligibility} from 'hats-core/Interfaces/IHatsEligibility.sol';

/**
 * @title Quartermaster
 * @author Pacto
 * @notice Timelocked crew add/remove (bootstrap without delay); crew-led offboard (`QUORUM_OF_CAST`); crew-hat `IHatsEligibility` (always eligible); `QuartermasterRole` admin. Revokes via Hats `setHatWearerStatus`
 * @dev EIP-1167 master; `initialize` for clones. Mutiny freeze reads wired `mutinyModule.activeMutinyId`. Access = hats only
 */
contract Quartermaster is IQuartermaster, IHatsEligibility, HatGated, RangeValidator, Initializable {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  uint256 public captainHatId;
  /// @inheritdoc IQuartermaster
  uint256 public crewHatId;
  /// @inheritdoc IQuartermaster
  uint256 public mutinyRoleHatId;
  /// @inheritdoc IQuartermaster
  uint256 public quartermasterRoleHatId;
  /// @inheritdoc IQuartermaster
  uint256 public treasuryAuthorityRoleHatId;
  /// @inheritdoc IQuartermaster
  address public mutinyModule;

  /// @notice Packed delay, offboard expiry/quorum, and offboard ids.
  GovConfig internal _gov;

  /// @notice Scheduled crew adds (`pendingAddCount` = length).
  PendingQueueLib.Entry[] internal _pendingAdds;
  /// @notice 1-based index into `_pendingAdds`; `0` means absent.
  mapping(address _candidate => uint256 _index) internal _pendingAddIndex;
  /// @notice Scheduled crew removes (`pendingRemoveCount` = length).
  PendingQueueLib.Entry[] internal _pendingRemoves;
  /// @notice 1-based index into `_pendingRemoves`; `0` means absent.
  mapping(address _crew => uint256 _index) internal _pendingRemoveIndex;
  /// @notice Crew-led offboard votes indexed by id.
  mapping(uint256 _offboardId => CrewOffboard _vote) internal _offboards;
  /// @notice Vote-registry; `true` iff `_voter` has cast a vote in `_offboardId`.
  mapping(uint256 _offboardId => mapping(address _voter => bool _voted)) internal _hasCrewOffboardVote;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Master-copy constructor; bakes the Hats Protocol singleton into runtime code
   *         shared by all clones and disables direct initialization of the master copy.
   * @param hats_ Hats Protocol address for this chain.
   */
  constructor(IHats hats_) HatGated(hats_) {
    _disableInitializers();
  }

  /// @inheritdoc IQuartermaster
  function initialize(InitParams calldata _p) external initializer {
    if (_p.mutinyModule == address(0)) revert Quartermaster_ZeroAddress();
    _validateDelay(_p.crewChangeDelay);
    _validateDelay(_p.crewOffboardExpiry);
    _validateQuorumBps(_p.crewOffboardQuorumBps);
    captainHatId = _p.captainHatId;
    crewHatId = _p.crewHatId;
    mutinyRoleHatId = _p.mutinyRoleHatId;
    quartermasterRoleHatId = _p.quartermasterRoleHatId;
    treasuryAuthorityRoleHatId = _p.treasuryAuthorityRoleHatId;
    mutinyModule = _p.mutinyModule;
    // delay / quorum already range-checked; both fit the packed widths.
    // forge-lint: disable-next-line(unsafe-typecast)
    _gov.crewChangeDelay = uint64(_p.crewChangeDelay);
    // forge-lint: disable-next-line(unsafe-typecast)
    _gov.crewOffboardExpiry = uint64(_p.crewOffboardExpiry);
    // forge-lint: disable-next-line(unsafe-typecast)
    _gov.crewOffboardQuorumBps = uint16(_p.crewOffboardQuorumBps);
    emit CrewChangeDelayUpdated(0, _p.crewChangeDelay);
    emit CrewOffboardExpiryUpdated(0, _p.crewOffboardExpiry);
    emit CrewOffboardQuorumBpsUpdated(0, _p.crewOffboardQuorumBps);
  }

  /*///////////////////////////////////////////////////////////////
                        CAPTAIN-GATED: ADDITION
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function requestAddCrew(address _candidate) external onlyHatWearer(captainHatId) {
    _requireRosterUnlocked();
    _validateAddCandidate(_candidate);
    if (_pendingAddIndex[_candidate] != 0) revert Quartermaster_DuplicateCrewAdd(_candidate);
    if (_HATS.hatSupply(crewHatId) >= _HATS.getHatMaxSupply(crewHatId)) revert Quartermaster_CrewFull();

    uint64 _eta = _etaFromDelay(_crewAddDelay());
    PendingQueueLib.enqueue(_pendingAdds, _pendingAddIndex, _candidate, _eta);
    emit CrewAddRequested(_candidate, _eta);
  }

  /// @inheritdoc IQuartermaster
  function bootstrapCrew(address[] calldata _candidates) external onlyHatWearer(captainHatId) {
    _requireRosterUnlocked();
    if (_HATS.hatSupply(crewHatId) != 0) revert Quartermaster_BootstrapRequiresEmptyCrew();

    uint256 _n = _candidates.length;
    if (_n == 0) revert Quartermaster_BootstrapEmpty();

    uint256 _max = uint256(_HATS.getHatMaxSupply(crewHatId));
    if (_n > _max) revert Quartermaster_CrewFull();

    for (uint256 _i = 0; _i < _n; _i++) {
      address _c = _candidates[_i];
      _validateAddCandidate(_c);
      _HATS.mintHat(crewHatId, _c);
      emit CrewAddExecuted(_c);
    }
  }

  /// @inheritdoc IQuartermaster
  function cancelAddCrew(address _candidate) external onlyHatWearer(captainHatId) {
    PendingQueueLib.dequeue(_pendingAdds, _pendingAddIndex, _candidate);
    emit CrewAddCancelled(_candidate);
  }

  /// @inheritdoc IQuartermaster
  function executeAddCrew(address _candidate) external {
    uint256 _eta = PendingQueueLib.etaOf(_pendingAdds, _pendingAddIndex, _candidate);
    if (_eta == 0) revert PendingQueueLib.PendingQueueLib_NotPending(_candidate);
    if (block.timestamp < _eta) revert Quartermaster_StillLocked(_candidate, _eta);
    _requireRosterUnlocked();
    if (_HATS.isWearerOfHat(_candidate, crewHatId)) revert Quartermaster_AlreadyCrew(_candidate);

    PendingQueueLib.dequeue(_pendingAdds, _pendingAddIndex, _candidate);
    _HATS.mintHat(crewHatId, _candidate);
    emit CrewAddExecuted(_candidate);
  }

  /*///////////////////////////////////////////////////////////////
                        CAPTAIN-GATED: REMOVAL
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function requestRemoveCrew(address _crew) external onlyHatWearer(captainHatId) {
    _requireRosterUnlocked();
    if (_crew == address(0)) revert Quartermaster_ZeroAddress();
    if (!_HATS.isWearerOfHat(_crew, crewHatId)) revert Quartermaster_NotCrew(_crew);

    uint64 _eta = _etaFromDelay(_gov.crewChangeDelay);
    PendingQueueLib.enqueue(_pendingRemoves, _pendingRemoveIndex, _crew, _eta);
    emit CrewRemoveRequested(_crew, _eta);
  }

  /// @inheritdoc IQuartermaster
  function cancelRemoveCrew(address _crew) external onlyHatWearer(captainHatId) {
    PendingQueueLib.dequeue(_pendingRemoves, _pendingRemoveIndex, _crew);
    emit CrewRemoveCancelled(_crew);
  }

  /// @inheritdoc IQuartermaster
  function executeRemoveCrew(address _crew) external {
    uint256 _eta = PendingQueueLib.etaOf(_pendingRemoves, _pendingRemoveIndex, _crew);
    if (_eta == 0) revert PendingQueueLib.PendingQueueLib_NotPending(_crew);
    if (block.timestamp < _eta) revert Quartermaster_StillLocked(_crew, _eta);
    _requireRosterUnlocked();
    if (!_HATS.isWearerOfHat(_crew, crewHatId)) revert Quartermaster_NotCrew(_crew);

    PendingQueueLib.dequeue(_pendingRemoves, _pendingRemoveIndex, _crew);
    _HATS.setHatWearerStatus(crewHatId, _crew, false, false);
    emit CrewRemoveExecuted(_crew);
  }

  /*///////////////////////////////////////////////////////////////
                        CREW-LED OFFBOARD
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function proposeOffboard(address _target) external onlyHatWearer(crewHatId) returns (uint256 _offboardId) {
    _requireRosterUnlocked();
    if (_target == address(0)) revert Quartermaster_ZeroAddress();
    if (_target == msg.sender) revert Quartermaster_SelfOffboard();
    if (_HATS.isWearerOfHat(_target, captainHatId)) revert Quartermaster_CandidateIsCaptain(_target);
    if (!_HATS.isWearerOfHat(_target, crewHatId)) revert Quartermaster_NotCrew(_target);
    if (_pendingRemoveIndex[_target] != 0) revert Quartermaster_PendingCaptainRemove(_target);

    uint64 _deadline = DeadlineLib.fromDuration(_gov.crewOffboardExpiry);

    GovConfig memory _cfg = _gov;
    _cfg.crewOffboardCount += 1;
    _cfg.activeCrewOffboardId = _cfg.crewOffboardCount;
    _offboardId = _cfg.crewOffboardCount;
    _gov = _cfg;

    uint64 _snapshot = _HATS.hatSupply(crewHatId);
    _offboards[_offboardId] = CrewOffboard({
      target: _target, executed: false, proposer: msg.sender, deadline: _deadline, snapshot: _snapshot, yeas: 0, nays: 0
    });
    emit CrewOffboardProposed(_offboardId, msg.sender, _target, _deadline, _snapshot);
  }

  /// @inheritdoc IQuartermaster
  function crewOffboardVote(uint256 _offboardId, bool _support) external onlyHatWearer(crewHatId) {
    _requireActiveOffboard(_offboardId);
    CrewOffboard storage _o = _offboards[_offboardId];
    _requireOffboardNotExpired(_o, _offboardId);
    if (_hasCrewOffboardVote[_offboardId][msg.sender]) revert Quartermaster_AlreadyVoted(msg.sender);

    _hasCrewOffboardVote[_offboardId][msg.sender] = true;
    if (_support) {
      unchecked {
        _o.yeas += 1;
      }
    } else {
      unchecked {
        _o.nays += 1;
      }
    }
    emit CrewOffboardVoteCast(_offboardId, msg.sender, _support);
  }

  /// @inheritdoc IQuartermaster
  function executeOffboard(uint256 _offboardId) external {
    _requireActiveOffboard(_offboardId);
    CrewOffboard storage _o = _offboards[_offboardId];
    if (_o.executed) revert Quartermaster_NoActiveOffboard();
    _requireOffboardNotExpired(_o, _offboardId);
    if (!_offboardPassed(_o)) revert Quartermaster_OffboardNotPassed(_o.yeas, _o.nays, _o.snapshot);
    if (!_HATS.isWearerOfHat(_o.target, crewHatId)) revert Quartermaster_NotCrew(_o.target);

    _o.executed = true;
    _gov.activeCrewOffboardId = 0;
    _HATS.setHatWearerStatus(crewHatId, _o.target, false, false);
    emit CrewOffboardExecuted(_offboardId, _o.target);
  }

  /// @inheritdoc IQuartermaster
  function expireOffboard(uint256 _offboardId) external {
    _requireActiveOffboard(_offboardId);
    CrewOffboard storage _o = _offboards[_offboardId];
    if (_o.executed) revert Quartermaster_NoActiveOffboard();
    if (block.timestamp < _o.deadline) revert Quartermaster_OffboardNotExpired(_offboardId, _o.deadline);

    _gov.activeCrewOffboardId = 0;
    emit CrewOffboardExpired(_offboardId);
  }

  /*///////////////////////////////////////////////////////////////
                            MUTINY HOOKS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function mintCrewFromMutiny(address _formerCaptain) external onlyHatWearer(mutinyRoleHatId) {
    _mintCrewFromMutiny(_formerCaptain);
  }

  /// @inheritdoc IQuartermaster
  function revokeCrewFromMutiny(address _crew) external onlyHatWearer(mutinyRoleHatId) {
    _revokeCrewFromMutiny(_crew);
  }

  /// @inheritdoc IQuartermaster
  function applySuccessionCrew(
    address _from,
    address _to,
    bool _seatFormerCaptain
  ) external onlyHatWearer(mutinyRoleHatId) {
    if (_HATS.isWearerOfHat(_to, crewHatId)) {
      _revokeCrewFromMutiny(_to);
    }
    if (_seatFormerCaptain) {
      _mintCrewFromMutiny(_from);
    }
  }

  /*///////////////////////////////////////////////////////////////
                        PARAMETER SETTERS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function setCrewChangeDelay(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateDelay(_newValue);
    uint256 _old = _gov.crewChangeDelay;
    // casting to 'uint64' is safe because `_validateDelay` caps at `MAX_GOV_DELAY` (60 days).
    // forge-lint: disable-next-line(unsafe-typecast)
    _gov.crewChangeDelay = uint64(_newValue);
    emit CrewChangeDelayUpdated(_old, _newValue);
  }

  /// @inheritdoc IQuartermaster
  function setCrewOffboardExpiry(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateDelay(_newValue);
    uint256 _old = _gov.crewOffboardExpiry;
    // casting to 'uint64' is safe because `_validateDelay` caps at `MAX_GOV_DELAY` (60 days).
    // forge-lint: disable-next-line(unsafe-typecast)
    _gov.crewOffboardExpiry = uint64(_newValue);
    emit CrewOffboardExpiryUpdated(_old, _newValue);
  }

  /// @inheritdoc IQuartermaster
  function setCrewOffboardQuorumBps(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateQuorumBps(_newValue);
    uint256 _old = _gov.crewOffboardQuorumBps;
    // casting to 'uint16' is safe because `_validateQuorumBps` caps at `MAX_QUORUM_BPS` (10_000).
    // forge-lint: disable-next-line(unsafe-typecast)
    _gov.crewOffboardQuorumBps = uint16(_newValue);
    emit CrewOffboardQuorumBpsUpdated(_old, _newValue);
  }

  /*///////////////////////////////////////////////////////////////
                        VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function crewChangeDelay() external view returns (uint256 _delay) {
    _delay = _gov.crewChangeDelay;
  }

  /// @inheritdoc IQuartermaster
  function crewOffboardExpiry() external view returns (uint256 _expiry) {
    _expiry = _gov.crewOffboardExpiry;
  }

  /// @inheritdoc IQuartermaster
  function crewOffboardQuorumBps() external view returns (uint256 _bps) {
    _bps = _gov.crewOffboardQuorumBps;
  }

  /// @inheritdoc IQuartermaster
  function activeCrewOffboardId() external view returns (uint256 _id) {
    _id = _gov.activeCrewOffboardId;
  }

  /// @inheritdoc IQuartermaster
  function crewOffboardCount() external view returns (uint256 _count) {
    _count = _gov.crewOffboardCount;
  }

  /// @inheritdoc IQuartermaster
  function pendingCrewAddAt(address _candidate) external view returns (uint256 _executableAt) {
    _executableAt = PendingQueueLib.etaOf(_pendingAdds, _pendingAddIndex, _candidate);
  }

  /// @inheritdoc IQuartermaster
  function pendingCrewRemoveAt(address _crew) external view returns (uint256 _executableAt) {
    _executableAt = PendingQueueLib.etaOf(_pendingRemoves, _pendingRemoveIndex, _crew);
  }

  /// @inheritdoc IQuartermaster
  function pendingAddAt(uint256 _index) external view returns (address _candidate, uint256 _executableAt) {
    PendingQueueLib.Entry storage _p = _pendingAdds[_index];
    _candidate = _p.account;
    _executableAt = _p.eta;
  }

  /// @inheritdoc IQuartermaster
  function pendingRemoveAt(uint256 _index) external view returns (address _crew, uint256 _executableAt) {
    PendingQueueLib.Entry storage _p = _pendingRemoves[_index];
    _crew = _p.account;
    _executableAt = _p.eta;
  }

  /// @inheritdoc IQuartermaster
  function pendingAdds() external view returns (address[] memory _candidates, uint256[] memory _executableAts) {
    (_candidates, _executableAts) = _pendingValues(_pendingAdds);
  }

  /// @inheritdoc IQuartermaster
  function pendingRemoves() external view returns (address[] memory _crew, uint256[] memory _executableAts) {
    (_crew, _executableAts) = _pendingValues(_pendingRemoves);
  }

  /// @inheritdoc IQuartermaster
  function pendingAddCount() external view returns (uint256 _count) {
    _count = _pendingAdds.length;
  }

  /// @inheritdoc IQuartermaster
  function pendingRemoveCount() external view returns (uint256 _count) {
    _count = _pendingRemoves.length;
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view returns (bool _quiet) {
    _quiet =
      _pendingAdds.length == 0 && _pendingRemoves.length == 0 && !mutinyActive() && _gov.activeCrewOffboardId == 0;
  }

  /// @inheritdoc IQuartermaster
  function crewOffboard(uint256 _id)
    external
    view
    returns (
      address _target,
      address _proposer,
      uint64 _deadline,
      uint64 _snapshot,
      uint64 _yeas,
      uint64 _nays,
      bool _executed
    )
  {
    CrewOffboard storage _o = _offboards[_id];
    _target = _o.target;
    _proposer = _o.proposer;
    _deadline = _o.deadline;
    _snapshot = _o.snapshot;
    _yeas = _o.yeas;
    _nays = _o.nays;
    _executed = _o.executed;
  }

  /// @inheritdoc IQuartermaster
  function hasCrewOffboardVote(uint256 _offboardId, address _voter) external view returns (bool _voted) {
    _voted = _hasCrewOffboardVote[_offboardId][_voter];
  }

  /// @inheritdoc IHatsEligibility
  function getWearerStatus(address, uint256) external pure returns (bool _eligible, bool _standing) {
    _eligible = true;
    _standing = true;
  }

  /// @inheritdoc IQuartermaster
  function mutinyActive() public view returns (bool _active) {
    _active = IMutinyModule(mutinyModule).activeMutinyId() != 0;
  }

  /// @inheritdoc IHatGated
  function hats() public view override(IHatGated, HatGated) returns (IHats _hats) {
    _hats = _HATS;
  }

  /*///////////////////////////////////////////////////////////////
                        INTERNAL LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Mint crew to `_formerCaptain` (mutiny succession). Caller must already be MutinyRole-gated.
   * @param _formerCaptain Recipient of the crew hat.
   */
  function _mintCrewFromMutiny(address _formerCaptain) internal {
    if (_formerCaptain == address(0)) revert Quartermaster_ZeroAddress();
    if (_HATS.isWearerOfHat(_formerCaptain, crewHatId)) revert Quartermaster_AlreadyCrew(_formerCaptain);
    if (_HATS.hatSupply(crewHatId) >= _HATS.getHatMaxSupply(crewHatId)) revert Quartermaster_CrewFull();

    _HATS.mintHat(crewHatId, _formerCaptain);
    emit CrewMintedFromMutiny(_formerCaptain);
  }

  /**
   * @notice Revoke crew from `_crew` (mutiny succession). Caller must already be MutinyRole-gated.
   * @param _crew Address that must lose the crew hat.
   */
  function _revokeCrewFromMutiny(address _crew) internal {
    if (_crew == address(0)) revert Quartermaster_ZeroAddress();
    if (!_HATS.isWearerOfHat(_crew, crewHatId)) revert Quartermaster_NotCrew(_crew);

    _HATS.setHatWearerStatus(crewHatId, _crew, false, false);
    emit CrewRevokedFromMutiny(_crew);
  }

  /**
   * @notice Timelock for a captain-scheduled crew add (`0` when no crew wearer yet; else `crewChangeDelay`).
   * @return _delay Seconds added to `block.timestamp` when recording a pending add.
   */
  function _crewAddDelay() internal view returns (uint256 _delay) {
    _delay = _HATS.hatSupply(crewHatId) == 0 ? 0 : _gov.crewChangeDelay;
  }

  /**
   * @notice `block.timestamp + _delay` as `uint64`, or `DeadlineLib_Overflow`.
   * @param _delay Seconds to add to `block.timestamp`.
   * @return _eta Packed executable-at timestamp.
   */
  function _etaFromDelay(uint256 _delay) internal view returns (uint64 _eta) {
    _eta = DeadlineLib.fromDuration(_delay);
  }

  /**
   * @notice Reverts unless `candidate` is a valid onboarding target before mint.
   * @param _candidate Proposed wearer of the crew hat.
   */
  function _validateAddCandidate(address _candidate) internal view {
    if (_candidate == address(0)) revert Quartermaster_ZeroAddress();
    if (_HATS.isWearerOfHat(_candidate, captainHatId)) revert Quartermaster_CandidateIsCaptain(_candidate);
    if (_HATS.isWearerOfHat(_candidate, crewHatId)) revert Quartermaster_AlreadyCrew(_candidate);
  }

  /**
   * @notice Reverts if mutiny mode is on or a crew-led offboard vote is live.
   */
  function _requireRosterUnlocked() internal view {
    if (IMutinyModule(mutinyModule).activeMutinyId() != 0) revert Quartermaster_MutinyActive();
    if (_gov.activeCrewOffboardId != 0) revert Quartermaster_CrewOffboardActive();
  }

  /**
   * @notice Reverts unless `_offboardId` is the current `activeCrewOffboardId` (and non-zero).
   * @param _offboardId Vote id supplied by the caller.
   */
  function _requireActiveOffboard(uint256 _offboardId) internal view {
    if (_offboardId == 0 || _offboardId != _gov.activeCrewOffboardId) revert Quartermaster_NoActiveOffboard();
  }

  /**
   * @notice Reverts if `_o` is at or past its deadline.
   * @param _o Offboard already loaded from storage.
   * @param _offboardId Vote id (for revert payload).
   */
  function _requireOffboardNotExpired(CrewOffboard storage _o, uint256 _offboardId) internal view {
    if (block.timestamp >= _o.deadline) revert Quartermaster_OffboardExpired(_offboardId);
  }

  /**
   * @notice `QUORUM_OF_CAST`: turnout reaches `crewOffboardQuorumBps` of snapshot and yeas strictly exceed nays.
   * @param _o Offboard being evaluated.
   * @return _passed True iff the crew offboard vote passes.
   */
  function _offboardPassed(CrewOffboard storage _o) internal view returns (bool _passed) {
    _passed = VoteThresholdLib.quorumOfCast(_o.yeas, _o.nays, _o.snapshot, _gov.crewOffboardQuorumBps);
  }

  /**
   * @notice Snapshot of a pending list as parallel address / eta arrays.
   * @param _list Entry array.
   * @return _accounts Addresses in list order.
   * @return _etas Matching executable-at timestamps.
   */
  function _pendingValues(PendingQueueLib
        .Entry[] storage _list) internal view returns (address[] memory _accounts, uint256[] memory _etas) {
    uint256 _n = _list.length;
    _accounts = new address[](_n);
    _etas = new uint256[](_n);
    for (uint256 _i; _i < _n; ++_i) {
      PendingQueueLib.Entry storage _p = _list[_i];
      _accounts[_i] = _p.account;
      _etas[_i] = _p.eta;
    }
  }
}
