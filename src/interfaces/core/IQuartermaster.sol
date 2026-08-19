// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IHatGated} from 'interfaces/utils/IHatGated.sol';
import {IQuiescent} from 'interfaces/utils/IQuiescent.sol';

/**
 * @title IQuartermaster
 * @author Pacto
 * @notice Timelocked crew add/remove (bootstrap without delay); crew-led offboard vote (`QUORUM_OF_CAST`); implements `IHatsEligibility` for the crew hat. Captain requests; anyone
 *         executes after `crewChangeDelay`. Crew may offboard one member at a time without the captain. When `mutinyActive` or an offboard is live, captain HR is frozen. Delay / offboard params: TA role + two-body
 */
interface IQuartermaster is IQuiescent, IHatGated {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Parameters required to initialize a Quartermaster clone.
   * @param captainHatId Captain hat id for authority checks.
   * @param crewHatId Crew hat id administered by this clone.
   * @param mutinyRoleHatId MutinyRole hat id; mutiny hooks require this gate.
   * @param quartermasterRoleHatId QuartermasterRole hat id worn by this clone.
   * @param treasuryAuthorityRoleHatId TreasuryAuthorityRole hat id; gates parameter setters.
   * @param crewChangeDelay Initial timelock in seconds for requested crew adds / removes.
   * @param crewOffboardExpiry Initial voting window in seconds for crew-led offboard (same range as TA `proposalExpiry`).
   * @param crewOffboardQuorumBps Initial quorum bps for crew-led offboard (`QUORUM_OF_CAST`).
   */
  struct InitParams {
    uint256 captainHatId;
    uint256 crewHatId;
    uint256 mutinyRoleHatId;
    uint256 quartermasterRoleHatId;
    uint256 treasuryAuthorityRoleHatId;
    uint256 crewChangeDelay;
    uint256 crewOffboardExpiry;
    uint256 crewOffboardQuorumBps;
  }

  /**
   * @notice Persisted crew-led offboard vote.
   * @param target Crew member to remove.
   * @param proposer Crew member that opened the vote.
   * @param deadline Unix timestamp after which `executeOffboard` reverts and `expireOffboard` is valid.
   * @param snapshot Crew hat supply at propose time.
   * @param yeas Yea vote count.
   * @param nays Nay vote count.
   * @param executed Whether the offboard has been finalized.
   */
  struct CrewOffboard {
    address target;
    address proposer;
    uint64 deadline;
    uint64 snapshot;
    uint64 yeas;
    uint64 nays;
    bool executed;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice A crew add was scheduled by the captain.
   * @param _candidate Address that may receive the crew hat after the delay.
   * @param _executableAt Timestamp when `executeAddCrew` becomes valid.
   */
  event CrewAddRequested(address indexed _candidate, uint256 _executableAt);

  /**
   * @notice A scheduled crew add was executed.
   * @param _candidate Address that received the crew hat.
   */
  event CrewAddExecuted(address indexed _candidate);

  /**
   * @notice A scheduled crew add was cancelled by the captain.
   * @param _candidate Address whose pending add was cleared.
   */
  event CrewAddCancelled(address indexed _candidate);

  /**
   * @notice A crew removal was scheduled by the captain.
   * @param _crew Address whose crew hat may be revoked after the delay.
   * @param _executableAt Timestamp when `executeRemoveCrew` becomes valid.
   */
  event CrewRemoveRequested(address indexed _crew, uint256 _executableAt);

  /**
   * @notice A scheduled crew removal was executed.
   * @param _crew Address that lost the crew hat.
   */
  event CrewRemoveExecuted(address indexed _crew);

  /**
   * @notice A scheduled crew removal was cancelled by the captain.
   * @param _crew Address whose pending removal was cleared.
   */
  event CrewRemoveCancelled(address indexed _crew);

  /**
   * @notice The MutinyModule minted a crew hat to a former captain after a successful mutiny.
   * @param _formerCaptain Address that received the crew hat.
   */
  event CrewMintedFromMutiny(address indexed _formerCaptain);

