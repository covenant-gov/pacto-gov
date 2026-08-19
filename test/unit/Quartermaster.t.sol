// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {HatGated} from 'contracts/utils/HatGated.sol';
import {RangeValidator} from 'contracts/utils/RangeValidator.sol';

import {CREW_CHANGE_DELAY, PROPOSAL_EXPIRY, SQUAD_QUORUM_BPS} from 'script/Constants.sol';

import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';

/**
 * @title UnitQuartermasterBase
 * @author Pacto
 * @notice Shared fixture for Quartermaster unit tests. Deploys a master copy, initializes
 *         it directly as a stand-in for a clone (master copy has `_disableInitializers()`
 *         baked into runtime, so the direct-init path represents the clone behavior
 *         except for the `disableInitializers` safeguard — which is covered in its own
 *         test). All IHats interactions are mocked with `vm.mockCall`.
 */
abstract contract UnitQuartermasterBase is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.quartermaster.HATS'))));

  uint256 internal constant _CAPTAIN_HAT = 1;
  uint256 internal constant _CREW_HAT = 2;
  uint256 internal constant _MUTINY_ROLE_HAT = 3;
  uint256 internal constant _QUARTERMASTER_ROLE_HAT = 4;
  uint256 internal constant _TREASURY_AUTHORITY_ROLE_HAT = 5;

  uint32 internal constant _CREW_MAX = 10_000;

  Quartermaster internal _master;
  Quartermaster internal _qm;

  address internal _captain = makeAddr('captain');
  address internal _mutinyClone = makeAddr('mutinyClone');
  address internal _treasuryClone = makeAddr('treasuryClone');
  address internal _stranger = makeAddr('stranger');
  address internal _alice = makeAddr('alice');
  address internal _bob = makeAddr('bob');

  function setUp() public {
    vm.etch(_HATS_ADDRESS, hex'00');
    _master = new Quartermaster(IHats(_HATS_ADDRESS));
    _qm = Quartermaster(Clones.clone(address(_master)));
    _initDefault();
  }

  function _qmParams(uint256 _delay) internal pure returns (IQuartermaster.InitParams memory _p) {
    _p = IQuartermaster.InitParams({
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      mutinyRoleHatId: _MUTINY_ROLE_HAT,
      quartermasterRoleHatId: _QUARTERMASTER_ROLE_HAT,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT,
      crewChangeDelay: _delay,
      crewOffboardExpiry: PROPOSAL_EXPIRY,
      crewOffboardQuorumBps: SQUAD_QUORUM_BPS
    });
  }

  function _initDefault() internal {
    _qm.initialize(_qmParams(CREW_CHANGE_DELAY));
  }

  function _mockWearer(address _account, uint256 _hatId, bool _isWearer) internal {
    vm.mockCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _account, _hatId), abi.encode(_isWearer)
    );
  }

  function _mockCrewCapacity(uint32 _supply, uint32 _max) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.hatSupply.selector, _CREW_HAT), abi.encode(_supply));
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.getHatMaxSupply.selector, _CREW_HAT), abi.encode(_max));
  }

  function _mockMintHat(uint256 _hatId, address _wearer, bool _ok) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _hatId, _wearer), abi.encode(_ok));
  }

  function _mockCheckHatWearerStatus(uint256 _hatId, address _wearer, bool _updated) internal {
    vm.mockCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.checkHatWearerStatus.selector, _hatId, _wearer), abi.encode(_updated)
    );
  }

  function _mockTransferHat(uint256 _hatId, address _from, address _to) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _hatId, _from, _to), abi.encode());
  }

  /// @notice Drive `candidate` through a full request→execute add-crew flow ending at `block.timestamp`.
  function _seedCrew(address _candidate) internal {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_candidate, _CAPTAIN_HAT, false);
    _mockWearer(_candidate, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);

    vm.prank(_captain);
    _qm.requestAddCrew(_candidate);

    vm.warp(block.timestamp + CREW_CHANGE_DELAY);
    _mockWearer(_candidate, _CREW_HAT, false);
    _mockMintHat(_CREW_HAT, _candidate, true);

    _qm.executeAddCrew(_candidate);
  }
}

