// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {SquadAdmin} from 'contracts/squad/SquadAdmin.sol';
import {SquadAdminExt} from 'contracts/squad/SquadAdminExt.sol';
import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';
import {ISquadAdminBase} from 'interfaces/squad/ISquadAdminBase.sol';
import {ISquadAdminExt} from 'interfaces/squad/ISquadAdminExt.sol';

/**
 * @title UnitSquadAdminBase
 * @author Pacto
 * @notice Shared fixture: `SquadAdmin` master plus an EIP-1167 clone (`Clones.clone`). Clone receives
 *         `initialize` in `setUp`; hat ids live on `SquadAdmin`, executor mapping on `SquadAdminBase`.
 */
abstract contract UnitSquadAdminBase is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.squadadmin.HATS'))));

  uint256 internal constant _CAPTAIN_HAT = 100;
  uint256 internal constant _SQUAD_ADMIN_HAT = 200;

  bytes32 internal constant _ROLE_APP = keccak256('pacto.squadadmin.role.app');
  bytes32 internal constant _ROLE_OTHER = keccak256('pacto.squadadmin.role.other');
  // forge-lint: disable-next-line(unsafe-typecast) — ASCII labels fit in `bytes32` (Solidity left-padding).
  bytes32 internal constant _ROLE_FULL = bytes32('FULL');
  // forge-lint: disable-next-line(unsafe-typecast) — ASCII labels fit in `bytes32` (Solidity left-padding).
  bytes32 internal constant _ROLE_PAUSE = bytes32('PAUSE');

  SquadAdmin internal _impl;
  address internal _clone;
  SquadAdmin internal _admin;

  address internal _captain = makeAddr('captain');
  address internal _alice = makeAddr('alice');
  address internal _bob = makeAddr('bob');
  address internal _stranger = makeAddr('stranger');

  function setUp() public {
    vm.etch(_HATS_ADDRESS, hex'00');
    _impl = new SquadAdmin(IHats(_HATS_ADDRESS));

    ISquadAdmin.InitParams memory _p =
      ISquadAdmin.InitParams({captainHatId: _CAPTAIN_HAT, squadAdminHatId: _SQUAD_ADMIN_HAT});
    _clone = Clones.clone(address(_impl));
    SquadAdmin(payable(_clone)).initialize(_p);
    _admin = SquadAdmin(payable(_clone));

    _mockCaptain(_captain, true);
    vm.startPrank(_captain);
    _admin.createRole(_ROLE_APP);
    _admin.createRole(_ROLE_OTHER);
    vm.stopPrank();
  }

  function _mockCaptain(address _account, bool _wearsCaptain) internal {
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeWithSelector(IHats.isWearerOfHat.selector, _account, _CAPTAIN_HAT),
      abi.encode(_wearsCaptain)
    );
  }
}

