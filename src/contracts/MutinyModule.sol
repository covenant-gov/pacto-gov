// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IMutinyModule} from 'interfaces/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';

/**
 * @title MutinyModule
 * @author Pacto
 * @notice Crew mutiny voting, strict majority of snapshot crew supply, captain `transferHat` + Quartermaster crew paths.
 * @dev Deployment: `Quartermaster` is constructed with `mutinyModule == address(this)`. Predict this module’s address
 *      (e.g. `vm.computeCreateAddress` on the deployer nonce, or CREATE2) before deploying `Quartermaster`, then deploy
 *      this contract so its address matches that prediction. Not a Zodiac `Module` in v1; wire avatar/exec context in scripts.
 */
contract MutinyModule is IMutinyModule {
  IQuartermaster internal immutable _quartermaster;
  IHats internal immutable _hats;
  uint256 internal immutable _captainHatId;
  uint256 internal immutable _crewHatId;

  /// @dev Tracked captain for `transferHat` `_from`; must match chain state at execute (captain `maxSupply == 1`).
  address internal _captainWearer;

  uint256 internal _latestMutinyId;
  uint256 internal _openMutinyId;

  mapping(uint256 _mutinyId => IMutinyModule.Round _round) internal _rounds;
  mapping(uint256 _mutinyId => uint256 _yeas) internal _yeaVotes;
  mapping(uint256 _mutinyId => mapping(address _voter => bool)) internal _hasVoted;

  /**
   * @notice Deploys the mutiny module
   * @param quartermaster_ Linked Quartermaster (must have set `mutinyModule` to this contract’s address)
   * @param hats_ Hats Protocol singleton
   * @param captainHatId_ Captain hat id (`transferHat` source / target)
   * @param crewHatId_ Crew hat id (electorate / supply snapshot)
   * @param initialCaptain_ Current captain wearer at deploy (must hold `captainHatId_`)
   */
  constructor(
    IQuartermaster quartermaster_,
    IHats hats_,
    uint256 captainHatId_,
    uint256 crewHatId_,
    address initialCaptain_
  ) {
    if (
      address(quartermaster_) == address(0) || address(hats_) == address(0) || initialCaptain_ == address(0)
        || captainHatId_ == 0 || crewHatId_ == 0
    ) {
      revert MutinyModule_InvalidSuccessor();
    }
    _quartermaster = quartermaster_;
    _hats = hats_;
    _captainHatId = captainHatId_;
    _crewHatId = crewHatId_;
    _captainWearer = initialCaptain_;
  }

  /// @inheritdoc IMutinyModule
  function startMutiny(address _proposedNewCaptain) external {
    if (_openMutinyId != 0) revert MutinyModule_MutinyAlreadyActive();
    if (_proposedNewCaptain == address(0)) revert MutinyModule_InvalidSuccessor();
    if (_proposedNewCaptain == _captainWearer) revert MutinyModule_InvalidSuccessor();
    if (_hats.balanceOf(_proposedNewCaptain, _captainHatId) != 0) revert MutinyModule_InvalidSuccessor();

    if (_hats.balanceOf(msg.sender, _crewHatId) == 0) revert MutinyModule_NotEligibleCrew();

    uint256 _eligible = _hats.hatSupply(_crewHatId);
    if (_eligible == 0) revert MutinyModule_InvalidMutiny();

    _latestMutinyId++;
    uint256 _id = _latestMutinyId;

    _rounds[_id] = IMutinyModule.Round({
      proposedNewCaptain: _proposedNewCaptain,
      snapshotBlock: block.number,
      eligibleCrewCount: _eligible,
      open: true,
      executed: false
    });
    _openMutinyId = _id;

    _quartermaster.setMutinyActive(true);

    emit MutinyStarted(_id, _proposedNewCaptain, block.number);
  }

  /// @inheritdoc IMutinyModule
  function castVote(uint256 _mutinyId, bool _yea) external {
    IMutinyModule.Round memory _r = _rounds[_mutinyId];
    if (!_r.open || _r.executed) revert MutinyModule_InvalidMutiny();
    if (_hasVoted[_mutinyId][msg.sender]) revert MutinyModule_AlreadyVoted();
    if (_hats.balanceOf(msg.sender, _crewHatId) == 0) revert MutinyModule_NotEligibleCrew();

    _hasVoted[_mutinyId][msg.sender] = true;
    if (_yea) {
      _yeaVotes[_mutinyId]++;
    }

    emit VoteCast(_mutinyId, msg.sender, _yea);
  }

  /// @inheritdoc IMutinyModule
  function executeMutiny(uint256 _mutinyId) external {
    IMutinyModule.Round memory _r = _rounds[_mutinyId];
    if (!_r.open || _r.executed) revert MutinyModule_InvalidMutiny();

    uint256 _yeas = _yeaVotes[_mutinyId];
    if (_yeas <= _r.eligibleCrewCount / 2) revert MutinyModule_NotExecutable();

    address _former = _captainWearer;
    address _newCaptain = _r.proposedNewCaptain;

    if (_hats.balanceOf(_former, _captainHatId) != 1) revert MutinyModule_NotExecutable();

    _hats.transferHat(_captainHatId, _former, _newCaptain);

    if (_newCaptain.code.length > 0) {
      _quartermaster.mintCrewFromMutiny(_former);
    } else if (_hats.balanceOf(_newCaptain, _crewHatId) != 0) {
      _quartermaster.crewHandoffForMutiny(_former, _newCaptain);
    } else {
      _quartermaster.mintCrewFromMutiny(_former);
    }

    _rounds[_mutinyId].open = false;
    _rounds[_mutinyId].executed = true;
    _openMutinyId = 0;
    _captainWearer = _newCaptain;

    _quartermaster.setMutinyActive(false);

    emit MutinyExecuted(_mutinyId, _newCaptain);
  }

  /// @inheritdoc IMutinyModule
  function QUARTERMASTER() external view returns (address _quartermasterOut) {
    return address(_quartermaster);
  }

  /// @inheritdoc IMutinyModule
  function HATS() external view returns (address _hatsOut) {
    return address(_hats);
  }

  /// @inheritdoc IMutinyModule
  function CAPTAIN_HAT_ID() external view returns (uint256 _captainHatIdOut) {
    return _captainHatId;
  }

  /// @inheritdoc IMutinyModule
  function CREW_HAT_ID() external view returns (uint256 _crewHatIdOut) {
    return _crewHatId;
  }

  /// @inheritdoc IMutinyModule
  function latestMutinyId() external view returns (uint256 _id) {
    return _latestMutinyId;
  }

  /// @inheritdoc IMutinyModule
  function isMutinyOpen(uint256 _mutinyId) external view returns (bool _open) {
    return _rounds[_mutinyId].open && !_rounds[_mutinyId].executed;
  }

  /// @inheritdoc IMutinyModule
  function proposedNewCaptain(uint256 _mutinyId) external view returns (address _proposed) {
    return _rounds[_mutinyId].proposedNewCaptain;
  }

  /// @inheritdoc IMutinyModule
  function mutinySnapshotBlock(uint256 _mutinyId) external view returns (uint256 _block) {
    return _rounds[_mutinyId].snapshotBlock;
  }

  /// @inheritdoc IMutinyModule
  function eligibleCrewCount(uint256 _mutinyId) external view returns (uint256 _count) {
    return _rounds[_mutinyId].eligibleCrewCount;
  }

  /// @inheritdoc IMutinyModule
  function yeaVotes(uint256 _mutinyId) external view returns (uint256 _yeas) {
    return _yeaVotes[_mutinyId];
  }

  /// @inheritdoc IMutinyModule
  function hasVoted(uint256 _mutinyId, address _voter) external view returns (bool _voted) {
    return _hasVoted[_mutinyId][_voter];
  }

  /// @inheritdoc IMutinyModule
  function isMutinyExecuted(uint256 _mutinyId) external view returns (bool _executed) {
    return _rounds[_mutinyId].executed;
  }
}
