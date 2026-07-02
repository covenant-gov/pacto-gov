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
    _c = makeAddr(string(abi.encodePacked(_label, block.timestamp, block.number)));
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
  function _setMutinyActiveViaModule(MutinyModule _mutiny, Quartermaster _qm, bool _active) internal {
    vm.prank(address(_mutiny));
    _qm.setMutinyActive(_active);
  }

  function _isCrewWearer(uint256 _crewHatId, address _who) internal view returns (bool _wears) {
    _wears = IHats(HATS_PROTOCOL_V1).isWearerOfHat(_who, _crewHatId);
  }

  function _crewHatSupply(uint256 _crewHatId) internal view returns (uint32 _supply) {
    _supply = IHats(HATS_PROTOCOL_V1).hatSupply(_crewHatId);
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

  /// @dev Crew hat admin is the QM clone (wears `quartermasterRoleHatId`).
  function _setCrewHatMaxSupplyViaQm(Quartermaster _qm, uint256 _crewHatId, uint32 _max) internal {
    vm.prank(address(_qm));
    IHats(HATS_PROTOCOL_V1).changeHatMaxSupply(_crewHatId, _max);
  }

  /// @dev Pins max supply to the live wearer count so the next mint request hits `Quartermaster_CrewFull`.
  function _pinCrewHatAtCapacity(Quartermaster _qm, uint256 _crewHatId) internal {
    _setCrewHatMaxSupplyViaQm(_qm, _crewHatId, _crewHatSupply(_crewHatId));
  }
}

/**
 * @title E2EQuartermasterTest
 * @author Pacto
 * @notice Forked E2E for `Quartermaster` / `IQuartermaster`. Categories mirror public API groupings.
 */