contract UnitQuartermasterInit is UnitQuartermasterBase {
  function test_Constructor_DisablesInitializersOnMaster() external {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _master.initialize(_qmParams(CREW_CHANGE_DELAY));
  }

  function test_Initialize_SetsHatIdsAndDelay() external view {
    assertEq(_qm.captainHatId(), _CAPTAIN_HAT);
    assertEq(_qm.crewHatId(), _CREW_HAT);
    assertEq(_qm.mutinyRoleHatId(), _MUTINY_ROLE_HAT);
    assertEq(_qm.quartermasterRoleHatId(), _QUARTERMASTER_ROLE_HAT);
    assertEq(_qm.treasuryAuthorityRoleHatId(), _TREASURY_AUTHORITY_ROLE_HAT);
    assertEq(_qm.crewChangeDelay(), CREW_CHANGE_DELAY);
    assertEq(_qm.crewOffboardExpiry(), PROPOSAL_EXPIRY);
    assertEq(_qm.crewOffboardQuorumBps(), SQUAD_QUORUM_BPS);
    assertFalse(_qm.mutinyActive());
    assertEq(_qm.activeCrewOffboardId(), 0);
    assertEq(_qm.pendingAddCount(), 0);
    assertEq(_qm.pendingRemoveCount(), 0);
    assertEq(address(_qm.hats()), _HATS_ADDRESS);
  }

  function test_Initialize_RevertsIfAlreadyInitialized() external {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _qm.initialize(_qmParams(CREW_CHANGE_DELAY));
  }

  function test_Initialize_RevertsOnDelayBelowMin() external {
    Quartermaster _fresh = Quartermaster(Clones.clone(address(_master)));
    vm.expectRevert(abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, 30, 60, 60 days));
    _fresh.initialize(_qmParams(30));
  }

  function test_Initialize_RevertsOnDelayAboveMax() external {
    Quartermaster _fresh = Quartermaster(Clones.clone(address(_master)));
    vm.expectRevert(abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, 61 days, 60, 60 days));
    _fresh.initialize(_qmParams(61 days));
  }

  function test_Initialize_RevertsOnOffboardExpiryBelowMin() external {
    Quartermaster _fresh = Quartermaster(Clones.clone(address(_master)));
    IQuartermaster.InitParams memory _p = _qmParams(CREW_CHANGE_DELAY);
    _p.crewOffboardExpiry = 30;
    vm.expectRevert(abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, 30, 60, 60 days));
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsOnOffboardQuorumBelowMin() external {
    Quartermaster _fresh = Quartermaster(Clones.clone(address(_master)));
    IQuartermaster.InitParams memory _p = _qmParams(CREW_CHANGE_DELAY);
    _p.crewOffboardQuorumBps = 100;
    vm.expectRevert(abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, 100, 500, 10_000));
    _fresh.initialize(_p);
  }
}

contract UnitQuartermasterAddRequest is UnitQuartermasterBase {
  function test_RequestAddCrew_HappyPath_EmitsAndStores() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);

    uint256 _expectedEta = block.timestamp;
    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewAddRequested(_alice, _expectedEta);

    vm.prank(_captain);
    _qm.requestAddCrew(_alice);

    assertEq(_qm.pendingCrewAddAt(_alice), _expectedEta);
    assertEq(_qm.pendingAddCount(), 1);
    (address _listed, uint256 _listedEta) = _qm.pendingAddAt(0);
    assertEq(_listed, _alice);
    assertEq(_listedEta, _expectedEta);
    assertFalse(_qm.isQuiet());
  }

  function test_RequestAddCrew_RevertsIfNotCaptain() external {
    _mockWearer(_stranger, _CAPTAIN_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _qm.requestAddCrew(_alice);
  }

  function test_RequestAddCrew_RevertsIfMutinyActive() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    vm.prank(_mutinyClone);
    _qm.setMutinyActive(true);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.requestAddCrew(_alice);
  }

  function test_RequestAddCrew_RevertsOnZeroAddress() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_ZeroAddress.selector);
    _qm.requestAddCrew(address(0));
  }

  function test_RequestAddCrew_RevertsIfCandidateIsCaptain() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_CandidateIsCaptain.selector, _alice));
    _qm.requestAddCrew(_alice);
  }

  function test_RequestAddCrew_RevertsIfAlreadyCrew() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _alice));
    _qm.requestAddCrew(_alice);
  }

  function test_RequestAddCrew_RevertsIfCrewFull() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(_CREW_MAX, _CREW_MAX);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_CrewFull.selector);
    _qm.requestAddCrew(_alice);
  }

  function test_RequestAddCrew_RevertsIfDuplicatePendingAdd() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);

    vm.prank(_captain);
    _qm.requestAddCrew(_alice);

    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_DuplicateCrewAdd.selector, _alice));
    _qm.requestAddCrew(_alice);
  }

  function test_RequestAddSecondCrew_UsesFullDelay_whenCrewExists() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);
    _mockMintHat(_CREW_HAT, _alice, true);
    address[] memory _bootstrap = new address[](1);
    _bootstrap[0] = _alice;
    vm.prank(_captain);
    _qm.bootstrapCrew(_bootstrap);

    _mockWearer(_bob, _CAPTAIN_HAT, false);
    _mockWearer(_bob, _CREW_HAT, false);
    _mockCrewCapacity(1, _CREW_MAX);

    vm.prank(_captain);
    _qm.requestAddCrew(_bob);
    assertEq(_qm.pendingCrewAddAt(_bob), block.timestamp + CREW_CHANGE_DELAY);
  }
}

