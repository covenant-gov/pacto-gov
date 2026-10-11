// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/utils/HatGated.sol';
import {RangeValidator} from 'contracts/utils/RangeValidator.sol';
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
 * @notice 51% snapshot mutiny or captain resignation; captain-hat `IHatsEligibility` (always eligible); QM reads `activeMutinyId` to freeze captain HR
 * @dev EIP-1167 master. Hats has no `wearerOfHat(hatId)` — store `quartermaster` and re-check `isWearerOfHat` on each call. Failed rounds expire after `mutinyExpiry` via permissionless `expireMutiny`
 */
contract MutinyModule is IMutinyModule, IHatsEligibility, HatGated, RangeValidator, Initializable {
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
  uint256 public treasuryAuthorityRoleHatId;

  /// @notice Packed `mutinyExpiry`, `activeMutinyId`, `mutinyCount`.
  GovConfig internal _gov;

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
    _requireActiveMutiny(_mutinyId);
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
    _validateDelay(_p.mutinyExpiry);
    captainHatId = _p.captainHatId;
    crewHatId = _p.crewHatId;
    mutinyRoleHatId = _p.mutinyRoleHatId;
    quartermasterRoleHatId = _p.quartermasterRoleHatId;
    captain = _p.captain;
    quartermaster = _p.quartermaster;
    safe = _p.safe;
    treasuryAuthorityRoleHatId = _p.treasuryAuthorityRoleHatId;
    // delay already range-checked; fits `uint64`.
    // forge-lint: disable-next-line(unsafe-typecast)
    _gov.mutinyExpiry = uint64(_p.mutinyExpiry);
    emit MutinyExpiryUpdated(0, _p.mutinyExpiry);
  }

  /*///////////////////////////////////////////////////////////////
                            MUTINY LIFECYCLE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IMutinyModule
  function startMutinyToCrewMember(address _proposedCrewMember, bool _seatFormerCaptain) external {
    _requireHatWearer(_proposedCrewMember, crewHatId);
    _startMutiny(_proposedCrewMember, _seatFormerCaptain);
  }

  /// @inheritdoc IMutinyModule
  function startMutinyToCommittee(address _proposedMultisigCommittee, bool _seatFormerCaptain) external {
    (bool ok, bytes memory data) = _proposedMultisigCommittee.staticcall(abi.encodeWithSignature('getThreshold()'));
    if (!ok || data.length != 32) revert MutinyModule_NotContract(_proposedMultisigCommittee);
    _startMutiny(_proposedMultisigCommittee, _seatFormerCaptain);
  }

  /// @inheritdoc IMutinyModule
  function startMutinyToArbitraryEoa(address _proposedArbitraryEoa, bool _seatFormerCaptain) external {
    if (_isContract(_proposedArbitraryEoa)) revert MutinyModule_NotEOA(_proposedArbitraryEoa);
    _startMutiny(_proposedArbitraryEoa, _seatFormerCaptain);
  }

  /// @inheritdoc IMutinyModule
  function startMutinyToArbitraryContract(address _proposedArbitraryContract, bool _seatFormerCaptain) external {
    if (!_isContract(_proposedArbitraryContract)) {
      revert MutinyModule_NotContract(_proposedArbitraryContract);
    }
    _startMutiny(_proposedArbitraryContract, _seatFormerCaptain);
  }

  /// @inheritdoc IMutinyModule
  function startMutinyToPauseCaptain(bool _seatFormerCaptain) external {
    _startMutiny(safe, _seatFormerCaptain);
  }

  /// @inheritdoc IMutinyModule
  function castVote(uint256 _mutinyId) external onlyHatWearer(crewHatId) activeMutiny(_mutinyId) {
    MutinyRound storage _r = _rounds[_mutinyId];
    _requireNotExpired(_r, _mutinyId);
    if (_hasVoted[_mutinyId][msg.sender]) revert MutinyModule_AlreadyVoted(msg.sender);
    // Roster is frozen for the round, so current crew wearership matches snapshot membership
    _hasVoted[_mutinyId][msg.sender] = true;
    unchecked {
      _r.yeas += 1;
    }
    emit MutinyVoteCast(_mutinyId, msg.sender);
  }

  /// @inheritdoc IMutinyModule
  function executeMutiny(uint256 _mutinyId) external activeMutiny(_mutinyId) {
    MutinyRound storage _r = _rounds[_mutinyId];
    if (_r.executed) revert MutinyModule_NoActiveMutiny();
    _requireNotExpired(_r, _mutinyId);
    if (_r.yeas * 2 <= _r.snapshot) revert MutinyModule_ThresholdNotReached(_r.yeas, _r.snapshot);

    address _from = _r.fromCaptain;
    address _to = _r.proposedNewCaptain;
    if (_from != captain) revert MutinyModule_StaleCaptain(_from);

    _r.executed = true;
    _gov.activeMutinyId = 0;

    _succeedCaptain(_from, _to, _r.seatFormerCaptain);

    emit MutinyExecuted(_mutinyId, _from, _to);
  }

  /// @inheritdoc IMutinyModule
  function expireMutiny(uint256 _mutinyId) external activeMutiny(_mutinyId) {
    MutinyRound storage _r = _rounds[_mutinyId];
    if (_r.executed) revert MutinyModule_NoActiveMutiny();
    if (block.timestamp < _r.deadline) revert MutinyModule_NotExpired(_mutinyId, _r.deadline);

    _gov.activeMutinyId = 0;
    emit MutinyExpired(_mutinyId);
  }

  /// @inheritdoc IMutinyModule
  function captainResign(address _newCaptain, bool _seatFormerCaptain) external onlyHatWearer(captainHatId) {
    if (_newCaptain == address(0)) revert MutinyModule_ZeroAddress();
    if (_newCaptain == msg.sender) revert MutinyModule_SameCaptain(_newCaptain);
    if (_gov.activeMutinyId != 0) revert MutinyModule_AlreadyActive();
    if (msg.sender != captain) revert MutinyModule_StaleCaptain(captain);

    _succeedCaptain(msg.sender, _newCaptain, _seatFormerCaptain);
    emit CaptainResigned(msg.sender, _newCaptain, _seatFormerCaptain);
  }

  /// @inheritdoc IMutinyModule
  function setMutinyExpiry(uint256 _newValue) external onlyHatWearer(treasuryAuthorityRoleHatId) {
    _validateDelay(_newValue);
    uint256 _old = _gov.mutinyExpiry;
    // casting to 'uint64' is safe because `_validateDelay` caps at `MAX_GOV_DELAY` (60 days).
    // forge-lint: disable-next-line(unsafe-typecast)
    _gov.mutinyExpiry = uint64(_newValue);
    emit MutinyExpiryUpdated(_old, _newValue);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IMutinyModule
  function activeMutinyId() external view returns (uint256 _id) {
    _id = _gov.activeMutinyId;
  }

  /// @inheritdoc IMutinyModule
  function mutinyCount() external view returns (uint256 _count) {
    _count = _gov.mutinyCount;
  }

  /// @inheritdoc IMutinyModule
  function mutinyExpiry() external view returns (uint256 _expiry) {
    _expiry = _gov.mutinyExpiry;
  }

  /// @inheritdoc IMutinyModule
  function mutiny(uint256 _id)
    external
    view
    returns (
      address _proposedNewCaptain,
      address _fromCaptain,
      uint64 _startedAt,
      uint64 _deadline,
      uint64 _snapshot,
      uint64 _yeas,
      bool _executed,
      bool _seatFormerCaptain
    )
  {
    MutinyRound storage _r = _rounds[_id];
    _proposedNewCaptain = _r.proposedNewCaptain;
    _fromCaptain = _r.fromCaptain;
    _startedAt = _r.startedAt;
    _deadline = _r.deadline;
    _snapshot = _r.snapshot;
    _yeas = _r.yeas;
    _executed = _r.executed;
    _seatFormerCaptain = _r.seatFormerCaptain;
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

  /// @inheritdoc IQuiescent
  function isQuiet() external view returns (bool _quiet) {
    _quiet = _gov.activeMutinyId == 0;
  }

  /// @inheritdoc IHatsEligibility
  function getWearerStatus(address, uint256) external pure returns (bool _eligible, bool _standing) {
    _eligible = true;
    _standing = true;
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
   * @param _seatFormerCaptain If true, execution mints a crew hat to the outgoing captain.
   */
  function _startMutiny(
    address _proposedNewCaptain,
    bool _seatFormerCaptain
  ) internal onlyHatWearer(crewHatId) mutinyCheck(_proposedNewCaptain) {
    address _qm = _liveQuartermaster();
    if (IQuartermaster(_qm).activeCrewOffboardId() != 0) revert MutinyModule_CrewOffboardActive();

    GovConfig memory _cfg = _gov;
    uint256 _deadline256 = block.timestamp + _cfg.mutinyExpiry;
    if (_deadline256 > type(uint64).max) revert MutinyModule_DeadlineOverflow();

    _cfg.mutinyCount += 1;
    _cfg.activeMutinyId = _cfg.mutinyCount;
    uint256 _id = _cfg.mutinyCount;
    _gov = _cfg;

    uint64 _snapshot = _HATS.hatSupply(crewHatId);

    _rounds[_id] = MutinyRound({
      proposedNewCaptain: _proposedNewCaptain,
      executed: false,
      seatFormerCaptain: _seatFormerCaptain,
      fromCaptain: captain,
      startedAt: uint64(block.timestamp),
      // casting to 'uint64' is safe because `_deadline256` is checked against `type(uint64).max` above.
      // forge-lint: disable-next-line(unsafe-typecast)
      deadline: uint64(_deadline256),
      snapshot: _snapshot,
      yeas: 0
    });

    emit MutinyStarted(_id, msg.sender, _proposedNewCaptain, _snapshot, _seatFormerCaptain);
  }

  /**
   * @notice Transfers captain hat and updates the `captain` identity cache
   * @dev Crew revoke/mint batched via Quartermaster `applySuccessionCrew`
   * @param _from Outgoing captain
   * @param _to Incoming captain
   * @param _seatFormerCaptain If true, mint a crew hat to `_from` after succession
   */
  function _succeedCaptain(address _from, address _to, bool _seatFormerCaptain) internal {
    captain = _to;
    _HATS.transferHat(captainHatId, _from, _to);
    IQuartermaster(_liveQuartermaster()).applySuccessionCrew(_from, _to, _seatFormerCaptain);
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
    if (_gov.activeMutinyId != 0) revert MutinyModule_AlreadyActive();
    if (!_HATS.isWearerOfHat(captain, captainHatId)) revert MutinyModule_StaleCaptain(captain);
  }

  /**
   * @notice Reverts if the specified mutiny id is not the active mutiny id
   * @param _mutinyId The mutiny id to check
   */
  function _requireActiveMutiny(uint256 _mutinyId) internal view {
    if (_mutinyId == 0 || _mutinyId != _gov.activeMutinyId) revert MutinyModule_NoActiveMutiny();
  }

  /**
   * @notice Reverts if `_r` is at or past its deadline.
   * @param _r Round already loaded from storage.
   * @param _mutinyId Round id (for revert payload).
   */
  function _requireNotExpired(MutinyRound storage _r, uint256 _mutinyId) internal view {
    if (block.timestamp >= _r.deadline) revert MutinyModule_Expired(_mutinyId);
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
