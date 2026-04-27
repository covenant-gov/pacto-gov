// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';
import {Test} from 'forge-std/Test.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title UnitNavePirataRegistryBase
 * @author Pacto
 * @notice Shared fixture for `NavePirataRegistry` unit tests. Deploys a fresh registry owned by
 *         an admin EOA; factory/upgrader wiring is performed per-suite so wiring-gate tests can
 *         observe the pre-wired state.
 */
abstract contract UnitNavePirataRegistryBase is Test {
  NavePirataRegistry internal _registry;

  address internal _admin = makeAddr('admin');
  address internal _factory = makeAddr('factory');
  address internal _upgrader = makeAddr('upgrader');
  address internal _stranger = makeAddr('stranger');

  function setUp() public virtual {
    _registry = new NavePirataRegistry(_admin);
  }

  function _wire() internal {
    vm.prank(_admin);
    _registry.setFactory(_factory);
    vm.prank(_admin);
    _registry.setUpgrader(_upgrader);
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

  function _sampleUpgrade(uint256 _seed) internal returns (INavePirataRegistry.UpgradeRecord memory _r) {
    _r = INavePirataRegistry.UpgradeRecord({
      roleHatId: _seed + 500,
      oldClone: makeAddr(string.concat('old-', vm.toString(_seed))),
      newClone: makeAddr(string.concat('new-', vm.toString(_seed))),
      masterCopy: makeAddr(string.concat('master-', vm.toString(_seed))),
      upgradedAt: uint64(block.timestamp)
    });
  }
}

contract UnitNavePirataRegistryConstruction is UnitNavePirataRegistryBase {
  function test_Constructor_RevertsOnZeroAdmin() external {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
    new NavePirataRegistry(address(0));
  }

  function test_Constructor_SetsOwner() external view {
    assertEq(_registry.owner(), _admin);
    assertEq(_registry.factory(), address(0));
    assertEq(_registry.upgrader(), address(0));
  }
}

contract UnitNavePirataRegistryWiring is UnitNavePirataRegistryBase {
  function test_SetFactory_HappyPath() external {
    vm.prank(_admin);
    _registry.setFactory(_factory);
    assertEq(_registry.factory(), _factory);
  }

  function test_SetFactory_RevertsIfNotOwner() external {
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _stranger));
    _registry.setFactory(_factory);
  }

  function test_SetFactory_RevertsOnZero() external {
    vm.prank(_admin);
    vm.expectRevert(INavePirataRegistry.NavePirataRegistry_ZeroAddress.selector);
    _registry.setFactory(address(0));
  }

  function test_SetFactory_RevertsIfAlreadyWired() external {
    vm.prank(_admin);
    _registry.setFactory(_factory);
    vm.prank(_admin);
    vm.expectRevert(INavePirataRegistry.NavePirataRegistry_AlreadyWired.selector);
    _registry.setFactory(makeAddr('other'));
  }

  function test_SetUpgrader_HappyPath() external {
    vm.prank(_admin);
    _registry.setUpgrader(_upgrader);
    assertEq(_registry.upgrader(), _upgrader);
  }

  function test_SetUpgrader_RevertsIfNotOwner() external {
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _stranger));
    _registry.setUpgrader(_upgrader);
  }

  function test_SetUpgrader_RevertsOnZero() external {
    vm.prank(_admin);
    vm.expectRevert(INavePirataRegistry.NavePirataRegistry_ZeroAddress.selector);
    _registry.setUpgrader(address(0));
  }

  function test_SetUpgrader_RevertsIfAlreadyWired() external {
    vm.prank(_admin);
    _registry.setUpgrader(_upgrader);
    vm.prank(_admin);
    vm.expectRevert(INavePirataRegistry.NavePirataRegistry_AlreadyWired.selector);
    _registry.setUpgrader(makeAddr('other'));
  }

  function test_AdminCanRenounceAfterWiring() external {
    _wire();
    vm.prank(_admin);
    _registry.renounceOwnership();
    assertEq(_registry.owner(), address(0));
  }
}

