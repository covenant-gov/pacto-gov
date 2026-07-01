// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';
import {SquadAdminExt} from 'contracts/squad/SquadAdminExt.sol';
import {HatGated} from 'contracts/utils/HatGated.sol';

import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';
import {ISquadAdminBase} from 'interfaces/squad/ISquadAdminBase.sol';
import {ISquadAdminExt} from 'interfaces/squad/ISquadAdminExt.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2ESquadAdminExtTest
 * @author Pacto
 * @notice Forked end-to-end scenarios for `SquadAdminExt` (owner bootstrap → `postInitialize` → captain gating).
 */
contract E2ESquadAdminExtTest is IntegrationBase {
  bytes32 internal constant _E2E_EXECUTOR_ROLE_APP = keccak256('pacto.e2e.squadadminext.role.app');

  function _extOwner() internal returns (address _owner) {
    _owner = makeAddr('e2eSquadAdminExtOwner');
    _fund(_owner, 1 ether);
  }

  function _freshExtInitialized(address _owner) internal returns (SquadAdminExt _ext) {
    _ext = _newSquadAdminExtClone();
    _ext.initialize(_owner);
  }

  function _extPostInitializedWithSquadHats() internal returns (SquadAdminExt _ext) {
    _ensureSquad();
    address _owner = _extOwner();
    _ext = _freshExtInitialized(_owner);
    vm.startPrank(_owner);
    _ext.createRole(_E2E_EXECUTOR_ROLE_APP);
    _ext.postInitialize(_baselineSquadAdminInit());
    vm.stopPrank();
  }

  /*///////////////////////////////////////////////////////////////
                        initialize(address)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_squadAdminExt_initialize_setsOwner() public {
    address _owner = _extOwner();
    SquadAdminExt _ext = _freshExtInitialized(_owner);
    assertEq(_ext.owner(), _owner);
  }

  function test_e2e_squadAdminExt_initialize_revertsWhenOwnerIsZero() public {
    SquadAdminExt _ext = _newSquadAdminExtClone();
    vm.expectRevert(ISquadAdminBase.SquadAdminBase_ZeroAddress.selector);
    _ext.initialize(address(0));
  }

  function test_e2e_squadAdminExt_initialize_revertsWhenAlreadyInitialized() public {
    address _owner = _extOwner();
    SquadAdminExt _ext = _freshExtInitialized(_owner);
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _ext.initialize(_owner);
  }

  function test_e2e_squadAdminExt_initialize_revertsOnInitParamsOverload() public {
    SquadAdminExt _ext = _newSquadAdminExtClone();
    vm.expectRevert(ISquadAdminExt.SquadAdminExt_UseAddressInitializer.selector);
    _ext.initialize(ISquadAdmin.InitParams({captainHatId: 1, squadAdminHatId: 2}));
  }

  function test_e2e_squadAdminExt_initialize_revertsOnUintHatIdOverload() public {
    SquadAdminExt _ext = _newSquadAdminExtClone();
    vm.expectRevert(ISquadAdminExt.SquadAdminExt_UseAddressInitializer.selector);
    _ext.initialize(uint256(1));
  }

  /*///////////////////////////////////////////////////////////////
                        owner-gated roster (pre postInitialize)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_squadAdminExt_ownerCanEnableExecutor_beforePostInitialize() public {
    address _owner = _extOwner();
    address _alice = makeAddr('e2eSquadAdminExtAliceEnable');
    SquadAdminExt _ext = _freshExtInitialized(_owner);

    vm.startPrank(_owner);
    _ext.createRole(_E2E_EXECUTOR_ROLE_APP);
    _ext.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
    vm.stopPrank();

    assertTrue(_ext.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));
  }

  function test_e2e_squadAdminExt_strangerCannotEnableExecutor_beforePostInitialize() public {
    address _owner = _extOwner();
    address _stranger = makeAddr('e2eSquadAdminExtStrangerPreInit');
    address _alice = makeAddr('e2eSquadAdminExtAliceStrangerPreInit');
    _fund(_stranger, 1 ether);
    SquadAdminExt _ext = _freshExtInitialized(_owner);

    vm.prank(_owner);
    _ext.createRole(_E2E_EXECUTOR_ROLE_APP);

    vm.expectRevert(ISquadAdminExt.SquadAdminExt_NotAllowed.selector);
    vm.prank(_stranger);
    _ext.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
  }

  function test_e2e_squadAdminExt_ownerCanDisableExecutor_beforePostInitialize() public {
    address _owner = _extOwner();
    address _alice = makeAddr('e2eSquadAdminExtAliceDisable');
    SquadAdminExt _ext = _freshExtInitialized(_owner);

    vm.startPrank(_owner);
    _ext.createRole(_E2E_EXECUTOR_ROLE_APP);
    _ext.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
    assertTrue(_ext.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));
    _ext.disableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
    vm.stopPrank();

    assertFalse(_ext.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));
  }

  function test_e2e_squadAdminExt_ownerCanToggleFullPermission_beforePostInitialize() public {
    address _owner = _extOwner();
    address _alice = makeAddr('e2eSquadAdminExtAliceFull');
    SquadAdminExt _ext = _freshExtInitialized(_owner);

    vm.startPrank(_owner);
    _ext.enableFullPermission(_alice, true);
    assertTrue(_ext.isExecutorFullPermission(_alice));
    _ext.enableFullPermission(_alice, false);
    vm.stopPrank();

    assertFalse(_ext.isExecutorFullPermission(_alice));
  }

  function test_e2e_squadAdminExt_ownerCanPauseExecutor_beforePostInitialize() public {
    address _owner = _extOwner();
    address _alice = makeAddr('e2eSquadAdminExtAlicePause');
    SquadAdminExt _ext = _freshExtInitialized(_owner);

    vm.startPrank(_owner);
    _ext.createRole(_E2E_EXECUTOR_ROLE_APP);
    _ext.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
    _ext.pauseExecutor(_alice, true);
    vm.stopPrank();

    assertTrue(_ext.isExecutorPaused(_alice));
    assertFalse(_ext.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));
  }

  /*///////////////////////////////////////////////////////////////
                        postInitialize(InitParams)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_squadAdminExt_postInitialize_clearsOwner_andPersistsHatIds() public {
    address _owner = _extOwner();
    SquadAdminExt _ext = _freshExtInitialized(_owner);
    ISquadAdmin.InitParams memory _p = ISquadAdmin.InitParams({captainHatId: 111, squadAdminHatId: 222});

    vm.prank(_owner);
    _ext.postInitialize(_p);

    assertEq(_ext.owner(), address(0));
    assertEq(_ext.captainHatId(), _p.captainHatId);
    assertEq(_ext.squadAdminHatId(), _p.squadAdminHatId);
  }

  function test_e2e_squadAdminExt_postInitialize_revertsWhenCallerIsNotOwner() public {
    address _owner = _extOwner();
    address _stranger = makeAddr('e2eSquadAdminExtStrangerPostInit');
    _fund(_stranger, 1 ether);
    SquadAdminExt _ext = _freshExtInitialized(_owner);

    vm.expectRevert(ISquadAdminExt.SquadAdminExt_NotAllowed.selector);
    vm.prank(_stranger);
    _ext.postInitialize(ISquadAdmin.InitParams({captainHatId: 1, squadAdminHatId: 2}));
  }

  function test_e2e_squadAdminExt_postInitialize_secondCall_revertsAfterOwnerCleared() public {
    address _owner = _extOwner();
    SquadAdminExt _ext = _freshExtInitialized(_owner);
    ISquadAdmin.InitParams memory _p = ISquadAdmin.InitParams({captainHatId: 333, squadAdminHatId: 444});

    vm.startPrank(_owner);
    _ext.postInitialize(_p);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _p.captainHatId, _owner));
    _ext.postInitialize(_p);
    vm.stopPrank();
  }

  /*///////////////////////////////////////////////////////////////
                        captain-gated roster (post postInitialize)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_squadAdminExt_captainCanEnableExecutor_afterPostInitialize() public withDeployedNavePirataSquad {
    SquadAdminExt _ext = _extPostInitializedWithSquadHats();
    address _alice = makeAddr('e2eSquadAdminExtAliceCaptain');

    vm.prank(_squadCaptain);
    _ext.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);

    assertTrue(_ext.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));
  }

  function test_e2e_squadAdminExt_captainCannotEnableExecutor_whenCallerIsNotCaptain()
    public
    withDeployedNavePirataSquad
  {
    SquadAdminExt _ext = _extPostInitializedWithSquadHats();
    address _alice = makeAddr('e2eSquadAdminExtAliceNotCaptain');
    address _notCaptain = makeAddr('e2eSquadAdminExtNotCaptain');
    _fund(_notCaptain, 1 ether);

    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _ext.captainHatId(), _notCaptain));
    vm.prank(_notCaptain);
    _ext.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
  }

  function test_e2e_squadAdminExt_strangerCannotMutateRoster_afterPostInitialize() public withDeployedNavePirataSquad {
    SquadAdminExt _ext = _extPostInitializedWithSquadHats();
    address _formerOwner = makeAddr('e2eSquadAdminExtOwner');
    address _stranger = makeAddr('e2eSquadAdminExtStrangerAfterPostInit');
    _fund(_stranger, 1 ether);
    address _alice = makeAddr('e2eSquadAdminExtAliceAfterPostInit');

    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _ext.captainHatId(), _formerOwner));
    vm.prank(_formerOwner);
    _ext.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);

    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _ext.captainHatId(), _stranger));
    vm.prank(_stranger);
    _ext.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
  }

  /*///////////////////////////////////////////////////////////////
                        factory standalone path
  //////////////////////////////////////////////////////////////*/

  function test_e2e_factory_deploySquadAdminExtStandalone_returnsCloneWithCode() public {
    address _owner = _extOwner();
    SquadAdminExt _clone = _deployStandaloneSquadAdminExt(_owner);
    assertGt(address(_clone).code.length, 0);
    assertEq(_clone.owner(), _owner);
  }

  function test_e2e_factory_deploySquadAdminExtStandalone_revertsOnZeroImplementation() public {
    address _owner = _extOwner();
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'squadAdminExtImplementation')
    );
    NavePirataFactory(_infra.navePirataFactory).deploySquadAdminExtStandalone(address(0), _owner);
  }

  function test_e2e_factory_deploySquadAdminExtStandalone_revertsOnZeroOwner() public {
    vm.expectRevert(abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'owner'));
    NavePirataFactory(_infra.navePirataFactory).deploySquadAdminExtStandalone(_masters.squadAdminExtImpl, address(0));
  }

  /*///////////////////////////////////////////////////////////////
                        fresh clone helpers (no full squad)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_squadAdminExtClone_doubleInitialize_reverts() public {
    address _owner = _extOwner();
    SquadAdminExt _ext = _freshExtInitialized(_owner);
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _ext.initialize(_owner);
  }

  /*///////////////////////////////////////////////////////////////
                        integration wiring
  //////////////////////////////////////////////////////////////*/

  function test_integration_squadAdminExtMasterDeployed() public view {
    assertGt(_masters.squadAdminExtImpl.code.length, 0);
    assertGt(_infra.navePirataFactory.code.length, 0);
  }
}
