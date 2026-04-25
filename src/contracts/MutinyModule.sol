// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {IMutinyModule} from 'interfaces/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';
import {IQuiescent} from 'interfaces/IQuiescent.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IHatsEligibility} from 'hats-core/Interfaces/IHatsEligibility.sol';

/**
 * @title MutinyModule
 * @author Pacto
 * @notice 51% snapshot mutiny or captain resignation; `IHatsEligibility` for the captain hat; `Quartermaster.setMutinyActive` while a round is live
 * @dev EIP-1167 master. Hats has no `wearerOfHat(hatId)` — store `quartermaster` and re-check `isWearerOfHat` on each call. A mutiny with no timeout can pin QM in mutiny until governance intervenes; see product notes on participation risk
 */
contract MutinyModule is IMutinyModule, IHatsEligibility, HatGated, Initializable {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IMutinyModule
  uint256 public override CAPTAIN_HAT_ID;
  /// @inheritdoc IMutinyModule
  uint256 public override CREW_HAT_ID;
  /// @inheritdoc IMutinyModule
  uint256 public override MUTINY_ROLE_HAT_ID;
  /// @inheritdoc IMutinyModule
  uint256 public override QUARTERMASTER_ROLE_HAT_ID;
  /// @inheritdoc IMutinyModule
  address public override captain;
  /// @inheritdoc IMutinyModule
  address public override quartermaster;
  /// @inheritdoc IMutinyModule
  uint256 public override activeMutinyId;

  /// @notice Monotonic round id counter; first issued is `1`, `0` means no active mutiny
  uint256 internal _nextMutinyId;

  /// @notice Round state indexed by mutiny id.
  mapping(uint256 _mutinyId => MutinyRound _round) internal _rounds;
  /// @notice Vote-registry; `true` iff `_voter` has cast a yea in `_mutinyId`.
  mapping(uint256 _mutinyId => mapping(address _voter => bool _voted)) internal _hasVoted;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Master copy: sets immutable Hats; disables direct init on the implementation
   * @param hats_ Hats Protocol address
   */
  constructor(IHats hats_) HatGated(hats_) {
    _disableInitializers();
  }

  /// @inheritdoc IMutinyModule
  function initialize(InitParams calldata _p) external override initializer {
    if (_p.captain == address(0) || _p.quartermaster == address(0)) revert MutinyModule_ZeroAddress();
    CAPTAIN_HAT_ID = _p.captainHatId;
    CREW_HAT_ID = _p.crewHatId;
    MUTINY_ROLE_HAT_ID = _p.mutinyRoleHatId;
    QUARTERMASTER_ROLE_HAT_ID = _p.quartermasterRoleHatId;
    captain = _p.captain;
    quartermaster = _p.quartermaster;
    _nextMutinyId = 0;
  }

  /*///////////////////////////////////////////////////////////////
                            MUTINY LIFECYCLE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IMutinyModule
  function startMutiny(address _proposedNewCaptain) external override onlyHatWearer(CREW_HAT_ID) {
    if (_proposedNewCaptain == address(0)) revert MutinyModule_ZeroAddress();
    if (_proposedNewCaptain == captain) revert MutinyModule_SameCaptain(_proposedNewCaptain);
    if (activeMutinyId != 0) revert MutinyModule_AlreadyActive();
    _requireLiveCaptain();

    uint256 _id = ++_nextMutinyId;
    uint64 _snapshot = _HATS.hatSupply(CREW_HAT_ID);

    _rounds[_id] = MutinyRound({
      proposedNewCaptain: _proposedNewCaptain,
      fromCaptain: captain,
      startedAt: uint64(block.timestamp),
      snapshot: _snapshot,
      yeas: 0,
      executed: false
    });
    activeMutinyId = _id;

    IQuartermaster(_liveQuartermaster()).setMutinyActive(true);
    emit MutinyStarted(_id, msg.sender, _proposedNewCaptain, _snapshot);
  }

  /// @inheritdoc IMutinyModule
  function castVote(uint256 _mutinyId) external override onlyHatWearer(CREW_HAT_ID) {
    if (_mutinyId == 0 || _mutinyId != activeMutinyId) revert MutinyModule_NoActiveMutiny();
    if (_hasVoted[_mutinyId][msg.sender]) revert MutinyModule_AlreadyVoted(msg.sender);
    // Roster is frozen for the round, so current crew wearership matches snapshot membership
    _hasVoted[_mutinyId][msg.sender] = true;
    unchecked {
      _rounds[_mutinyId].yeas += 1;
    }
    emit MutinyVoteCast(_mutinyId, msg.sender);
  }

  /// @inheritdoc IMutinyModule
  function executeMutiny(uint256 _mutinyId) external override {
    MutinyRound storage _r = _rounds[_mutinyId];
    if (_mutinyId == 0 || _mutinyId != activeMutinyId || _r.executed) revert MutinyModule_NoActiveMutiny();
    if (_r.yeas * 2 <= _r.snapshot) revert MutinyModule_ThresholdNotReached(_r.yeas, _r.snapshot);

    address _from = _r.fromCaptain;
    address _to = _r.proposedNewCaptain;
    if (_from != captain) revert MutinyModule_StaleCaptain(_from);

    _r.executed = true;
    activeMutinyId = 0;

    _succeedCaptain(_from, _to);
    IQuartermaster(_liveQuartermaster()).setMutinyActive(false);

    emit MutinyExecuted(_mutinyId, _from, _to);
  }

  /// @inheritdoc IMutinyModule
  function captainResign(address _newCaptain) external override onlyHatWearer(CAPTAIN_HAT_ID) {
    if (_newCaptain == address(0)) revert MutinyModule_ZeroAddress();
    if (_newCaptain == msg.sender) revert MutinyModule_SameCaptain(_newCaptain);
    if (activeMutinyId != 0) revert MutinyModule_AlreadyActive();
    if (msg.sender != captain) revert MutinyModule_StaleCaptain(captain);

    _succeedCaptain(msg.sender, _newCaptain);
    emit CaptainResigned(msg.sender, _newCaptain);
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Transfers captain hat; updates `captain` before `transferHat` so `getWearerStatus` accepts the new wearer. EOA ex-captain: QM mint or crew handoff
   * @dev Contract ex-captains do not receive a crew seat; EOA ex-captains do via `mintCrewFromMutiny` or `crewHandoffForMutiny`
   * @param _from Outgoing captain
   * @param _to Incoming captain
   */
  function _succeedCaptain(address _from, address _to) internal {
    address _qm = _liveQuartermaster();
    captain = _to;
    _HATS.transferHat(CAPTAIN_HAT_ID, _from, _to);

    if (_from.code.length == 0) {
      if (_HATS.isWearerOfHat(_to, CREW_HAT_ID)) {
        IQuartermaster(_qm).crewHandoffForMutiny(_from, _to);
      } else {
        IQuartermaster(_qm).mintCrewFromMutiny(_from);
      }
    }
  }

  /**
   * @notice Returns stored `quartermaster` if it still wears `QUARTERMASTER_ROLE_HAT_ID`, else reverts `MutinyModule_StaleQuartermaster` (role hat moved)
   * @return _qm Live Quartermaster clone
   */
  function _liveQuartermaster() internal view returns (address _qm) {
    _qm = quartermaster;
    if (!_HATS.isWearerOfHat(_qm, QUARTERMASTER_ROLE_HAT_ID)) revert MutinyModule_StaleQuartermaster(_qm);
  }

  /// @notice Reverts if cached `captain` does not wear `CAPTAIN_HAT_ID` (stale or phantom)
  function _requireLiveCaptain() internal view {
    if (!_HATS.isWearerOfHat(captain, CAPTAIN_HAT_ID)) revert MutinyModule_StaleCaptain(captain);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IMutinyModule
  function mutiny(uint256 _id)
    external
    view
    override
    returns (address _proposedNewCaptain, uint64 _startedAt, uint64 _snapshot, uint64 _yeas, bool _executed)
  {
    MutinyRound storage _r = _rounds[_id];
    _proposedNewCaptain = _r.proposedNewCaptain;
    _startedAt = _r.startedAt;
    _snapshot = _r.snapshot;
    _yeas = _r.yeas;
    _executed = _r.executed;
  }

  /// @inheritdoc IMutinyModule
  function hasVoted(uint256 _mutinyId, address _voter) external view override returns (bool _voted) {
    _voted = _hasVoted[_mutinyId][_voter];
  }

  /// @inheritdoc IMutinyModule
  function isInSnapshot(uint256 _mutinyId, address _voter) external view override returns (bool _inSnapshot) {
    MutinyRound storage _r = _rounds[_mutinyId];
    if (_r.startedAt == 0 || _r.executed || _mutinyId != activeMutinyId) _inSnapshot = false;
    else _inSnapshot = _HATS.isWearerOfHat(_voter, CREW_HAT_ID);
  }

  /**
   * @notice Captain hat eligibility: only cached `captain` is eligible; `standing` always `true`
   * @dev Called on mint/transfer; `captain` is set before `transferHat` so the new wearer passes
   * @param _wearer Wearer to evaluate
   * @return _eligible Whether `_wearer == captain`
   * @return _standing Always `true`
   */
  function getWearerStatus(
    address _wearer,
    uint256 /*_hatId*/
  ) external view override returns (bool _eligible, bool _standing) {
    _eligible = _wearer == captain;
    _standing = true;
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view override returns (bool _quiet) {
    _quiet = activeMutinyId == 0;
  }
}
