// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {WarGameRegistry} from 'contracts/factory/WarGameRegistry.sol';
import {Test} from 'forge-std/Test.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {IWarGameRegistry} from 'interfaces/factory/IWarGameRegistry.sol';

/**
 * @title UnitWarGameRegistryBase
 * @author Pacto
 * @notice Shared fixture for `WarGameRegistry` unit tests.
 */
abstract contract UnitWarGameRegistryBase is Test {
  WarGameRegistry internal _registry;

  address internal _factory = makeAddr('factory');
  address internal _stranger = makeAddr('stranger');
  bytes32 internal constant _SQUAD_ID = keccak256('pacto.wargame.squad');

  function setUp() public virtual {
    _registry = new WarGameRegistry();
  }

  function _wire() internal {
    _registry.initialize(_factory);
  }

  function _sampleDeployment(uint256 _topHatId) internal returns (INavePirataRegistry.Deployment memory _d) {
    _d = INavePirataRegistry.Deployment({
      safe: makeAddr(string.concat('safe-', vm.toString(_topHatId))),
      quartermaster: makeAddr(string.concat('qm-', vm.toString(_topHatId))),
      mutinyModule: makeAddr(string.concat('mm-', vm.toString(_topHatId))),
      treasuryAuthority: makeAddr(string.concat('ta-', vm.toString(_topHatId))),
      squadAdminProxy: makeAddr(string.concat('sa-', vm.toString(_topHatId))),
      topHatId: _topHatId,
      captainHatId: _topHatId + 10,
      crewHatId: _topHatId + 11,
      squadAdminHatId: _topHatId + 12,
      mutinyRoleHatId: _topHatId + 13,
      quartermasterRoleHatId: _topHatId + 14,
      treasuryAuthorityRoleHatId: _topHatId + 15,
      deployedAt: uint64(block.timestamp),
      deployer: makeAddr(string.concat('deployer-', vm.toString(_topHatId)))
    });
  }
}

contract UnitWarGameRegistryConstruction is UnitWarGameRegistryBase {
  function test_Constructor_LeavesWiringUnset() external view {
    assertEq(_registry.factory(), address(0));
  }
}

contract UnitWarGameRegistryInitialize is UnitWarGameRegistryBase {
  function test_Initialize_HappyPath() external {
    _registry.initialize(_factory);
    assertEq(_registry.factory(), _factory);
  }

  function test_Initialize_RevertsOnZeroFactory() external {
    vm.expectRevert(IWarGameRegistry.WarGameRegistry_ZeroAddress.selector);
    _registry.initialize(address(0));
  }

  function test_Initialize_RevertsIfAlreadyWired() external {
    _registry.initialize(_factory);
    vm.expectRevert(IWarGameRegistry.WarGameRegistry_AlreadyWired.selector);
    _registry.initialize(makeAddr('other-factory'));
  }
}

