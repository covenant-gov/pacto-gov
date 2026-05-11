// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {RangeValidator} from 'contracts/abstracts/RangeValidator.sol';
import {IQuiescent} from 'interfaces/abstracts/IQuiescent.sol';
import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IHatsEligibility} from 'hats-core/Interfaces/IHatsEligibility.sol';

/**
 * @title Quartermaster
 * @author Pacto
 * @notice Timelocked crew add/remove (bootstrap without delay); crew-hat `IHatsEligibility`; `QuartermasterRole` admin. Revokes via local flags + Hats re-checks
 * @dev EIP-1167 master; `initialize` for clones. Access = hats only
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
  uint256 public crewChangeDelay;
  /// @inheritdoc IQuartermaster
  bool public mutinyActive;

  /// @inheritdoc IQuartermaster
  mapping(address _candidate => uint256 _executableAt) public pendingCrewAddAt;
  /// @inheritdoc IQuartermaster
  mapping(address _crew => uint256 _executableAt) public pendingCrewRemoveAt;

  /**
   * @notice Eligibility map backing `IHatsEligibility.getWearerStatus` for the crew hat.
   * @dev Set to `true` on mint (including mutiny paths) and to `false` on executed removal.
   */
  mapping(address _wearer => bool _eligible) internal _crewEligible;

  /// @notice Count of outstanding pending adds. Used by `isQuiet`.
  uint256 internal _pendingAddCount;
  /// @notice Count of outstanding pending removes. Used by `isQuiet`.
  uint256 internal _pendingRemoveCount;

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
  function initialize(InitParams calldata _p) external override initializer {
    _validateDelay(_p.crewChangeDelay);
    captainHatId = _p.captainHatId;
    crewHatId = _p.crewHatId;
    mutinyRoleHatId = _p.mutinyRoleHatId;
    quartermasterRoleHatId = _p.quartermasterRoleHatId;
    treasuryAuthorityRoleHatId = _p.treasuryAuthorityRoleHatId;
    crewChangeDelay = _p.crewChangeDelay;
    emit CrewChangeDelayUpdated(0, _p.crewChangeDelay);
  }

  /*///////////////////////////////////////////////////////////////
                        CAPTAIN-GATED: ADDITION
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function requestAddCrew(address _candidate) external override onlyHatWearer(captainHatId) {
    if (mutinyActive) revert Quartermaster_MutinyActive();
    _validateAddCandidate(_candidate);
    if (_HATS.hatSupply(crewHatId) >= _HATS.getHatMaxSupply(crewHatId)) revert Quartermaster_CrewFull();

    if (pendingCrewAddAt[_candidate] == 0) _pendingAddCount++;
    uint256 _eta = block.timestamp + _crewAddDelay();
    pendingCrewAddAt[_candidate] = _eta;
    emit CrewAddRequested(_candidate, _eta);
  }

  /// @inheritdoc IQuartermaster
  function bootstrapCrew(address[] calldata _candidates) external override onlyHatWearer(captainHatId) {
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (_HATS.hatSupply(crewHatId) != 0) revert Quartermaster_BootstrapRequiresEmptyCrew();

    uint256 _n = _candidates.length;
    if (_n == 0) revert Quartermaster_BootstrapEmpty();

    uint256 _max = uint256(_HATS.getHatMaxSupply(crewHatId));
    if (_n > _max) revert Quartermaster_CrewFull();

    for (uint256 _i = 0; _i < _n; _i++) {
      address _c = _candidates[_i];
      _validateAddCandidate(_c);
      for (uint256 _j = _i + 1; _j < _n; _j++) {
        if (_c == _candidates[_j]) revert Quartermaster_DuplicateCrewAdd(_c);
      }
    }

    for (uint256 _i = 0; _i < _n; _i++) {
      address _a = _candidates[_i];
      _crewEligible[_a] = true;
      _HATS.mintHat(crewHatId, _a);
      emit CrewAddExecuted(_a);
    }
  }

  /// @inheritdoc IQuartermaster
  function cancelAddCrew(address _candidate) external override onlyHatWearer(captainHatId) {
    if (pendingCrewAddAt[_candidate] == 0) revert Quartermaster_NotPending(_candidate);
    delete pendingCrewAddAt[_candidate];
    _pendingAddCount--;
    emit CrewAddCancelled(_candidate);
  }

  /// @inheritdoc IQuartermaster
  function executeAddCrew(address _candidate) external override {
    uint256 _eta = pendingCrewAddAt[_candidate];
    if (_eta == 0) revert Quartermaster_NotPending(_candidate);
    if (block.timestamp < _eta) revert Quartermaster_StillLocked(_candidate, _eta);
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (_HATS.isWearerOfHat(_candidate, crewHatId)) revert Quartermaster_AlreadyCrew(_candidate);

    delete pendingCrewAddAt[_candidate];
    _pendingAddCount--;
    _crewEligible[_candidate] = true;
    _HATS.mintHat(crewHatId, _candidate);
    emit CrewAddExecuted(_candidate);
  }

  /*///////////////////////////////////////////////////////////////
                        CAPTAIN-GATED: REMOVAL
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function requestRemoveCrew(address _crew) external override onlyHatWearer(captainHatId) {
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (_crew == address(0)) revert Quartermaster_ZeroAddress();
    if (!_HATS.isWearerOfHat(_crew, crewHatId)) revert Quartermaster_NotCrew(_crew);

    if (pendingCrewRemoveAt[_crew] == 0) _pendingRemoveCount++;
    uint256 _eta = block.timestamp + crewChangeDelay;
    pendingCrewRemoveAt[_crew] = _eta;
    emit CrewRemoveRequested(_crew, _eta);
  }

  /// @inheritdoc IQuartermaster
  function cancelRemoveCrew(address _crew) external override onlyHatWearer(captainHatId) {
    if (pendingCrewRemoveAt[_crew] == 0) revert Quartermaster_NotPending(_crew);
    delete pendingCrewRemoveAt[_crew];
    _pendingRemoveCount--;
    emit CrewRemoveCancelled(_crew);
  }

  /// @inheritdoc IQuartermaster
  function executeRemoveCrew(address _crew) external override {
    uint256 _eta = pendingCrewRemoveAt[_crew];
    if (_eta == 0) revert Quartermaster_NotPending(_crew);
    if (block.timestamp < _eta) revert Quartermaster_StillLocked(_crew, _eta);
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (!_HATS.isWearerOfHat(_crew, crewHatId)) revert Quartermaster_NotCrew(_crew);

    delete pendingCrewRemoveAt[_crew];
    _pendingRemoveCount--;
    _crewEligible[_crew] = false;
    _HATS.checkHatWearerStatus(crewHatId, _crew);
    emit CrewRemoveExecuted(_crew);
  }

  /*///////////////////////////////////////////////////////////////
                            MUTINY HOOKS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function mintCrewFromMutiny(address _formerCaptain) external override onlyHatWearer(mutinyRoleHatId) {
    if (_formerCaptain == address(0)) revert Quartermaster_ZeroAddress();
    if (_HATS.isWearerOfHat(_formerCaptain, crewHatId)) revert Quartermaster_AlreadyCrew(_formerCaptain);
    if (_HATS.hatSupply(crewHatId) >= _HATS.getHatMaxSupply(crewHatId)) revert Quartermaster_CrewFull();

    _crewEligible[_formerCaptain] = true;
    _HATS.mintHat(crewHatId, _formerCaptain);
    emit CrewMintedFromMutiny(_formerCaptain);
  }

  /// @inheritdoc IQuartermaster
  function crewHandoffForMutiny(
    address _formerCaptain,
    address _newCaptain
  ) external override onlyHatWearer(mutinyRoleHatId) {
    if (_formerCaptain == address(0) || _newCaptain == address(0)) {
      revert Quartermaster_ZeroAddress();
    }
    if (!_HATS.isWearerOfHat(_newCaptain, crewHatId)) revert Quartermaster_NotCrew(_newCaptain);
    if (_HATS.isWearerOfHat(_formerCaptain, crewHatId)) revert Quartermaster_AlreadyCrew(_formerCaptain);

    _crewEligible[_formerCaptain] = true;
    _HATS.transferHat(crewHatId, _newCaptain, _formerCaptain);
    emit CrewHandoffForMutiny(_formerCaptain, _newCaptain);
  }

  /// @inheritdoc IQuartermaster
  function setMutinyActive(bool _active) external override onlyHatWearer(mutinyRoleHatId) {
    mutinyActive = _active;
    emit MutinyActiveSet(_active);
  }

  /*///////////////////////////////////////////////////////////////
                        PARAMETER SETTERS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function setCrewChangeDelay(uint256 _newValue) external override onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateDelay(_newValue);
    uint256 _old = crewChangeDelay;
    crewChangeDelay = _newValue;
    emit CrewChangeDelayUpdated(_old, _newValue);
  }

  /*///////////////////////////////////////////////////////////////
                        VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IHatsEligibility
  function getWearerStatus(
    address _wearer,
    uint256 /*_hatId*/
  ) external view override returns (bool _eligible, bool _standing) {
    _eligible = _crewEligible[_wearer];
    _standing = true;
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view override returns (bool _quiet) {
    _quiet = _pendingAddCount == 0 && _pendingRemoveCount == 0 && !mutinyActive;
  }

  /*///////////////////////////////////////////////////////////////
                        INTERNAL LOGIC
  //////////////////////////////////////////////////////////////*/

  function _crewAddDelay() internal view returns (uint256 _delay) {
    _delay = _HATS.hatSupply(crewHatId) == 0 ? 0 : crewChangeDelay;
  }

  function _validateAddCandidate(address _candidate) internal view {
    if (_candidate == address(0)) revert Quartermaster_ZeroAddress();
    if (_HATS.isWearerOfHat(_candidate, captainHatId)) revert Quartermaster_CandidateIsCaptain(_candidate);
    if (_HATS.isWearerOfHat(_candidate, crewHatId)) revert Quartermaster_AlreadyCrew(_candidate);
  }
}
