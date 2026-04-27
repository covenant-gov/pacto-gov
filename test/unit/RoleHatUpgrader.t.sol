// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {RoleHatUpgrader} from 'contracts/factory/RoleHatUpgrader.sol';
import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IHatsIdUtilities} from 'hats-core/Interfaces/IHatsIdUtilities.sol';
import {IQuiescent} from 'interfaces/abstracts/IQuiescent.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {IRoleHatClonesFactory} from 'interfaces/factory/IRoleHatClonesFactory.sol';
import {IRoleHatUpgrader} from 'interfaces/factory/IRoleHatUpgrader.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title UnitRoleHatUpgraderBase
 * @author Pacto
 * @notice Shared fixture for `RoleHatUpgrader` unit tests. All external contracts (Hats, the
 *         clones factory, the registry, and old-clone `IQuiescent`) are stubbed with
 *         `vm.mockCall` — no helper contracts (see `.cursor/rules/solidity-unit-tests.mdc`).
 */
abstract contract UnitRoleHatUpgraderBase is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.upgrader.HATS'))));
  address internal constant _CLONES_ADDRESS = address(uint160(uint256(keccak256('pacto.upgrader.CLONES'))));
  address internal constant _REGISTRY_ADDRESS = address(uint160(uint256(keccak256('pacto.upgrader.REGISTRY'))));

  uint256 internal constant _ROLE_HAT_ID = 0xabc;
  uint256 internal constant _TOP_HAT_ID = 0xf00d;

  RoleHatUpgrader internal _upgrader;

  address internal _admin = makeAddr('admin');
  address internal _caller = makeAddr('caller');
  address internal _stranger = makeAddr('stranger');
  address internal _oldClone = makeAddr('oldClone');
  address internal _newClone = makeAddr('newClone');
  address internal _masterCopy = makeAddr('masterCopy');

  function setUp() public virtual {
    vm.etch(_HATS_ADDRESS, hex'00');
    vm.etch(_CLONES_ADDRESS, hex'00');
    vm.etch(_REGISTRY_ADDRESS, hex'00');
    vm.etch(_oldClone, hex'00');

    _upgrader = new RoleHatUpgrader(
      IHats(_HATS_ADDRESS), IRoleHatClonesFactory(_CLONES_ADDRESS), INavePirataRegistry(_REGISTRY_ADDRESS), _admin
    );
  }

  function _mockIsAdmin(address _who, uint256 _hatId, bool _is) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.isAdminOfHat.selector, _who, _hatId), abi.encode(_is));
  }

  function _mockIsQuiet(address _clone, bool _quiet) internal {
    vm.mockCall(_clone, abi.encodeWithSelector(IQuiescent.isQuiet.selector), abi.encode(_quiet));
  }

  function _mockCreateClone(address _master, bytes memory _initData, bytes32 _salt, address _result) internal {
    vm.mockCall(
      _CLONES_ADDRESS,
      abi.encodeWithSelector(IRoleHatClonesFactory.createClone.selector, _master, _initData, _salt),
      abi.encode(_result)
    );
  }

  function _mockTransferHat(uint256 _hatId, address _from, address _to) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _hatId, _from, _to), abi.encode());
  }

  function _mockTransferHatReverts(uint256 _hatId, address _from, address _to) internal {
    vm.mockCallRevert(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _hatId, _from, _to), bytes('hats-boom')
    );
  }

  function _mockGetAdminAtLevel(uint256 _hatId, uint32 _level, uint256 _result) internal {
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeWithSelector(IHatsIdUtilities.getAdminAtLevel.selector, _hatId, _level),
      abi.encode(_result)
    );
  }

  function _mockRecordUpgrade(uint256 _topHatId, INavePirataRegistry.UpgradeRecord memory _record) internal {
    vm.mockCall(
      _REGISTRY_ADDRESS,
      abi.encodeWithSelector(INavePirataRegistry.recordUpgrade.selector, _topHatId, _record),
      abi.encode()
    );
  }

  function _expectedSalt(uint256 _hatId, bytes32 _rawSalt) internal pure returns (bytes32) {
    return keccak256(abi.encode(_hatId, _rawSalt));
  }
}

