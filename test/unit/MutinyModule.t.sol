// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {HatGated} from 'contracts/utils/HatGated.sol';
import {RangeValidator} from 'contracts/utils/RangeValidator.sol';

import {PROPOSAL_EXPIRY} from 'script/Constants.sol';

import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IMutinyModule} from 'interfaces/core/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';

/**
 * @title UnitMutinyModuleBase
 * @author Pacto
 * @notice Shared fixture for MutinyModule tests. Deploys a master, clones it, initializes the
 *         clone with fake peer addresses (captain EOA, Quartermaster address), then stages Hats
 *         state via `vm.mockCall`. No concrete Hats, Quartermaster, or Safe contracts are
 *         deployed — all external interactions are mocked.
 */
abstract contract UnitMutinyModuleBase is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.mutiny.HATS'))));

  uint256 internal constant _CAPTAIN_HAT = 10;
  uint256 internal constant _CREW_HAT = 20;
  uint256 internal constant _MUTINY_ROLE_HAT = 30;
  uint256 internal constant _QM_ROLE_HAT = 40;
  uint256 internal constant _TA_ROLE_HAT = 50;

  MutinyModule internal _master;
  MutinyModule internal _mm;

  address internal _captain = makeAddr('captain');
  address internal _quartermaster = makeAddr('quartermaster');
  address internal _alice = makeAddr('alice');
  address internal _bob = makeAddr('bob');
  address internal _carol = makeAddr('carol');
  address internal _stranger = makeAddr('stranger');
  address internal _newCaptainEoa = makeAddr('newCaptainEoa');
  address internal _squadSafe = makeAddr('mutinySquadSafe');

  function setUp() public virtual {
    vm.etch(_HATS_ADDRESS, hex'00');
    _master = new MutinyModule(IHats(_HATS_ADDRESS));
    _mm = MutinyModule(Clones.clone(address(_master)));
    _mockWearer(_quartermaster, _QM_ROLE_HAT, true);
    _initDefault(_captain, _quartermaster);
  }

  function _initParams(
    address _initialCaptain,
    address _qmPeer
  ) internal view returns (IMutinyModule.InitParams memory _p) {
    _p = IMutinyModule.InitParams({
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      mutinyRoleHatId: _MUTINY_ROLE_HAT,
      quartermasterRoleHatId: _QM_ROLE_HAT,
      captain: _initialCaptain,
      quartermaster: _qmPeer,
      safe: _squadSafe,
      treasuryAuthorityRoleHatId: _TA_ROLE_HAT,
      mutinyExpiry: PROPOSAL_EXPIRY
    });
  }

  function _initDefault(address _initialCaptain, address _qmPeer) internal {
    _mm.initialize(_initParams(_initialCaptain, _qmPeer));
  }

  function _mockWearer(address _account, uint256 _hatId, bool _isWearer) internal {
    vm.mockCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _account, _hatId), abi.encode(_isWearer)
    );
  }

  function _mockHatSupply(uint256 _hatId, uint32 _supply) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.hatSupply.selector, _hatId), abi.encode(_supply));
  }

  function _mockTransferHat(uint256 _hatId, address _from, address _to) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _hatId, _from, _to), abi.encode());
  }

  function _mockQmNoActiveOffboard() internal {
    vm.mockCall(
      _quartermaster, abi.encodeWithSelector(IQuartermaster.activeCrewOffboardId.selector), abi.encode(uint256(0))
    );
  }

  function _mockQmMintCrewFromMutiny(address _formerCaptain) internal {
    vm.mockCall(
      _quartermaster, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _formerCaptain), abi.encode()
    );
  }

  function _mockQmRevokeCrewFromMutiny(address _crew) internal {
    vm.mockCall(
      _quartermaster, abi.encodeWithSelector(IQuartermaster.revokeCrewFromMutiny.selector, _crew), abi.encode()
    );
  }

  /// @notice Seeds a winning mutiny (5 crew, 3 yeas ⇒ threshold met) and leaves it un-executed.
  function _stageWinningMutiny(
    address _proposedNewCaptain,
    bool _seatFormerCaptain
  ) internal returns (uint256 _mutinyId) {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockWearer(_carol, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();

    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_proposedNewCaptain, _seatFormerCaptain);
    _mutinyId = _mm.activeMutinyId();

    vm.prank(_alice);
    _mm.castVote(_mutinyId);
    vm.prank(_bob);
    _mm.castVote(_mutinyId);
    vm.prank(_carol);
    _mm.castVote(_mutinyId);
  }
}

