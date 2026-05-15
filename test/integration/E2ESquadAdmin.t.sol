// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';

import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';
import {ISquadAdminBase} from 'interfaces/squad/ISquadAdminBase.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2ESquadAdminTest
 * @author Pacto
 * @notice Forked end-to-end scenarios for `SquadAdmin` / `ISquadAdmin` / `ISquadAdminBase`; names follow public API
 *         groupings. Later sections may still be stubs.
 */
contract E2ESquadAdminTest is IntegrationBase {
  bytes32 internal constant _E2E_EXECUTOR_ROLE_APP = keccak256('pacto.e2e.squadadmin.role.app');
  bytes32 internal constant _E2E_EXECUTOR_ROLE_OTHER = keccak256('pacto.e2e.squadadmin.role.other');

  /*///////////////////////////////////////////////////////////////
                        initialize / postInitialize / views
  //////////////////////////////////////////////////////////////*/

  function test_e2e_squadAdmin_cloneFromFactory_matchesRegistryDeployment() public withDeployedNavePirataSquad {
    INavePirataRegistry.Deployment memory _d = NavePirataRegistry(_infra.registry).deployment(_squadTopHatId);
    assertEq(address(_squadSquadAdmin), _d.squadAdminProxy);
    assertGt(address(_squadSquadAdmin).code.length, 0);
  }

  function test_e2e_squadAdmin_hatIds_matchRegistryRecord() public withDeployedNavePirataSquad {
    INavePirataRegistry.Deployment memory _d = NavePirataRegistry(_infra.registry).deployment(_squadTopHatId);
    assertEq(_squadSquadAdmin.captainHatId(), _d.captainHatId);
    assertEq(_squadSquadAdmin.squadAdminHatId(), _d.squadAdminHatId);
    assertEq(_squadSquadAdmin.squadAdminHatId(), _squadSquadAdminHatId);
  }

  function test_e2e_initialize_revertsWhenAlreadyInitialized() public withDeployedNavePirataSquad {
    ISquadAdmin.InitParams memory _p = _baselineSquadAdminInit();
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _squadSquadAdmin.initialize(_p);
  }

  function test_e2e_initialize_revertsWhenCalledOnFreshCloneTwice() public withDeployedNavePirataSquad {
    ISquadAdmin.InitParams memory _p = _baselineSquadAdminInit();
    address _clone = address(_newSquadAdminClone());
    ISquadAdmin(payable(_clone)).initialize(_p);
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    ISquadAdmin(payable(_clone)).initialize(_p);
  }

  function test_e2e_postInitialize_updatesHatIds_whenCallerWearsCaptainHat() public withDeployedNavePirataSquad {
    INavePirataRegistry.Deployment memory _d = NavePirataRegistry(_infra.registry).deployment(_squadTopHatId);
    assertNotEq(_d.mutinyRoleHatId, _d.squadAdminHatId, 'pick distinct hat id for postInitialize');

    ISquadAdmin.InitParams memory _next =
      ISquadAdmin.InitParams({captainHatId: _d.captainHatId, squadAdminHatId: _d.mutinyRoleHatId});

    vm.prank(_squadCaptain);
    _squadSquadAdmin.postInitialize(_next);

    assertEq(_squadSquadAdmin.captainHatId(), _d.captainHatId);
    assertEq(_squadSquadAdmin.squadAdminHatId(), _d.mutinyRoleHatId);
  }

  function test_e2e_postInitialize_revertsWhenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    address _stranger = makeAddr('e2eSquadAdminStranger');
    _fund(_stranger, 1 ether);

    ISquadAdmin.InitParams memory _p = _baselineSquadAdminInit();

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadSquadAdmin.captainHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadSquadAdmin.postInitialize(_p);
  }

  /*///////////////////////////////////////////////////////////////
                        enableExecutor / disableExecutor
  //////////////////////////////////////////////////////////////*/

  function test_e2e_enableExecutor_succeeds_whenCallerWearsCaptainHat() public withDeployedNavePirataSquad {
    address _alice = makeAddr('e2eSquadAdminAlice');

    vm.prank(_squadCaptain);
    _squadSquadAdmin.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);

    assertTrue(_squadSquadAdmin.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));
  }

  function test_e2e_enableExecutor_revertsWhenExecutorIsZeroAddress() public withDeployedNavePirataSquad {
    vm.expectRevert(ISquadAdminBase.SquadAdminBase_ZeroAddress.selector);
    vm.prank(_squadCaptain);
    _squadSquadAdmin.enableExecutor(address(0), _E2E_EXECUTOR_ROLE_APP);
  }

  function test_e2e_enableExecutor_revertsWhenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    address _stranger = makeAddr('e2eSquadAdminStrangerEnable');
    _fund(_stranger, 1 ether);
    address _alice = makeAddr('e2eSquadAdminAliceTarget');

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadSquadAdmin.captainHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadSquadAdmin.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
  }

  function test_e2e_disableExecutor_succeeds_whenCallerWearsCaptainHat() public withDeployedNavePirataSquad {
    address _alice = makeAddr('e2eSquadAdminAliceDisable');

    vm.startPrank(_squadCaptain);
    _squadSquadAdmin.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
    assertTrue(_squadSquadAdmin.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));

    _squadSquadAdmin.disableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);
    vm.stopPrank();

    assertFalse(_squadSquadAdmin.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));
  }

  function test_e2e_disableExecutor_revertsWhenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    address _stranger = makeAddr('e2eSquadAdminStrangerDisable');
    _fund(_stranger, 1 ether);
    address _alice = makeAddr('e2eSquadAdminAliceDisableTarget');

    vm.prank(_squadCaptain);
    _squadSquadAdmin.enableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadSquadAdmin.captainHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadSquadAdmin.disableExecutor(_alice, _E2E_EXECUTOR_ROLE_APP);

    assertTrue(_squadSquadAdmin.hasExecutorRole(_alice, _E2E_EXECUTOR_ROLE_APP));
  }

  /*///////////////////////////////////////////////////////////////
                        enableFullPermission
  //////////////////////////////////////////////////////////////*/

  function test_e2e_enableFullPermission_succeeds_whenCallerWearsCaptainHat() public withDeployedNavePirataSquad {}

  function test_e2e_enableFullPermission_revertsWhenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

  function test_e2e_hasExecutorRole_reflectsFullPermission_acrossDistinctRoles() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        pauseExecutor
  //////////////////////////////////////////////////////////////*/

  function test_e2e_pauseExecutor_blocksHasExecutorRole_whenPaused() public withDeployedNavePirataSquad {}

  function test_e2e_pauseExecutor_unpause_restoresPriorRoleBits() public withDeployedNavePirataSquad {}

  function test_e2e_pauseExecutor_revertsWhenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        views (isExecutorFullPermission / isExecutorPaused)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_isExecutorFullPermission_reflectsStorage() public withDeployedNavePirataSquad {}

  function test_e2e_isExecutorPaused_reflectsStorage() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        events (smoke / ordering)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_enableExecutor_emitsExecutorEnabled() public withDeployedNavePirataSquad {}

  function test_e2e_disableExecutor_emitsExecutorDisabled() public withDeployedNavePirataSquad {}

  function test_e2e_enableFullPermission_emitsFullPermissionEnabled() public withDeployedNavePirataSquad {}

  function test_e2e_pauseExecutor_emitsExecutorPaused() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        integration wiring
  //////////////////////////////////////////////////////////////*/

  function test_integration_squadAdminMasterDeployedAndFactoryLive() public view {}

  function test_integration_squadAdminProxyMatchesRegistryDeployment() public withDeployedNavePirataSquad {}

  function test_integration_squadAdminCaptainHatId_alignsWithTreasuryCaptainHatId()
    public
    withDeployedNavePirataSquad
  {}

  /*///////////////////////////////////////////////////////////////
                        factory standalone SquadAdmin (captain-hat-only init)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_factory_deploySquadAdminStandaloneCaptainHat_returnsCloneWithCode() public {}

  function test_e2e_factory_deploySquadAdminStandaloneCaptainHat_revertsOnZeroImplementation() public {}

  function test_e2e_factory_deploySquadAdminStandaloneCaptainHat_revertsOnZeroCaptainHatId() public {}
}