contract UnitRoleHatUpgraderConstruction is UnitRoleHatUpgraderBase {
  function test_Constructor_SetsImmutablesAndOwner() external view {
    assertEq(address(_upgrader.hats()), _HATS_ADDRESS);
    assertEq(address(_upgrader.clonesFactory()), _CLONES_ADDRESS);
    assertEq(address(_upgrader.registry()), _REGISTRY_ADDRESS);
    assertEq(_upgrader.owner(), _admin);
    assertFalse(_upgrader.allowListEnabled());
  }

  function test_Constructor_RevertsOnZeroHats() external {
    vm.expectRevert(IRoleHatUpgrader.RoleHatUpgrader_ZeroAddress.selector);
    new RoleHatUpgrader(
      IHats(address(0)), IRoleHatClonesFactory(_CLONES_ADDRESS), INavePirataRegistry(_REGISTRY_ADDRESS), _admin
    );
  }

  function test_Constructor_RevertsOnZeroClones() external {
    vm.expectRevert(IRoleHatUpgrader.RoleHatUpgrader_ZeroAddress.selector);
    new RoleHatUpgrader(
      IHats(_HATS_ADDRESS), IRoleHatClonesFactory(address(0)), INavePirataRegistry(_REGISTRY_ADDRESS), _admin
    );
  }

  function test_Constructor_RevertsOnZeroRegistry() external {
    vm.expectRevert(IRoleHatUpgrader.RoleHatUpgrader_ZeroAddress.selector);
    new RoleHatUpgrader(
      IHats(_HATS_ADDRESS), IRoleHatClonesFactory(_CLONES_ADDRESS), INavePirataRegistry(address(0)), _admin
    );
  }
}

contract UnitRoleHatUpgraderAllowList is UnitRoleHatUpgraderBase {
  function test_SetAllowListEnabled_AdminOnly() external {
    vm.prank(_admin);
    vm.expectEmit(false, false, false, true, address(_upgrader));
    emit IRoleHatUpgrader.AllowListEnabledSet(true);
    _upgrader.setAllowListEnabled(true);
    assertTrue(_upgrader.allowListEnabled());
  }

  function test_SetAllowListEnabled_RevertsIfNotOwner() external {
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _stranger));
    _upgrader.setAllowListEnabled(true);
  }

  function test_SetMasterCopyAllowed_AdminOnly() external {
    vm.prank(_admin);
    vm.expectEmit(true, true, false, true, address(_upgrader));
    emit IRoleHatUpgrader.MasterCopyAllowListUpdated(IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _masterCopy, true);
    _upgrader.setMasterCopyAllowed(IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _masterCopy, true);
    assertTrue(_upgrader.isMasterCopyAllowed(IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _masterCopy));
  }

  function test_SetMasterCopyAllowed_RevertsOnZero() external {
    vm.prank(_admin);
    vm.expectRevert(IRoleHatUpgrader.RoleHatUpgrader_ZeroAddress.selector);
    _upgrader.setMasterCopyAllowed(IRoleHatUpgrader.RoleKind.QUARTERMASTER, address(0), true);
  }

  function test_SetMasterCopyAllowed_RevertsIfNotOwner() external {
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _stranger));
    _upgrader.setMasterCopyAllowed(IRoleHatUpgrader.RoleKind.QUARTERMASTER, _masterCopy, true);
  }
}

