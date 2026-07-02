// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {TreasuryAuthority} from 'contracts/core/TreasuryAuthority.sol';
import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';
import {HatGated} from 'contracts/utils/HatGated.sol';
import {RangeValidator} from 'contracts/utils/RangeValidator.sol';

import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';
import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {IRoleHatClonesFactory} from 'interfaces/factory/IRoleHatClonesFactory.sol';

import {CREW_CHANGE_DELAY, DEPLOY_NAV_PIRATA_SALT_NONCE, HATS_PROTOCOL_V1} from 'script/Constants.sol';

import {IHats} from 'hats-core/Interfaces/IHats.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2EQuartermasterBase
 * @author Pacto
 * @notice Quartermaster-specific fixtures on the mainnet fork from `IntegrationBase`: fresh clones for init
 *         scenarios, unbootstrapped squads for `bootstrapCrew`, and small prank / warp helpers for timelocked flows.
 */
abstract contract E2EQuartermasterBase is IntegrationBase {
  uint256 internal constant _FRESH_SQUAD_SALT = DEPLOY_NAV_PIRATA_SALT_NONCE + 1;

  /// @dev Fresh QM clone for init / revert scenarios.
  function _newQmClone() internal returns (Quartermaster _clone) {
    bytes32 _salt = keccak256(abi.encodePacked('e2eQmClone', address(this), block.timestamp, block.number));
    _clone = Quartermaster(
      IRoleHatClonesFactory(_infra.clonesFactory).createClone(_masters.quartermaster, new bytes(0), _salt)
    );
  }

  /// @dev Init params aligned with the deployed squad quartermaster clone (requires `_ensureSquad` first).
  function _baselineQmInit() internal view returns (IQuartermaster.InitParams memory _p) {
    _p = IQuartermaster.InitParams({
      captainHatId: _squadQuartermaster.captainHatId(),
      crewHatId: _squadQuartermaster.crewHatId(),
      mutinyRoleHatId: _squadQuartermaster.mutinyRoleHatId(),
      quartermasterRoleHatId: _squadQuartermaster.quartermasterRoleHatId(),
      treasuryAuthorityRoleHatId: _squadQuartermaster.treasuryAuthorityRoleHatId(),
      crewChangeDelay: _squadQuartermaster.crewChangeDelay()
    });
  }

  /// @dev Unique labeled address; funds 1 ether so fork txs can be sent when needed.
  function _qmLabeledAddr(string memory _label) internal returns (address _a) {
    _a = makeAddr(_label);
    _fund(_a, 1 ether);
  }

  /// @dev Collision-resistant candidate for add / bootstrap paths.
  function _qmCandidate(string memory _label) internal returns (address _c) {
    _c = _qmLabeledAddr(string(abi.encodePacked(_label, block.timestamp, block.number)));
  }

  /// @dev Second squad on the fork with an empty crew roster (no `bootstrapCrew`).
  function _deployFreshSquadWithoutBootstrap(uint256 _saltNonce)
    internal
    returns (
      Quartermaster _qm,
      MutinyModule _mutiny,
      TreasuryAuthority _ta,
      address _captain,
      uint256 _crewHatId,
      uint256 _topHatId
    )
  {
    _captain = makeAddr(string(abi.encodePacked('e2eQmCaptain', _saltNonce)));
    _fund(_captain, 50 ether);

    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: _captain,
      metadataURI: string(abi.encodePacked('ipfs://integration-qm-squad-', _saltNonce)),
      squadParams: _squadParamsProduction(),
      quartermasterMasterCopy: _masters.quartermaster,
      mutinyMasterCopy: _masters.mutinyModule,
      treasuryAuthorityMasterCopy: _masters.treasuryAuthority,
      squadAdminImplementation: _masters.squadAdminImpl,
      saltNonce: _saltNonce
    });

    _fund(address(this), 200 ether);
    (uint256 _topHat,, address _qmAddr, address _mmAddr, address _taAddr,) =
      NavePirataFactory(_infra.navePirataFactory).deployNavePirata(_p);

    _topHatId = _topHat;
    _qm = Quartermaster(_qmAddr);
    _mutiny = MutinyModule(_mmAddr);
    _ta = TreasuryAuthority(payable(_taAddr));
    _crewHatId = NavePirataRegistry(_infra.registry).deployment(_topHat).crewHatId;
  }

  /// @dev One-shot bootstrap on a fresh squad clone.
  function _bootstrapCrewBatch(Quartermaster _qm, address _captain, address[] memory _crew) internal {
    vm.prank(_captain);
    _qm.bootstrapCrew(_crew);
  }

  function _bootstrapOneCrew(Quartermaster _qm, address _captain, address _crew) internal {
    address[] memory _batch = new address[](1);
    _batch[0] = _crew;
    _bootstrapCrewBatch(_qm, _captain, _batch);
  }

  /// @dev Captain schedules a crew add on `_qm`.
  function _captainRequestAddCrew(Quartermaster _qm, address _captain, address _candidate) internal {
    vm.prank(_captain);
    _qm.requestAddCrew(_candidate);
  }

  /// @dev Captain schedules a crew removal on `_qm`.
  function _captainRequestRemoveCrew(Quartermaster _qm, address _captain, address _crew) internal {
    vm.prank(_captain);
    _qm.requestRemoveCrew(_crew);
  }

  /// @dev Advances time by the clone's configured `crewChangeDelay`.
  function _warpPastCrewChangeDelay(Quartermaster _qm) internal {
    vm.warp(block.timestamp + _qm.crewChangeDelay());
  }

  /// @dev Warps to `pendingCrewAddAt` when still in the future.
  function _warpToPendingAddExecutable(Quartermaster _qm, address _candidate) internal {
    uint256 _eta = _qm.pendingCrewAddAt(_candidate);
    if (_eta > block.timestamp) vm.warp(_eta);
  }

  /// @dev Warps to `pendingCrewRemoveAt` when still in the future.
  function _warpToPendingRemoveExecutable(Quartermaster _qm, address _crew) internal {
    uint256 _eta = _qm.pendingCrewRemoveAt(_crew);
    if (_eta > block.timestamp) vm.warp(_eta);
  }

  /// @dev Opens a mutiny round on the deployed squad when QM is not already frozen.
  function _ensureSquadMutinyActive() internal returns (uint256 _mutinyId) {
    if (!_squadQuartermaster.mutinyActive()) {
      vm.prank(_squadCrew[0]);
      _squadMutiny.startMutinyToArbitraryEoa(_squadProposedCaptain);
    }
    _mutinyId = _squadMutiny.activeMutinyId();
  }

  /// @dev MutinyRole-gated toggle without going through vote flow (fresh squads with no crew yet).
  function _setMutinyActiveViaModule(MutinyModule _mutiny, bool _active) internal {
    vm.prank(address(_mutiny));
    Quartermaster(_mutiny.quartermaster()).setMutinyActive(_active);
  }

  function _isCrewWearer(uint256 _crewHatId, address _who) internal view returns (bool _wears) {
    _wears = IHats(HATS_PROTOCOL_V1).isWearerOfHat(_who, _crewHatId);
  }

  function _crewHatSupply(uint256 _crewHatId) internal view returns (uint32 _supply) {
    _supply = IHats(HATS_PROTOCOL_V1).hatSupply(_crewHatId);
  }

  function _crewHatMaxSupply(uint256 _crewHatId) internal view returns (uint32 _max) {
    _max = IHats(HATS_PROTOCOL_V1).getHatMaxSupply(_crewHatId);
  }

  function _registryDeployment(uint256 _topHatId) internal view returns (INavePirataRegistry.Deployment memory _d) {
    _d = NavePirataRegistry(_infra.registry).deployment(_topHatId);
  }

  function _belowMinCrewChangeDelay() internal pure returns (uint256 _v) {
    _v = 30 seconds;
  }

  function _aboveMaxCrewChangeDelay() internal pure returns (uint256 _v) {
    _v = 61 days;
  }

  function _validAlternateCrewChangeDelay() internal pure returns (uint256 _v) {
    _v = 14 days;
  }
}

/**
 * @title E2EQuartermasterTest
 * @author Pacto
 * @notice Forked E2E for `Quartermaster` / `IQuartermaster`. Categories mirror public API groupings;
 *         empty bodies are intentional until step 3.
 */
contract E2EQuartermasterTest is E2EQuartermasterBase {
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

  function test_e2e_requestAddCrew_succeeds_schedulesFullDelay_whenCrewAlreadyExists()
    public
    withDeployedNavePirataSquad
  {}

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