contract UnitMutinyModuleInit is UnitMutinyModuleBase {
  function test_Constructor_DisablesInitializersOnMaster() external {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _master.initialize(_initParams(_captain, _quartermaster));
  }

  function test_Initialize_SetsStorage() external view {
    assertEq(_mm.captainHatId(), _CAPTAIN_HAT);
    assertEq(_mm.crewHatId(), _CREW_HAT);
    assertEq(_mm.mutinyRoleHatId(), _MUTINY_ROLE_HAT);
    assertEq(_mm.quartermasterRoleHatId(), _QM_ROLE_HAT);
    assertEq(_mm.captain(), _captain);
    assertEq(_mm.quartermaster(), _quartermaster);
    assertEq(_mm.safe(), _squadSafe);
    assertEq(_mm.treasuryAuthorityRoleHatId(), _TA_ROLE_HAT);
    assertEq(_mm.mutinyExpiry(), PROPOSAL_EXPIRY);
    assertEq(_mm.activeMutinyId(), 0);
    assertEq(_mm.mutinyCount(), 0);
    assertTrue(_mm.isQuiet());
    assertEq(address(_mm.hats()), _HATS_ADDRESS);
  }

  function test_Initialize_RevertsOnZeroCaptain() external {
    MutinyModule _fresh = MutinyModule(Clones.clone(address(_master)));
    IMutinyModule.InitParams memory _p = _initParams(address(0), _quartermaster);
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsOnZeroQuartermaster() external {
    MutinyModule _fresh = MutinyModule(Clones.clone(address(_master)));
    IMutinyModule.InitParams memory _p = _initParams(_captain, address(0));
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsOnZeroSafe() external {
    MutinyModule _fresh = MutinyModule(Clones.clone(address(_master)));
    IMutinyModule.InitParams memory _p = _initParams(_captain, _quartermaster);
    _p.safe = address(0);
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsOnExpiryBelowMin() external {
    MutinyModule _fresh = MutinyModule(Clones.clone(address(_master)));
    IMutinyModule.InitParams memory _p = _initParams(_captain, _quartermaster);
    _p.mutinyExpiry = 30;
    vm.expectRevert(abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, 30, 60, 60 days));
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsIfAlreadyInitialized() external {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _mm.initialize(_initParams(_captain, _quartermaster));
  }

  function test_GetWearerStatus_AlwaysEligibleAndStanding() external view {
    (bool _eligible, bool _standing) = _mm.getWearerStatus(_captain, _CAPTAIN_HAT);
    assertTrue(_eligible);
    assertTrue(_standing);

    (bool _eligibleAlt, bool _standingAlt) = _mm.getWearerStatus(_alice, _CAPTAIN_HAT);
    assertTrue(_eligibleAlt);
    assertTrue(_standingAlt);
  }
}

contract UnitMutinyModuleStart is UnitMutinyModuleBase {
  function test_StartMutiny_HappyPath_EmitsAndSetsActiveId() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();

    vm.expectEmit(true, true, true, true, address(_mm));
    emit IMutinyModule.MutinyStarted(1, _alice, _newCaptainEoa, 5, false);

    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);

    assertEq(_mm.activeMutinyId(), 1);
    assertFalse(_mm.isQuiet());

    (
      address _proposed,
      address _fromCaptain,
      uint64 _startedAt,
      uint64 _deadline,
      uint64 _snapshot,
      uint64 _yeas,
      bool _executed,
      bool _seatFormerCaptain
    ) = _mm.mutiny(1);
    assertEq(_proposed, _newCaptainEoa);
    assertEq(_fromCaptain, _captain);
    assertEq(_startedAt, uint64(block.timestamp));
    assertEq(uint256(_deadline), block.timestamp + PROPOSAL_EXPIRY);
    assertEq(_snapshot, 5);
    assertEq(_yeas, 0);
    assertFalse(_executed);
    assertFalse(_seatFormerCaptain);
    assertEq(_mm.mutinyCount(), 1);
    assertFalse(_mm.thresholdReached(1));
  }

  function test_StartMutiny_RevertsIfNotCrew() external {
    _mockWearer(_stranger, _CREW_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CREW_HAT, _stranger));
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
  }

  function test_StartMutiny_RevertsOnZeroNewCaptain() external {
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _mm.startMutinyToArbitraryEoa(address(0), false);
  }

  function test_StartMutiny_RevertsOnSameCaptain() external {
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_SameCaptain.selector, _captain));
    _mm.startMutinyToArbitraryEoa(_captain, false);
  }

  function test_StartMutiny_RevertsIfAlreadyActive() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();

    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);

    vm.prank(_alice);
    vm.expectRevert(IMutinyModule.MutinyModule_AlreadyActive.selector);
    _mm.startMutinyToArbitraryEoa(_bob, false);
  }

  function test_StartMutiny_RevertsOnStaleQuartermaster() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_quartermaster, _QM_ROLE_HAT, false);
    _mockHatSupply(_CREW_HAT, 5);
    // `_startMutiny` calls `_liveQuartermaster` for the crew-offboard check; stale role hat reverts.
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleQuartermaster.selector, _quartermaster));
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
  }

  function test_StartMutiny_RevertsOnStaleCaptain() external {
    _mockWearer(_captain, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleCaptain.selector, _captain));
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
  }

  function test_StartMutinyToPauseCaptain_OpensRoundTargetingSafe() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();

    vm.expectEmit(true, true, true, true, address(_mm));
    emit IMutinyModule.MutinyStarted(1, _alice, _squadSafe, 5, false);

    vm.prank(_alice);
    _mm.startMutinyToPauseCaptain(false);

    (address _proposed,,,,,,,) = _mm.mutiny(1);
    assertEq(_proposed, _squadSafe);
    assertEq(_mm.safe(), _squadSafe);
  }
}

