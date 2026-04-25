// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {MutinyModule} from 'contracts/MutinyModule.sol';
import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IMutinyModule} from 'interfaces/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';

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

  MutinyModule internal _master;
  MutinyModule internal _mm;

  address internal _captain = makeAddr('captain');
  address internal _quartermaster = makeAddr('quartermaster');
  address internal _alice = makeAddr('alice');
  address internal _bob = makeAddr('bob');
  address internal _carol = makeAddr('carol');
  address internal _stranger = makeAddr('stranger');
  address internal _newCaptainEoa = makeAddr('newCaptainEoa');

  function setUp() public virtual {
    vm.etch(_HATS_ADDRESS, hex'00');
    _master = new MutinyModule(IHats(_HATS_ADDRESS));
    _mm = MutinyModule(Clones.clone(address(_master)));
    _mockWearer(_quartermaster, _QM_ROLE_HAT, true);
    _initDefault(_captain, _quartermaster);
  }

  function _initDefault(address _initialCaptain, address _qmPeer) internal {
    IMutinyModule.InitParams memory _p = IMutinyModule.InitParams({
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      mutinyRoleHatId: _MUTINY_ROLE_HAT,
      quartermasterRoleHatId: _QM_ROLE_HAT,
      captain: _initialCaptain,
      quartermaster: _qmPeer
    });
    _mm.initialize(_p);
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

  function _mockQMMutinyActive(bool _active) internal {
    vm.mockCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.setMutinyActive.selector, _active), abi.encode());
  }

  function _mockQMMintCrewFromMutiny(address _formerCaptain) internal {
    vm.mockCall(
      _quartermaster, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _formerCaptain), abi.encode()
    );
  }

  function _mockQMCrewHandoffForMutiny(address _formerCaptain, address _newCaptain) internal {
    vm.mockCall(
      _quartermaster,
      abi.encodeWithSelector(IQuartermaster.crewHandoffForMutiny.selector, _formerCaptain, _newCaptain),
      abi.encode()
    );
  }

  /// @notice Seeds a winning mutiny (5 crew, 3 yeas ⇒ threshold met) and leaves it un-executed.
  function _stageWinningMutiny(address _proposedNewCaptain) internal returns (uint256 _mutinyId) {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockWearer(_carol, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQMMutinyActive(true);

    vm.prank(_alice);
    _mm.startMutiny(_proposedNewCaptain);
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
    IMutinyModule.InitParams memory _p = IMutinyModule.InitParams({
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      mutinyRoleHatId: _MUTINY_ROLE_HAT,
      quartermasterRoleHatId: _QM_ROLE_HAT,
      captain: _captain,
      quartermaster: _quartermaster
    });
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _master.initialize(_p);
  }

  function test_Initialize_SetsStorage() external view {
    assertEq(_mm.captainHatId(), _CAPTAIN_HAT);
    assertEq(_mm.crewHatId(), _CREW_HAT);
    assertEq(_mm.mutinyRoleHatId(), _MUTINY_ROLE_HAT);
    assertEq(_mm.quartermasterRoleHatId(), _QM_ROLE_HAT);
    assertEq(_mm.captain(), _captain);
    assertEq(_mm.quartermaster(), _quartermaster);
    assertEq(_mm.activeMutinyId(), 0);
    assertTrue(_mm.isQuiet());
  }

  function test_Initialize_RevertsOnZeroCaptain() external {
    MutinyModule _fresh = MutinyModule(Clones.clone(address(_master)));
    IMutinyModule.InitParams memory _p = IMutinyModule.InitParams({
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      mutinyRoleHatId: _MUTINY_ROLE_HAT,
      quartermasterRoleHatId: _QM_ROLE_HAT,
      captain: address(0),
      quartermaster: _quartermaster
    });
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsOnZeroQuartermaster() external {
    MutinyModule _fresh = MutinyModule(Clones.clone(address(_master)));
    IMutinyModule.InitParams memory _p = IMutinyModule.InitParams({
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      mutinyRoleHatId: _MUTINY_ROLE_HAT,
      quartermasterRoleHatId: _QM_ROLE_HAT,
      captain: _captain,
      quartermaster: address(0)
    });
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsIfAlreadyInitialized() external {
    IMutinyModule.InitParams memory _p = IMutinyModule.InitParams({
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      mutinyRoleHatId: _MUTINY_ROLE_HAT,
      quartermasterRoleHatId: _QM_ROLE_HAT,
      captain: _captain,
      quartermaster: _quartermaster
    });
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _mm.initialize(_p);
  }

  function test_GetWearerStatus_MatchesCachedCaptain() external view {
    (bool _eligible, bool _standing) = _mm.getWearerStatus(_captain, _CAPTAIN_HAT);
    assertTrue(_eligible);
    assertTrue(_standing);

    (bool _eligibleAlt,) = _mm.getWearerStatus(_alice, _CAPTAIN_HAT);
    assertFalse(_eligibleAlt);
  }
}

contract UnitMutinyModuleStart is UnitMutinyModuleBase {
  function test_StartMutiny_HappyPath_EmitsAndFreezesQM() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQMMutinyActive(true);

    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.setMutinyActive.selector, true));
    vm.expectEmit(true, true, true, true, address(_mm));
    emit IMutinyModule.MutinyStarted(1, _alice, _newCaptainEoa, 5);

    vm.prank(_alice);
    _mm.startMutiny(_newCaptainEoa);

    assertEq(_mm.activeMutinyId(), 1);
    assertFalse(_mm.isQuiet());

    (address _proposed, uint64 _startedAt, uint64 _snapshot, uint64 _yeas, bool _executed) = _mm.mutiny(1);
    assertEq(_proposed, _newCaptainEoa);
    assertEq(_startedAt, uint64(block.timestamp));
    assertEq(_snapshot, 5);
    assertEq(_yeas, 0);
    assertFalse(_executed);
  }

  function test_StartMutiny_RevertsIfNotCrew() external {
    _mockWearer(_stranger, _CREW_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CREW_HAT, _stranger));
    _mm.startMutiny(_newCaptainEoa);
  }

  function test_StartMutiny_RevertsOnZeroNewCaptain() external {
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _mm.startMutiny(address(0));
  }

  function test_StartMutiny_RevertsOnSameCaptain() external {
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_SameCaptain.selector, _captain));
    _mm.startMutiny(_captain);
  }

  function test_StartMutiny_RevertsIfAlreadyActive() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQMMutinyActive(true);

    vm.prank(_alice);
    _mm.startMutiny(_newCaptainEoa);

    vm.prank(_alice);
    vm.expectRevert(IMutinyModule.MutinyModule_AlreadyActive.selector);
    _mm.startMutiny(_bob);
  }

  function test_StartMutiny_RevertsOnStaleQuartermaster() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_quartermaster, _QM_ROLE_HAT, false);
    _mockHatSupply(_CREW_HAT, 5);
    // setMutinyActive is attempted *after* _requireLiveCaptain passes; it calls _liveQuartermaster
    // which reverts due to the stale role hat.
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleQuartermaster.selector, _quartermaster));
    _mm.startMutiny(_newCaptainEoa);
  }

  function test_StartMutiny_RevertsOnStaleCaptain() external {
    _mockWearer(_captain, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleCaptain.selector, _captain));
    _mm.startMutiny(_newCaptainEoa);
  }
}

