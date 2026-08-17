// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/utils/HatGated.sol';
import {IMutinyModule} from 'interfaces/core/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';
import {IHatGated} from 'interfaces/utils/IHatGated.sol';
import {IQuiescent} from 'interfaces/utils/IQuiescent.sol';

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
  uint256 public captainHatId;
  /// @inheritdoc IMutinyModule
  uint256 public crewHatId;
  /// @inheritdoc IMutinyModule
  uint256 public mutinyRoleHatId;
  /// @inheritdoc IMutinyModule
  uint256 public quartermasterRoleHatId;
  /// @inheritdoc IMutinyModule
  address public captain;
  /// @inheritdoc IMutinyModule
  address public quartermaster;
  /// @inheritdoc IMutinyModule
  address public safe;
  /// @inheritdoc IMutinyModule
  uint256 public activeMutinyId;

  /// @inheritdoc IMutinyModule
  uint256 public mutinyCount;

  /// @notice Round state indexed by mutiny id.
  mapping(uint256 _mutinyId => MutinyRound _round) internal _rounds;
  /// @notice Vote-registry; `true` iff `_voter` has cast a yea in `_mutinyId`.
  mapping(uint256 _mutinyId => mapping(address _voter => bool _voted)) internal _hasVoted;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Runs `_mutinyCheck` before the wrapped function body.
   * @param _target Proposed successor from the mutiny entrypoint.
   */
  modifier mutinyCheck(address _target) {
    _mutinyCheck(_target);
    _;
  }

  /**
   * @notice Requires `_mutinyId` to be the current `activeMutinyId` (and non-zero).
   * @param _mutinyId Round id supplied by the caller.
   */
  modifier activeMutiny(uint256 _mutinyId) {
    _activeMutinyId(_mutinyId);
    _;
  }

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
  function initialize(InitParams calldata _p) external initializer {
    if (_p.captain == address(0) || _p.quartermaster == address(0) || _p.safe == address(0)) {
      revert MutinyModule_ZeroAddress();
    }
    captainHatId = _p.captainHatId;
    crewHatId = _p.crewHatId;
    mutinyRoleHatId = _p.mutinyRoleHatId;
    quartermasterRoleHatId = _p.quartermasterRoleHatId;
    captain = _p.captain;
    quartermaster = _p.quartermaster;
    safe = _p.safe;
    mutinyCount = 0;
  }

  /*///////////////////////////////////////////////////////////////
                            MUTINY LIFECYCLE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IMutinyModule
  function startMutinyToCrewMember(address _proposedCrewMember) external {
    _requireHatWearer(_proposedCrewMember, crewHatId);
    _startMutiny(_proposedCrewMember);
  }

  /// @inheritdoc IMutinyModule
  function startMutinyToCommittee(address _proposedMultisigCommittee) external {
    (bool ok, bytes memory data) = _proposedMultisigCommittee.staticcall(abi.encodeWithSignature('getThreshold()'));
    if (!ok || data.length != 32) revert MutinyModule_NotContract(_proposedMultisigCommittee);
    _startMutiny(_proposedMultisigCommittee);
  }

  /// @inheritdoc IMutinyModule
  function startMutinyToArbitraryEoa(address _proposedArbitraryEoa) external {
    if (_isContract(_proposedArbitraryEoa)) revert MutinyModule_NotEOA(_proposedArbitraryEoa);
    _startMutiny(_proposedArbitraryEoa);
  }

  /// @inheritdoc IMutinyModule
  function startMutinyToArbitraryContract(address _proposedArbitraryContract) external {
    if (!_isContract(_proposedArbitraryContract)) {
      revert MutinyModule_NotContract(_proposedArbitraryContract);
    }
    _startMutiny(_proposedArbitraryContract);
  }

  /// @inheritdoc IMutinyModule
  function startMutinyToPauseCaptain() external {
    _startMutiny(safe);
  }

  /// @inheritdoc IMutinyModule
  function castVote(uint256 _mutinyId) external onlyHatWearer(crewHatId) activeMutiny(_mutinyId) {
    if (_hasVoted[_mutinyId][msg.sender]) revert MutinyModule_AlreadyVoted(msg.sender);
    // Roster is frozen for the round, so current crew wearership matches snapshot membership
    _hasVoted[_mutinyId][msg.sender] = true;
    unchecked {
      _rounds[_mutinyId].yeas += 1;
    }
    emit MutinyVoteCast(_mutinyId, msg.sender);
  }

  /// @inheritdoc IMutinyModule
  function executeMutiny(uint256 _mutinyId) external activeMutiny(_mutinyId) {
    MutinyRound storage _r = _rounds[_mutinyId];
    if (_r.executed) revert MutinyModule_NoActiveMutiny();
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
  function captainResign(address _newCaptain) external onlyHatWearer(captainHatId) {
    if (_newCaptain == address(0)) revert MutinyModule_ZeroAddress();
    if (_newCaptain == msg.sender) revert MutinyModule_SameCaptain(_newCaptain);
    if (activeMutinyId != 0) revert MutinyModule_AlreadyActive();
    if (msg.sender != captain) revert MutinyModule_StaleCaptain(captain);

    _succeedCaptain(msg.sender, _newCaptain);
    emit CaptainResigned(msg.sender, _newCaptain);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IMutinyModule
  function mutiny(uint256 _id)
    external
    view
    returns (
      address _proposedNewCaptain,
      address _fromCaptain,
      uint64 _startedAt,
      uint64 _snapshot,
      uint64 _yeas,
      bool _executed
    )
  {
    MutinyRound storage _r = _rounds[_id];
    _proposedNewCaptain = _r.proposedNewCaptain;
    _fromCaptain = _r.fromCaptain;
    _startedAt = _r.startedAt;
    _snapshot = _r.snapshot;
    _yeas = _r.yeas;
    _executed = _r.executed;
  }

  /// @inheritdoc IMutinyModule
  function thresholdReached(uint256 _id) external view returns (bool _reached) {
    MutinyRound storage _r = _rounds[_id];
    if (_r.startedAt == 0) return false;
    _reached = uint256(_r.yeas) * 2 > _r.snapshot;
  }

  /// @inheritdoc IMutinyModule
  function hasVoted(uint256 _mutinyId, address _voter) external view returns (bool _voted) {
    _voted = _hasVoted[_mutinyId][_voter];
  }

  /// @inheritdoc IMutinyModule
  function isInSnapshot(uint256 _mutinyId, address _voter) external view returns (bool _inSnapshot) {
    MutinyRound storage _r = _rounds[_mutinyId];
    if (_r.startedAt == 0 || _r.executed) _inSnapshot = false;
    else _inSnapshot = _HATS.isWearerOfHat(_voter, crewHatId);
  }

  /// @inheritdoc IHatsEligibility
  function getWearerStatus(
    address _wearer,
    uint256 /*_hatId*/
  ) external view returns (bool _eligible, bool _standing) {
    _eligible = _wearer == captain;
    _standing = true;
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view returns (bool _quiet) {
    _quiet = activeMutinyId == 0;
  }

  /// @inheritdoc IHatGated
  function hats() public view override(IHatGated, HatGated) returns (IHats _hats) {
    _hats = _HATS;
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Starts a mutiny round.
   * @param _proposedNewCaptain The address of the proposed new captain.
   */
  function _startMutiny(address _proposedNewCaptain)
    internal
    onlyHatWearer(crewHatId)
    mutinyCheck(_proposedNewCaptain)
  {
    uint256 _id = ++mutinyCount;
    uint64 _snapshot = _HATS.hatSupply(crewHatId);

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

  /**
   * @notice Transfers captain hat; updates `captain` before `transferHat` so `getWearerStatus` accepts the new wearer. EOA ex-captain: QM mint or crew handoff
   * @dev Contract ex-captains do not receive a crew seat; EOA ex-captains do via `mintCrewFromMutiny` or `crewHandoffForMutiny`
   * @param _from Outgoing captain
   * @param _to Incoming captain
   */
  function _succeedCaptain(address _from, address _to) internal {
    address _qm = _liveQuartermaster();
    captain = _to;
    _HATS.transferHat(captainHatId, _from, _to);

    // is ex-captain an EOA? if so, mint or handoff crew hat
    if (_from.code.length == 0) {
      if (_HATS.isWearerOfHat(_to, crewHatId)) {
        IQuartermaster(_qm).crewHandoffForMutiny(_from, _to);
      } else {
        IQuartermaster(_qm).mintCrewFromMutiny(_from);
      }
    }
  }

  /**
   * @notice Returns stored `quartermaster` if it still wears `quartermasterRoleHatId`, else reverts `MutinyModule_StaleQuartermaster` (role hat moved)
   * @return _qm Live Quartermaster clone
   */
  function _liveQuartermaster() internal view returns (address _qm) {
    _qm = quartermaster;
    if (!_HATS.isWearerOfHat(_qm, quartermasterRoleHatId)) revert MutinyModule_StaleQuartermaster(_qm);
  }

  /**
   * @notice Reverts if cached `captain` does not wear `captainHatId` (stale or phantom) or if a mutiny is already active
   * @param _target The target address to check
   */
  function _mutinyCheck(address _target) internal view {
    if (_target == address(0)) revert MutinyModule_ZeroAddress();
    if (_target == captain) revert MutinyModule_SameCaptain(_target);
    if (activeMutinyId != 0) revert MutinyModule_AlreadyActive();
    if (!_HATS.isWearerOfHat(captain, captainHatId)) revert MutinyModule_StaleCaptain(captain);
  }

  /**
   * @notice Reverts if the specified mutiny id is not the active mutiny id
   * @param _mutinyId The mutiny id to check
   */
  function _activeMutinyId(uint256 _mutinyId) internal view {
    if (_mutinyId == 0) revert MutinyModule_NoActiveMutiny();
    if (_mutinyId != activeMutinyId) revert MutinyModule_NoActiveMutiny();
  }

  /**
   * @notice Checks if the address is a contract.
   * @param _address The address to check.
   * @return True if the address is a contract, false otherwise.
   */
  function _isContract(address _address) internal view returns (bool) {
    return _address.code.length > 0;
  }
}