contract UnitRoleHatUpgraderCeremony is UnitRoleHatUpgraderBase {
  bytes internal _initData = abi.encodeWithSignature('initialize(uint256)', 42);
  bytes32 internal _rawSalt = keccak256('salt-v1');

  function _setupHappyPath() internal {
    _mockIsAdmin(_caller, _ROLE_HAT_ID, true);
    _mockIsQuiet(_oldClone, true);
    bytes32 _salt = _expectedSalt(_ROLE_HAT_ID, _rawSalt);
    _mockCreateClone(_masterCopy, _initData, _salt, _newClone);
    _mockTransferHat(_ROLE_HAT_ID, _oldClone, _newClone);
    _mockGetAdminAtLevel(_ROLE_HAT_ID, 0, _TOP_HAT_ID);
    _mockRecordUpgrade(
      _TOP_HAT_ID,
      INavePirataRegistry.UpgradeRecord({
        roleHatId: _ROLE_HAT_ID,
        oldClone: _oldClone,
        newClone: _newClone,
        masterCopy: _masterCopy,
        upgradedAt: uint64(block.timestamp)
      })
    );
  }

  function test_UpgradeRole_HappyPath_EmitsAndReturnsNewClone() external {
    _setupHappyPath();

    vm.expectEmit(true, true, true, true, address(_upgrader));
    emit IRoleHatUpgrader.RoleHatUpgraded(
      _ROLE_HAT_ID, _oldClone, _newClone, _masterCopy, IRoleHatUpgrader.RoleKind.MUTINY_MODULE
    );

    vm.prank(_caller);
    address _result = _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _ROLE_HAT_ID, _oldClone, _masterCopy, _initData, _rawSalt
    );

    assertEq(_result, _newClone);
  }

  function test_UpgradeRole_CallsClonesFactoryWithNamespacedSalt() external {
    _setupHappyPath();

    bytes32 _expected = _expectedSalt(_ROLE_HAT_ID, _rawSalt);
    vm.expectCall(
      _CLONES_ADDRESS,
      abi.encodeWithSelector(IRoleHatClonesFactory.createClone.selector, _masterCopy, _initData, _expected)
    );

    vm.prank(_caller);
    _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.QUARTERMASTER, _ROLE_HAT_ID, _oldClone, _masterCopy, _initData, _rawSalt
    );
  }

  function test_UpgradeRole_CallsRegistryWithDerivedTopHat() external {
    _setupHappyPath();

    INavePirataRegistry.UpgradeRecord memory _expected = INavePirataRegistry.UpgradeRecord({
      roleHatId: _ROLE_HAT_ID,
      oldClone: _oldClone,
      newClone: _newClone,
      masterCopy: _masterCopy,
      upgradedAt: uint64(block.timestamp)
    });
    vm.expectCall(
      _REGISTRY_ADDRESS, abi.encodeWithSelector(INavePirataRegistry.recordUpgrade.selector, _TOP_HAT_ID, _expected)
    );

    vm.prank(_caller);
    _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.TREASURY_AUTHORITY, _ROLE_HAT_ID, _oldClone, _masterCopy, _initData, _rawSalt
    );
  }

  function test_UpgradeRole_RevertsOnZeroOldClone() external {
    vm.prank(_caller);
    vm.expectRevert(IRoleHatUpgrader.RoleHatUpgrader_ZeroAddress.selector);
    _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _ROLE_HAT_ID, address(0), _masterCopy, _initData, _rawSalt
    );
  }

  function test_UpgradeRole_RevertsOnZeroMasterCopy() external {
    vm.prank(_caller);
    vm.expectRevert(IRoleHatUpgrader.RoleHatUpgrader_ZeroAddress.selector);
    _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _ROLE_HAT_ID, _oldClone, address(0), _initData, _rawSalt
    );
  }

  function test_UpgradeRole_RevertsIfNotAdmin() external {
    _mockIsAdmin(_caller, _ROLE_HAT_ID, false);
    vm.prank(_caller);
    vm.expectRevert(abi.encodeWithSelector(IRoleHatUpgrader.RoleHatUpgrader_NotAdmin.selector, _ROLE_HAT_ID, _caller));
    _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _ROLE_HAT_ID, _oldClone, _masterCopy, _initData, _rawSalt
    );
  }

  function test_UpgradeRole_RevertsIfNotQuiet() external {
    _mockIsAdmin(_caller, _ROLE_HAT_ID, true);
    _mockIsQuiet(_oldClone, false);
    vm.prank(_caller);
    vm.expectRevert(abi.encodeWithSelector(IRoleHatUpgrader.RoleHatUpgrader_NotQuiet.selector, _oldClone));
    _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _ROLE_HAT_ID, _oldClone, _masterCopy, _initData, _rawSalt
    );
  }

  function test_UpgradeRole_RevertsIfAllowListBlocksMaster() external {
    vm.prank(_admin);
    _upgrader.setAllowListEnabled(true);

    _mockIsAdmin(_caller, _ROLE_HAT_ID, true);

    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IRoleHatUpgrader.RoleHatUpgrader_MasterCopyNotAllowed.selector,
        IRoleHatUpgrader.RoleKind.MUTINY_MODULE,
        _masterCopy
      )
    );
    _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _ROLE_HAT_ID, _oldClone, _masterCopy, _initData, _rawSalt
    );
  }

  function test_UpgradeRole_PassesWhenAllowListAllowsMaster() external {
    vm.prank(_admin);
    _upgrader.setAllowListEnabled(true);
    vm.prank(_admin);
    _upgrader.setMasterCopyAllowed(IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _masterCopy, true);

    _setupHappyPath();

    vm.prank(_caller);
    address _result = _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _ROLE_HAT_ID, _oldClone, _masterCopy, _initData, _rawSalt
    );
    assertEq(_result, _newClone);
  }

  function test_UpgradeRole_RevertsIfHatsTransferFails() external {
    _mockIsAdmin(_caller, _ROLE_HAT_ID, true);
    _mockIsQuiet(_oldClone, true);
    bytes32 _salt = _expectedSalt(_ROLE_HAT_ID, _rawSalt);
    _mockCreateClone(_masterCopy, _initData, _salt, _newClone);
    _mockTransferHatReverts(_ROLE_HAT_ID, _oldClone, _newClone);

    vm.prank(_caller);
    vm.expectRevert(IRoleHatUpgrader.RoleHatUpgrader_TransferFailed.selector);
    _upgrader.upgradeRole(
      IRoleHatUpgrader.RoleKind.MUTINY_MODULE, _ROLE_HAT_ID, _oldClone, _masterCopy, _initData, _rawSalt
    );
  }
}
