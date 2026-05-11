// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';

import {IMutinyModule} from 'interfaces/core/IMutinyModule.sol';
import {IRoleHatClonesFactory} from 'interfaces/factory/IRoleHatClonesFactory.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2EMutinyModuleBase
 * @author Pacto
 * @notice Mutiny-specific fixtures: modifiers deploy via `NavePirataFactory`, onboard crew through `Quartermaster`,
 *         then advance mutiny state on the mainnet fork from `IntegrationBase`.
 */
abstract contract E2EMutinyModuleBase is IntegrationBase {
  uint256 internal _squadActiveMutinyId;

  bool internal _fixtureHasOpenRound;
  bool internal _fixtureHasVoteMajority;

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

  function test_e2e_captainResign_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

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
