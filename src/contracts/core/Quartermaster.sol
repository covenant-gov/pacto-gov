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
 * @notice Timelocked crew add/remove (bootstrap without delay); crew-hat `IHatsEligibility`; `QuartermasterRole` admin. Revokes via local flags + Hats re-checks
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
  bool public mutinyActive;

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
  function requestAddCrew(address _candidate) external onlyHatWearer(captainHatId) {
    if (mutinyActive) revert Quartermaster_MutinyActive();
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
    if (mutinyActive) revert Quartermaster_MutinyActive();
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
    if (mutinyActive) revert Quartermaster_MutinyActive();
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
    if (mutinyActive) revert Quartermaster_MutinyActive();
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
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (!_HATS.isWearerOfHat(_crew, crewHatId)) revert Quartermaster_NotCrew(_crew);

    delete pendingCrewRemoveAt[_crew];
    pendingRemoveCount--;
    _pendingRemoves.remove(_crew);
    crewEligible[_crew] = false;
    _HATS.checkHatWearerStatus(crewHatId, _crew);
    emit CrewRemoveExecuted(_crew);
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
  function pendingAddAt(uint256 _i) external view returns (address _candidate, uint256 _executableAt) {
    _candidate = _pendingAdds.at(_i);
    _executableAt = pendingCrewAddAt[_candidate];
  }

  /// @inheritdoc IQuartermaster
  function pendingRemoveAt(uint256 _i) external view returns (address _crew, uint256 _executableAt) {
    _crew = _pendingRemoves.at(_i);
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
    _quiet = pendingAddCount == 0 && pendingRemoveCount == 0 && !mutinyActive;
  }

  /// @inheritdoc IHatGated
  function hats() public view override(IHatGated, HatGated) returns (IHats _hats) {
    _hats = _HATS;
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
}
