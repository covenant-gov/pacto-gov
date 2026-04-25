// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {GovernanceParams} from 'contracts/abstracts/GovernanceParams.sol';
import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';
import {IQuiescent} from 'interfaces/IQuiescent.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IHatsEligibility} from 'hats-core/Interfaces/IHatsEligibility.sol';

/**
 * @title Quartermaster
 * @author Pacto
 * @notice Timelocked crew add/remove; crew-hat `IHatsEligibility`; `QuartermasterRole` admin. Revokes via local flags + Hats re-checks
 * @dev EIP-1167 master; `initialize` for clones. Access = hats only
 */
contract Quartermaster is IQuartermaster, IHatsEligibility, HatGated, GovernanceParams, Initializable {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  uint256 public override CAPTAIN_HAT_ID;
  /// @inheritdoc IQuartermaster
  uint256 public override CREW_HAT_ID;
  /// @inheritdoc IQuartermaster
  uint256 public override MUTINY_ROLE_HAT_ID;
  /// @inheritdoc IQuartermaster
  uint256 public override QUARTERMASTER_ROLE_HAT_ID;
  /// @inheritdoc IQuartermaster
  uint256 public override TREASURY_AUTHORITY_ROLE_HAT_ID;
  /// @inheritdoc IQuartermaster
  uint256 public override crewChangeDelay;
  /// @inheritdoc IQuartermaster
  bool public override mutinyActive;

  /// @inheritdoc IQuartermaster
  mapping(address _candidate => uint256 _executableAt) public override pendingCrewAddAt;
  /// @inheritdoc IQuartermaster
  mapping(address _crew => uint256 _executableAt) public override pendingCrewRemoveAt;

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
    CAPTAIN_HAT_ID = _p.captainHatId;
    CREW_HAT_ID = _p.crewHatId;
    MUTINY_ROLE_HAT_ID = _p.mutinyRoleHatId;
    QUARTERMASTER_ROLE_HAT_ID = _p.quartermasterRoleHatId;
    TREASURY_AUTHORITY_ROLE_HAT_ID = _p.treasuryAuthorityRoleHatId;
    crewChangeDelay = _p.crewChangeDelay;
    emit CrewChangeDelayUpdated(0, _p.crewChangeDelay);
  }

  /*///////////////////////////////////////////////////////////////
                        CAPTAIN-GATED: ADDITION
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function requestAddCrew(address _candidate) external override onlyHatWearer(CAPTAIN_HAT_ID) {
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (_candidate == address(0)) revert Quartermaster_ZeroAddress();
    if (_HATS.isWearerOfHat(_candidate, CAPTAIN_HAT_ID)) revert Quartermaster_CandidateIsCaptain(_candidate);
    if (_HATS.isWearerOfHat(_candidate, CREW_HAT_ID)) revert Quartermaster_AlreadyCrew(_candidate);
    if (_HATS.hatSupply(CREW_HAT_ID) >= _HATS.getHatMaxSupply(CREW_HAT_ID)) revert Quartermaster_CrewFull();

    if (pendingCrewAddAt[_candidate] == 0) _pendingAddCount++;
    uint256 _eta = block.timestamp + crewChangeDelay;
    pendingCrewAddAt[_candidate] = _eta;
    emit CrewAddRequested(_candidate, _eta);
  }

  /// @inheritdoc IQuartermaster
  function cancelAddCrew(address _candidate) external override onlyHatWearer(CAPTAIN_HAT_ID) {
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
    if (_HATS.isWearerOfHat(_candidate, CREW_HAT_ID)) revert Quartermaster_AlreadyCrew(_candidate);

    delete pendingCrewAddAt[_candidate];
    _pendingAddCount--;
    _crewEligible[_candidate] = true;
    _HATS.mintHat(CREW_HAT_ID, _candidate);
    emit CrewAddExecuted(_candidate);
  }

  /*///////////////////////////////////////////////////////////////
                        CAPTAIN-GATED: REMOVAL
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function requestRemoveCrew(address _crew) external override onlyHatWearer(CAPTAIN_HAT_ID) {
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (_crew == address(0)) revert Quartermaster_ZeroAddress();
    if (!_HATS.isWearerOfHat(_crew, CREW_HAT_ID)) revert Quartermaster_NotCrew(_crew);

    if (pendingCrewRemoveAt[_crew] == 0) _pendingRemoveCount++;
    uint256 _eta = block.timestamp + crewChangeDelay;
    pendingCrewRemoveAt[_crew] = _eta;
    emit CrewRemoveRequested(_crew, _eta);
  }

  /// @inheritdoc IQuartermaster
  function cancelRemoveCrew(address _crew) external override onlyHatWearer(CAPTAIN_HAT_ID) {
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
    if (!_HATS.isWearerOfHat(_crew, CREW_HAT_ID)) revert Quartermaster_NotCrew(_crew);

    delete pendingCrewRemoveAt[_crew];
    _pendingRemoveCount--;
    _crewEligible[_crew] = false;
    _HATS.checkHatWearerStatus(CREW_HAT_ID, _crew);
    emit CrewRemoveExecuted(_crew);
  }

  /*///////////////////////////////////////////////////////////////
                            MUTINY HOOKS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function mintCrewFromMutiny(address _formerCaptain) external override onlyHatWearer(MUTINY_ROLE_HAT_ID) {
    if (_formerCaptain == address(0)) revert Quartermaster_ZeroAddress();
    if (_HATS.isWearerOfHat(_formerCaptain, CREW_HAT_ID)) revert Quartermaster_AlreadyCrew(_formerCaptain);
    if (_HATS.hatSupply(CREW_HAT_ID) >= _HATS.getHatMaxSupply(CREW_HAT_ID)) revert Quartermaster_CrewFull();

    _crewEligible[_formerCaptain] = true;
    _HATS.mintHat(CREW_HAT_ID, _formerCaptain);
    emit CrewMintedFromMutiny(_formerCaptain);
  }

  /// @inheritdoc IQuartermaster
  function crewHandoffForMutiny(
    address _formerCaptain,
    address _newCaptain
  ) external override onlyHatWearer(MUTINY_ROLE_HAT_ID) {
    if (_formerCaptain == address(0) || _newCaptain == address(0)) {
      revert Quartermaster_ZeroAddress();
    }
    if (!_HATS.isWearerOfHat(_newCaptain, CREW_HAT_ID)) revert Quartermaster_NotCrew(_newCaptain);
    if (_HATS.isWearerOfHat(_formerCaptain, CREW_HAT_ID)) revert Quartermaster_AlreadyCrew(_formerCaptain);

    _crewEligible[_formerCaptain] = true;
    _HATS.transferHat(CREW_HAT_ID, _newCaptain, _formerCaptain);
    emit CrewHandoffForMutiny(_formerCaptain, _newCaptain);
  }

  /// @inheritdoc IQuartermaster
  function setMutinyActive(bool _active) external override onlyHatWearer(MUTINY_ROLE_HAT_ID) {
    mutinyActive = _active;
    emit MutinyActiveSet(_active);
  }

  /*///////////////////////////////////////////////////////////////
                        PARAMETER SETTERS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IQuartermaster
  function setCrewChangeDelay(uint256 _newValue) external override onlyHatWearer(TREASURY_AUTHORITY_ROLE_HAT_ID) {
    _validateDelay(_newValue);
    uint256 _old = crewChangeDelay;
    crewChangeDelay = _newValue;
    emit CrewChangeDelayUpdated(_old, _newValue);
  }

  /*///////////////////////////////////////////////////////////////
                        VIEWS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns eligibility and standing for a prospective or current crew-hat wearer.
   * @dev Standing is always `true`; revocations are expressed purely via `eligible`. The
   *      hat id parameter is part of the `IHatsEligibility` ABI but not used here because
   *      this module is only ever attached to the crew hat; answering uniformly for any
   *      hat id keeps the function side-effect free and avoids a revert path in Hats.
   * @param _wearer Current or prospective crew-hat wearer.
   * @return eligible Whether the wearer is currently eligible.
   * @return standing Whether the wearer is in good standing (always `true`).
   */
  function getWearerStatus(
    address _wearer,
    uint256 /*_hatId*/
  ) external view override returns (bool eligible, bool standing) {
    return (_crewEligible[_wearer], true);
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view override returns (bool _quiet) {
    return _pendingAddCount == 0 && _pendingRemoveCount == 0 && !mutinyActive;
  }
}
