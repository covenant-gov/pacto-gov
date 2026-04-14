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
  IHats internal immutable _hats;

  /// @inheritdoc IQuartermaster
  uint256 public immutable CREW_HAT_ID;

  /// @inheritdoc IQuartermaster
  uint256 public immutable CAPTAIN_HAT_ID;

  /// @inheritdoc IQuartermaster
  uint256 public immutable crewChangeDelay;

  /// @inheritdoc IQuartermaster
  address public immutable mutinyModule;

  /// @inheritdoc IQuartermaster
  bool public mutinyActive;

  mapping(address _candidate => uint256 _executableAt) internal _pendingCrewAddAt;
  mapping(address _crew => uint256 _executableAt) internal _pendingCrewRemoveAt;

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
    _hats = IHats(hatsAddr);
    CREW_HAT_ID = _crewHatId;
    CAPTAIN_HAT_ID = _captainHatId;
    crewChangeDelay = _crewChangeDelay;
    mutinyModule = _mutinyModule;
  }

  /// @inheritdoc IQuartermaster
  function requestAddCrew(address _candidate) external {
    _onlyCaptain();
    if (mutinyActive) revert Quartermaster_MutinyActive();
    _validateCrewCandidate(_candidate);
    uint256 _at = block.timestamp + crewChangeDelay;
    _pendingCrewAddAt[_candidate] = _at;
    emit CrewAddScheduled(_candidate, _at);
  }

  /// @inheritdoc IQuartermaster
  function requestRemoveCrew(address _crew) external {
    _onlyCaptain();
    if (mutinyActive) revert Quartermaster_MutinyActive();
    if (_hats.balanceOf(_crew, CREW_HAT_ID) == 0) revert Quartermaster_InvalidCandidate();
    uint256 _at = block.timestamp + crewChangeDelay;
    _pendingCrewRemoveAt[_crew] = _at;
    emit CrewRemoveScheduled(_crew, _at);
  }

  /// @inheritdoc IQuartermaster
  function executeAddCrew(address _candidate) external {
    uint256 _pending = _pendingCrewAddAt[_candidate];
    if (_pending == 0) revert Quartermaster_NoPendingOperation();
    if (block.timestamp < _pending) revert Quartermaster_NotExecutable();
    _pendingCrewAddAt[_candidate] = 0;
    _validateCrewCandidate(_candidate);
    _mintCrew(_candidate);
    emit CrewAddExecuted(_candidate);
  }

  /// @inheritdoc IQuartermaster
  function executeRemoveCrew(address _crew) external {
    uint256 _pending = _pendingCrewRemoveAt[_crew];
    if (_pending == 0) revert Quartermaster_NoPendingOperation();
    if (block.timestamp < _pending) revert Quartermaster_NotExecutable();
    _pendingCrewRemoveAt[_crew] = 0;
    if (_hats.balanceOf(_crew, CREW_HAT_ID) == 0) revert Quartermaster_NoPendingOperation();
    _hats.setHatWearerStatus(CREW_HAT_ID, _crew, false, false);
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
    if (_hats.balanceOf(_newCaptain, CREW_HAT_ID) != 0) {
      _hats.transferHat(CREW_HAT_ID, _newCaptain, _formerCaptain);
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

  /// @inheritdoc IQuartermaster
  function pendingCrewAddAt(address _candidate) external view returns (uint256 _executableAt) {
    return _pendingCrewAddAt[_candidate];
  }

  /// @inheritdoc IQuartermaster
  function pendingCrewRemoveAt(address _crew) external view returns (uint256 _executableAt) {
    return _pendingCrewRemoveAt[_crew];
  }

  /// @inheritdoc IQuartermaster
  function HATS() external view returns (address _hatsOut) {
    return address(_hats);
  }

  function _mintCrew(address _wearer) internal {
    uint32 _supply = _hats.hatSupply(CREW_HAT_ID);
    uint32 _max = _hats.getHatMaxSupply(CREW_HAT_ID);
    if (_supply >= _max) revert Quartermaster_CrewHatMaxSupply();
    _hats.mintHat(CREW_HAT_ID, _wearer);
  }

  function _onlyCaptain() internal view {
    if (_hats.balanceOf(msg.sender, CAPTAIN_HAT_ID) != 1) {
      revert Quartermaster_OnlyCaptain();
    }
  }

  function _onlyMutinyModule() internal view {
    if (msg.sender != mutinyModule) {
      revert Quartermaster_OnlyMutinyModule();
    }
  }

  function _isCaptain(address _account) internal view returns (bool) {
    return _hats.balanceOf(_account, CAPTAIN_HAT_ID) == 1;
  }

  function _validateCrewCandidate(address _candidate) internal view {
    if (_candidate == address(0)) revert Quartermaster_InvalidCandidate();
    if (_isCaptain(_candidate)) revert Quartermaster_InvalidCandidate();
    if (_hats.balanceOf(_candidate, CREW_HAT_ID) != 0) revert Quartermaster_InvalidCandidate();
  }
}