contract UnitNavePirataRegistryRegisterDeployment is UnitNavePirataRegistryBase {
  function setUp() public override {
    super.setUp();
    _wire();
  }

  function test_RegisterDeployment_HappyPath() external {
    INavePirataRegistry.Deployment memory _d = _sampleDeployment(1);

    vm.expectEmit(true, false, false, true, address(_registry));
    emit INavePirataRegistry.NavePirataRegistered(1, _d);

    vm.prank(_factory);
    _registry.registerDeployment(_d);

    assertEq(_registry.deploymentCount(), 1);
    assertEq(_registry.deploymentAt(0), 1);

    INavePirataRegistry.Deployment memory _stored = _registry.deployment(1);
    assertEq(_stored.safe, _d.safe);
    assertEq(_stored.topHatId, _d.topHatId);
    assertEq(_stored.deployer, _d.deployer);
  }

  function test_RegisterDeployment_RevertsIfNotFactory() external {
    INavePirataRegistry.Deployment memory _d = _sampleDeployment(1);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(INavePirataRegistry.NavePirataRegistry_NotFactory.selector, _stranger));
    _registry.registerDeployment(_d);
  }

  function test_RegisterDeployment_RevertsOnDuplicateTopHat() external {
    INavePirataRegistry.Deployment memory _d = _sampleDeployment(7);
    vm.prank(_factory);
    _registry.registerDeployment(_d);

    vm.prank(_factory);
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataRegistry.NavePirataRegistry_AlreadyRegistered.selector, uint256(7))
    );
    _registry.registerDeployment(_d);
  }

  function test_RegisterDeployment_Enumerates() external {
    for (uint256 _i = 1; _i <= 3; _i++) {
      vm.prank(_factory);
      _registry.registerDeployment(_sampleDeployment(_i));
    }

    assertEq(_registry.deploymentCount(), 3);
    assertEq(_registry.deploymentAt(0), 1);
    assertEq(_registry.deploymentAt(1), 2);
    assertEq(_registry.deploymentAt(2), 3);
  }
}

contract UnitNavePirataRegistryRecordUpgrade is UnitNavePirataRegistryBase {
  uint256 internal constant _TOPHAT = 42;

  function setUp() public override {
    super.setUp();
    _wire();
    vm.prank(_factory);
    _registry.registerDeployment(_sampleDeployment(_TOPHAT));
  }

  function test_RecordUpgrade_HappyPath() external {
    INavePirataRegistry.UpgradeRecord memory _r = _sampleUpgrade(1);

    vm.expectEmit(true, false, false, true, address(_registry));
    emit INavePirataRegistry.RoleHatUpgradeRecorded(_TOPHAT, _r);

    vm.prank(_upgrader);
    _registry.recordUpgrade(_TOPHAT, _r);

    assertEq(_registry.upgradeCount(_TOPHAT), 1);
    INavePirataRegistry.UpgradeRecord memory _stored = _registry.upgradeAt(_TOPHAT, 0);
    assertEq(_stored.roleHatId, _r.roleHatId);
    assertEq(_stored.newClone, _r.newClone);
    assertEq(_stored.masterCopy, _r.masterCopy);
  }

  function test_RecordUpgrade_RevertsIfNotUpgrader() external {
    INavePirataRegistry.UpgradeRecord memory _r = _sampleUpgrade(1);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(INavePirataRegistry.NavePirataRegistry_NotUpgrader.selector, _stranger));
    _registry.recordUpgrade(_TOPHAT, _r);
  }

  function test_RecordUpgrade_RevertsIfTopHatUnknown() external {
    INavePirataRegistry.UpgradeRecord memory _r = _sampleUpgrade(1);
    vm.prank(_upgrader);
    vm.expectRevert(abi.encodeWithSelector(INavePirataRegistry.NavePirataRegistry_NotRegistered.selector, uint256(99)));
    _registry.recordUpgrade(99, _r);
  }

  function test_RecordUpgrade_Appends() external {
    for (uint256 _i = 1; _i <= 3; _i++) {
      vm.prank(_upgrader);
      _registry.recordUpgrade(_TOPHAT, _sampleUpgrade(_i));
    }
    assertEq(_registry.upgradeCount(_TOPHAT), 3);
    assertEq(_registry.upgradeAt(_TOPHAT, 2).roleHatId, 3 + 500);
  }
}
