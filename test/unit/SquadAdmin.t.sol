// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SquadAdmin} from 'contracts/SquadAdmin.sol';
import {SquadAdminImpl} from 'contracts/SquadAdminImpl.sol';
import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {ISquadAdmin} from 'interfaces/ISquadAdmin.sol';

/**
 * @title UnitSquadAdminBase
 * @author Pacto
 * @notice Shared fixture for SquadAdmin tests. Deploys a fresh `SquadAdminImpl` master and an
 *         `ERC1967Proxy` (SquadAdmin) wired to it. All Hats calls are stubbed via `vm.mockCall`.
 *         The UUPS upgrade path is exercised against a *second, independently-deployed*
 *         `SquadAdminImpl` — the real production contract — so no mock helper contracts are
 *         required (see `.cursor/rules/solidity-unit-tests.mdc`).
 */
abstract contract UnitSquadAdminBase is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.squadadmin.HATS'))));

  uint256 internal constant _CAPTAIN_HAT = 100;
  uint256 internal constant _SQUAD_ADMIN_HAT = 200;

  SquadAdminImpl internal _impl;
  SquadAdmin internal _proxy;
  SquadAdminImpl internal _admin; // impl-typed handle against the proxy address

  address internal _captain = makeAddr('captain');
  address internal _alice = makeAddr('alice');
  address internal _bob = makeAddr('bob');
  address internal _stranger = makeAddr('stranger');

  function setUp() public virtual {
    vm.etch(_HATS_ADDRESS, hex'00');
    _impl = new SquadAdminImpl(IHats(_HATS_ADDRESS));

    SquadAdminImpl.InitParams memory _p =
      SquadAdminImpl.InitParams({captainHatId: _CAPTAIN_HAT, squadAdminHatId: _SQUAD_ADMIN_HAT});
    bytes memory _initData = abi.encodeCall(SquadAdminImpl.initialize, (_p));

    _proxy = new SquadAdmin(address(_impl), _initData);
    _admin = SquadAdminImpl(payable(address(_proxy)));
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
    SquadAdminImpl.InitParams memory _p =
      SquadAdminImpl.InitParams({captainHatId: _CAPTAIN_HAT, squadAdminHatId: _SQUAD_ADMIN_HAT});
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _impl.initialize(_p);
  }

  function test_Initialize_SeedsStorageBehindProxy() external view {
    assertEq(_admin.CAPTAIN_HAT_ID(), _CAPTAIN_HAT);
    assertEq(_admin.SQUAD_ADMIN_HAT_ID(), _SQUAD_ADMIN_HAT);
    assertTrue(_admin.isQuiet());
  }

  function test_Initialize_RevertsOnDoubleInit() external {
    SquadAdminImpl.InitParams memory _p = SquadAdminImpl.InitParams({captainHatId: 1, squadAdminHatId: 2});
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _admin.initialize(_p);
  }

  function test_IsExecutor_FalseForUnknown() external view {
    assertFalse(_admin.isExecutor(_alice));
  }

  function test_ErcNamespacedSlot_MatchesSpec() external view {
    bytes32 _expected = keccak256(abi.encode(uint256(keccak256('pacto.squadadmin.v1')) - 1)) & ~bytes32(uint256(0xff));
    uint256 _storedCaptain = uint256(vm.load(address(_proxy), _expected));
    assertEq(_storedCaptain, _CAPTAIN_HAT);
  }
}