contract UnitQuartermasterAddCancel is UnitQuartermasterBase {
  function test_CancelAddCrew_HappyPath_ClearsAndEmits() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);

    vm.prank(_captain);
    _qm.requestAddCrew(_alice);

    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewAddCancelled(_alice);
    vm.prank(_captain);
    _qm.cancelAddCrew(_alice);

    assertEq(_qm.pendingCrewAddAt(_alice), 0);
    assertTrue(_qm.isQuiet());
  }

  function test_CancelAddCrew_RevertsIfNotPending() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotPending.selector, _alice));
    _qm.cancelAddCrew(_alice);
  }

  function test_CancelAddCrew_RevertsIfNotCaptain() external {
    _mockWearer(_stranger, _CAPTAIN_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _qm.cancelAddCrew(_alice);
  }
}

contract UnitQuartermasterAddExecute is UnitQuartermasterBase {
  function test_ExecuteAddCrew_HappyPath_MintsAndEmits() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);
    vm.prank(_captain);
    _qm.requestAddCrew(_alice);

    _mockWearer(_alice, _CREW_HAT, false);
    _mockMintHat(_CREW_HAT, _alice, true);

    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _CREW_HAT, _alice));
    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewAddExecuted(_alice);

    _qm.executeAddCrew(_alice);

    assertEq(_qm.pendingCrewAddAt(_alice), 0);
    assertTrue(_qm.isQuiet());
    (bool _eligible, bool _standing) = _qm.getWearerStatus(_alice, _CREW_HAT);
    assertTrue(_eligible);
    assertTrue(_standing);
  }

  function test_ExecuteAddCrew_RevertsIfNotPending() external {
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotPending.selector, _alice));
    _qm.executeAddCrew(_alice);
  }

  function test_ExecuteAddCrew_RevertsIfStillLocked() external {
    _seedCrew(_alice);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_bob, _CAPTAIN_HAT, false);
    _mockWearer(_bob, _CREW_HAT, false);
    _mockCrewCapacity(1, _CREW_MAX);
    vm.prank(_captain);
    _qm.requestAddCrew(_bob);
    uint256 _eta = _qm.pendingCrewAddAt(_bob);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_StillLocked.selector, _bob, _eta));
    _qm.executeAddCrew(_bob);
  }

  function test_ExecuteAddCrew_RevertsIfMutinyActive() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);
    vm.prank(_captain);
    _qm.requestAddCrew(_alice);

    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    vm.prank(_mutinyClone);
    _qm.setMutinyActive(true);

    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.executeAddCrew(_alice);
  }

  function test_ExecuteAddCrew_RevertsIfAlreadyCrewAtExecuteTime() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);
    vm.prank(_captain);
    _qm.requestAddCrew(_alice);

    vm.warp(block.timestamp + CREW_CHANGE_DELAY);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _alice));
    _qm.executeAddCrew(_alice);
  }
}