  /**
   * @notice The MutinyModule handed the new captain's existing crew hat to the former captain.
   * @param _formerCaptain Address that received the crew hat.
   * @param _newCaptain Address whose crew hat was transferred.
   */
  event CrewHandoffForMutiny(address indexed _formerCaptain, address indexed _newCaptain);

  /**
   * @notice Mutiny mode toggled (disables captain-driven onboarding while active).
   * @param _active True when a mutiny is in progress.
   */
  event MutinyActiveSet(bool _active);

  /**
   * @notice The crew change delay parameter was updated via a Treasury Authority proposal.
   * @param _oldValue Previous delay, in seconds.
   * @param _newValue New delay, in seconds.
   */
  event CrewChangeDelayUpdated(uint256 _oldValue, uint256 _newValue);

  /**
   * @notice Crew opened an offboard vote against a fellow crew member.
   * @param _offboardId Vote identifier.
   * @param _proposer Crew member that opened the vote.
   * @param _target Crew member to remove.
   * @param _deadline Timestamp after which the vote can only be expired.
   * @param _snapshot Crew snapshot at propose time.
   */
  event CrewOffboardProposed(
    uint256 indexed _offboardId,
    address indexed _proposer,
    address indexed _target,
    uint256 _deadline,
    uint256 _snapshot
  );

  /**
   * @notice Crew member voted on an offboard.
   * @param _offboardId Vote identifier.
   * @param _voter Crew member that voted.
   * @param _support True for yea, false for nay.
   */
  event CrewOffboardVoteCast(uint256 indexed _offboardId, address indexed _voter, bool _support);

  /**
   * @notice Offboard passed and the target lost the crew hat.
   * @param _offboardId Vote identifier.
   * @param _target Address that lost the crew hat.
   */
  event CrewOffboardExecuted(uint256 indexed _offboardId, address indexed _target);

  /**
   * @notice Offboard expired without execution; roster freeze was lifted.
   * @param _offboardId Vote identifier.
   */
  event CrewOffboardExpired(uint256 indexed _offboardId);

  /**
   * @notice Crew-led offboard quorum bps was updated via a Treasury Authority proposal.
   * @param _oldValue Previous bps.
   * @param _newValue New bps.
   */
  event CrewOffboardQuorumBpsUpdated(uint256 _oldValue, uint256 _newValue);

  /**
   * @notice Crew-led offboard voting window was updated via a Treasury Authority proposal.
   * @param _oldValue Previous expiry, in seconds.
   * @param _newValue New expiry, in seconds.
   */
  event CrewOffboardExpiryUpdated(uint256 _oldValue, uint256 _newValue);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice No pending operation exists for the target.
   * @param _target Address whose pending entry was expected but missing.
   */
  error Quartermaster_NotPending(address _target);

  /**
   * @notice The scheduled delay has not yet elapsed for the target.
   * @param _target Address whose pending entry is still locked.
   * @param _executableAt Timestamp after which execution becomes valid.
   */
  error Quartermaster_StillLocked(address _target, uint256 _executableAt);

  /**
   * @notice The target already wears the crew hat.
   * @param _target Address that already holds the crew hat.
   */
  error Quartermaster_AlreadyCrew(address _target);

  /**
   * @notice The candidate currently wears the captain hat (captain ∩ crew = ∅ invariant).
   * @param _target Address that wears the captain hat.
   */
  error Quartermaster_CandidateIsCaptain(address _target);

  /**
   * @notice The target does not wear the crew hat.
   * @param _target Address expected to wear the crew hat.
   */
  error Quartermaster_NotCrew(address _target);

  /**
   * @notice Second `requestAddCrew` for `_address` while the first scheduled add is still pending.
   * @param _address The duplicate candidate key.
   */
  error Quartermaster_DuplicateCrewAdd(address _address);

  /**
   * @notice Voter has already voted in this offboard.
   * @param _voter Address that attempted a duplicate vote.
   */
  error Quartermaster_AlreadyVoted(address _voter);

  /**
   * @notice The offboard voting window has ended.
   * @param _offboardId Vote identifier.
   */
  error Quartermaster_OffboardExpired(uint256 _offboardId);

  /**
   * @notice `expireOffboard` was called before the vote deadline.
   * @param _offboardId Vote identifier.
   * @param _deadline Timestamp after which expiry is valid.
   */
  error Quartermaster_OffboardNotExpired(uint256 _offboardId, uint256 _deadline);