contract UnitSquadAdminExecutorRoster is UnitSquadAdminBase {
  function test_EnableExecutor_HappyPath() external {
    _mockCaptain(_captain, true);

    vm.expectEmit(true, false, false, true, address(_admin));
    emit ISquadAdmin.ExecutorEnabled(_alice);

    vm.prank(_captain);
    _admin.enableExecutor(_alice);

    assertTrue(_admin.isExecutor(_alice));
  }

  function test_EnableExecutor_RevertsIfNotCaptain() external {
    _mockCaptain(_stranger, false);
    vm.prank(_stranger);
    vm.expectRevert(ISquadAdmin.SquadAdmin_NotCaptain.selector);
    _admin.enableExecutor(_alice);
  }

  function test_EnableExecutor_RevertsOnZeroAddress() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    vm.expectRevert(ISquadAdmin.SquadAdmin_ZeroAddress.selector);
    _admin.enableExecutor(address(0));
  }

  function test_EnableExecutor_RevertsIfAlreadyEnabled() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice);

    vm.prank(_captain);
    vm.expectRevert(ISquadAdmin.SquadAdmin_AlreadyExecutor.selector);
    _admin.enableExecutor(_alice);
  }

  function test_DisableExecutor_HappyPath() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice);

    vm.expectEmit(true, false, false, true, address(_admin));
    emit ISquadAdmin.ExecutorDisabled(_alice);

    vm.prank(_captain);
    _admin.disableExecutor(_alice);

    assertFalse(_admin.isExecutor(_alice));
  }

  function test_DisableExecutor_RevertsIfNotCaptain() external {
    _mockCaptain(_stranger, false);
    vm.prank(_stranger);
    vm.expectRevert(ISquadAdmin.SquadAdmin_NotCaptain.selector);
    _admin.disableExecutor(_alice);
  }

  function test_DisableExecutor_RevertsIfNotEnabled() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    vm.expectRevert(ISquadAdmin.SquadAdmin_NotExecutor.selector);
    _admin.disableExecutor(_alice);
  }

  function test_EnableThenDisableRoundtrip_IsolatesPerExecutor() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice);
    vm.prank(_captain);
    _admin.enableExecutor(_bob);

    vm.prank(_captain);
    _admin.disableExecutor(_alice);

    assertFalse(_admin.isExecutor(_alice));
    assertTrue(_admin.isExecutor(_bob));
  }
}

contract UnitSquadAdminUpgrade is UnitSquadAdminBase {
  /// @notice ERC-1967 implementation-slot constant (per EIP-1967).
  bytes32 internal constant _ERC1967_IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  /// @notice Independently-deployed production `SquadAdminImpl` used as the upgrade target.
  SquadAdminImpl internal _nextImpl;

  function setUp() public override {
    super.setUp();
    _nextImpl = new SquadAdminImpl(IHats(_HATS_ADDRESS));
  }

  function test_UpgradeToAndCall_HappyPath_SwapsImplementationSlot_AndPreservesStorage() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    _admin.enableExecutor(_alice);

    assertEq(_readImplementationSlot(), address(_impl));

    vm.prank(_captain);
    _admin.upgradeToAndCall(address(_nextImpl), '');

    assertEq(_readImplementationSlot(), address(_nextImpl));
    assertEq(_admin.CAPTAIN_HAT_ID(), _CAPTAIN_HAT);
    assertEq(_admin.SQUAD_ADMIN_HAT_ID(), _SQUAD_ADMIN_HAT);
    assertTrue(_admin.isExecutor(_alice));
  }

  function test_UpgradeToAndCall_RevertsIfNotCaptain() external {
    _mockCaptain(_stranger, false);
    vm.prank(_stranger);
    vm.expectRevert(ISquadAdmin.SquadAdmin_NotCaptain.selector);
    _admin.upgradeToAndCall(address(_nextImpl), '');
  }

  function test_UpgradeToAndCall_RevertsOnZeroImplementation() external {
    _mockCaptain(_captain, true);
    vm.prank(_captain);
    vm.expectRevert(ISquadAdmin.SquadAdmin_ZeroAddress.selector);
    _admin.upgradeToAndCall(address(0), '');
  }

  function _readImplementationSlot() internal view returns (address _implementation) {
    _implementation = address(uint160(uint256(vm.load(address(_proxy), _ERC1967_IMPLEMENTATION_SLOT))));
  }
}
