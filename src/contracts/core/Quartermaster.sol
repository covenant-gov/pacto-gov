// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/utils/HatGated.sol';
import {RangeValidator} from 'contracts/utils/RangeValidator.sol';
import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';
import {IHatGated} from 'interfaces/utils/IHatGated.sol';
import {IQuiescent} from 'interfaces/utils/IQuiescent.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IHatsEligibility} from 'hats-core/Interfaces/IHatsEligibility.sol';

/**
 * @title Quartermaster
 * @author Pacto
 * @notice Timelocked crew add/remove (bootstrap without delay); crew-led offboard (`QUORUM_OF_CAST`); crew-hat `IHatsEligibility`; `QuartermasterRole` admin. Revokes via local flags + Hats re-checks
 * @dev EIP-1167 master; `initialize` for clones. Access = hats only
 */
contract Quartermaster is IQuartermaster, IHatsEligibility, HatGated, RangeValidator, Initializable {
  using EnumerableSet for EnumerableSet.AddressSet;

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
  uint256 public crewChangeDelay;
  /// @inheritdoc IQuartermaster
  uint256 public crewOffboardExpiry;
  /// @inheritdoc IQuartermaster
  uint256 public crewOffboardQuorumBps;
  /// @inheritdoc IQuartermaster
  bool public mutinyActive;
  /// @inheritdoc IQuartermaster
  uint256 public activeCrewOffboardId;
  /// @inheritdoc IQuartermaster
  uint256 public crewOffboardCount;

  /// @inheritdoc IQuartermaster
  mapping(address _candidate => uint256 _executableAt) public pendingCrewAddAt;
  /// @inheritdoc IQuartermaster
  mapping(address _crew => uint256 _executableAt) public pendingCrewRemoveAt;

  /// @inheritdoc IQuartermaster
  mapping(address _wearer => bool _eligible) public crewEligible;

  /// @inheritdoc IQuartermaster
  uint256 public pendingAddCount;
  /// @inheritdoc IQuartermaster
  uint256 public pendingRemoveCount;

  /// @notice Enumerable keys for `pendingCrewAddAt`. Updated in lockstep with `pendingAddCount`.
  EnumerableSet.AddressSet internal _pendingAdds;
  /// @notice Enumerable keys for `pendingCrewRemoveAt`. Updated in lockstep with `pendingRemoveCount`.
  EnumerableSet.AddressSet internal _pendingRemoves;
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
    _validateDelay(_p.crewChangeDelay);
    _validateDelay(_p.crewOffboardExpiry);
    _validateQuorumBps(_p.crewOffboardQuorumBps);
    captainHatId = _p.captainHatId;
    crewHatId = _p.crewHatId;
    mutinyRoleHatId = _p.mutinyRoleHatId;
    quartermasterRoleHatId = _p.quartermasterRoleHatId;
    treasuryAuthorityRoleHatId = _p.treasuryAuthorityRoleHatId;
    crewChangeDelay = _p.crewChangeDelay;
    crewOffboardExpiry = _p.crewOffboardExpiry;
    crewOffboardQuorumBps = _p.crewOffboardQuorumBps;
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
    if (pendingCrewAddAt[_candidate] != 0) revert Quartermaster_DuplicateCrewAdd(_candidate);
    if (_HATS.hatSupply(crewHatId) >= _HATS.getHatMaxSupply(crewHatId)) revert Quartermaster_CrewFull();

    pendingAddCount++;
    _pendingAdds.add(_candidate);
    uint256 _eta = block.timestamp + _crewAddDelay();
    pendingCrewAddAt[_candidate] = _eta;
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
      crewEligible[_c] = true;
      _HATS.mintHat(crewHatId, _c);
      emit CrewAddExecuted(_c);
    }
  }

  /// @inheritdoc IQuartermaster
  function cancelAddCrew(address _candidate) external onlyHatWearer(captainHatId) {
    if (pendingCrewAddAt[_candidate] == 0) revert Quartermaster_NotPending(_candidate);
    delete pendingCrewAddAt[_candidate];
    pendingAddCount--;
    _pendingAdds.remove(_candidate);
    emit CrewAddCancelled(_candidate);
  }

  /// @inheritdoc IQuartermaster
  function executeAddCrew(address _candidate) external {
    uint256 _eta = pendingCrewAddAt[_candidate];
    if (_eta == 0) revert Quartermaster_NotPending(_candidate);
    if (block.timestamp < _eta) revert Quartermaster_StillLocked(_candidate, _eta);
    _requireRosterUnlocked();
    if (_HATS.isWearerOfHat(_candidate, crewHatId)) revert Quartermaster_AlreadyCrew(_candidate);

    delete pendingCrewAddAt[_candidate];
    pendingAddCount--;
    _pendingAdds.remove(_candidate);
    crewEligible[_candidate] = true;
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

    if (pendingCrewRemoveAt[_crew] == 0) {
      pendingRemoveCount++;
      _pendingRemoves.add(_crew);
    }
    uint256 _eta = block.timestamp + crewChangeDelay;
    pendingCrewRemoveAt[_crew] = _eta;
    emit CrewRemoveRequested(_crew, _eta);
  }

  /// @inheritdoc IQuartermaster
  function cancelRemoveCrew(address _crew) external onlyHatWearer(captainHatId) {
    if (pendingCrewRemoveAt[_crew] == 0) revert Quartermaster_NotPending(_crew);
    delete pendingCrewRemoveAt[_crew];
    pendingRemoveCount--;
    _pendingRemoves.remove(_crew);
    emit CrewRemoveCancelled(_crew);
  }

  /// @inheritdoc IQuartermaster
  function executeRemoveCrew(address _crew) external {
    uint256 _eta = pendingCrewRemoveAt[_crew];
    if (_eta == 0) revert Quartermaster_NotPending(_crew);
    if (block.timestamp < _eta) revert Quartermaster_StillLocked(_crew, _eta);
    _requireRosterUnlocked();
    if (!_HATS.isWearerOfHat(_crew, crewHatId)) revert Quartermaster_NotCrew(_crew);

    delete pendingCrewRemoveAt[_crew];
    pendingRemoveCount--;
    _pendingRemoves.remove(_crew);
    crewEligible[_crew] = false;
    _HATS.checkHatWearerStatus(crewHatId, _crew);
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
    if (pendingCrewRemoveAt[_target] != 0) revert Quartermaster_PendingCaptainRemove(_target);

    uint256 _deadline256 = block.timestamp + crewOffboardExpiry;
    if (_deadline256 > type(uint64).max) revert Quartermaster_DeadlineOverflow();

    _offboardId = ++crewOffboardCount;
    uint64 _snapshot = _HATS.hatSupply(crewHatId);
    _offboards[_offboardId] = CrewOffboard({
      target: _target,
      proposer: msg.sender,
      // casting to 'uint64' is safe because `_deadline256` is checked against `type(uint64).max` above.
      // forge-lint: disable-next-line(unsafe-typecast)
      deadline: uint64(_deadline256),
      snapshot: _snapshot,
      yeas: 0,
      nays: 0,
      executed: false
    });
    activeCrewOffboardId = _offboardId;
    emit CrewOffboardProposed(_offboardId, msg.sender, _target, _deadline256, _snapshot);
  }

  /// @inheritdoc IQuartermaster
  function crewOffboardVote(uint256 _offboardId, bool _support) external onlyHatWearer(crewHatId) {
    _requireActiveOffboard(_offboardId);
    _requireOffboardNotExpired(_offboardId);
    if (_hasCrewOffboardVote[_offboardId][msg.sender]) revert Quartermaster_AlreadyVoted(msg.sender);

    _hasCrewOffboardVote[_offboardId][msg.sender] = true;
    CrewOffboard storage _o = _offboards[_offboardId];
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
    _requireOffboardNotExpired(_offboardId);
    if (!_offboardPassed(_o)) revert Quartermaster_OffboardNotPassed(_o.yeas, _o.nays, _o.snapshot);
    if (!_HATS.isWearerOfHat(_o.target, crewHatId)) revert Quartermaster_NotCrew(_o.target);

    _o.executed = true;
    activeCrewOffboardId = 0;
    crewEligible[_o.target] = false;
    _HATS.checkHatWearerStatus(crewHatId, _o.target);
    emit CrewOffboardExecuted(_offboardId, _o.target);
  }

  /// @inheritdoc IQuartermaster
  function expireOffboard(uint256 _offboardId) external {
    _requireActiveOffboard(_offboardId);
    CrewOffboard storage _o = _offboards[_offboardId];
    if (_o.executed) revert Quartermaster_NoActiveOffboard();
    if (block.timestamp < _o.deadline) revert Quartermaster_OffboardNotExpired(_offboardId, _o.deadline);

    activeCrewOffboardId = 0;
    emit CrewOffboardExpired(_offboardId);
  }

  /*///////////////////////////////////////////////////////////////
                            MUTINY HOOKS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function mintCrewFromMutiny(address _formerCaptain) external onlyHatWearer(mutinyRoleHatId) {
    if (_formerCaptain == address(0)) revert Quartermaster_ZeroAddress();
    if (_HATS.isWearerOfHat(_formerCaptain, crewHatId)) revert Quartermaster_AlreadyCrew(_formerCaptain);
    if (_HATS.hatSupply(crewHatId) >= _HATS.getHatMaxSupply(crewHatId)) revert Quartermaster_CrewFull();

    crewEligible[_formerCaptain] = true;
    _HATS.mintHat(crewHatId, _formerCaptain);
    emit CrewMintedFromMutiny(_formerCaptain);
  }

  /// @inheritdoc IQuartermaster
  function crewHandoffForMutiny(address _formerCaptain, address _newCaptain) external onlyHatWearer(mutinyRoleHatId) {
    if (_formerCaptain == address(0) || _newCaptain == address(0)) {
      revert Quartermaster_ZeroAddress();
    }
    if (!_HATS.isWearerOfHat(_newCaptain, crewHatId)) revert Quartermaster_NotCrew(_newCaptain);
    if (_HATS.isWearerOfHat(_formerCaptain, crewHatId)) revert Quartermaster_AlreadyCrew(_formerCaptain);

    crewEligible[_formerCaptain] = true;
    _HATS.transferHat(crewHatId, _newCaptain, _formerCaptain);
    emit CrewHandoffForMutiny(_formerCaptain, _newCaptain);
  }

  /// @inheritdoc IQuartermaster
  function setMutinyActive(bool _active) external onlyHatWearer(mutinyRoleHatId) {
    mutinyActive = _active;
    emit MutinyActiveSet(_active);
  }

  /*///////////////////////////////////////////////////////////////
                        PARAMETER SETTERS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function setCrewChangeDelay(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateDelay(_newValue);
    uint256 _old = crewChangeDelay;
    crewChangeDelay = _newValue;
    emit CrewChangeDelayUpdated(_old, _newValue);
  }

  /// @inheritdoc IQuartermaster
  function setCrewOffboardExpiry(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateDelay(_newValue);
    uint256 _old = crewOffboardExpiry;
    crewOffboardExpiry = _newValue;
    emit CrewOffboardExpiryUpdated(_old, _newValue);
  }

  /// @inheritdoc IQuartermaster
  function setCrewOffboardQuorumBps(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateQuorumBps(_newValue);
    uint256 _old = crewOffboardQuorumBps;
    crewOffboardQuorumBps = _newValue;
    emit CrewOffboardQuorumBpsUpdated(_old, _newValue);
  }

  /*///////////////////////////////////////////////////////////////
                        VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IHatsEligibility
  function getWearerStatus(
    address _wearer,
    uint256 /*_hatId*/
  ) external view returns (bool _eligible, bool _standing) {
    _eligible = crewEligible[_wearer];
    _standing = true;
  }

  /// @inheritdoc IQuartermaster
  function pendingAddAt(uint256 _index) external view returns (address _candidate, uint256 _executableAt) {
    _candidate = _pendingAdds.at(_index);
    _executableAt = pendingCrewAddAt[_candidate];
  }

  /// @inheritdoc IQuartermaster
  function pendingRemoveAt(uint256 _index) external view returns (address _crew, uint256 _executableAt) {
    _crew = _pendingRemoves.at(_index);
    _executableAt = pendingCrewRemoveAt[_crew];
  }

  /// @inheritdoc IQuartermaster
  function pendingAdds() external view returns (address[] memory _candidates, uint256[] memory _executableAts) {
    _candidates = _pendingAdds.values();
    uint256 _n = _candidates.length;
    _executableAts = new uint256[](_n);
    for (uint256 _i; _i < _n; ++_i) {
      _executableAts[_i] = pendingCrewAddAt[_candidates[_i]];
    }
  }

  /// @inheritdoc IQuartermaster
  function pendingRemoves() external view returns (address[] memory _crew, uint256[] memory _executableAts) {
    _crew = _pendingRemoves.values();
    uint256 _n = _crew.length;
    _executableAts = new uint256[](_n);
    for (uint256 _i; _i < _n; ++_i) {
      _executableAts[_i] = pendingCrewRemoveAt[_crew[_i]];
    }
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view returns (bool _quiet) {
    _quiet = pendingAddCount == 0 && pendingRemoveCount == 0 && !mutinyActive && activeCrewOffboardId == 0;
  }

  /// @inheritdoc IHatGated
  function hats() public view override(IHatGated, HatGated) returns (IHats _hats) {
    _hats = _HATS;
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

  /*///////////////////////////////////////////////////////////////
                        INTERNAL LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Timelock for a captain-scheduled crew add (`0` when no crew wearer yet; else `crewChangeDelay`).
   * @return _delay Seconds added to `block.timestamp` when recording `pendingCrewAddAt`.
   */
  function _crewAddDelay() internal view returns (uint256 _delay) {
    _delay = _HATS.hatSupply(crewHatId) == 0 ? 0 : crewChangeDelay;
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
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (activeCrewOffboardId != 0) revert Quartermaster_CrewOffboardActive();
  }

  /**
   * @notice Reverts unless `_offboardId` is the current `activeCrewOffboardId` (and non-zero).
   * @param _offboardId Vote id supplied by the caller.
   */
  function _requireActiveOffboard(uint256 _offboardId) internal view {
    if (_offboardId == 0 || _offboardId != activeCrewOffboardId) revert Quartermaster_NoActiveOffboard();
  }

  /**
   * @notice Reverts if the active offboard at `_offboardId` is at or past its deadline.
   * @param _offboardId Vote that must still be inside its voting window.
   */
  function _requireOffboardNotExpired(uint256 _offboardId) internal view {
    if (block.timestamp >= _offboards[_offboardId].deadline) revert Quartermaster_OffboardExpired(_offboardId);
  }

  /**
   * @notice `QUORUM_OF_CAST`: turnout reaches `crewOffboardQuorumBps` of snapshot and yeas strictly exceed nays.
   * @param _o Offboard being evaluated.
   * @return _passed True iff the crew offboard vote passes.
   */
  function _offboardPassed(CrewOffboard storage _o) internal view returns (bool _passed) {
    uint256 _cast = uint256(_o.yeas) + uint256(_o.nays);
    if (_cast * 10_000 < uint256(_o.snapshot) * crewOffboardQuorumBps) _passed = false;
    else _passed = _o.yeas > _o.nays;
  }
}
