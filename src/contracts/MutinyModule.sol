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
  /// @inheritdoc IMutinyModule
  address public immutable QUARTERMASTER;

  /// @inheritdoc IMutinyModule
  address public immutable HATS;

  /// @inheritdoc IMutinyModule
  uint256 public immutable CAPTAIN_HAT_ID;

  /// @inheritdoc IMutinyModule
  uint256 public immutable CREW_HAT_ID;

  /// @dev Tracked captain for `transferHat` `_from`; must match chain state at execute (captain `maxSupply == 1`).
  address internal _captainWearer;

  /// @inheritdoc IMutinyModule
  uint256 public latestMutinyId;

  uint256 internal _openMutinyId;

  /// @inheritdoc IMutinyModule
  mapping(uint256 _mutinyId => IMutinyModule.Round _round) public rounds;

  /// @inheritdoc IMutinyModule
  mapping(uint256 _mutinyId => uint256 _yeas) public yeaVotes;

  /// @inheritdoc IMutinyModule
  mapping(uint256 _mutinyId => mapping(address _voter => bool)) public hasVoted;

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
    QUARTERMASTER = address(quartermaster_);
    HATS = address(hats_);
    CAPTAIN_HAT_ID = captainHatId_;
    CREW_HAT_ID = crewHatId_;
    _captainWearer = initialCaptain_;
  }

  /// @inheritdoc IMutinyModule
  function startMutiny(address _proposedNewCaptain) external {
    if (_openMutinyId != 0) revert MutinyModule_MutinyAlreadyActive();
    if (_proposedNewCaptain == address(0)) revert MutinyModule_InvalidSuccessor();
    if (_proposedNewCaptain == _captainWearer) revert MutinyModule_InvalidSuccessor();
    if (IHats(HATS).balanceOf(_proposedNewCaptain, CAPTAIN_HAT_ID) != 0) revert MutinyModule_InvalidSuccessor();

    if (IHats(HATS).balanceOf(msg.sender, CREW_HAT_ID) == 0) revert MutinyModule_NotEligibleCrew();

    uint256 _eligible = IHats(HATS).hatSupply(CREW_HAT_ID);
    if (_eligible == 0) revert MutinyModule_InvalidMutiny();

    latestMutinyId++;
    uint256 _id = latestMutinyId;

    rounds[_id] = IMutinyModule.Round({
      proposedNewCaptain: _proposedNewCaptain,
      snapshotBlock: block.number,
      eligibleCrewCount: _eligible,
      open: true,
      executed: false
    });
    _openMutinyId = _id;

    IQuartermaster(QUARTERMASTER).setMutinyActive(true);

    emit MutinyStarted(_id, _proposedNewCaptain, block.number);
  }

  /// @inheritdoc IMutinyModule
  function castVote(uint256 _mutinyId, bool _yea) external {
    IMutinyModule.Round memory _r = rounds[_mutinyId];
    if (!_r.open || _r.executed) revert MutinyModule_InvalidMutiny();
    if (hasVoted[_mutinyId][msg.sender]) revert MutinyModule_AlreadyVoted();
    if (IHats(HATS).balanceOf(msg.sender, CREW_HAT_ID) == 0) revert MutinyModule_NotEligibleCrew();

    hasVoted[_mutinyId][msg.sender] = true;
    if (_yea) {
      yeaVotes[_mutinyId]++;
    }

    emit VoteCast(_mutinyId, msg.sender, _yea);
  }

  /// @inheritdoc IMutinyModule
  function executeMutiny(uint256 _mutinyId) external {
    IMutinyModule.Round memory _r = rounds[_mutinyId];
    if (!_r.open || _r.executed) revert MutinyModule_InvalidMutiny();

    uint256 _yeas = yeaVotes[_mutinyId];
    if (_yeas <= _r.eligibleCrewCount / 2) revert MutinyModule_NotExecutable();

    address _former = _captainWearer;
    address _newCaptain = _r.proposedNewCaptain;

    if (IHats(HATS).balanceOf(_former, CAPTAIN_HAT_ID) != 1) revert MutinyModule_NotExecutable();

    IHats(HATS).transferHat(CAPTAIN_HAT_ID, _former, _newCaptain);

    if (_newCaptain.code.length > 0) {
      IQuartermaster(QUARTERMASTER).mintCrewFromMutiny(_former);
    } else if (IHats(HATS).balanceOf(_newCaptain, CREW_HAT_ID) != 0) {
      IQuartermaster(QUARTERMASTER).crewHandoffForMutiny(_former, _newCaptain);
    } else {
      IQuartermaster(QUARTERMASTER).mintCrewFromMutiny(_former);
    }

    rounds[_mutinyId].open = false;
    rounds[_mutinyId].executed = true;
    _openMutinyId = 0;
    _captainWearer = _newCaptain;

    IQuartermaster(QUARTERMASTER).setMutinyActive(false);

    emit MutinyExecuted(_mutinyId, _newCaptain);
  }

  /// @inheritdoc IMutinyModule
  function isMutinyOpen(uint256 _mutinyId) external view returns (bool _open) {
    IMutinyModule.Round memory _r = rounds[_mutinyId];
    return _r.open && !_r.executed;
  }
}