contract UnitQuartermasterRemove is UnitQuartermasterBase {
  function test_RequestRemoveCrew_HappyPath() external {
    _seedCrew(_alice);

    _mockWearer(_alice, _CREW_HAT, true);
    uint256 _expectedEta = block.timestamp + CREW_CHANGE_DELAY;
    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewRemoveRequested(_alice, _expectedEta);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);

    assertEq(_qm.pendingCrewRemoveAt(_alice), _expectedEta);
    assertFalse(_qm.isQuiet());
  }

  function test_RequestRemoveCrew_RevertsIfMutinyActive() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    vm.prank(_mutinyClone);
    _qm.setMutinyActive(true);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.requestRemoveCrew(_alice);
  }

  function test_RequestRemoveCrew_RevertsOnZero() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_ZeroAddress.selector);
    _qm.requestRemoveCrew(address(0));
  }

  function test_RequestRemoveCrew_RevertsIfNotCrew() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, false);
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotCrew.selector, _alice));
    _qm.requestRemoveCrew(_alice);
  }

  function test_CancelRemoveCrew_HappyPath() external {
    _seedCrew(_alice);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);

    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewRemoveCancelled(_alice);
    vm.prank(_captain);
    _qm.cancelRemoveCrew(_alice);
    assertEq(_qm.pendingCrewRemoveAt(_alice), 0);
    assertTrue(_qm.isQuiet());
  }

  function test_CancelRemoveCrew_RevertsIfNotPending() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotPending.selector, _alice));
    _qm.cancelRemoveCrew(_alice);
  }

  function test_ExecuteRemoveCrew_HappyPath_FlipsEligibilityAndPokesHats() external {
    _seedCrew(_alice);

    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);

    vm.warp(block.timestamp + CREW_CHANGE_DELAY);
    _mockWearer(_alice, _CREW_HAT, true);
    _mockCheckHatWearerStatus(_CREW_HAT, _alice, true);

    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.checkHatWearerStatus.selector, _CREW_HAT, _alice));
    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewRemoveExecuted(_alice);

    _qm.executeRemoveCrew(_alice);

    (bool _eligible,) = _qm.getWearerStatus(_alice, _CREW_HAT);
    assertFalse(_eligible);
    assertEq(_qm.pendingCrewRemoveAt(_alice), 0);
    assertTrue(_qm.isQuiet());
  }

  function test_ExecuteRemoveCrew_RevertsIfNotPending() external {
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotPending.selector, _alice));
    _qm.executeRemoveCrew(_alice);
  }

  function test_ExecuteRemoveCrew_RevertsIfStillLocked() external {
    _seedCrew(_alice);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);
    uint256 _eta = _qm.pendingCrewRemoveAt(_alice);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_StillLocked.selector, _alice, _eta));
    _qm.executeRemoveCrew(_alice);
  }

  function test_ExecuteRemoveCrew_RevertsIfMutinyActive() external {
    _seedCrew(_alice);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);

    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    vm.prank(_mutinyClone);
    _qm.setMutinyActive(true);

    vm.warp(block.timestamp + CREW_CHANGE_DELAY);
    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.executeRemoveCrew(_alice);
  }

  function test_ExecuteRemoveCrew_RevertsIfAlreadyNonCrew() external {
    _seedCrew(_alice);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);

    vm.warp(block.timestamp + CREW_CHANGE_DELAY);
    _mockWearer(_alice, _CREW_HAT, false);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotCrew.selector, _alice));
    _qm.executeRemoveCrew(_alice);
  }
}