contract UnitWarGameRegistryRegister is UnitWarGameRegistryBase {
  function setUp() public override {
    super.setUp();
    _wire();
  }

  function test_Register_HappyPath() external {
    INavePirataRegistry.Deployment memory _d = _sampleDeployment(1);

    vm.expectEmit(true, true, false, true, address(_registry));
    emit IWarGameRegistry.WarGameRegistered(_SQUAD_ID, 1, _d);

    vm.prank(_factory);
    _registry.register(_SQUAD_ID, _d);

    assertEq(_registry.activeTopHatId(_SQUAD_ID), 1);
    INavePirataRegistry.Deployment memory _active = _registry.active(_SQUAD_ID);
    assertEq(_active.safe, _d.safe);
    assertEq(_active.topHatId, 1);

    IWarGameRegistry.Record memory _record = _registry.record(1);
    assertEq(_record.squadId, _SQUAD_ID);
    assertEq(uint8(_record.status), uint8(IWarGameRegistry.Status.Active));
    assertEq(_record.deployment.deployer, _d.deployer);

    uint256[] memory _history = _registry.history(_SQUAD_ID);
    assertEq(_history.length, 1);
    assertEq(_history[0], 1);
  }

  function test_Register_RevertsIfNotFactory() external {
    INavePirataRegistry.Deployment memory _d = _sampleDeployment(1);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(IWarGameRegistry.WarGameRegistry_NotFactory.selector, _stranger));
    _registry.register(_SQUAD_ID, _d);
  }

  function test_Register_RevertsOnZeroSquadId() external {
    INavePirataRegistry.Deployment memory _d = _sampleDeployment(1);
    vm.prank(_factory);
    vm.expectRevert(IWarGameRegistry.WarGameRegistry_ZeroSquadId.selector);
    _registry.register(bytes32(0), _d);
  }

  function test_Register_RevertsOnDuplicateTopHat() external {
    INavePirataRegistry.Deployment memory _d = _sampleDeployment(7);
    vm.prank(_factory);
    _registry.register(_SQUAD_ID, _d);

    vm.prank(_factory);
    vm.expectRevert(abi.encodeWithSelector(IWarGameRegistry.WarGameRegistry_AlreadyRegistered.selector, uint256(7)));
    _registry.register(keccak256('other-squad'), _d);
  }

  function test_Register_AutoRetiresPreviousActive() external {
    INavePirataRegistry.Deployment memory _first = _sampleDeployment(1);
    INavePirataRegistry.Deployment memory _second = _sampleDeployment(2);

    vm.prank(_factory);
    _registry.register(_SQUAD_ID, _first);

    vm.expectEmit(true, true, false, true, address(_registry));
    emit IWarGameRegistry.WarGameRetired(_SQUAD_ID, 1);
    vm.expectEmit(true, true, false, true, address(_registry));
    emit IWarGameRegistry.WarGameRegistered(_SQUAD_ID, 2, _second);

    vm.prank(_factory);
    _registry.register(_SQUAD_ID, _second);

    assertEq(_registry.activeTopHatId(_SQUAD_ID), 2);
    assertEq(uint8(_registry.record(1).status), uint8(IWarGameRegistry.Status.Retired));
    assertEq(uint8(_registry.record(2).status), uint8(IWarGameRegistry.Status.Active));
    assertEq(_registry.active(_SQUAD_ID).topHatId, 2);

    uint256[] memory _history = _registry.history(_SQUAD_ID);
    assertEq(_history.length, 2);
    assertEq(_history[0], 1);
    assertEq(_history[1], 2);
  }
}

contract UnitWarGameRegistryRetire is UnitWarGameRegistryBase {
  function setUp() public override {
    super.setUp();
    _wire();
    vm.prank(_factory);
    _registry.register(_SQUAD_ID, _sampleDeployment(1));
  }

  function test_Retire_HappyPath() external {
    vm.expectEmit(true, true, false, true, address(_registry));
    emit IWarGameRegistry.WarGameRetired(_SQUAD_ID, 1);

    vm.prank(_factory);
    _registry.retire(_SQUAD_ID);

    assertEq(_registry.activeTopHatId(_SQUAD_ID), 0);
    assertEq(_registry.active(_SQUAD_ID).topHatId, 0);
    assertEq(uint8(_registry.record(1).status), uint8(IWarGameRegistry.Status.Retired));

    uint256[] memory _history = _registry.history(_SQUAD_ID);
    assertEq(_history.length, 1);
    assertEq(_history[0], 1);
  }

  function test_Retire_RevertsIfNotFactory() external {
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(IWarGameRegistry.WarGameRegistry_NotFactory.selector, _stranger));
    _registry.retire(_SQUAD_ID);
  }

  function test_Retire_RevertsIfNoActive() external {
    vm.prank(_factory);
    _registry.retire(_SQUAD_ID);

    vm.prank(_factory);
    vm.expectRevert(abi.encodeWithSelector(IWarGameRegistry.WarGameRegistry_NoActive.selector, _SQUAD_ID));
    _registry.retire(_SQUAD_ID);
  }

  function test_Retire_RevertsIfUnknownSquad() external {
    bytes32 _unknown = keccak256('unknown');
    vm.prank(_factory);
    vm.expectRevert(abi.encodeWithSelector(IWarGameRegistry.WarGameRegistry_NoActive.selector, _unknown));
    _registry.retire(_unknown);
  }
}