  /**
   * @notice Turnout or yeas-vs-nays failed `QUORUM_OF_CAST`.
   * @param _yeas Current yea count.
   * @param _nays Current nay count.
   * @param _snapshot Snapshot size fixed when the vote opened.
   */
  error Quartermaster_OffboardNotPassed(uint256 _yeas, uint256 _nays, uint256 _snapshot);

  /**
   * @notice Captain already has a pending remove on this address.
   * @param _crew Address with `pendingCrewRemoveAt` set.
   */
  error Quartermaster_PendingCaptainRemove(address _crew);

  /// @notice Crew onboarding is blocked while a mutiny is active.
  error Quartermaster_MutinyActive();
  /// @notice Captain HR and a second offboard are blocked while a crew-led offboard vote is live.
  error Quartermaster_CrewOffboardActive();
  /// @notice Proposer cannot open an offboard against themselves.
  error Quartermaster_SelfOffboard();
  /// @notice No active crew-led offboard exists for the requested id.
  error Quartermaster_NoActiveOffboard();
  /// @notice `block.timestamp + crewOffboardExpiry` exceeds `type(uint64).max`.
  error Quartermaster_DeadlineOverflow();
  /// @notice The crew hat has reached its max supply cap.
  error Quartermaster_CrewFull();
  /// @notice A required address argument was zero.
  error Quartermaster_ZeroAddress();
  /// @notice `bootstrapCrew` only runs before any crew wearer exists.
  error Quartermaster_BootstrapRequiresEmptyCrew();
  /// @notice `bootstrapCrew` was called with an empty candidates array.
  error Quartermaster_BootstrapEmpty();

  /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Per-clone initializer; sets hat ids, crew-change delay, and crew-offboard params.
   * @param _p Bootstrap parameters.
   */
  function initialize(InitParams calldata _p) external;

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Schedule minting the crew hat to `_candidate`; delay is zero while no crew wearer yet else `crewChangeDelay`. Captain-gated.
   * @dev Reverts if mutiny active, `_candidate` is invalid captain/crew, crew full, or there is already a pending add for `_candidate`.
   * @param _candidate Address to receive the crew hat.
   */
  function requestAddCrew(address _candidate) external;

  /**
   * @notice Cancel a previously requested crew add. Captain-gated.
   * @param _candidate Address whose pending add should be cleared.
   */
  function cancelAddCrew(address _candidate) external;

  /**
   * @notice Execute a scheduled crew add after the delay. Permissionless.
   * @param _candidate Address to receive the crew hat.
   */
  function executeAddCrew(address _candidate) external;

  /**
   * @notice Mint the crew hat to every address in `_candidates` immediately; only valid while no crew wearer exists yet.
   * @dev Captain-gated. One-shot bootstrap; afterward use `requestAddCrew` / `executeAddCrew` with delay.
   * @param _candidates Addresses to onboard as crew together.
   */
  function bootstrapCrew(address[] calldata _candidates) external;

  /**
   * @notice Schedule burning the crew hat from `_crew` after `crewChangeDelay`. Captain-gated.
   * @dev Reverts if a mutiny is active or the target does not wear the crew hat.
   * @param _crew Address to remove from crew.
   */
  function requestRemoveCrew(address _crew) external;

  /**
   * @notice Cancel a previously requested crew removal. Captain-gated.
   * @param _crew Address whose pending removal should be cleared.
   */
  function cancelRemoveCrew(address _crew) external;

  /**
   * @notice Execute a scheduled crew removal after the delay. Permissionless.
   * @param _crew Address to remove from crew.
   */
  function executeRemoveCrew(address _crew) external;

  /**
   * @notice Open a crew-led offboard against `_target`. Crew-hat-gated; one live vote at a time; no captain.
   * @dev Reverts if mutiny is active, another offboard is live, `_target` is the caller, not crew, or has a pending captain remove.
   * @param _target Crew member to remove.
   * @return _offboardId New vote id.
   */
  function proposeOffboard(address _target) external returns (uint256 _offboardId);