contract UnitQuartermasterMutinyHooks is UnitQuartermasterBase {
  function test_MintCrewFromMutiny_HappyPath() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);
    _mockMintHat(_CREW_HAT, _alice, true);

    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewMintedFromMutiny(_alice);
    vm.prank(_mutinyClone);
    _qm.mintCrewFromMutiny(_alice);

    (bool _eligible,) = _qm.getWearerStatus(_alice, _CREW_HAT);
    assertTrue(_eligible);
    assertTrue(_qm.crewEligible(_alice));
    assertEq(_qm.pendingAddCount(), 0);
  }

  function test_MintCrewFromMutiny_RevertsIfNotMutinyRole() external {
    _mockWearer(_stranger, _MUTINY_ROLE_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _MUTINY_ROLE_HAT, _stranger));
    _qm.mintCrewFromMutiny(_alice);
  }

  function test_MintCrewFromMutiny_RevertsOnZero() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    vm.prank(_mutinyClone);
    vm.expectRevert(IQuartermaster.Quartermaster_ZeroAddress.selector);
    _qm.mintCrewFromMutiny(address(0));
  }

  function test_MintCrewFromMutiny_RevertsIfAlreadyCrew() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_mutinyClone);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _alice));
    _qm.mintCrewFromMutiny(_alice);
  }

  function test_MintCrewFromMutiny_RevertsIfCrewFull() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockCrewCapacity(_CREW_MAX, _CREW_MAX);
    vm.prank(_mutinyClone);
    vm.expectRevert(IQuartermaster.Quartermaster_CrewFull.selector);
    _qm.mintCrewFromMutiny(_alice);
  }

  function test_CrewHandoffForMutiny_HappyPath() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockTransferHat(_CREW_HAT, _bob, _alice);

    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _CREW_HAT, _bob, _alice));
    vm.expectEmit(true, true, false, true, address(_qm));
    emit IQuartermaster.CrewHandoffForMutiny(_alice, _bob);

    vm.prank(_mutinyClone);
    _qm.crewHandoffForMutiny(_alice, _bob);

    (bool _eligible,) = _qm.getWearerStatus(_alice, _CREW_HAT);
    assertTrue(_eligible);
    assertTrue(_qm.crewEligible(_alice));
    assertEq(_qm.pendingAddCount(), 0);
  }

  function test_CrewHandoffForMutiny_RevertsOnZero() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    vm.prank(_mutinyClone);
    vm.expectRevert(IQuartermaster.Quartermaster_ZeroAddress.selector);
    _qm.crewHandoffForMutiny(address(0), _bob);
  }

  function test_CrewHandoffForMutiny_RevertsIfNewCaptainNotCrew() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    _mockWearer(_bob, _CREW_HAT, false);
    vm.prank(_mutinyClone);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotCrew.selector, _bob));
    _qm.crewHandoffForMutiny(_alice, _bob);
  }

  function test_CrewHandoffForMutiny_RevertsIfFormerAlreadyCrew() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_mutinyClone);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _alice));
    _qm.crewHandoffForMutiny(_alice, _bob);
  }

  function test_SetMutinyActive_TogglesAndEmits() external {
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);

    vm.expectEmit(false, false, false, true, address(_qm));
    emit IQuartermaster.MutinyActiveSet(true);
    vm.prank(_mutinyClone);
    _qm.setMutinyActive(true);
    assertTrue(_qm.mutinyActive());
    assertFalse(_qm.isQuiet());

    vm.expectEmit(false, false, false, true, address(_qm));
    emit IQuartermaster.MutinyActiveSet(false);
    vm.prank(_mutinyClone);
    _qm.setMutinyActive(false);
    assertFalse(_qm.mutinyActive());
    assertTrue(_qm.isQuiet());
  }

  function test_SetMutinyActive_RevertsIfNotMutinyRole() external {
    _mockWearer(_stranger, _MUTINY_ROLE_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _MUTINY_ROLE_HAT, _stranger));
    _qm.setMutinyActive(true);
  }
}

contract UnitQuartermasterBootstrap is UnitQuartermasterBase {
  function test_BootstrapCrew_HappyPath_mintsMultipleAndEligible() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    _mockWearer(_bob, _CAPTAIN_HAT, false);
    _mockWearer(_bob, _CREW_HAT, false);
    _mockCrewCapacity(0, _CREW_MAX);
    _mockMintHat(_CREW_HAT, _alice, true);
    _mockMintHat(_CREW_HAT, _bob, true);

    address[] memory _c = new address[](2);
    _c[0] = _alice;
    _c[1] = _bob;

    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewAddExecuted(_alice);
    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewAddExecuted(_bob);
    vm.prank(_captain);
    _qm.bootstrapCrew(_c);

    (bool _aOk,) = _qm.getWearerStatus(_alice, _CREW_HAT);
    (bool _bOk,) = _qm.getWearerStatus(_bob, _CREW_HAT);
    assertTrue(_aOk);
    assertTrue(_bOk);
    assertTrue(_qm.crewEligible(_alice));
    assertEq(_qm.pendingAddCount(), 0);
    assertTrue(_qm.isQuiet());
  }

  function test_BootstrapCrew_RevertsIfNotCaptain() external {
    _mockWearer(_stranger, _CAPTAIN_HAT, false);
    address[] memory _c = new address[](1);
    _c[0] = _alice;
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    vm.prank(_stranger);
    _qm.bootstrapCrew(_c);
  }

  function test_BootstrapCrew_RevertsIfMutinyActive() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    vm.prank(_mutinyClone);
    _qm.setMutinyActive(true);

    address[] memory _c = new address[](1);
    _c[0] = _alice;
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_MutinyActive.selector));
    vm.prank(_captain);
    _qm.bootstrapCrew(_c);
  }

  function test_BootstrapCrew_RevertsIfBootstrapRequiresEmptyCrew() external {
    _seedCrew(_alice);
    _mockCrewCapacity(1, _CREW_MAX);

    address[] memory _c = new address[](1);
    _c[0] = _bob;

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_BootstrapRequiresEmptyCrew.selector));
    vm.prank(_captain);
    _qm.bootstrapCrew(_c);
  }

  function test_BootstrapCrew_RevertsIfEmptyCandidates() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockCrewCapacity(0, _CREW_MAX);
    address[] memory _c = new address[](0);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_BootstrapEmpty.selector));
    vm.prank(_captain);
    _qm.bootstrapCrew(_c);
  }

  function test_BootstrapCrew_RevertsIfSameCandidateListedTwice() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    // Models the second-loop `_validateAddCandidate` path after a duplicate would have minted once on-chain.
    _mockWearer(_alice, _CREW_HAT, true);
    _mockCrewCapacity(0, _CREW_MAX);

    address[] memory _c = new address[](2);
    _c[0] = _alice;
    _c[1] = _alice;

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _alice));
    vm.prank(_captain);
    _qm.bootstrapCrew(_c);
  }

  function test_BootstrapCrew_RevertsIfMoreCandidatesThanMaxSupply() external {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockCrewCapacity(0, 3);

    address[] memory _c = new address[](4);
    _c[0] = makeAddr('b0');
    _c[1] = makeAddr('b1');
    _c[2] = makeAddr('b2');
    _c[3] = makeAddr('b3');
    _mockWearer(_c[0], _CAPTAIN_HAT, false);
    _mockWearer(_c[1], _CAPTAIN_HAT, false);
    _mockWearer(_c[2], _CAPTAIN_HAT, false);
    _mockWearer(_c[3], _CAPTAIN_HAT, false);
    _mockWearer(_c[0], _CREW_HAT, false);
    _mockWearer(_c[1], _CREW_HAT, false);
    _mockWearer(_c[2], _CREW_HAT, false);
    _mockWearer(_c[3], _CREW_HAT, false);

    vm.expectRevert(IQuartermaster.Quartermaster_CrewFull.selector);
    vm.prank(_captain);
    _qm.bootstrapCrew(_c);
  }
}

