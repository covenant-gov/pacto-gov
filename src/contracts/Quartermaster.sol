// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';

/**
 * @title Quartermaster
 * @author Pacto
 * @notice Timelocked crew adds/removes via Hats; mutiny-only hooks for succession paths.
 */
contract Quartermaster is IQuartermaster {
  /// @inheritdoc IQuartermaster
  address public immutable HATS;

  /// @inheritdoc IQuartermaster
  uint256 public immutable CREW_HAT_ID;

  /// @inheritdoc IQuartermaster
  uint256 public immutable CAPTAIN_HAT_ID;

  /// @inheritdoc IQuartermaster
  uint256 public immutable CREW_CHANGE_DELAY;

  /// @inheritdoc IQuartermaster
  address public immutable MUTINY_MODULE;

  /// @inheritdoc IQuartermaster
  bool public mutinyActive;

  /// @inheritdoc IQuartermaster
  mapping(address _candidate => uint256 _executableAt) public pendingCrewAddAt;

  /// @inheritdoc IQuartermaster
  mapping(address _crew => uint256 _executableAt) public pendingCrewRemoveAt;

  /**
   * @notice Deploys the Quartermaster
   * @param hatsAddr Hats Protocol (or compatible) contract
   * @param _crewHatId Crew hat id this contract administers in Hats
   * @param _captainHatId Captain hat id for access control
   * @param _crewChangeDelay Seconds between schedule and execute
   * @param _mutinyModule Mutiny module address (may not be zero)
   */
  constructor(
    address hatsAddr,
    uint256 _crewHatId,
    uint256 _captainHatId,
    uint256 _crewChangeDelay,
    address _mutinyModule
  ) {
    if (hatsAddr == address(0) || _mutinyModule == address(0)) {
      revert Quartermaster_InvalidCandidate();
    }
    HATS = hatsAddr;
    CREW_HAT_ID = _crewHatId;
    CAPTAIN_HAT_ID = _captainHatId;
    CREW_CHANGE_DELAY = _crewChangeDelay;
    MUTINY_MODULE = _mutinyModule;
  }

  /// @inheritdoc IQuartermaster
  function requestAddCrew(address _candidate) external {
    _onlyCaptain();
    if (mutinyActive) revert Quartermaster_MutinyActive();
    _validateCrewCandidate(_candidate);
    uint256 _at = block.timestamp + CREW_CHANGE_DELAY;
    pendingCrewAddAt[_candidate] = _at;
    emit CrewAddScheduled(_candidate, _at);
  }

  /// @inheritdoc IQuartermaster
  function requestRemoveCrew(address _crew) external {
    _onlyCaptain();
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (IHats(HATS).balanceOf(_crew, CREW_HAT_ID) == 0) revert Quartermaster_InvalidCandidate();
    uint256 _at = block.timestamp + CREW_CHANGE_DELAY;
    pendingCrewRemoveAt[_crew] = _at;
    emit CrewRemoveScheduled(_crew, _at);
  }

  /// @inheritdoc IQuartermaster
  function executeAddCrew(address _candidate) external {
    uint256 _pending = pendingCrewAddAt[_candidate];
    if (_pending == 0) revert Quartermaster_NoPendingOperation();
    if (block.timestamp < _pending) revert Quartermaster_NotExecutable();
    pendingCrewAddAt[_candidate] = 0;
    _validateCrewCandidate(_candidate);
    _mintCrew(_candidate);
    emit CrewAddExecuted(_candidate);
  }

  /// @inheritdoc IQuartermaster
  function executeRemoveCrew(address _crew) external {
    uint256 _pending = pendingCrewRemoveAt[_crew];
    if (_pending == 0) revert Quartermaster_NoPendingOperation();
    if (block.timestamp < _pending) revert Quartermaster_NotExecutable();
    pendingCrewRemoveAt[_crew] = 0;
    if (IHats(HATS).balanceOf(_crew, CREW_HAT_ID) == 0) revert Quartermaster_NoPendingOperation();
    IHats(HATS).setHatWearerStatus(CREW_HAT_ID, _crew, false, false);
    emit CrewRemoveExecuted(_crew);
  }

  /// @inheritdoc IQuartermaster
  function mintCrewFromMutiny(address _to) external {
    _onlyMutinyModule();
    if (_isCaptain(_to)) revert Quartermaster_InvalidCandidate();
    _mintCrew(_to);
  }

  /// @inheritdoc IQuartermaster
  function crewHandoffForMutiny(address _formerCaptain, address _newCaptain) external {
    _onlyMutinyModule();
    if (_formerCaptain == address(0) || _newCaptain == address(0)) revert Quartermaster_InvalidCandidate();
    if (IHats(HATS).balanceOf(_newCaptain, CREW_HAT_ID) != 0) {
      IHats(HATS).transferHat(CREW_HAT_ID, _newCaptain, _formerCaptain);
    } else {
      _mintCrew(_formerCaptain);
    }
  }

  /// @inheritdoc IQuartermaster
  function setMutinyActive(bool _active) external {
    _onlyMutinyModule();
    mutinyActive = _active;
    emit MutinyActiveSet(_active);
  }

  function _mintCrew(address _wearer) internal {
    uint32 _supply = IHats(HATS).hatSupply(CREW_HAT_ID);
    uint32 _max = IHats(HATS).getHatMaxSupply(CREW_HAT_ID);
    if (_supply >= _max) revert Quartermaster_CrewHatMaxSupply();
    IHats(HATS).mintHat(CREW_HAT_ID, _wearer);
  }

  function _onlyCaptain() internal view {
    if (IHats(HATS).balanceOf(msg.sender, CAPTAIN_HAT_ID) != 1) {
      revert Quartermaster_OnlyCaptain();
    }
  }

  function _onlyMutinyModule() internal view {
    if (msg.sender != MUTINY_MODULE) {
      revert Quartermaster_OnlyMutinyModule();
    }
  }

  function _isCaptain(address _account) internal view returns (bool) {
    return IHats(HATS).balanceOf(_account, CAPTAIN_HAT_ID) == 1;
  }

  function _validateCrewCandidate(address _candidate) internal view {
    if (_candidate == address(0)) revert Quartermaster_InvalidCandidate();
    if (_isCaptain(_candidate)) revert Quartermaster_InvalidCandidate();
    if (IHats(HATS).balanceOf(_candidate, CREW_HAT_ID) != 0) revert Quartermaster_InvalidCandidate();
  }
}
