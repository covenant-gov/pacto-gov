// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';

import {IMutinyModule} from 'interfaces/core/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';
import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {IRoleHatClonesFactory} from 'interfaces/factory/IRoleHatClonesFactory.sol';
import {CREW_CHANGE_DELAY} from 'script/Constants.sol';

import {IntegrationBase} from './IntegrationBase.sol';

/**
 * @title E2EMutinyModuleBase
 * @author Pacto
 * @notice Mutiny-specific fixtures: modifiers deploy via `NavePirataFactory`, onboard crew through `Quartermaster`,
 *         then advance mutiny state on the mainnet fork from `IntegrationBase`.
 */
abstract contract E2EMutinyModuleBase is IntegrationBase {
  MutinyModule internal _squadMutiny;
  Quartermaster internal _squadQuartermaster;
  address internal _squadSafe;
  uint256 internal _squadTopHatId;
  uint256 internal _squadCrewHatId;
  address internal _squadCaptain;
  address internal _squadProposedCaptain;
  address[] internal _squadCrew;
  uint256 internal _squadActiveMutinyId;

  bool internal _fixtureHasSquad;
  bool internal _fixtureHasOpenRound;
  bool internal _fixtureHasVoteMajority;

  modifier withDeployedNavePirataSquad() {
    _ensureSquad();
    _;
  }

  modifier withOpenMutinyRound() {
    _ensureSquad();
    _ensureOpenRound();
    _;
  }

  modifier withMutinyVotesAboveMajority() {
    _ensureSquad();
    _ensureOpenRound();
    _ensureVotesAboveMajority();
    _;
  }

  /// @dev Idempotent squad bootstrap: registry factory deploy, onboard five crew via timelock, exposes `_squad*` storage.
  function _ensureSquad() internal {
    if (_fixtureHasSquad) return;

    _squadCaptain = makeAddr('e2eSquadCaptain');
    _squadProposedCaptain = makeAddr('e2eProposedCaptain');
    _fund(_squadCaptain, 50 ether);
    _fund(_squadProposedCaptain, 1 ether);

    _squadCrew.push(makeAddr('e2eCrew0'));
    _squadCrew.push(makeAddr('e2eCrew1'));
    _squadCrew.push(makeAddr('e2eCrew2'));
    _squadCrew.push(makeAddr('e2eCrew3'));
    _squadCrew.push(makeAddr('e2eCrew4'));
    for (uint256 _i = 0; _i < _squadCrew.length; _i++) {
      _fund(_squadCrew[_i], 50 ether);
    }

    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: _squadCaptain,
      metadataURI: 'ipfs://e2e-mutiny-squad',
      squadParams: _squadParamsProduction(),
      quartermasterMasterCopy: _masters.quartermaster,
      mutinyMasterCopy: _masters.mutinyModule,
      treasuryAuthorityMasterCopy: _masters.treasuryAuthority,
      squadAdminImplementation: _masters.squadAdminImpl,
      saltNonce: _freshSquadSalt()
    });

    _fund(address(this), 200 ether);
    (uint256 _topHat,, address _qm, address _mm,,) = NavePirataFactory(_infra.navePirataFactory).deployNavePirata(_p);

    _squadTopHatId = _topHat;
    _squadQuartermaster = Quartermaster(_qm);
    _squadMutiny = MutinyModule(_mm);

    INavePirataRegistry.Deployment memory _d = NavePirataRegistry(_infra.registry).deployment(_topHat);
    _squadSafe = _d.safe;
    _squadCrewHatId = _d.crewHatId;

    vm.startPrank(_squadCaptain);
    for (uint256 _j = 0; _j < _squadCrew.length; _j++) {
      IQuartermaster(address(_squadQuartermaster)).requestAddCrew(_squadCrew[_j]);
    }
    vm.stopPrank();
    vm.warp(block.timestamp + CREW_CHANGE_DELAY + 1);
    for (uint256 _k = 0; _k < _squadCrew.length; _k++) {
      IQuartermaster(address(_squadQuartermaster)).executeAddCrew(_squadCrew[_k]);
    }

    _fixtureHasSquad = true;
  }

  /// @dev Opens one mutiny from `_squadCrew[0]` if not already running.
  function _ensureOpenRound() internal {
    if (_fixtureHasOpenRound) return;

    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutiny(_squadProposedCaptain);
    _squadActiveMutinyId = _squadMutiny.activeMutinyId();
    _fixtureHasOpenRound = true;
  }

  /// @dev Casts the minimum consecutive crew yeas needed for strict majority over the round snapshot (`yeas * 2 > snapshot`).
  function _ensureVotesAboveMajority() internal {
    if (_fixtureHasVoteMajority) return;

    (,, uint64 _snapshot,,) = _squadMutiny.mutiny(_squadActiveMutinyId);
    uint256 _minYeas = uint256(_snapshot) / 2 + 1;

    for (uint256 _i = 0; _i < _minYeas; _i++) {
      vm.prank(_squadCrew[_i]);
      _squadMutiny.castVote(_squadActiveMutinyId);
    }

    _fixtureHasVoteMajority = true;
  }
}