contract UnitQuartermasterParameterSetters is UnitQuartermasterBase {
  function test_SetCrewChangeDelay_HappyPathEmitsAndUpdates() external {
    _mockWearer(_treasuryClone, _TREASURY_AUTHORITY_ROLE_HAT, true);

    vm.expectEmit(false, false, false, true, address(_qm));
    emit IQuartermaster.CrewChangeDelayUpdated(CREW_CHANGE_DELAY, 14 days);
    vm.prank(_treasuryClone);
    _qm.setCrewChangeDelay(14 days);

    assertEq(_qm.crewChangeDelay(), 14 days);
  }

  function test_SetCrewChangeDelay_RevertsIfNotTreasuryAuthority() external {
    _mockWearer(_stranger, _TREASURY_AUTHORITY_ROLE_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _TREASURY_AUTHORITY_ROLE_HAT, _stranger)
    );
    _qm.setCrewChangeDelay(14 days);
  }

  function test_SetCrewChangeDelay_RevertsOutOfRange() external {
    _mockWearer(_treasuryClone, _TREASURY_AUTHORITY_ROLE_HAT, true);
    vm.prank(_treasuryClone);
    vm.expectRevert(abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, 0, 60, 60 days));
    _qm.setCrewChangeDelay(0);
  }
}

contract UnitQuartermasterEligibility is UnitQuartermasterBase {
  function test_GetWearerStatus_DefaultsIneligibleTrueStanding() external view {
    (bool _eligible, bool _standing) = _qm.getWearerStatus(_alice, _CREW_HAT);
    assertFalse(_eligible);
    assertTrue(_standing);
  }

  function test_GetWearerStatus_ReflectsMintRevokeCycle() external {
    _seedCrew(_alice);
    (bool _eligible, bool _standing) = _qm.getWearerStatus(_alice, _CREW_HAT);
    assertTrue(_eligible);
    assertTrue(_standing);

    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);

    vm.warp(_qm.pendingCrewRemoveAt(_alice));
    _mockWearer(_alice, _CREW_HAT, true);
    _mockCheckHatWearerStatus(_CREW_HAT, _alice, true);
    _qm.executeRemoveCrew(_alice);

    (bool _eligibleAfter,) = _qm.getWearerStatus(_alice, _CREW_HAT);
    assertFalse(_eligibleAfter);
  }
}