contract UnitSquadAdminInit is UnitSquadAdminBase {
  function test_Constructor_DisablesInitializersOnMaster() external {
    ISquadAdmin.InitParams memory _p =
      ISquadAdmin.InitParams({captainHatId: _CAPTAIN_HAT, squadAdminHatId: _SQUAD_ADMIN_HAT});
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _impl.initialize(_p);
  }

  function test_Initialize_SeedsHatIdsOnClone() external view {
    assertEq(_admin.captainHatId(), _CAPTAIN_HAT);
    assertEq(_admin.squadAdminHatId(), _SQUAD_ADMIN_HAT);
  }

  function test_Clone_BeforeInitialize_HatIdsZero() external {
    address _rawClone = Clones.clone(address(_impl));
    SquadAdmin _fresh = SquadAdmin(payable(_rawClone));
    assertEq(_fresh.captainHatId(), 0);
    assertEq(_fresh.squadAdminHatId(), 0);
  }

  function test_Initialize_RevertsOnDoubleInit() external {
    ISquadAdmin.InitParams memory _p = ISquadAdmin.InitParams({captainHatId: 1, squadAdminHatId: 2});
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _admin.initialize(_p);
  }

  function test_InitializeUint256_SeedsCaptainHatOnly() external {
    uint256 _cap = 501;
    address _rawClone = Clones.clone(address(_impl));
    SquadAdmin _g = SquadAdmin(payable(_rawClone));
    _g.initialize(_cap);

    assertEq(_g.captainHatId(), _cap);
    assertEq(_g.squadAdminHatId(), 0);
  }

  function test_InitializeUint256_RevertsOnSecondInit() external {
    address _rawClone = Clones.clone(address(_impl));
    SquadAdmin _g = SquadAdmin(payable(_rawClone));
    _g.initialize(uint256(42));

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _g.initialize(uint256(99));
  }

  function test_InitializeUint256_ThenInitParamsReverts() external {
    address _rawClone = Clones.clone(address(_impl));
    SquadAdmin _g = SquadAdmin(payable(_rawClone));
    _g.initialize(uint256(1));

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _g.initialize(ISquadAdmin.InitParams({captainHatId: 9, squadAdminHatId: 9}));
  }

  function test_CaptainGate_UsesHatIdFromInitialize() external {
    uint256 _customCaptainHat = 333;
    uint256 _customSquadHat = 444;
    address _rawClone = Clones.clone(address(_impl));
    SquadAdmin _g = SquadAdmin(payable(_rawClone));
    _g.initialize(ISquadAdmin.InitParams({captainHatId: _customCaptainHat, squadAdminHatId: _customSquadHat}));

    assertEq(_g.captainHatId(), _customCaptainHat);
    assertEq(_g.squadAdminHatId(), _customSquadHat);

    vm.mockCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _captain, _customCaptainHat), abi.encode(true)
    );

    vm.startPrank(_captain);
    _g.createRole(_ROLE_APP);
    _g.enableExecutor(_alice, _ROLE_APP);
    vm.stopPrank();
    assertTrue(_g.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_HasExecutorRole_FalseForUnknown() external view {
    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_APP));
    assertFalse(_admin.isExecutorFullPermission(_alice));
    assertFalse(_admin.isExecutorPaused(_alice));
  }

  function test_PostInitialize_UpdatesHatIds() external {
    _mockCaptain(_captain, true);
    uint256 _newCap = 777;
    uint256 _newSquad = 888;
    vm.prank(_captain);
    _admin.postInitialize(ISquadAdmin.InitParams({captainHatId: _newCap, squadAdminHatId: _newSquad}));
    assertEq(_admin.captainHatId(), _newCap);
    assertEq(_admin.squadAdminHatId(), _newSquad);
  }

  function test_PostInitialize_RevertsIfNotCaptain() external {
    _mockCaptain(_stranger, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _admin.postInitialize(ISquadAdmin.InitParams({captainHatId: 1, squadAdminHatId: 2}));
  }
}