  /**
   * @notice Cast a yea or nay on the active offboard. Crew-hat-gated.
   * @param _offboardId Active offboard id.
   * @param _support True for yea, false for nay.
   */
  function crewOffboardVote(uint256 _offboardId, bool _support) external;

  /**
   * @notice Finalize an offboard if `QUORUM_OF_CAST` passed and the deadline has not passed. Permissionless.
   * @param _offboardId Vote to execute.
   */
  function executeOffboard(uint256 _offboardId) external;

  /**
   * @notice Clear a failed active offboard after its deadline. Permissionless; lifts the roster freeze.
   * @param _offboardId Active offboard id that has passed `deadline` without `executeOffboard`.
   */
  function expireOffboard(uint256 _offboardId) external;

  /**
   * @notice Mint one crew hat to `_formerCaptain` with no delay (mutiny / succession path).
   * @dev Only callable by the MutinyRole hat wearer; used to seat a deposed human captain as crew.
   * @param _formerCaptain Recipient of the crew hat.
   */
  function mintCrewFromMutiny(address _formerCaptain) external;

  /**
   * @notice Hand the existing crew hat from the elected successor to the former captain in one step.
   * @dev Only callable by the MutinyRole hat wearer. Used when the new captain was already crew.
   * @param _formerCaptain Previous captain (receives crew).
   * @param _newCaptain New captain (must not retain the crew hat after execution).
   */
  function crewHandoffForMutiny(address _formerCaptain, address _newCaptain) external;

  /**
   * @notice Toggle mutiny mode to guard captain-driven onboarding.
   * @dev Only callable by the MutinyRole hat wearer.
   * @param _active True to block captain onboarding while a mutiny runs.
   */
  function setMutinyActive(bool _active) external;

  /**
   * @notice Update the crew change delay. TreasuryAuthorityRole-gated.
   * @dev Must fall within the delay bounds enforced by the inherited `RangeValidator` base contract.
   * @param _newValue New delay in seconds.
   */
  function setCrewChangeDelay(uint256 _newValue) external;

  /**
   * @notice Update the crew-led offboard voting window. TreasuryAuthorityRole-gated.
   * @param _newValue New expiry in seconds.
   */
  function setCrewOffboardExpiry(uint256 _newValue) external;

  /**
   * @notice Update the crew-led offboard quorum bps. TreasuryAuthorityRole-gated.
   * @param _newValue New quorum in basis points.
   */
  function setCrewOffboardQuorumBps(uint256 _newValue) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Seconds between scheduling and executing a crew add / remove.
   * @return _delay The current delay value.
   */
  function crewChangeDelay() external view returns (uint256 _delay);

  /**
   * @notice Seconds from offboard propose until the vote may be expired.
   * @return _expiry The current expiry value.
   */
  function crewOffboardExpiry() external view returns (uint256 _expiry);

  /**
   * @notice Quorum in basis points for crew-led offboard (`QUORUM_OF_CAST`).
   * @return _bps The current quorum value.
   */
  function crewOffboardQuorumBps() external view returns (uint256 _bps);

  /**
   * @notice Id of the currently active crew-led offboard, or zero if none.
   * @return _id The active offboard id.
   */
  function activeCrewOffboardId() external view returns (uint256 _id);

  /**
   * @notice Highest offboard id ever issued (`0` before the first vote).
   * @return _count Last issued id.
   */
  function crewOffboardCount() external view returns (uint256 _count);

  /**
   * @notice Whether a mutiny is currently active.
   * @return _active True if mutiny is active.
   */
  function mutinyActive() external view returns (bool _active);

  /**
   * @notice Timestamp after which `executeAddCrew` succeeds, or zero if none.
   * @param _candidate Candidate address.
   * @return _executableAt Unix timestamp, or zero.
   */
  function pendingCrewAddAt(address _candidate) external view returns (uint256 _executableAt);

  /**
   * @notice Timestamp after which `executeRemoveCrew` succeeds, or zero if none.
   * @param _crew Crew address.
   * @return _executableAt Unix timestamp, or zero.
   */
  function pendingCrewRemoveAt(address _crew) external view returns (uint256 _executableAt);