contract UnitMutinyModuleVote is UnitMutinyModuleBase {
  uint256 internal _mutinyId;

  function setUp() public override {
    super.setUp();
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();
    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
    _mutinyId = _mm.activeMutinyId();
  }

  function test_CastVote_HappyPath_EmitsAndTallies() external {
    _mockWearer(_bob, _CREW_HAT, true);
    vm.expectEmit(true, true, false, true, address(_mm));
    emit IMutinyModule.MutinyVoteCast(_mutinyId, _bob);
    vm.prank(_bob);
    _mm.castVote(_mutinyId);

    assertTrue(_mm.hasVoted(_mutinyId, _bob));
    (,,,,, uint64 _yeas,,) = _mm.mutiny(_mutinyId);
    assertEq(_yeas, 1);
    assertFalse(_mm.thresholdReached(_mutinyId));
  }

  function test_CastVote_RevertsIfNotCrew() external {
    _mockWearer(_stranger, _CREW_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CREW_HAT, _stranger));
    _mm.castVote(_mutinyId);
  }

  function test_CastVote_RevertsOnZeroId() external {
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _mm.castVote(0);
  }

  function test_CastVote_RevertsOnWrongId() external {
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _mm.castVote(_mutinyId + 1);
  }

  function test_CastVote_RevertsOnDoubleVote() external {
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    _mm.castVote(_mutinyId);

    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_AlreadyVoted.selector, _alice));
    _mm.castVote(_mutinyId);
  }

  function test_IsInSnapshot_ReturnsCurrentCrewWhileActive() external {
    _mockWearer(_bob, _CREW_HAT, true);
    assertTrue(_mm.isInSnapshot(_mutinyId, _bob));
    _mockWearer(_stranger, _CREW_HAT, false);
    assertFalse(_mm.isInSnapshot(_mutinyId, _stranger));
  }

  function test_IsInSnapshot_FalseForUnknownId() external view {
    assertFalse(_mm.isInSnapshot(9999, _alice));
  }
}