contract UnitSquadAdminExecutorRoster is UnitSquadAdminBase {
  function test_EnableExecutor_HappyPath() external {
    _mockCaptain(_captain, true);

    vm.expectEmit(true, true, false, false, address(_admin));
    emit ISquadAdminBase.ExecutorEnabled(_alice, _ROLE_APP);

    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_APP);

    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_APP));
    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_OTHER));
    assertFalse(_admin.isExecutorFullPermission(_alice));
  }

  function test_EnableExecutor_RevertsIfNotCaptain() external {
    _mockCaptain(_stranger, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _admin.enableExecutor(_alice, _ROLE_APP);
  }

  function test_EnableFullPermission_RevertsIfNotCaptain() external {
    _mockCaptain(_stranger, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _admin.enableFullPermission(_alice, true);
  }

  function test_PauseExecutor_RevertsIfNotCaptain() external {
    _mockCaptain(_stranger, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _admin.pauseExecutor(_alice, true);
  }

  function test_EnableExecutor_RevertsOnZeroAddress() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    vm.expectRevert(ISquadAdminBase.SquadAdminBase_ZeroAddress.selector);
    _admin.enableExecutor(address(0), _ROLE_APP);
  }

  function test_EnableExecutor_AllowsRepeatEnable_SameRole() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_APP);
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_APP);
    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_EnableExecutor_SecondRoleSameAddress() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_APP);
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_OTHER);

    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_APP));
    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_OTHER));
  }

  function test_DisableExecutor_HappyPath() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_APP);

    vm.expectEmit(true, true, false, false, address(_admin));
    emit ISquadAdminBase.ExecutorDisabled(_alice, _ROLE_APP);

    vm.prank(_captain);
    _admin.disableExecutor(_alice, _ROLE_APP);

    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_DisableExecutor_RevertsIfNotCaptain() external {
    _mockCaptain(_stranger, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _admin.disableExecutor(_alice, _ROLE_APP);
  }

  function test_DisableExecutor_AllowsWhenRoleWasNeverEnabled() external {
    _mockCaptain(_captain, true);
    vm.expectEmit(true, true, false, false, address(_admin));
    emit ISquadAdminBase.ExecutorDisabled(_alice, _ROLE_APP);
    vm.prank(_captain);
    _admin.disableExecutor(_alice, _ROLE_APP);
    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_EnableThenDisable_IsolatesPerExecutorAndRole() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_APP);
    vm.prank(_captain);
    _admin.enableExecutor(_bob, _ROLE_APP);

    vm.prank(_captain);
    _admin.disableExecutor(_alice, _ROLE_APP);

    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_APP));
    assertTrue(_admin.hasExecutorRole(_bob, _ROLE_APP));
  }

  function test_EnableFullPermission_EmitsAndGrantsEveryRole() external {
    _mockCaptain(_captain, true);
    vm.expectEmit(true, false, false, true, address(_admin));
    emit ISquadAdminBase.FullPermissionEnabled(_alice, true);
    vm.prank(_captain);
    _admin.enableFullPermission(_alice, true);

    assertTrue(_admin.isExecutorFullPermission(_alice));
    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_APP));
    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_OTHER));
  }

  function test_EnableFullPermission_False_ClearsFullSlot() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableFullPermission(_alice, true);
    vm.prank(_captain);
    _admin.enableFullPermission(_alice, false);

    assertFalse(_admin.isExecutorFullPermission(_alice));
    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_EnableExecutor_WithFullRoleKey_MatchesFullPermissionSlot() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_FULL);
    assertTrue(_admin.isExecutorFullPermission(_alice));
    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_PauseExecutorBlocksHasExecutorRole_KeepsFullFlagInStorage() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableFullPermission(_alice, true);
    vm.expectEmit(true, false, false, true, address(_admin));
    emit ISquadAdminBase.ExecutorPaused(_alice, true);
    vm.prank(_captain);
    _admin.pauseExecutor(_alice, true);

    assertTrue(_admin.isExecutorPaused(_alice));
    assertFalse(_admin.isExecutorFullPermission(_alice));
    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_APP));
    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_FULL));
  }

  function test_PauseExecutorFalse_RestoresRoles() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_APP);
    vm.prank(_captain);
    _admin.pauseExecutor(_alice, true);

    assertTrue(_admin.isExecutorPaused(_alice));
    assertFalse(_admin.hasExecutorRole(_alice, _ROLE_APP));

    vm.prank(_captain);
    _admin.pauseExecutor(_alice, false);

    assertFalse(_admin.isExecutorPaused(_alice));
    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_DisableExecutor_OnPauseSlot_ClearsPause() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.pauseExecutor(_alice, true);
    assertTrue(_admin.isExecutorPaused(_alice));

    vm.prank(_captain);
    _admin.disableExecutor(_alice, _ROLE_PAUSE);

    assertFalse(_admin.isExecutorPaused(_alice));
  }
}

