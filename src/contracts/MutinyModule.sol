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
 * @notice Crew-driven captain succession. Wears `MutinyRole` (admin of the captain hat) and
 *         doubles as the captain hat's `IHatsEligibility` module. Succession happens via one of
 *         two paths: (a) crew-forced mutiny (snapshot-gated 51% yea threshold, permissionless
 *         finalization) or (b) captain voluntary resignation (captain-gated, blocked during
 *         active mutiny). Both paths perform the captain-hat transfer and the Quartermaster crew
 *         mint / hand-off atomically; mutiny also drives `Quartermaster.setMutinyActive` so the
 *         crew roster is frozen for the duration of the round.
 * @dev Deployed as the master copy for EIP-1167 clones. Constructor disables direct init; each
 *      clone is wired by `initialize(InitParams)`. Because Hats Protocol exposes no
 *      `wearerOfHat(id)` getter, the Quartermaster peer address is stored at init and every
 *      outbound peer call re-asserts `IHats.isWearerOfHat(quartermaster, QUARTERMASTER_ROLE_HAT_ID)`
 *      so a stale pointer (after a QuartermasterRole upgrade) reverts rather than silently misroutes.
 *      The captain cache is similarly kept authoritative by this contract being the sole admin of
 *      the captain hat.
 *
 *      There is no mutiny-expiry path: a mutiny that never reaches threshold leaves the round
 *      open and Quartermaster frozen. The release valve is the captain's own `captainResign`
 *      path, which is blocked during active mutiny — so a stalled mutiny must either be carried
 *      through to execution or cleared by a governance-level intervention. This is an
 *      acknowledged product-side risk (see architecture invariant #13 / participation risk) and
 *      not a safety concern.
 */
contract MutinyModule is IMutinyModule, IHatsEligibility, HatGated, Initializable {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters required to initialize a MutinyModule clone.
   * @param captainHatId Captain hat id administered by this clone (as MutinyRole wearer).
   * @param crewHatId Crew hat id (consulted for snapshot-gated voting checks).
   * @param mutinyRoleHatId MutinyRole hat id worn by this clone.
   * @param quartermasterRoleHatId QuartermasterRole hat id worn by the peer Quartermaster clone.
   * @param captain Initial captain-hat wearer (must be marked eligible before the factory mints the hat).
   * @param quartermaster Peer Quartermaster clone address (verified at every outbound call).
   */
  struct InitParams {
    uint256 captainHatId;
    uint256 crewHatId;
    uint256 mutinyRoleHatId;
    uint256 quartermasterRoleHatId;
    address captain;
    address quartermaster;
  }

  /**
   * @notice Persisted mutiny round state.
   * @param proposedNewCaptain Successor if the round passes.
   * @param fromCaptain Captain at the time the round opened (snapshot-locked).
   * @param startedAt Timestamp the round opened.
   * @param snapshot Size of the crew electorate at `startedAt`.
   * @param yeas Yea vote count.
   * @param executed Whether the round has been finalized.
   */
  struct MutinyRound {
    address proposedNewCaptain;
    address fromCaptain;
    uint64 startedAt;
    uint64 snapshot;
    uint64 yeas;
    bool executed;
  }

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

  /**
   * @notice Monotonically increasing id counter for new rounds. First issued id is `1`; id `0`
   *         is reserved as the "no active mutiny" sentinel.
   */
  uint256 internal _nextMutinyId;

  /// @notice Round state indexed by mutiny id.
  mapping(uint256 _mutinyId => MutinyRound _round) internal _rounds;

  /// @notice Vote-registry; `true` iff `_voter` has cast a yea in `_mutinyId`.
  mapping(uint256 _mutinyId => mapping(address _voter => bool _voted)) internal _hasVoted;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Master-copy constructor; bakes the Hats singleton into runtime code shared by all
   *         clones and disables direct initialization of the master copy itself.
   * @param hats_ Hats Protocol address for this chain.
   */
  constructor(IHats hats_) HatGated(hats_) {
    _disableInitializers();
  }

  /**
   * @notice Per-clone initializer. Seeds hat ids and the two peer addresses (initial captain,
   *         Quartermaster clone). The initial captain is marked eligible via
   *         `getWearerStatus(captain, captainHatId)` so that the factory's subsequent
   *         `Hats.mintHat(captainHatId, captain)` passes the eligibility check routed through
   *         this module.
   * @param _p Bootstrap parameters.
   */
  function initialize(InitParams calldata _p) external initializer {
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
    // Snapshot membership is equivalent to current crew-hat wearership while the round is open,
    // because Quartermaster freezes the roster for the duration of the active mutiny.
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
   * @notice Performs the captain-hat transfer and the matching crew-side mint / hand-off
   *         (for EOA predecessors only) in a single atomic sequence. Updates the local captain
   *         cache before the `transferHat` call so the eligibility callback routed through
   *         `getWearerStatus` admits the incoming wearer.
   * @dev Contract predecessors get no crew seat (the "human-captain" rule — they are not
   *      considered crew by the architecture). For EOA predecessors the module either hands off
   *      the successor's existing crew hat (successor already crew) or mints a fresh one through
   *      Quartermaster.
   * @param _from Outgoing captain.
   * @param _to Incoming captain.
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
   * @notice Returns the Quartermaster peer address after verifying it still wears
   *         `QUARTERMASTER_ROLE_HAT_ID`. Reverts with `MutinyModule_StaleQuartermaster` if the
   *         role hat has moved (indicating this module needs a paired upgrade).
   * @return _qm Live Quartermaster clone address.
   */
  function _liveQuartermaster() internal view returns (address _qm) {
    _qm = quartermaster;
    if (!_HATS.isWearerOfHat(_qm, QUARTERMASTER_ROLE_HAT_ID)) revert MutinyModule_StaleQuartermaster(_qm);
  }

  /**
   * @notice Verifies the cached captain address still wears `CAPTAIN_HAT_ID`. Mutiny cannot be
   *         opened against a phantom captain.
   */
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
    return (_r.proposedNewCaptain, _r.startedAt, _r.snapshot, _r.yeas, _r.executed);
  }

  /// @inheritdoc IMutinyModule
  function hasVoted(uint256 _mutinyId, address _voter) external view override returns (bool _voted) {
    return _hasVoted[_mutinyId][_voter];
  }

  /// @inheritdoc IMutinyModule
  function isInSnapshot(uint256 _mutinyId, address _voter) external view override returns (bool _inSnapshot) {
    MutinyRound storage _r = _rounds[_mutinyId];
    if (_r.startedAt == 0 || _r.executed || _mutinyId != activeMutinyId) return false;
    return _HATS.isWearerOfHat(_voter, CREW_HAT_ID);
  }

  /**
   * @notice `IHatsEligibility` implementation for the captain hat. Only the address currently
   *         cached as `captain` is eligible; everyone else is ineligible. Standing is always
   *         `true` — there is no good-standing differentiation for captain in this module.
   * @dev Hats invokes this on `mintHat`, `transferHat`, and explicit `checkHatWearerStatus`
   *      calls; the cache is updated before every outbound transfer, so the incoming wearer
   *      passes the check.
   * @param _wearer Prospective wearer.
   * @return eligible Whether the wearer is currently the captain in our ledger.
   * @return standing Always `true`.
   */
  function getWearerStatus(
    address _wearer,
    uint256 /*_hatId*/
  ) external view override returns (bool eligible, bool standing) {
    return (_wearer == captain, true);
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external view override returns (bool _quiet) {
    return activeMutinyId == 0;
  }
}