/**
 * @title E2EMutinyModuleTest
 * @author Pacto
 * @notice End-to-end scenarios for `MutinyModule` against real peer contracts. Function names follow
 *          branching in `MutinyModule` / `IMutinyModule`; empty bodies are intentional for a follow-up pass.
 */
contract E2EMutinyModuleTest is E2EMutinyModuleBase {
  /*///////////////////////////////////////////////////////////////
                        initialize
  //////////////////////////////////////////////////////////////*/

  function test_e2e_initialize_reverts_whenCaptainIsZero() public withDeployedNavePirataSquad {
    bytes32 _salt =
      keccak256(abi.encodePacked('test_e2e_initialize_reverts_whenCaptainIsZero', address(this), block.chainid));

    address _clone = IRoleHatClonesFactory(_infra.clonesFactory).createClone(_masters.mutinyModule, new bytes(0), _salt);

    IMutinyModule.InitParams memory _p = IMutinyModule.InitParams({
      captainHatId: _squadMutiny.captainHatId(),
      crewHatId: _squadMutiny.crewHatId(),
      mutinyRoleHatId: _squadMutiny.mutinyRoleHatId(),
      quartermasterRoleHatId: _squadMutiny.quartermasterRoleHatId(),
      captain: address(0),
      quartermaster: address(_squadQuartermaster)
    });

    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    MutinyModule(_clone).initialize(_p);
  }

  function test_e2e_initialize_reverts_whenQuartermasterIsZero() public withDeployedNavePirataSquad {}

  function test_e2e_initialize_reverts_whenAlreadyInitialized() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        startMutiny
  //////////////////////////////////////////////////////////////*/

  function test_e2e_startMutiny_reverts_whenCallerDoesNotWearCrewHat() public withDeployedNavePirataSquad {
    address _stranger = makeAddr('e2eStartMutinyStranger');

    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadCrewHatId, _stranger));
    vm.prank(_stranger);
    _squadMutiny.startMutiny(_squadProposedCaptain);
  }

  function test_e2e_startMutiny_reverts_whenProposedCaptainIsZero() public withDeployedNavePirataSquad {}

  function test_e2e_startMutiny_reverts_whenProposedCaptainIsCurrentCaptain() public withDeployedNavePirataSquad {}

  function test_e2e_startMutiny_reverts_whenMutinyAlreadyActive() public withDeployedNavePirataSquad {}

  function test_e2e_startMutiny_reverts_whenQuartermasterPeerIsStale() public withDeployedNavePirataSquad {}

  function test_e2e_startMutiny_reverts_whenCaptainCacheDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

  function test_e2e_startMutiny_succeeds_emitsAndFreezesQuartermaster() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        castVote
  //////////////////////////////////////////////////////////////*/

  function test_e2e_castVote_reverts_whenCallerDoesNotWearCrewHat()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {
    address _stranger = makeAddr('e2eCastVoteStranger');

    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadCrewHatId, _stranger));
    vm.prank(_stranger);
    _squadMutiny.castVote(_squadActiveMutinyId);
  }

  function test_e2e_castVote_reverts_whenMutinyIdIsZero() public withDeployedNavePirataSquad withOpenMutinyRound {}

  function test_e2e_castVote_reverts_whenMutinyIdIsNotActive() public withDeployedNavePirataSquad withOpenMutinyRound {}

  function test_e2e_castVote_reverts_whenVoterAlreadyVotedYea()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {}

  function test_e2e_castVote_succeeds_talliesYeaAndEmits() public withDeployedNavePirataSquad withOpenMutinyRound {}

  /*///////////////////////////////////////////////////////////////
                        executeMutiny
  //////////////////////////////////////////////////////////////*/

  function test_e2e_executeMutiny_reverts_whenMutinyIdIsZero() public withDeployedNavePirataSquad {
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _squadMutiny.executeMutiny(0);
  }

  function test_e2e_executeMutiny_reverts_whenMutinyIdNotActive() public withDeployedNavePirataSquad {}

  function test_e2e_executeMutiny_reverts_whenRoundAlreadyExecuted()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
    withMutinyVotesAboveMajority
  {}

  function test_e2e_executeMutiny_reverts_whenYeasDoNotExceedMajorityOfSnapshot()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {}

  function test_e2e_executeMutiny_reverts_whenCaptainCacheDoesNotMatchRoundFromCaptain()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
    withMutinyVotesAboveMajority
  {}

  function test_e2e_executeMutiny_succeeds_whenSuccessorIsEoaFormerCrewNotWearingCrewHat()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
    withMutinyVotesAboveMajority
  {}

  function test_e2e_executeMutiny_succeeds_whenSuccessorAlreadyWearsCrewHat()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
    withMutinyVotesAboveMajority
  {}

  function test_e2e_executeMutiny_succeeds_whenFormerCaptainIsContractSkipsCrewMint()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
    withMutinyVotesAboveMajority
  {}

  /*///////////////////////////////////////////////////////////////
                        captainResign
  //////////////////////////////////////////////////////////////*/

  function test_e2e_captainResign_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    address _stranger = makeAddr('e2eCaptainResignStranger');
    uint256 _captainHatId = _squadMutiny.captainHatId();

    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _captainHatId, _stranger));
    vm.prank(_stranger);
    _squadMutiny.captainResign(_squadProposedCaptain);
  }

  function test_e2e_captainResign_reverts_whenNewCaptainIsZero() public withDeployedNavePirataSquad {}

  function test_e2e_captainResign_reverts_whenNewCaptainIsCaller() public withDeployedNavePirataSquad {}

  function test_e2e_captainResign_reverts_whenMutinyAlreadyActive()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {}

  function test_e2e_captainResign_reverts_whenCaptainCacheNotMsgSender() public withDeployedNavePirataSquad {}

  function test_e2e_captainResign_succeeds_handoffToEoa() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        views / eligibility / isQuiet
  //////////////////////////////////////////////////////////////*/

  function test_e2e_getWearerStatus_eligibleOnlyForTrackedCaptain() public withDeployedNavePirataSquad {}

  function test_e2e_isQuiet_trueWhenNoMutiny_falseWhenRoundOpen()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {}

  function test_e2e_isInSnapshot_reflectsCurrentCrewWearershipDuringActiveRound()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {}

  /*///////////////////////////////////////////////////////////////
                        default deploy wiring
  //////////////////////////////////////////////////////////////*/

  function test_integration_registryFactoryIsWiredAndMutinyMasterDeployed() public view {
    assertEq(NavePirataRegistry(_infra.registry).factory(), _infra.navePirataFactory);
    MutinyModule _master = MutinyModule(_masters.mutinyModule);
    assertGt(address(_master).code.length, 0);
  }
}