contract UnitSquadAdminExt is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.squadadmin.ext.HATS'))));

  bytes32 internal constant _ROLE_APP = keccak256('pacto.squadadmin.ext.role');

  SquadAdminExt internal _admin;
  address internal _moloch = makeAddr('moloch');
  address internal _alice = makeAddr('alice');
  address internal _captain = makeAddr('extCaptain');
  address internal _stranger = makeAddr('stranger');

  function setUp() external {
    vm.etch(_HATS_ADDRESS, hex'00');
    SquadAdminExt _impl = new SquadAdminExt(IHats(_HATS_ADDRESS));
    address _clone = Clones.clone(address(_impl));
    SquadAdminExt(payable(_clone)).initialize(_moloch);
    _admin = SquadAdminExt(payable(_clone));

    vm.prank(_moloch);
    _admin.createRole(_ROLE_APP);
  }

  function test_Ext_RevertsHatStyleInitializers() external {
    SquadAdminExt _freshImpl = new SquadAdminExt(IHats(_HATS_ADDRESS));
    address _raw = Clones.clone(address(_freshImpl));
    SquadAdminExt _g = SquadAdminExt(payable(_raw));

    vm.expectRevert(ISquadAdminExt.SquadAdminExt_UseAddressInitializer.selector);
    _g.initialize(ISquadAdmin.InitParams({captainHatId: 1, squadAdminHatId: 2}));

    vm.expectRevert(ISquadAdminExt.SquadAdminExt_UseAddressInitializer.selector);
    _g.initialize(uint256(1));
  }

  function test_Ext_Initialize_RevertsZeroOwner() external {
    SquadAdminExt _freshImpl = new SquadAdminExt(IHats(_HATS_ADDRESS));
    address _raw = Clones.clone(address(_freshImpl));
    SquadAdminExt _g = SquadAdminExt(payable(_raw));
    vm.expectRevert(ISquadAdminBase.SquadAdminBase_ZeroAddress.selector);
    _g.initialize(address(0));
  }

  function test_Ext_OwnerGate_EnableExecutor() external {
    vm.prank(_moloch);
    _admin.enableExecutor(_alice, _ROLE_APP);
    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_Ext_NotOwner_Reverts() external {
    vm.prank(_stranger);
    vm.expectRevert(ISquadAdminExt.SquadAdminExt_NotAllowed.selector);
    _admin.enableExecutor(_alice, _ROLE_APP);
  }

  function test_Ext_PostInitialize_ClearsOwnerAndSetsHats() external {
    uint256 _cap = 555;
    uint256 _squad = 666;
    vm.prank(_moloch);
    _admin.postInitialize(ISquadAdmin.InitParams({captainHatId: _cap, squadAdminHatId: _squad}));
    assertEq(_admin.owner(), address(0));
    assertEq(_admin.captainHatId(), _cap);
    assertEq(_admin.squadAdminHatId(), _squad);
  }

  function test_Ext_PostInitialize_RevertsIfNotOwner() external {
    vm.prank(_stranger);
    vm.expectRevert(ISquadAdminExt.SquadAdminExt_NotAllowed.selector);
    _admin.postInitialize(ISquadAdmin.InitParams({captainHatId: 1, squadAdminHatId: 2}));
  }

  function test_Ext_AfterPostInitialize_CaptainHatGateApplies() external {
    uint256 _cap = 555;
    vm.prank(_moloch);
    _admin.postInitialize(ISquadAdmin.InitParams({captainHatId: _cap, squadAdminHatId: 666}));
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _captain, _cap), abi.encode(true));
    vm.prank(_captain);
    _admin.enableExecutor(_alice, _ROLE_APP);
    assertTrue(_admin.hasExecutorRole(_alice, _ROLE_APP));
  }

  function test_Ext_AfterPostInitialize_MolochCannotManageRosterWithoutHat() external {
    uint256 _cap = 555;
    vm.prank(_moloch);
    _admin.postInitialize(ISquadAdmin.InitParams({captainHatId: _cap, squadAdminHatId: 666}));
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _moloch, _cap), abi.encode(false));
    vm.prank(_moloch);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _cap, _moloch));
    _admin.enableExecutor(_alice, _ROLE_APP);
  }

  function test_Ext_SecondInitParamsInitializer_RevertsAfterAddressInit() external {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _admin.initialize(ISquadAdmin.InitParams({captainHatId: 1, squadAdminHatId: 2}));
  }

  function test_Ext_SecondInitializeUint_RevertsAfterAddressInit() external {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _admin.initialize(uint256(1));
  }
}