contract UnitMutinyModuleExecute is UnitMutinyModuleBase {
  function test_ExecuteMutiny_HappyPath_NonCrewSuccessor_NoSeat() external {
    uint256 _id = _stageWinningMutiny(_newCaptainEoa, false);
    assertTrue(_mm.thresholdReached(_id));
    assertFalse(_mm.thresholdReached(0));

    _mockTransferHat(_CAPTAIN_HAT, _captain, _newCaptainEoa);
    _mockWearer(_newCaptainEoa, _CREW_HAT, false);
    _mockQmNoActiveOffboard();

    vm.expectCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _CAPTAIN_HAT, _captain, _newCaptainEoa)
    );
    vm.expectEmit(true, true, true, true, address(_mm));
    emit IMutinyModule.MutinyExecuted(_id, _captain, _newCaptainEoa);

    _mm.executeMutiny(_id);

    assertEq(_mm.captain(), _newCaptainEoa);
    assertEq(_mm.activeMutinyId(), 0);
    assertTrue(_mm.isQuiet());
    (,,,,,, bool _executed, bool _seatFormerCaptain) = _mm.mutiny(_id);
    assertTrue(_executed);
    assertFalse(_seatFormerCaptain);

    (bool _oldElig,) = _mm.getWearerStatus(_captain, _CAPTAIN_HAT);
    (bool _newElig,) = _mm.getWearerStatus(_newCaptainEoa, _CAPTAIN_HAT);
    assertTrue(_oldElig);
    assertTrue(_newElig);
  }

  function test_ExecuteMutiny_HappyPath_NonCrewSuccessor_SeatFormer() external {
    uint256 _id = _stageWinningMutiny(_newCaptainEoa, true);

    _mockTransferHat(_CAPTAIN_HAT, _captain, _newCaptainEoa);
    _mockWearer(_newCaptainEoa, _CREW_HAT, false);
    _mockQmMintCrewFromMutiny(_captain);
    _mockQmNoActiveOffboard();

    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _captain));

    _mm.executeMutiny(_id);
    assertEq(_mm.captain(), _newCaptainEoa);
    (,,,,,,, bool _seatFormerCaptain) = _mm.mutiny(_id);
    assertTrue(_seatFormerCaptain);
  }

  function test_ExecuteMutiny_HappyPath_CrewSuccessor_RevokesOnly() external {
    address _crewSuccessor = _bob;
    uint256 _id = _stageWinningMutiny(_crewSuccessor, false);

    _mockTransferHat(_CAPTAIN_HAT, _captain, _crewSuccessor);
    _mockWearer(_crewSuccessor, _CREW_HAT, true);
    _mockQmRevokeCrewFromMutiny(_crewSuccessor);
    _mockQmNoActiveOffboard();

    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.revokeCrewFromMutiny.selector, _crewSuccessor));

    _mm.executeMutiny(_id);
    assertEq(_mm.captain(), _crewSuccessor);
  }

  function test_ExecuteMutiny_HappyPath_CrewSuccessor_RevokeAndSeatFormer() external {
    address _crewSuccessor = _bob;
    uint256 _id = _stageWinningMutiny(_crewSuccessor, true);

    _mockTransferHat(_CAPTAIN_HAT, _captain, _crewSuccessor);
    _mockWearer(_crewSuccessor, _CREW_HAT, true);
    _mockQmRevokeCrewFromMutiny(_crewSuccessor);
    _mockQmMintCrewFromMutiny(_captain);
    _mockQmNoActiveOffboard();

    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.revokeCrewFromMutiny.selector, _crewSuccessor));
    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _captain));

    _mm.executeMutiny(_id);
    assertEq(_mm.captain(), _crewSuccessor);
  }

  function test_ExecuteMutiny_HappyPath_DelegatedCaptain_SeatFormer() external {
    // EIP-7702-style designator on the outgoing captain must not block seating when opted in.
    bytes memory _delegation = bytes.concat(hex'ef0100', bytes20(address(_master)));
    vm.etch(_captain, _delegation);

    uint256 _id = _stageWinningMutiny(_bob, true);
    _mockTransferHat(_CAPTAIN_HAT, _captain, _bob);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockQmRevokeCrewFromMutiny(_bob);
    _mockQmMintCrewFromMutiny(_captain);
    _mockQmNoActiveOffboard();

    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.revokeCrewFromMutiny.selector, _bob));
    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _captain));

    _mm.executeMutiny(_id);
    assertEq(_mm.captain(), _bob);
  }

  function test_ExecuteMutiny_RevertsOnZeroId() external {
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _mm.executeMutiny(0);
  }

  function test_ExecuteMutiny_RevertsOnUnknownId() external {
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _mm.executeMutiny(42);
  }

  function test_ExecuteMutiny_RevertsIfAlreadyExecuted() external {
    uint256 _id = _stageWinningMutiny(_newCaptainEoa, false);
    _mockTransferHat(_CAPTAIN_HAT, _captain, _newCaptainEoa);
    _mockWearer(_newCaptainEoa, _CREW_HAT, false);
    _mockQmNoActiveOffboard();
    _mm.executeMutiny(_id);

    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _mm.executeMutiny(_id);
  }

  function test_ExecuteMutiny_RevertsIfThresholdNotReached() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();

    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
    uint256 _id = _mm.activeMutinyId();

    vm.prank(_alice);
    _mm.castVote(_id);
    vm.prank(_bob);
    _mm.castVote(_id);

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_ThresholdNotReached.selector, 2, 5));
    _mm.executeMutiny(_id);
  }

  function test_ExecuteMutiny_RevertsOnStaleCaptainCache() external {
    uint256 _id = _stageWinningMutiny(_newCaptainEoa, false);
    // Simulate captain cache drift by forcing the stored captain to be something other than
    // the fromCaptain of the round. We can't mutate storage directly without vm.store; instead
    // we kick off a fresh scenario where captain in state is already the same — the only way
    // the check can fire is if the executeMutiny is interleaved with another state-mutating
    // path. Use vm.store to corrupt captain slot.
    vm.store(address(_mm), bytes32(uint256(4)), bytes32(uint256(uint160(_alice)))); // `captain` slot
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleCaptain.selector, _captain));
    _mm.executeMutiny(_id);
  }
}