contract UnitQuartermasterPendingViews is UnitQuartermasterBase {
  address internal _carol = makeAddr('carol');

  function test_PendingSets_TwoAddsOneRemove_CancelAndExecute() external {
    _seedCrew(_alice);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_bob, _CAPTAIN_HAT, false);
    _mockWearer(_bob, _CREW_HAT, false);
    _mockWearer(_carol, _CAPTAIN_HAT, false);
    _mockWearer(_carol, _CREW_HAT, false);
    _mockCrewCapacity(1, _CREW_MAX);

    vm.prank(_captain);
    _qm.requestAddCrew(_bob);
    vm.prank(_captain);
    _qm.requestAddCrew(_carol);

    _mockWearer(_alice, _CREW_HAT, true);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);

    assertEq(_qm.pendingAddCount(), 2);
    assertEq(_qm.pendingRemoveCount(), 1);
    assertFalse(_qm.isQuiet());

    (address[] memory _adds, uint256[] memory _addEtas) = _qm.pendingAdds();
    assertEq(_adds.length, 2);
    assertEq(_addEtas.length, 2);
    (address _add0, uint256 _eta0) = _qm.pendingAddAt(0);
    (address _add1, uint256 _eta1) = _qm.pendingAddAt(1);
    assertEq(_adds[0], _add0);
    assertEq(_adds[1], _add1);
    assertEq(_addEtas[0], _eta0);
    assertEq(_addEtas[1], _eta1);

    (address[] memory _rems, uint256[] memory _remEtas) = _qm.pendingRemoves();
    assertEq(_rems.length, 1);
    assertEq(_rems[0], _alice);
    (address _rem0, uint256 _remEta0) = _qm.pendingRemoveAt(0);
    assertEq(_rem0, _alice);
    assertEq(_remEtas[0], _remEta0);

    vm.prank(_captain);
    _qm.cancelAddCrew(_bob);
    assertEq(_qm.pendingAddCount(), 1);
    (address[] memory _addsAfterCancel,) = _qm.pendingAdds();
    assertEq(_addsAfterCancel.length, 1);
    assertEq(_addsAfterCancel[0], _carol);

    vm.warp(_qm.pendingCrewAddAt(_carol));
    _mockWearer(_carol, _CREW_HAT, false);
    _mockMintHat(_CREW_HAT, _carol, true);
    _qm.executeAddCrew(_carol);

    assertEq(_qm.pendingAddCount(), 0);
    assertEq(_qm.pendingRemoveCount(), 1);
    assertTrue(_qm.crewEligible(_carol));
    assertFalse(_qm.isQuiet());
  }

  function test_RequestRemoveCrew_RerequestOverwritesEtaWithoutChangingCount() external {
    _seedCrew(_alice);
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CREW_HAT, true);

    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);
    uint256 _firstEta = _qm.pendingCrewRemoveAt(_alice);
    assertEq(_qm.pendingRemoveCount(), 1);

    vm.warp(block.timestamp + 1 hours);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_alice);

    assertEq(_qm.pendingRemoveCount(), 1);
    assertGt(_qm.pendingCrewRemoveAt(_alice), _firstEta);
    (address[] memory _rems,) = _qm.pendingRemoves();
    assertEq(_rems.length, 1);
    assertEq(_rems[0], _alice);
  }

  function test_PendingAddAt_RevertsOutOfBounds() external {
    vm.expectRevert();
    _qm.pendingAddAt(0);
  }

  function test_PendingRemoveAt_RevertsOutOfBounds() external {
    vm.expectRevert();
    _qm.pendingRemoveAt(0);
  }
}

