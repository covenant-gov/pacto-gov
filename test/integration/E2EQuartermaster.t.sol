// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2EQuartermasterTest
 * @author Pacto
 * @notice Forked E2E for `Quartermaster` / `IQuartermaster`. Categories mirror public API groupings;
 *         empty bodies are intentional until step 3.
 */
contract E2EQuartermasterTest is IntegrationBase {
  /*///////////////////////////////////////////////////////////////
                        initialize
  //////////////////////////////////////////////////////////////*/

  function test_e2e_initialize_reverts_whenAlreadyInitialized() public withDeployedNavePirataSquad {}

  function test_e2e_initialize_reverts_whenCrewChangeDelayBelowMin() public withDeployedNavePirataSquad {}

  function test_e2e_initialize_reverts_whenCrewChangeDelayAboveMax() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        clone / wiring (factory deploy)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_quartermaster_cloneFromFactory_matchesRegistryDeployment() public withDeployedNavePirataSquad {}

  function test_e2e_quartermaster_hatIds_matchRegistryRecord() public withDeployedNavePirataSquad {}

  function test_e2e_quartermaster_crewChangeDelay_matchesProductionDefault() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        requestAddCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_requestAddCrew_succeeds_emitsAndStoresPending() public withDeployedNavePirataSquad {}

  function test_e2e_requestAddCrew_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

  function test_e2e_requestAddCrew_reverts_whenMutinyActive() public withDeployedNavePirataSquad {}

  function test_e2e_requestAddCrew_reverts_whenCandidateIsZero() public withDeployedNavePirataSquad {}

  function test_e2e_requestAddCrew_reverts_whenCandidateIsCaptain() public withDeployedNavePirataSquad {}

  function test_e2e_requestAddCrew_reverts_whenCandidateAlreadyWearsCrewHat() public withDeployedNavePirataSquad {}

  function test_e2e_requestAddCrew_reverts_whenDuplicatePendingAdd() public withDeployedNavePirataSquad {}

  function test_e2e_requestAddCrew_reverts_whenCrewFull() public withDeployedNavePirataSquad {}

  function test_e2e_requestAddCrew_usesFullDelay_whenCrewAlreadyExists() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        cancelAddCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_cancelAddCrew_succeeds_clearsPendingAndEmits() public withDeployedNavePirataSquad {}

  function test_e2e_cancelAddCrew_reverts_whenNoPendingAdd() public withDeployedNavePirataSquad {}

  function test_e2e_cancelAddCrew_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        executeAddCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_executeAddCrew_succeeds_mintsCrewHatAndEmits() public withDeployedNavePirataSquad {}

  function test_e2e_executeAddCrew_reverts_whenNoPendingAdd() public withDeployedNavePirataSquad {}

  function test_e2e_executeAddCrew_reverts_whenStillLocked() public withDeployedNavePirataSquad {}

  function test_e2e_executeAddCrew_reverts_whenMutinyActive() public withDeployedNavePirataSquad {}

  function test_e2e_executeAddCrew_reverts_whenCandidateAlreadyCrewAtExecuteTime() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        bootstrapCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_bootstrapCrew_succeeds_mintsMultipleImmediately() public {}

  function test_e2e_bootstrapCrew_reverts_whenCallerDoesNotWearCaptainHat() public {}

  function test_e2e_bootstrapCrew_reverts_whenMutinyActive() public {}

  function test_e2e_bootstrapCrew_reverts_whenCrewAlreadyExists() public withDeployedNavePirataSquad {}

  function test_e2e_bootstrapCrew_reverts_whenCandidatesEmpty() public {}

  function test_e2e_bootstrapCrew_reverts_whenMoreCandidatesThanMaxSupply() public {}

  function test_e2e_bootstrapCrew_succeeds_whenSameCandidateListedTwice() public {}

  /*///////////////////////////////////////////////////////////////
                        requestRemoveCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_requestRemoveCrew_succeeds_emitsAndStoresPending() public withDeployedNavePirataSquad {}

  function test_e2e_requestRemoveCrew_reverts_whenMutinyActive() public withDeployedNavePirataSquad {}

  function test_e2e_requestRemoveCrew_reverts_whenTargetIsZero() public withDeployedNavePirataSquad {}

  function test_e2e_requestRemoveCrew_reverts_whenTargetDoesNotWearCrewHat() public withDeployedNavePirataSquad {}

  function test_e2e_requestRemoveCrew_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        cancelRemoveCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_cancelRemoveCrew_succeeds_clearsPendingAndEmits() public withDeployedNavePirataSquad {}

  function test_e2e_cancelRemoveCrew_reverts_whenNoPendingRemove() public withDeployedNavePirataSquad {}

  function test_e2e_cancelRemoveCrew_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        executeRemoveCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_executeRemoveCrew_succeeds_revokesCrewHatAndEmits() public withDeployedNavePirataSquad {}

  function test_e2e_executeRemoveCrew_reverts_whenNoPendingRemove() public withDeployedNavePirataSquad {}

  function test_e2e_executeRemoveCrew_reverts_whenStillLocked() public withDeployedNavePirataSquad {}

  function test_e2e_executeRemoveCrew_reverts_whenMutinyActive() public withDeployedNavePirataSquad {}

  function test_e2e_executeRemoveCrew_reverts_whenTargetAlreadyNonCrew() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        mutiny hooks (MutinyRole-gated)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_mintCrewFromMutiny_succeeds_whenCalledByMutinyModule() public withDeployedNavePirataSquad {}

  function test_e2e_mintCrewFromMutiny_reverts_whenCallerDoesNotWearMutinyRoleHat()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_mintCrewFromMutiny_reverts_whenFormerCaptainIsZero() public withDeployedNavePirataSquad {}

  function test_e2e_mintCrewFromMutiny_reverts_whenFormerCaptainAlreadyCrew() public withDeployedNavePirataSquad {}

  function test_e2e_mintCrewFromMutiny_reverts_whenCrewFull() public withDeployedNavePirataSquad {}

  function test_e2e_crewHandoffForMutiny_succeeds_whenCalledByMutinyModule() public withDeployedNavePirataSquad {}

  function test_e2e_crewHandoffForMutiny_reverts_whenCallerDoesNotWearMutinyRoleHat()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_crewHandoffForMutiny_reverts_whenFormerCaptainIsZero() public withDeployedNavePirataSquad {}

  function test_e2e_crewHandoffForMutiny_reverts_whenNewCaptainDoesNotWearCrewHat()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_crewHandoffForMutiny_reverts_whenFormerCaptainAlreadyCrew() public withDeployedNavePirataSquad {}

  function test_e2e_setMutinyActive_succeeds_togglesFlagAndEmits() public withDeployedNavePirataSquad {}

  function test_e2e_setMutinyActive_reverts_whenCallerDoesNotWearMutinyRoleHat() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        setCrewChangeDelay (TreasuryAuthorityRole-gated)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_setCrewChangeDelay_succeeds_whenCalledByTreasuryAuthority() public withDeployedNavePirataSquad {}

  function test_e2e_setCrewChangeDelay_reverts_whenCallerDoesNotWearTreasuryAuthorityRoleHat()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_setCrewChangeDelay_reverts_whenValueOutOfRange() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        views / eligibility / isQuiet
  //////////////////////////////////////////////////////////////*/

  function test_e2e_getWearerStatus_defaultsIneligibleForNonCrew() public withDeployedNavePirataSquad {}

  function test_e2e_getWearerStatus_reflectsCrewMintAndRemoveCycle() public withDeployedNavePirataSquad {}

  function test_e2e_isQuiet_falseWhenPendingAddOrRemove() public withDeployedNavePirataSquad {}

  function test_e2e_isQuiet_trueWhenNoPendingOperationsAndNoMutiny() public withDeployedNavePirataSquad {}

  function test_e2e_pendingCrewAddAt_reflectsScheduledAdd() public withDeployedNavePirataSquad {}

  function test_e2e_pendingCrewRemoveAt_reflectsScheduledRemove() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        integration wiring
  //////////////////////////////////////////////////////////////*/

  function test_integration_registryUpgraderIsWiredAndQuartermasterMasterDeployed() public view {
    assertEq(NavePirataRegistry(_infra.registry).upgrader(), _infra.upgrader);
    Quartermaster _master = Quartermaster(_masters.quartermaster);
    assertGt(address(_master).code.length, 0);
  }

  function test_integration_quartermasterCloneMatchesRegistryDeployment() public withDeployedNavePirataSquad {}
}