contract UnitMutinyModuleCaptainResign is UnitMutinyModuleBase {
  function test_CaptainResign_HappyPath_NonCrew_NoSeat() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockTransferHat(_CAPTAIN_HAT, _captain, _newCaptainEoa);
    _mockWearer(_newCaptainEoa, _CREW_HAT, false);

    vm.expectCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _CAPTAIN_HAT, _captain, _newCaptainEoa)
    );
    vm.expectEmit(true, true, false, true, address(_mm));
    emit IMutinyModule.CaptainResigned(_captain, _newCaptainEoa, false);

    vm.prank(_captain);
    _mm.captainResign(_newCaptainEoa, false);

    assertEq(_mm.captain(), _newCaptainEoa);
  }

  function test_CaptainResign_HappyPath_NonCrew_SeatFormer() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockTransferHat(_CAPTAIN_HAT, _captain, _newCaptainEoa);
    _mockWearer(_newCaptainEoa, _CREW_HAT, false);
    _mockQmMintCrewFromMutiny(_captain);

    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _captain));
    vm.expectEmit(true, true, false, true, address(_mm));
    emit IMutinyModule.CaptainResigned(_captain, _newCaptainEoa, true);

    vm.prank(_captain);
    _mm.captainResign(_newCaptainEoa, true);

    assertEq(_mm.captain(), _newCaptainEoa);
  }

  function test_CaptainResign_HappyPath_CrewSuccessor_RevokesOnly() external {
    address _crewSuccessor = _bob;
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockTransferHat(_CAPTAIN_HAT, _captain, _crewSuccessor);
    _mockWearer(_crewSuccessor, _CREW_HAT, true);
    _mockQmRevokeCrewFromMutiny(_crewSuccessor);

    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.revokeCrewFromMutiny.selector, _crewSuccessor));

    vm.prank(_captain);
    _mm.captainResign(_crewSuccessor, false);
    assertEq(_mm.captain(), _crewSuccessor);
  }

  function test_CaptainResign_RevertsIfNotCaptainWearer() external {
    _mockWearer(_stranger, _CAPTAIN_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _mm.captainResign(_newCaptainEoa, false);
  }

  function test_CaptainResign_RevertsOnZeroNewCaptain() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _mm.captainResign(address(0), false);
  }

  function test_CaptainResign_RevertsIfSameAddress() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_SameCaptain.selector, _captain));
    _mm.captainResign(_captain, false);
  }

  function test_CaptainResign_RevertsDuringActiveMutiny() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();
    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);

    vm.prank(_captain);
    vm.expectRevert(IMutinyModule.MutinyModule_AlreadyActive.selector);
    _mm.captainResign(_bob, false);
  }

  function test_CaptainResign_RevertsOnStaleCaptainCache() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.store(address(_mm), bytes32(uint256(4)), bytes32(uint256(uint160(_alice))));
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleCaptain.selector, _alice));
    _mm.captainResign(_newCaptainEoa, false);
  }
}