contract E2EQuartermasterTest is E2EQuartermasterBase {
  /*///////////////////////////////////////////////////////////////
                        initialize
  //////////////////////////////////////////////////////////////*/

  function test_e2e_initialize_reverts_whenAlreadyInitialized() public withDeployedNavePirataSquad {
    Quartermaster _clone = _newQmClone();
    IQuartermaster.InitParams memory _p = _baselineQmInit();
    _clone.initialize(_p);

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _clone.initialize(_p);
  }

  function test_e2e_initialize_reverts_whenCrewChangeDelayBelowMin() public withDeployedNavePirataSquad {
    Quartermaster _clone = _newQmClone();
    IQuartermaster.InitParams memory _p = _baselineQmInit();
    _p.crewChangeDelay = _belowMinCrewChangeDelay();

    vm.expectRevert(
      abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, _belowMinCrewChangeDelay(), 60, 60 days)
    );
    _clone.initialize(_p);
  }

  function test_e2e_initialize_reverts_whenCrewChangeDelayAboveMax() public withDeployedNavePirataSquad {
    Quartermaster _clone = _newQmClone();
    IQuartermaster.InitParams memory _p = _baselineQmInit();
    _p.crewChangeDelay = _aboveMaxCrewChangeDelay();

    vm.expectRevert(
      abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, _aboveMaxCrewChangeDelay(), 60, 60 days)
    );
    _clone.initialize(_p);
  }

  /*///////////////////////////////////////////////////////////////
                        clone / wiring (factory deploy)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_quartermaster_cloneFromFactory_matchesRegistryDeployment() public withDeployedNavePirataSquad {
    INavePirataRegistry.Deployment memory _d = _registryDeployment(_squadTopHatId);
    assertEq(address(_squadQuartermaster), _d.quartermaster);
    assertGt(address(_squadQuartermaster).code.length, 0);
  }

  function test_e2e_quartermaster_hatIds_matchRegistryRecord() public withDeployedNavePirataSquad {
    INavePirataRegistry.Deployment memory _d = _registryDeployment(_squadTopHatId);
    assertEq(_squadQuartermaster.captainHatId(), _d.captainHatId);
    assertEq(_squadQuartermaster.crewHatId(), _d.crewHatId);
    assertEq(_squadQuartermaster.mutinyRoleHatId(), _d.mutinyRoleHatId);
    assertEq(_squadQuartermaster.quartermasterRoleHatId(), _d.quartermasterRoleHatId);
    assertEq(_squadQuartermaster.treasuryAuthorityRoleHatId(), _d.treasuryAuthorityRoleHatId);
  }

  function test_e2e_quartermaster_crewChangeDelay_matchesProductionDefault() public withDeployedNavePirataSquad {
    assertEq(_squadQuartermaster.crewChangeDelay(), CREW_CHANGE_DELAY);
  }

  /*///////////////////////////////////////////////////////////////
                        requestAddCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_requestAddCrew_succeeds_emitsAndStoresPending() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmAddPending');
    uint256 _expectedEta = block.timestamp + CREW_CHANGE_DELAY;

    vm.expectEmit(true, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewAddRequested(_candidate, _expectedEta);
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);

    assertEq(_squadQuartermaster.pendingCrewAddAt(_candidate), _expectedEta);
    assertFalse(_squadQuartermaster.isQuiet());
  }

  function test_e2e_requestAddCrew_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    address _stranger = _qmLabeledAddr('e2eQmAddNotCaptain');
    address _candidate = _qmCandidate('e2eQmAddNotCaptainTarget');

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadQuartermaster.captainHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadQuartermaster.requestAddCrew(_candidate);
  }

  function test_e2e_requestAddCrew_reverts_whenMutinyActive() public withDeployedNavePirataSquad {
    _ensureSquadMutinyActive();
    address _candidate = _qmCandidate('e2eQmAddMutiny');

    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
  }

  function test_e2e_requestAddCrew_reverts_whenCandidateIsZero() public withDeployedNavePirataSquad {
    vm.expectRevert(IQuartermaster.Quartermaster_ZeroAddress.selector);
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, address(0));
  }

  function test_e2e_requestAddCrew_reverts_whenCandidateIsCaptain() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_CandidateIsCaptain.selector, _squadCaptain));
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _squadCaptain);
  }

  function test_e2e_requestAddCrew_reverts_whenCandidateAlreadyWearsCrewHat() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _squadCrew[0]));
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _squadCrew[0]);
  }

  function test_e2e_requestAddCrew_reverts_whenDuplicatePendingAdd() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmDupAdd');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_DuplicateCrewAdd.selector, _candidate));
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
  }

  function test_e2e_requestAddCrew_reverts_whenCrewFull() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmAddCrewFull');
    _pinCrewHatAtCapacity(_squadQuartermaster, _squadCrewHatId);

    vm.expectRevert(IQuartermaster.Quartermaster_CrewFull.selector);
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
  }

  function test_e2e_requestAddCrew_succeeds_schedulesFullDelay_whenCrewAlreadyExists()
    public
    withDeployedNavePirataSquad
  {
    address _candidate = _qmCandidate('e2eQmAddFullDelay');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
    assertEq(_squadQuartermaster.pendingCrewAddAt(_candidate), block.timestamp + CREW_CHANGE_DELAY);
  }

  /*///////////////////////////////////////////////////////////////
                        cancelAddCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_cancelAddCrew_succeeds_clearsPendingAndEmits() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmCancelAdd');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);

    vm.expectEmit(true, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewAddCancelled(_candidate);
    vm.prank(_squadCaptain);
    _squadQuartermaster.cancelAddCrew(_candidate);

    assertEq(_squadQuartermaster.pendingCrewAddAt(_candidate), 0);
    assertTrue(_squadQuartermaster.isQuiet());
  }

  function test_e2e_cancelAddCrew_reverts_whenNoPendingAdd() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmCancelAddNone');

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotPending.selector, _candidate));
    vm.prank(_squadCaptain);
    _squadQuartermaster.cancelAddCrew(_candidate);
  }

  function test_e2e_cancelAddCrew_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmCancelAddNotCaptain');
    address _stranger = _qmLabeledAddr('e2eQmCancelAddStranger');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadQuartermaster.captainHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadQuartermaster.cancelAddCrew(_candidate);
  }

  /*///////////////////////////////////////////////////////////////
                        executeAddCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_executeAddCrew_succeeds_mintsCrewHatAndEmits() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmExecAdd');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
    _warpToPendingAddExecutable(_squadQuartermaster, _candidate);

    vm.expectEmit(true, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewAddExecuted(_candidate);
    _squadQuartermaster.executeAddCrew(_candidate);

    assertTrue(_isCrewWearer(_squadCrewHatId, _candidate));
    (bool _eligible,) = _squadQuartermaster.getWearerStatus(_candidate, _squadCrewHatId);
    assertTrue(_eligible);
    assertEq(_squadQuartermaster.pendingCrewAddAt(_candidate), 0);
  }

  function test_e2e_executeAddCrew_reverts_whenNoPendingAdd() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmExecAddNone');

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotPending.selector, _candidate));
    _squadQuartermaster.executeAddCrew(_candidate);
  }

  function test_e2e_executeAddCrew_reverts_whenStillLocked() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmExecAddLocked');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
    uint256 _eta = _squadQuartermaster.pendingCrewAddAt(_candidate);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_StillLocked.selector, _candidate, _eta));
    _squadQuartermaster.executeAddCrew(_candidate);
  }

  function test_e2e_executeAddCrew_reverts_whenMutinyActive() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmExecAddMutiny');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
    _warpToPendingAddExecutable(_squadQuartermaster, _candidate);
    _ensureSquadMutinyActive();

    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _squadQuartermaster.executeAddCrew(_candidate);
  }

  function test_e2e_executeAddCrew_reverts_whenCandidateAlreadyCrewAtExecuteTime() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmExecAddAlreadyCrew');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
    _warpToPendingAddExecutable(_squadQuartermaster, _candidate);

    vm.prank(address(_squadMutiny));
    _squadQuartermaster.mintCrewFromMutiny(_candidate);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _candidate));
    _squadQuartermaster.executeAddCrew(_candidate);
  }

  /*///////////////////////////////////////////////////////////////
                        bootstrapCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_bootstrapCrew_succeeds_mintsMultipleImmediately() public {
    (Quartermaster _qm,,, address _captain, uint256 _crewHatId,) = _deployFreshSquadWithoutBootstrap(_FRESH_SQUAD_SALT);
    address _alice = _qmCandidate('e2eQmBootstrapAlice');
    address _bob = _qmCandidate('e2eQmBootstrapBob');

    address[] memory _batch = new address[](2);
    _batch[0] = _alice;
    _batch[1] = _bob;

    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewAddExecuted(_alice);
    vm.expectEmit(true, false, false, true, address(_qm));
    emit IQuartermaster.CrewAddExecuted(_bob);
    _bootstrapCrewBatch(_qm, _captain, _batch);

    assertTrue(_isCrewWearer(_crewHatId, _alice));
    assertTrue(_isCrewWearer(_crewHatId, _bob));
    (bool _aOk,) = _qm.getWearerStatus(_alice, _crewHatId);
    (bool _bOk,) = _qm.getWearerStatus(_bob, _crewHatId);
    assertTrue(_aOk);
    assertTrue(_bOk);
    assertTrue(_qm.isQuiet());
  }

  function test_e2e_bootstrapCrew_reverts_whenCallerDoesNotWearCaptainHat() public {
    (Quartermaster _qm,,,,,) = _deployFreshSquadWithoutBootstrap(_FRESH_SQUAD_SALT);
    address _stranger = _qmLabeledAddr('e2eQmBootstrapNotCaptain');
    address _candidate = _qmCandidate('e2eQmBootstrapTarget');

    address[] memory _batch = new address[](1);
    _batch[0] = _candidate;

    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _qm.captainHatId(), _stranger));
    vm.prank(_stranger);
    _qm.bootstrapCrew(_batch);
  }

  function test_e2e_bootstrapCrew_reverts_whenMutinyActive() public {
    (Quartermaster _qm, MutinyModule _mutiny,, address _captain,,) =
      _deployFreshSquadWithoutBootstrap(_FRESH_SQUAD_SALT + 1);
    _setMutinyActiveViaModule(_mutiny, _qm, true);

    address _candidate = _qmCandidate('e2eQmBootstrapMutiny');
    address[] memory _batch = new address[](1);
    _batch[0] = _candidate;

    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    vm.prank(_captain);
    _qm.bootstrapCrew(_batch);
  }

  function test_e2e_bootstrapCrew_reverts_whenCrewAlreadyExists() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmBootstrapNonEmpty');
    address[] memory _batch = new address[](1);
    _batch[0] = _candidate;

    vm.expectRevert(IQuartermaster.Quartermaster_BootstrapRequiresEmptyCrew.selector);
    vm.prank(_squadCaptain);
    _squadQuartermaster.bootstrapCrew(_batch);
  }

  function test_e2e_bootstrapCrew_reverts_whenCandidatesEmpty() public {
    (Quartermaster _qm,,, address _captain,,) = _deployFreshSquadWithoutBootstrap(_FRESH_SQUAD_SALT + 2);
    address[] memory _batch = new address[](0);

    vm.expectRevert(IQuartermaster.Quartermaster_BootstrapEmpty.selector);
    vm.prank(_captain);
    _qm.bootstrapCrew(_batch);
  }

  function test_e2e_bootstrapCrew_reverts_whenMoreCandidatesThanMaxSupply() public {
    (Quartermaster _qm,,, address _captain, uint256 _crewHatId,) =
      _deployFreshSquadWithoutBootstrap(_FRESH_SQUAD_SALT + 3);
    _setCrewHatMaxSupplyViaQm(_qm, _crewHatId, 3);

    address[] memory _batch = new address[](4);
    _batch[0] = _qmCandidate('e2eQmBootstrapOver0');
    _batch[1] = _qmCandidate('e2eQmBootstrapOver1');
    _batch[2] = _qmCandidate('e2eQmBootstrapOver2');
    _batch[3] = _qmCandidate('e2eQmBootstrapOver3');

    vm.expectRevert(IQuartermaster.Quartermaster_CrewFull.selector);
    vm.prank(_captain);
    _qm.bootstrapCrew(_batch);
  }

  function test_e2e_bootstrapCrew_reverts_whenSameCandidateListedTwice() public {
    (Quartermaster _qm,,, address _captain,,) = _deployFreshSquadWithoutBootstrap(_FRESH_SQUAD_SALT + 4);
    address _alice = _qmCandidate('e2eQmBootstrapDupAlice');

    address[] memory _batch = new address[](2);
    _batch[0] = _alice;
    _batch[1] = _alice;

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _alice));
    vm.prank(_captain);
    _qm.bootstrapCrew(_batch);
  }

  /*///////////////////////////////////////////////////////////////
                        requestRemoveCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_requestRemoveCrew_succeeds_emitsAndStoresPending() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[4];
    uint256 _expectedEta = block.timestamp + CREW_CHANGE_DELAY;

    vm.expectEmit(true, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewRemoveRequested(_crew, _expectedEta);
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);

    assertEq(_squadQuartermaster.pendingCrewRemoveAt(_crew), _expectedEta);
    assertFalse(_squadQuartermaster.isQuiet());
  }

  function test_e2e_requestRemoveCrew_reverts_whenMutinyActive() public withDeployedNavePirataSquad {
    _ensureSquadMutinyActive();

    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _squadCrew[0]);
  }

  function test_e2e_requestRemoveCrew_reverts_whenTargetIsZero() public withDeployedNavePirataSquad {
    vm.expectRevert(IQuartermaster.Quartermaster_ZeroAddress.selector);
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, address(0));
  }

  function test_e2e_requestRemoveCrew_reverts_whenTargetDoesNotWearCrewHat() public withDeployedNavePirataSquad {
    address _stranger = _qmLabeledAddr('e2eQmRemoveNotCrew');

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotCrew.selector, _stranger));
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _stranger);
  }

  function test_e2e_requestRemoveCrew_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    address _stranger = _qmLabeledAddr('e2eQmRemoveNotCaptain');

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadQuartermaster.captainHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadQuartermaster.requestRemoveCrew(_squadCrew[0]);
  }

  /*///////////////////////////////////////////////////////////////
                        cancelRemoveCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_cancelRemoveCrew_succeeds_clearsPendingAndEmits() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[3];
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);

    vm.expectEmit(true, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewRemoveCancelled(_crew);
    vm.prank(_squadCaptain);
    _squadQuartermaster.cancelRemoveCrew(_crew);

    assertEq(_squadQuartermaster.pendingCrewRemoveAt(_crew), 0);
    assertTrue(_squadQuartermaster.isQuiet());
  }

  function test_e2e_cancelRemoveCrew_reverts_whenNoPendingRemove() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotPending.selector, _squadCrew[0]));
    vm.prank(_squadCaptain);
    _squadQuartermaster.cancelRemoveCrew(_squadCrew[0]);
  }

  function test_e2e_cancelRemoveCrew_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[2];
    address _stranger = _qmLabeledAddr('e2eQmCancelRemoveNotCaptain');
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadQuartermaster.captainHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadQuartermaster.cancelRemoveCrew(_crew);
  }

  /*///////////////////////////////////////////////////////////////
                        executeRemoveCrew
  //////////////////////////////////////////////////////////////*/

  function test_e2e_executeRemoveCrew_succeeds_revokesCrewHatAndEmits() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[4];
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);
    _warpToPendingRemoveExecutable(_squadQuartermaster, _crew);

    vm.expectEmit(true, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewRemoveExecuted(_crew);
    _squadQuartermaster.executeRemoveCrew(_crew);

    assertFalse(_isCrewWearer(_squadCrewHatId, _crew));
    (bool _eligible,) = _squadQuartermaster.getWearerStatus(_crew, _squadCrewHatId);
    assertFalse(_eligible);
    assertEq(_squadQuartermaster.pendingCrewRemoveAt(_crew), 0);
  }

  function test_e2e_executeRemoveCrew_reverts_whenNoPendingRemove() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotPending.selector, _squadCrew[0]));
    _squadQuartermaster.executeRemoveCrew(_squadCrew[0]);
  }

  function test_e2e_executeRemoveCrew_reverts_whenStillLocked() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[1];
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);
    uint256 _eta = _squadQuartermaster.pendingCrewRemoveAt(_crew);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_StillLocked.selector, _crew, _eta));
    _squadQuartermaster.executeRemoveCrew(_crew);
  }

  function test_e2e_executeRemoveCrew_reverts_whenMutinyActive() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[1];
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);
    _warpToPendingRemoveExecutable(_squadQuartermaster, _crew);
    _ensureSquadMutinyActive();

    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _squadQuartermaster.executeRemoveCrew(_crew);
  }

  function test_e2e_executeRemoveCrew_reverts_whenTargetAlreadyNonCrew() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[2];
    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);
    _warpToPendingRemoveExecutable(_squadQuartermaster, _crew);

    vm.prank(_crew);
    IHats(HATS_PROTOCOL_V1).renounceHat(_squadCrewHatId);

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotCrew.selector, _crew));
    _squadQuartermaster.executeRemoveCrew(_crew);
  }

  /*///////////////////////////////////////////////////////////////
                        mutiny hooks (MutinyRole-gated)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_mintCrewFromMutiny_succeeds_whenCalledByMutinyModule() public withDeployedNavePirataSquad {
    address _formerCaptain = _qmCandidate('e2eQmMintFromMutiny');

    vm.expectEmit(true, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewMintedFromMutiny(_formerCaptain);
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.mintCrewFromMutiny(_formerCaptain);

    assertTrue(_isCrewWearer(_squadCrewHatId, _formerCaptain));
    (bool _eligible,) = _squadQuartermaster.getWearerStatus(_formerCaptain, _squadCrewHatId);
    assertTrue(_eligible);
  }

  function test_e2e_mintCrewFromMutiny_reverts_whenCallerDoesNotWearMutinyRoleHat() public withDeployedNavePirataSquad {
    address _stranger = _qmLabeledAddr('e2eQmMintNotMutiny');

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadQuartermaster.mutinyRoleHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadQuartermaster.mintCrewFromMutiny(_stranger);
  }

  function test_e2e_mintCrewFromMutiny_reverts_whenFormerCaptainIsZero() public withDeployedNavePirataSquad {
    vm.expectRevert(IQuartermaster.Quartermaster_ZeroAddress.selector);
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.mintCrewFromMutiny(address(0));
  }

  function test_e2e_mintCrewFromMutiny_reverts_whenFormerCaptainAlreadyCrew() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _squadCrew[0]));
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.mintCrewFromMutiny(_squadCrew[0]);
  }

  function test_e2e_mintCrewFromMutiny_reverts_whenCrewFull() public withDeployedNavePirataSquad {
    address _formerCaptain = _qmCandidate('e2eQmMintCrewFull');
    _pinCrewHatAtCapacity(_squadQuartermaster, _squadCrewHatId);

    vm.expectRevert(IQuartermaster.Quartermaster_CrewFull.selector);
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.mintCrewFromMutiny(_formerCaptain);
  }

  function test_e2e_crewHandoffForMutiny_succeeds_whenCalledByMutinyModule() public withDeployedNavePirataSquad {
    address _formerCaptain = _squadCaptain;
    address _newCaptain = _squadCrew[0];

    vm.expectEmit(true, true, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewHandoffForMutiny(_formerCaptain, _newCaptain);
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.crewHandoffForMutiny(_formerCaptain, _newCaptain);

    assertTrue(_isCrewWearer(_squadCrewHatId, _formerCaptain));
    assertFalse(_isCrewWearer(_squadCrewHatId, _newCaptain));
    (bool _eligible,) = _squadQuartermaster.getWearerStatus(_formerCaptain, _squadCrewHatId);
    assertTrue(_eligible);
  }

  function test_e2e_crewHandoffForMutiny_reverts_whenCallerDoesNotWearMutinyRoleHat()
    public
    withDeployedNavePirataSquad
  {
    address _stranger = _qmLabeledAddr('e2eQmHandoffNotMutiny');

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadQuartermaster.mutinyRoleHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadQuartermaster.crewHandoffForMutiny(_squadCaptain, _squadCrew[0]);
  }

  function test_e2e_crewHandoffForMutiny_reverts_whenFormerCaptainIsZero() public withDeployedNavePirataSquad {
    vm.expectRevert(IQuartermaster.Quartermaster_ZeroAddress.selector);
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.crewHandoffForMutiny(address(0), _squadCrew[0]);
  }

  function test_e2e_crewHandoffForMutiny_reverts_whenNewCaptainDoesNotWearCrewHat() public withDeployedNavePirataSquad {
    address _notCrew = _qmLabeledAddr('e2eQmHandoffNotCrew');

    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_NotCrew.selector, _notCrew));
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.crewHandoffForMutiny(_squadCaptain, _notCrew);
  }

  function test_e2e_crewHandoffForMutiny_reverts_whenFormerCaptainAlreadyCrew() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IQuartermaster.Quartermaster_AlreadyCrew.selector, _squadCrew[1]));
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.crewHandoffForMutiny(_squadCrew[1], _squadCrew[0]);
  }

  function test_e2e_setMutinyActive_succeeds_togglesFlagAndEmits() public withDeployedNavePirataSquad {
    vm.expectEmit(false, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.MutinyActiveSet(true);
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.setMutinyActive(true);
    assertTrue(_squadQuartermaster.mutinyActive());
    assertFalse(_squadQuartermaster.isQuiet());

    vm.expectEmit(false, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.MutinyActiveSet(false);
    vm.prank(address(_squadMutiny));
    _squadQuartermaster.setMutinyActive(false);
    assertFalse(_squadQuartermaster.mutinyActive());
    assertTrue(_squadQuartermaster.isQuiet());
  }

  function test_e2e_setMutinyActive_reverts_whenCallerDoesNotWearMutinyRoleHat() public withDeployedNavePirataSquad {
    address _stranger = _qmLabeledAddr('e2eQmSetMutinyNotRole');

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadQuartermaster.mutinyRoleHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadQuartermaster.setMutinyActive(true);
  }

  /*///////////////////////////////////////////////////////////////
                        setCrewChangeDelay (TreasuryAuthorityRole-gated)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_setCrewChangeDelay_succeeds_whenCalledByTreasuryAuthority() public withDeployedNavePirataSquad {
    uint256 _newDelay = _validAlternateCrewChangeDelay();

    vm.expectEmit(false, false, false, true, address(_squadQuartermaster));
    emit IQuartermaster.CrewChangeDelayUpdated(CREW_CHANGE_DELAY, _newDelay);
    vm.prank(address(_squadTreasury));
    _squadQuartermaster.setCrewChangeDelay(_newDelay);

    assertEq(_squadQuartermaster.crewChangeDelay(), _newDelay);
  }

  function test_e2e_setCrewChangeDelay_reverts_whenCallerDoesNotWearTreasuryAuthorityRoleHat()
    public
    withDeployedNavePirataSquad
  {
    address _stranger = _qmLabeledAddr('e2eQmSetDelayNotTa');

    vm.expectRevert(
      abi.encodeWithSelector(
        HatGated.HatGated_NotHatWearer.selector, _squadQuartermaster.treasuryAuthorityRoleHatId(), _stranger
      )
    );
    vm.prank(_stranger);
    _squadQuartermaster.setCrewChangeDelay(_validAlternateCrewChangeDelay());
  }

  function test_e2e_setCrewChangeDelay_reverts_whenValueOutOfRange() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(RangeValidator.RangeValidator_OutOfRange.selector, 0, 60, 60 days));
    vm.prank(address(_squadTreasury));
    _squadQuartermaster.setCrewChangeDelay(0);
  }

  /*///////////////////////////////////////////////////////////////
                        views / eligibility / isQuiet
  //////////////////////////////////////////////////////////////*/

  function test_e2e_getWearerStatus_defaultsIneligibleForNonCrew() public withDeployedNavePirataSquad {
    address _stranger = _qmLabeledAddr('e2eQmEligibilityDefault');

    (bool _eligible, bool _standing) = _squadQuartermaster.getWearerStatus(_stranger, _squadCrewHatId);
    assertFalse(_eligible);
    assertTrue(_standing);
  }

  function test_e2e_getWearerStatus_reflectsCrewMintAndRemoveCycle() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[4];

    (bool _eligibleBefore,) = _squadQuartermaster.getWearerStatus(_crew, _squadCrewHatId);
    assertTrue(_eligibleBefore);

    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);
    _warpToPendingRemoveExecutable(_squadQuartermaster, _crew);
    _squadQuartermaster.executeRemoveCrew(_crew);

    (bool _eligibleAfter,) = _squadQuartermaster.getWearerStatus(_crew, _squadCrewHatId);
    assertFalse(_eligibleAfter);
  }

  function test_e2e_isQuiet_falseWhenPendingAddOrRemove() public withDeployedNavePirataSquad {
    assertTrue(_squadQuartermaster.isQuiet());

    address _candidate = _qmCandidate('e2eQmQuietAdd');
    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
    assertFalse(_squadQuartermaster.isQuiet());

    vm.prank(_squadCaptain);
    _squadQuartermaster.cancelAddCrew(_candidate);
    assertTrue(_squadQuartermaster.isQuiet());

    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _squadCrew[3]);
    assertFalse(_squadQuartermaster.isQuiet());
  }

  function test_e2e_isQuiet_trueWhenNoPendingOperationsAndNoMutiny() public withDeployedNavePirataSquad {
    assertTrue(_squadQuartermaster.isQuiet());
    assertFalse(_squadQuartermaster.mutinyActive());
  }

  function test_e2e_pendingCrewAddAt_reflectsScheduledAdd() public withDeployedNavePirataSquad {
    address _candidate = _qmCandidate('e2eQmPendingAddAt');
    uint256 _expectedEta = block.timestamp + CREW_CHANGE_DELAY;

    _captainRequestAddCrew(_squadQuartermaster, _squadCaptain, _candidate);
    assertEq(_squadQuartermaster.pendingCrewAddAt(_candidate), _expectedEta);
  }

  function test_e2e_pendingCrewRemoveAt_reflectsScheduledRemove() public withDeployedNavePirataSquad {
    address _crew = _squadCrew[3];
    uint256 _expectedEta = block.timestamp + CREW_CHANGE_DELAY;

    _captainRequestRemoveCrew(_squadQuartermaster, _squadCaptain, _crew);
    assertEq(_squadQuartermaster.pendingCrewRemoveAt(_crew), _expectedEta);
  }

  /*///////////////////////////////////////////////////////////////
                        integration wiring
  //////////////////////////////////////////////////////////////*/

  function test_integration_registryUpgraderIsWiredAndQuartermasterMasterDeployed() public view {
    assertEq(NavePirataRegistry(_infra.registry).upgrader(), _infra.upgrader);
    Quartermaster _master = Quartermaster(_masters.quartermaster);
    assertGt(address(_master).code.length, 0);
  }

  function test_integration_quartermasterCloneMatchesRegistryDeployment() public withDeployedNavePirataSquad {
    assertEq(address(_squadQuartermaster), NavePirataRegistry(_infra.registry).deployment(_squadTopHatId).quartermaster);
  }
}