contract UnitMutinyModuleVote is UnitMutinyModuleBase {
  uint256 internal _mutinyId;

  function setUp() public override {
    super.setUp();
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQMMutinyActive(true);
    vm.prank(_alice);
    _mm.startMutiny(_newCaptainEoa);
    _mutinyId = _mm.activeMutinyId();
  }

  function test_CastVote_HappyPath_EmitsAndTallies() external {
    _mockWearer(_bob, _CREW_HAT, true);
    vm.expectEmit(true, true, false, true, address(_mm));
    emit IMutinyModule.MutinyVoteCast(_mutinyId, _bob);
    vm.prank(_bob);
    _mm.castVote(_mutinyId);

    assertTrue(_mm.hasVoted(_mutinyId, _bob));
    (,,, uint64 _yeas,) = _mm.mutiny(_mutinyId);
    assertEq(_yeas, 1);
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
  function test_ExecuteMutiny_HappyPath_EOA_NonCrewSuccessor() external {
    uint256 _id = _stageWinningMutiny(_newCaptainEoa);

    _mockTransferHat(_CAPTAIN_HAT, _captain, _newCaptainEoa);
    _mockWearer(_newCaptainEoa, _CREW_HAT, false);
    _mockQMMintCrewFromMutiny(_captain);
    _mockQMMutinyActive(false);

    vm.expectCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _CAPTAIN_HAT, _captain, _newCaptainEoa)
    );
    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _captain));
    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.setMutinyActive.selector, false));
    vm.expectEmit(true, true, true, true, address(_mm));
    emit IMutinyModule.MutinyExecuted(_id, _captain, _newCaptainEoa);

    _mm.executeMutiny(_id);

    assertEq(_mm.captain(), _newCaptainEoa);
    assertEq(_mm.activeMutinyId(), 0);
    assertTrue(_mm.isQuiet());
    (,,,, bool _executed) = _mm.mutiny(_id);
    assertTrue(_executed);

    // Eligibility flipped to the new captain.
    (bool _oldElig,) = _mm.getWearerStatus(_captain, _CAPTAIN_HAT);
    (bool _newElig,) = _mm.getWearerStatus(_newCaptainEoa, _CAPTAIN_HAT);
    assertFalse(_oldElig);
    assertTrue(_newElig);
  }

  function test_ExecuteMutiny_HappyPath_EOA_CrewSuccessor() external {
    address _crewSuccessor = _bob;
    uint256 _id = _stageWinningMutiny(_crewSuccessor);

    _mockTransferHat(_CAPTAIN_HAT, _captain, _crewSuccessor);
    _mockWearer(_crewSuccessor, _CREW_HAT, true);
    _mockQMCrewHandoffForMutiny(_captain, _crewSuccessor);
    _mockQMMutinyActive(false);

    vm.expectCall(
      _quartermaster, abi.encodeWithSelector(IQuartermaster.crewHandoffForMutiny.selector, _captain, _crewSuccessor)
    );

    _mm.executeMutiny(_id);
    assertEq(_mm.captain(), _crewSuccessor);
  }

  function test_ExecuteMutiny_HappyPath_ContractFormerCaptain_NoCrewMint() external {
    // Re-initialize a fresh clone with a contract captain (non-zero code length).
    MutinyModule _mm2 = MutinyModule(Clones.clone(address(_master)));
    address _contractCaptain = address(_master); // any address with bytecode
    _mockWearer(_quartermaster, _QM_ROLE_HAT, true);
    IMutinyModule.InitParams memory _p = IMutinyModule.InitParams({
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      mutinyRoleHatId: _MUTINY_ROLE_HAT,
      quartermasterRoleHatId: _QM_ROLE_HAT,
      captain: _contractCaptain,
      quartermaster: _quartermaster
    });
    _mm2.initialize(_p);

    _mockWearer(_contractCaptain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockWearer(_carol, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQMMutinyActive(true);

    vm.prank(_alice);
    _mm2.startMutiny(_newCaptainEoa);
    uint256 _id = _mm2.activeMutinyId();

    vm.prank(_alice);
    _mm2.castVote(_id);
    vm.prank(_bob);
    _mm2.castVote(_id);
    vm.prank(_carol);
    _mm2.castVote(_id);

    _mockTransferHat(_CAPTAIN_HAT, _contractCaptain, _newCaptainEoa);
    _mockQMMutinyActive(false);

    // NOTE: We don't mock mintCrewFromMutiny — if it's called, the test will fail because the
    // call returns empty bytes but the mock is absent. vm.expectCall negation is not a feature,
    // so we rely on the Quartermaster mock specifically targeting setMutinyActive(false).
    _mm2.executeMutiny(_id);
    assertEq(_mm2.captain(), _newCaptainEoa);
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
    uint256 _id = _stageWinningMutiny(_newCaptainEoa);
    _mockTransferHat(_CAPTAIN_HAT, _captain, _newCaptainEoa);
    _mockWearer(_newCaptainEoa, _CREW_HAT, false);
    _mockQMMintCrewFromMutiny(_captain);
    _mockQMMutinyActive(false);
    _mm.executeMutiny(_id);

    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _mm.executeMutiny(_id);
  }

  function test_ExecuteMutiny_RevertsIfThresholdNotReached() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQMMutinyActive(true);

    vm.prank(_alice);
    _mm.startMutiny(_newCaptainEoa);
    uint256 _id = _mm.activeMutinyId();

    vm.prank(_alice);
    _mm.castVote(_id);
    vm.prank(_bob);
    _mm.castVote(_id);

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_ThresholdNotReached.selector, 2, 5));
    _mm.executeMutiny(_id);
  }

  function test_ExecuteMutiny_RevertsOnStaleCaptainCache() external {
    uint256 _id = _stageWinningMutiny(_newCaptainEoa);
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
  function test_CaptainResign_HappyPath_EoaToEoaNonCrew() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockTransferHat(_CAPTAIN_HAT, _captain, _newCaptainEoa);
    _mockWearer(_newCaptainEoa, _CREW_HAT, false);
    _mockQMMintCrewFromMutiny(_captain);

    vm.expectCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _CAPTAIN_HAT, _captain, _newCaptainEoa)
    );
    vm.expectCall(_quartermaster, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _captain));
    vm.expectEmit(true, true, false, true, address(_mm));
    emit IMutinyModule.CaptainResigned(_captain, _newCaptainEoa);

    vm.prank(_captain);
    _mm.captainResign(_newCaptainEoa);

    assertEq(_mm.captain(), _newCaptainEoa);
  }

  function test_CaptainResign_HappyPath_EoaToEoaCrewSuccessor() external {
    address _crewSuccessor = _bob;
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockTransferHat(_CAPTAIN_HAT, _captain, _crewSuccessor);
    _mockWearer(_crewSuccessor, _CREW_HAT, true);
    _mockQMCrewHandoffForMutiny(_captain, _crewSuccessor);

    vm.expectCall(
      _quartermaster, abi.encodeWithSelector(IQuartermaster.crewHandoffForMutiny.selector, _captain, _crewSuccessor)
    );

    vm.prank(_captain);
    _mm.captainResign(_crewSuccessor);
    assertEq(_mm.captain(), _crewSuccessor);
  }

  function test_CaptainResign_RevertsIfNotCaptainWearer() external {
    _mockWearer(_stranger, _CAPTAIN_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _mm.captainResign(_newCaptainEoa);
  }

  function test_CaptainResign_RevertsOnZeroNewCaptain() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _mm.captainResign(address(0));
  }

  function test_CaptainResign_RevertsIfSameAddress() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_SameCaptain.selector, _captain));
    _mm.captainResign(_captain);
  }

  function test_CaptainResign_RevertsDuringActiveMutiny() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockHatSupply(_CREW_HAT, 5);
    _mockQMMutinyActive(true);
    vm.prank(_alice);
    _mm.startMutiny(_newCaptainEoa);

    vm.prank(_captain);
    vm.expectRevert(IMutinyModule.MutinyModule_AlreadyActive.selector);
    _mm.captainResign(_bob);
  }

  function test_CaptainResign_RevertsOnStaleCaptainCache() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.store(address(_mm), bytes32(uint256(4)), bytes32(uint256(uint160(_alice))));
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleCaptain.selector, _alice));
    _mm.captainResign(_newCaptainEoa);
  }
}