contract UnitMutinyModuleExpiry is UnitMutinyModuleBase {
  function test_StartMutiny_RevertsIfCrewOffboardActive() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    vm.mockCall(
      _quartermaster, abi.encodeWithSelector(IQuartermaster.activeCrewOffboardId.selector), abi.encode(uint256(1))
    );

    vm.prank(_alice);
    vm.expectRevert(IMutinyModule.MutinyModule_CrewOffboardActive.selector);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
  }

  function test_ExecuteMutiny_RevertsAfterDeadline() external {
    uint256 _id = _stageWinningMutiny(_newCaptainEoa, false);
    vm.warp(block.timestamp + PROPOSAL_EXPIRY);

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_Expired.selector, _id));
    _mm.executeMutiny(_id);
  }

  function test_CastVote_RevertsAfterDeadline() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();
    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
    uint256 _id = _mm.activeMutinyId();

    vm.warp(block.timestamp + PROPOSAL_EXPIRY);
    vm.prank(_bob);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_Expired.selector, _id));
    _mm.castVote(_id);
  }

  function test_ExpireMutiny_HappyPath_ClearsQmAndAllowsNewRound() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();
    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
    uint256 _id = _mm.activeMutinyId();

    vm.warp(block.timestamp + PROPOSAL_EXPIRY);
    _mockQmNoActiveOffboard();
    vm.expectEmit(true, false, false, true, address(_mm));
    emit IMutinyModule.MutinyExpired(_id);
    _mm.expireMutiny(_id);

    assertEq(_mm.activeMutinyId(), 0);
    assertTrue(_mm.isQuiet());

    _mockQmNoActiveOffboard();
    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_bob, false);
    assertEq(_mm.activeMutinyId(), 2);
  }

  function test_ExpireMutiny_RevertsBeforeDeadline() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();
    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
    uint256 _id = _mm.activeMutinyId();
    uint256 _deadline = uint256(block.timestamp) + PROPOSAL_EXPIRY;

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_NotExpired.selector, _id, _deadline));
    _mm.expireMutiny(_id);
  }

  function test_CaptainResign_WorksAfterExpireMutiny() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQmNoActiveOffboard();
    vm.prank(_alice);
    _mm.startMutinyToArbitraryEoa(_newCaptainEoa, false);
    uint256 _id = _mm.activeMutinyId();

    vm.warp(block.timestamp + PROPOSAL_EXPIRY);
    _mockQmNoActiveOffboard();
    _mm.expireMutiny(_id);

    _mockTransferHat(_CAPTAIN_HAT, _captain, _bob);
    _mockWearer(_bob, _CREW_HAT, false);
    vm.prank(_captain);
    _mm.captainResign(_bob, false);
    assertEq(_mm.captain(), _bob);
  }

  function test_SetMutinyExpiry_HappyPath() external {
    address _ta = makeAddr('treasuryAuthority');
    _mockWearer(_ta, _TA_ROLE_HAT, true);
    vm.expectEmit(false, false, false, true, address(_mm));
    emit IMutinyModule.MutinyExpiryUpdated(PROPOSAL_EXPIRY, 14 days);
    vm.prank(_ta);
    _mm.setMutinyExpiry(14 days);
    assertEq(_mm.mutinyExpiry(), 14 days);
  }

  function test_SetMutinyExpiry_RevertsIfNotTreasuryAuthority() external {
    _mockWearer(_stranger, _TA_ROLE_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _TA_ROLE_HAT, _stranger));
    _mm.setMutinyExpiry(14 days);
  }
}