contract UnitQuartermasterCrewOffboard is UnitQuartermasterBase {
  address internal _carol = makeAddr('carol');

  function _stageOffboardElectorate() internal {
    _mockWearer(_alice, _CREW_HAT, true);
    _mockWearer(_bob, _CREW_HAT, true);
    _mockWearer(_carol, _CREW_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_bob, _CAPTAIN_HAT, false);
    _mockWearer(_carol, _CAPTAIN_HAT, false);
    _mockCrewCapacity(5, _CREW_MAX);
  }

  function _passOffboardOnCarol() internal returns (uint256 _id) {
    _stageOffboardElectorate();
    vm.prank(_alice);
    _id = _qm.proposeOffboard(_carol);
    vm.prank(_alice);
    _qm.crewOffboardVote(_id, true);
    vm.prank(_bob);
    _qm.crewOffboardVote(_id, true);
  }

  function test_ProposeOffboard_HappyPath_FreezesRoster() external {
    _stageOffboardElectorate();
    uint256 _deadline = block.timestamp + PROPOSAL_EXPIRY;

    vm.expectEmit(true, true, true, true, address(_qm));
    emit IQuartermaster.CrewOffboardProposed(1, _alice, _carol, _deadline, 5);
    vm.prank(_alice);
    uint256 _id = _qm.proposeOffboard(_carol);

    assertEq(_id, 1);
    assertEq(_qm.activeCrewOffboardId(), 1);
    assertFalse(_qm.isQuiet());

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_stranger, _CAPTAIN_HAT, false);
    _mockWearer(_stranger, _CREW_HAT, false);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_CrewOffboardActive.selector);
    _qm.requestAddCrew(_stranger);
  }

  function test_ProposeOffboard_RevertsOnSelf() external {
    _stageOffboardElectorate();
    vm.prank(_alice);
    vm.expectRevert(IQuartermaster.Quartermaster_SelfOffboard.selector);
    _qm.proposeOffboard(_alice);
  }

  function test_ProposeOffboard_RevertsIfMutinyActive() external {
    _stageOffboardElectorate();
    _mockWearer(_mutinyClone, _MUTINY_ROLE_HAT, true);
    vm.prank(_mutinyClone);
    _qm.setMutinyActive(true);
    vm.prank(_alice);
    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.proposeOffboard(_carol);
  }

  function test_ProposeOffboard_RevertsIfPendingCaptainRemove() external {
    _stageOffboardElectorate();
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_carol);
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_PendingCaptainRemove.selector, _carol));
    _qm.proposeOffboard(_carol);
  }

  function test_ProposeOffboard_RevertsIfAnotherLive() external {
    _stageOffboardElectorate();
    vm.prank(_alice);
    _qm.proposeOffboard(_carol);
    vm.prank(_bob);
    vm.expectRevert(IQuartermaster.Quartermaster_CrewOffboardActive.selector);
    _qm.proposeOffboard(_alice);
  }

  function test_ExecuteOffboard_HappyPath_AtQuorumYeasAhead() external {
    uint256 _id = _passOffboardOnCarol();
    _mockWearer(_carol, _CREW_HAT, true);
    _mockCheckHatWearerStatus(_CREW_HAT, _carol, true);

    vm.expectEmit(true, true, false, true, address(_qm));
    emit IQuartermaster.CrewOffboardExecuted(_id, _carol);
    _qm.executeOffboard(_id);

    assertEq(_qm.activeCrewOffboardId(), 0);
    assertTrue(_qm.isQuiet());
    (bool _eligible,) = _qm.getWearerStatus(_carol, _CREW_HAT);
    assertFalse(_eligible);
  }

  function test_ExecuteOffboard_RevertsIfTurnoutShort() external {
    _stageOffboardElectorate();
    vm.prank(_alice);
    uint256 _id = _qm.proposeOffboard(_carol);
    vm.prank(_alice);
    _qm.crewOffboardVote(_id, true);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_OffboardNotPassed.selector, 1, 0, 5));
    _qm.executeOffboard(_id);
  }

  function test_ExecuteOffboard_RevertsIfYeasNotAhead() external {
    _stageOffboardElectorate();
    vm.prank(_alice);
    uint256 _id = _qm.proposeOffboard(_carol);
    vm.prank(_alice);
    _qm.crewOffboardVote(_id, true);
    vm.prank(_bob);
    _qm.crewOffboardVote(_id, false);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_OffboardNotPassed.selector, 1, 1, 5));
    _qm.executeOffboard(_id);
  }

  function test_ExpireOffboard_HappyPath_ThenNewVote() external {
    _stageOffboardElectorate();
    vm.prank(_alice);
    uint256 _id = _qm.proposeOffboard(_carol);
    vm.warp(block.timestamp + PROPOSAL_EXPIRY);

    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewOffboardExpired(_id);
    _qm.expireOffboard(_id);
    assertEq(_qm.activeCrewOffboardId(), 0);

    vm.prank(_bob);
    uint256 _id2 = _qm.proposeOffboard(_alice);
    assertEq(_id2, 2);
  }

  function test_CrewOffboardVote_RevertsOnDoubleVote() external {
    uint256 _id = _passOffboardOnCarol();
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyVoted.selector, _alice));
    _qm.crewOffboardVote(_id, true);
  }

  function test_SetCrewOffboardParams_HappyPath() external {
    _mockWearer(_treasuryClone, _TREASURY_AUTHORITY_ROLE_HAT, true);
    vm.prank(_treasuryClone);
    _qm.setCrewOffboardExpiry(14 days);
    vm.prank(_treasuryClone);
    _qm.setCrewOffboardQuorumBps(4000);
    assertEq(_qm.crewOffboardExpiry(), 14 days);
    assertEq(_qm.crewOffboardQuorumBps(), 4000);
  }
}