  /**
   * @notice Number of outstanding scheduled crew adds.
   * @return _count Set length; matches `pendingAdds` / `pendingAddAt`.
   */
  function pendingAddCount() external view returns (uint256 _count);

  /**
   * @notice Number of outstanding scheduled crew removes.
   * @return _count Set length; matches `pendingRemoves` / `pendingRemoveAt`.
   */
  function pendingRemoveCount() external view returns (uint256 _count);

  /**
   * @notice Pending add at index `_index`. Reverts if `_index >= pendingAddCount()`.
   * @param _index Zero-based index into the pending-add set.
   * @return _candidate Address waiting to receive the crew hat.
   * @return _executableAt Timestamp when `executeAddCrew` becomes valid.
   */
  function pendingAddAt(uint256 _index) external view returns (address _candidate, uint256 _executableAt);

  /**
   * @notice Pending remove at index `_index`. Reverts if `_index >= pendingRemoveCount()`.
   * @param _index Zero-based index into the pending-remove set.
   * @return _crew Address waiting to lose the crew hat.
   * @return _executableAt Timestamp when `executeRemoveCrew` becomes valid.
   */
  function pendingRemoveAt(uint256 _index) external view returns (address _crew, uint256 _executableAt);

  /**
   * @notice All pending crew adds and their executable timestamps.
   * @return _candidates Addresses waiting to receive the crew hat.
   * @return _executableAts Matching `executeAddCrew` timestamps.
   */
  function pendingAdds() external view returns (address[] memory _candidates, uint256[] memory _executableAts);

  /**
   * @notice All pending crew removes and their executable timestamps.
   * @return _crew Addresses waiting to lose the crew hat.
   * @return _executableAts Matching `executeRemoveCrew` timestamps.
   */
  function pendingRemoves() external view returns (address[] memory _crew, uint256[] memory _executableAts);

  /**
   * @notice Local crew-hat eligibility flag for `_wearer` (same bit as `getWearerStatus`).
   * @param _wearer Address to query.
   * @return _eligible True if this contract treats `_wearer` as eligible crew.
   */
  function crewEligible(address _wearer) external view returns (bool _eligible);

  /**
   * @notice Captain hat id for access-control checks.
   * @return _captainHatId The captain hat id.
   */
  function captainHatId() external view returns (uint256 _captainHatId);

  /**
   * @notice Crew hat id administered by this contract.
   * @return _crewHatId The crew hat id.
   */
  function crewHatId() external view returns (uint256 _crewHatId);

  /**
   * @notice Role hat worn by the active MutinyModule clone.
   * @return _mutinyRoleHatId The MutinyRole hat id.
   */
  function mutinyRoleHatId() external view returns (uint256 _mutinyRoleHatId);

  /**
   * @notice Role hat worn by the active Quartermaster clone.
   * @return _quartermasterRoleHatId The QuartermasterRole hat id.
   */
  function quartermasterRoleHatId() external view returns (uint256 _quartermasterRoleHatId);

  /**
   * @notice Role hat worn by the active TreasuryAuthority clone.
   * @return _treasuryAuthorityRoleHatId The TreasuryAuthorityRole hat id.
   */
  function treasuryAuthorityRoleHatId() external view returns (uint256 _treasuryAuthorityRoleHatId);

  /**
   * @notice Read the state of a crew-led offboard vote.
   * @param _id Vote identifier.
   * @return _target Crew member to remove.
   * @return _proposer Crew member that opened the vote.
   * @return _deadline Timestamp after which the vote can only be expired.
   * @return _snapshot Crew snapshot at propose time.
   * @return _yeas Yea vote count.
   * @return _nays Nay vote count.
   * @return _executed Whether the vote has already been executed.
   */
  function crewOffboard(uint256 _id)
    external
    view
    returns (
      address _target,
      address _proposer,
      uint64 _deadline,
      uint64 _snapshot,
      uint64 _yeas,
      uint64 _nays,
      bool _executed
    );

  /**
   * @notice Whether `_voter` has cast a vote in `_offboardId`.
   * @param _offboardId Vote identifier.
   * @param _voter Voter address.
   * @return _voted True if the voter has voted in this offboard.
   */
  function hasCrewOffboardVote(uint256 _offboardId, address _voter) external view returns (bool _voted);
}
