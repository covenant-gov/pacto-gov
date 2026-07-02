// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';
import {HatGated} from 'contracts/utils/HatGated.sol';

import {IMutinyModule} from 'interfaces/core/IMutinyModule.sol';
import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';
import {IRoleHatClonesFactory} from 'interfaces/factory/IRoleHatClonesFactory.sol';

import {DEPLOY_NAV_PIRATA_SALT_NONCE, HATS_PROTOCOL_V1} from 'script/Constants.sol';

import {IHats} from 'hats-core/Interfaces/IHats.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/// @dev Bytecode holder used as initial captain in contract-captain mutiny scenarios.
contract E2EContractCaptain {}

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

  /// @dev Fresh mutiny clone for init / revert scenarios.
  function _newMutinyClone() internal returns (MutinyModule _clone) {
    bytes32 _salt = keccak256(abi.encodePacked('e2eMutinyClone', address(this), block.timestamp, block.number));
    _clone =
      MutinyModule(IRoleHatClonesFactory(_infra.clonesFactory).createClone(_masters.mutinyModule, new bytes(0), _salt));
  }

  /// @dev Init params aligned with the deployed squad mutiny clone.
  function _baselineMutinyInit() internal view returns (IMutinyModule.InitParams memory _p) {
    _p = IMutinyModule.InitParams({
      captainHatId: _squadMutiny.captainHatId(),
      crewHatId: _squadMutiny.crewHatId(),
      mutinyRoleHatId: _squadMutiny.mutinyRoleHatId(),
      quartermasterRoleHatId: _squadMutiny.quartermasterRoleHatId(),
      captain: _squadCaptain,
      quartermaster: address(_squadQuartermaster),
      safe: _squadSafe
    });
  }

  /// @dev Opens one mutiny from `_squadCrew[0]` if not already running.
  function _ensureOpenRound() internal {
    if (_fixtureHasOpenRound) return;

    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryEoa(_squadProposedCaptain);
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

  /// @dev Casts exactly `_yeaCount` consecutive crew yeas on `_mutinyId`.
  function _castVotes(uint256 _mutinyId, uint256 _yeaCount) internal {
    for (uint256 _i = 0; _i < _yeaCount; _i++) {
      vm.prank(_squadCrew[_i]);
      _squadMutiny.castVote(_mutinyId);
    }
  }

  /// @dev Second squad on the fork with a custom initial captain (distinct salt from `_ensureSquad`).
  function _deployFreshSquadWithCaptain(
    address _captain,
    uint256 _saltNonce
  )
    internal
    returns (
      MutinyModule _mutiny,
      Quartermaster _qm,
      uint256 _crewHatId,
      address[] memory _crew,
      address _proposedCaptain
    )
  {
    _proposedCaptain = makeAddr(string(abi.encodePacked('e2eMutinyProposed', _saltNonce)));
    _fund(_proposedCaptain, 1 ether);
    _fund(_captain, 50 ether);

    _crew = new address[](5);
    for (uint256 _i = 0; _i < _crew.length; _i++) {
      _crew[_i] = makeAddr(string(abi.encodePacked('e2eMutinyCrew', _saltNonce, _i)));
      _fund(_crew[_i], 50 ether);
    }

    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: _captain,
      metadataURI: string(abi.encodePacked('ipfs://integration-mutiny-squad-', _saltNonce)),
      squadParams: _squadParamsProduction(),
      quartermasterMasterCopy: _masters.quartermaster,
      mutinyMasterCopy: _masters.mutinyModule,
      treasuryAuthorityMasterCopy: _masters.treasuryAuthority,
      squadAdminImplementation: _masters.squadAdminImpl,
      saltNonce: _saltNonce
    });

    _fund(address(this), 200 ether);
    (uint256 _topHat,, address _qmAddr, address _mmAddr,,) =
      NavePirataFactory(_infra.navePirataFactory).deployNavePirata(_p);

    _mutiny = MutinyModule(_mmAddr);
    _qm = Quartermaster(_qmAddr);
    _crewHatId = NavePirataRegistry(_infra.registry).deployment(_topHat).crewHatId;

    vm.prank(_captain);
    _qm.bootstrapCrew(_crew);
  }
}

/**
 * @title E2EMutinyModuleTest
 * @author Pacto
 * @notice Forked E2E for `MutinyModule`. Categories mirror `MutinyModule` / `IMutinyModule`: init, four
 *         `startMutinyTo*` entrypoints (plus shared `onlyHatWearer(crewHatId)` and `_mutinyCheck` / `_liveQuartermaster`),
 *         vote / execute / resign, views.
 */
contract E2EMutinyModuleTest is E2EMutinyModuleBase {
  /*///////////////////////////////////////////////////////////////
                        initialize
  //////////////////////////////////////////////////////////////*/

  function test_e2e_initialize_reverts_whenCaptainIsZero() public withDeployedNavePirataSquad {
    MutinyModule _clone = _newMutinyClone();
    IMutinyModule.InitParams memory _p = _baselineMutinyInit();
    _p.captain = address(0);

    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _clone.initialize(_p);
  }

  function test_e2e_initialize_reverts_whenQuartermasterIsZero() public withDeployedNavePirataSquad {
    MutinyModule _clone = _newMutinyClone();
    IMutinyModule.InitParams memory _p = _baselineMutinyInit();
    _p.quartermaster = address(0);

    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    _clone.initialize(_p);
  }

  function test_e2e_initialize_reverts_whenAlreadyInitialized() public withDeployedNavePirataSquad {
    IMutinyModule.InitParams memory _p = _baselineMutinyInit();

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _squadMutiny.initialize(_p);
  }

  /*///////////////////////////////////////////////////////////////
              mutiny start — onlyHatWearer(crewHatId)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_mutinyStart_reverts_whenCallerDoesNotWearCrewHat() public withDeployedNavePirataSquad {
    address _stranger = makeAddr('e2eMutinyStartStranger');

    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadCrewHatId, _stranger));
    vm.prank(_stranger);
    _squadMutiny.startMutinyToArbitraryEoa(_squadProposedCaptain);
  }

  /*///////////////////////////////////////////////////////////////
        mutiny start — _mutinyCheck / _liveQuartermaster (shared)
  //////////////////////////////////////////////////////////////*/

  function test_e2e_mutinyStart_reverts_whenProposedIsZero() public withDeployedNavePirataSquad {
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryEoa(address(0));
  }

  function test_e2e_mutinyStart_reverts_whenProposedIsCurrentCaptain() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_SameCaptain.selector, _squadCaptain));
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryEoa(_squadCaptain);
  }

  function test_e2e_mutinyStart_reverts_whenRoundAlreadyActive() public withDeployedNavePirataSquad {
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryEoa(_squadProposedCaptain);

    vm.expectRevert(IMutinyModule.MutinyModule_AlreadyActive.selector);
    vm.prank(_squadCrew[1]);
    _squadMutiny.startMutinyToArbitraryEoa(makeAddr('e2eMutinySecondTarget'));
  }

  function test_e2e_mutinyStart_reverts_whenQuartermasterPeerIsStale() public withDeployedNavePirataSquad {
    address _staleQm = makeAddr('e2eMutinyStaleQuartermaster');
    vm.store(address(_squadMutiny), bytes32(uint256(5)), bytes32(uint256(uint160(_staleQm))));

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleQuartermaster.selector, _staleQm));
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryEoa(_squadProposedCaptain);
  }

  function test_e2e_mutinyStart_reverts_whenCaptainDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    uint256 _captainHatId = _squadMutiny.captainHatId();
    vm.prank(_squadCaptain);
    IHats(HATS_PROTOCOL_V1).renounceHat(_captainHatId);

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleCaptain.selector, _squadCaptain));
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryEoa(makeAddr('e2eMutinyAfterHatMove'));
  }

  /*///////////////////////////////////////////////////////////////
                        startMutinyToCrewMember
  //////////////////////////////////////////////////////////////*/

  function test_e2e_startMutinyToCrewMember_reverts_whenProposedDoesNotWearCrewHat()
    public
    withDeployedNavePirataSquad
  {
    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadCrewHatId, _squadProposedCaptain)
    );
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToCrewMember(_squadProposedCaptain);
  }

  function test_e2e_startMutinyToCrewMember_succeeds_opensRound() public withDeployedNavePirataSquad {
    address _crewSuccessor = _squadCrew[2];
    uint64 _snapshot = uint64(IHats(HATS_PROTOCOL_V1).hatSupply(_squadCrewHatId));

    vm.expectEmit(true, true, true, true, address(_squadMutiny));
    emit IMutinyModule.MutinyStarted(1, _squadCrew[0], _crewSuccessor, _snapshot);

    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToCrewMember(_crewSuccessor);

    assertEq(_squadMutiny.activeMutinyId(), 1);
    (address _proposed,,,,) = _squadMutiny.mutiny(1);
    assertEq(_proposed, _crewSuccessor);
    assertTrue(_squadQuartermaster.mutinyActive());
  }

  /*///////////////////////////////////////////////////////////////
                        startMutinyToCommittee
  //////////////////////////////////////////////////////////////*/

  function test_e2e_startMutinyToCommittee_reverts_whenGetThresholdInvalid() public withDeployedNavePirataSquad {
    address _notCommittee = makeAddr('e2eMutinyNotCommittee');

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_NotContract.selector, _notCommittee));
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToCommittee(_notCommittee);
  }

  function test_e2e_startMutinyToCommittee_succeeds_opensRound() public withDeployedNavePirataSquad {
    uint64 _snapshot = uint64(IHats(HATS_PROTOCOL_V1).hatSupply(_squadCrewHatId));

    vm.expectEmit(true, true, true, true, address(_squadMutiny));
    emit IMutinyModule.MutinyStarted(1, _squadCrew[0], _squadSafe, _snapshot);

    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToCommittee(_squadSafe);

    (address _proposed,,,,) = _squadMutiny.mutiny(1);
    assertEq(_proposed, _squadSafe);
  }

  /*///////////////////////////////////////////////////////////////
                        startMutinyToArbitraryEoa
  //////////////////////////////////////////////////////////////*/

  function test_e2e_startMutinyToArbitraryEOA_reverts_whenProposedHasCode() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_NotEOA.selector, _squadSafe));
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryEoa(_squadSafe);
  }

  function test_e2e_startMutinyToArbitraryEOA_succeeds_emitsAndFreezesQuartermaster()
    public
    withDeployedNavePirataSquad
  {
    uint64 _snapshot = uint64(IHats(HATS_PROTOCOL_V1).hatSupply(_squadCrewHatId));

    vm.expectEmit(true, true, true, true, address(_squadMutiny));
    emit IMutinyModule.MutinyStarted(1, _squadCrew[0], _squadProposedCaptain, _snapshot);

    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryEoa(_squadProposedCaptain);

    assertEq(_squadMutiny.activeMutinyId(), 1);
    assertFalse(_squadMutiny.isQuiet());
    assertTrue(_squadQuartermaster.mutinyActive());

    (address _proposed, uint64 _startedAt, uint64 _storedSnapshot, uint64 _yeas, bool _executed) =
      _squadMutiny.mutiny(1);
    assertEq(_proposed, _squadProposedCaptain);
    assertEq(_startedAt, uint64(block.timestamp));
    assertEq(_storedSnapshot, _snapshot);
    assertEq(_yeas, 0);
    assertFalse(_executed);
  }

  /*///////////////////////////////////////////////////////////////
                    startMutinyToArbitraryContract
  //////////////////////////////////////////////////////////////*/

  function test_e2e_startMutinyToArbitraryContract_reverts_whenProposedIsEoa() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_NotContract.selector, _squadProposedCaptain));
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryContract(_squadProposedCaptain);
  }

  function test_e2e_startMutinyToArbitraryContract_succeeds_opensRound() public withDeployedNavePirataSquad {
    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToArbitraryContract(_squadSafe);

    (address _proposed,,,,) = _squadMutiny.mutiny(1);
    assertEq(_proposed, _squadSafe);
    assertEq(_squadMutiny.activeMutinyId(), 1);
  }

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

  function test_e2e_castVote_reverts_whenMutinyIdIsZero() public withDeployedNavePirataSquad withOpenMutinyRound {
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    vm.prank(_squadCrew[1]);
    _squadMutiny.castVote(0);
  }

  function test_e2e_castVote_reverts_whenMutinyIdIsNotActive() public withDeployedNavePirataSquad withOpenMutinyRound {
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    vm.prank(_squadCrew[1]);
    _squadMutiny.castVote(_squadActiveMutinyId + 1);
  }

  function test_e2e_castVote_reverts_whenVoterAlreadyVotedYea() public withDeployedNavePirataSquad withOpenMutinyRound {
    vm.prank(_squadCrew[0]);
    _squadMutiny.castVote(_squadActiveMutinyId);

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_AlreadyVoted.selector, _squadCrew[0]));
    vm.prank(_squadCrew[0]);
    _squadMutiny.castVote(_squadActiveMutinyId);
  }

  function test_e2e_castVote_succeeds_talliesYeaAndEmits() public withDeployedNavePirataSquad withOpenMutinyRound {
    vm.expectEmit(true, true, false, true, address(_squadMutiny));
    emit IMutinyModule.MutinyVoteCast(_squadActiveMutinyId, _squadCrew[1]);

    vm.prank(_squadCrew[1]);
    _squadMutiny.castVote(_squadActiveMutinyId);

    assertTrue(_squadMutiny.hasVoted(_squadActiveMutinyId, _squadCrew[1]));
    (,,, uint64 _yeas,) = _squadMutiny.mutiny(_squadActiveMutinyId);
    assertEq(_yeas, 1);
  }

  /*///////////////////////////////////////////////////////////////
                        executeMutiny
  //////////////////////////////////////////////////////////////*/

  function test_e2e_executeMutiny_reverts_whenMutinyIdIsZero() public withDeployedNavePirataSquad {
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _squadMutiny.executeMutiny(0);
  }

  function test_e2e_executeMutiny_reverts_whenMutinyIdNotActive() public withDeployedNavePirataSquad {
    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _squadMutiny.executeMutiny(42);
  }

  function test_e2e_executeMutiny_reverts_whenRoundAlreadyExecuted()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
    withMutinyVotesAboveMajority
  {
    _squadMutiny.executeMutiny(_squadActiveMutinyId);

    vm.expectRevert(IMutinyModule.MutinyModule_NoActiveMutiny.selector);
    _squadMutiny.executeMutiny(_squadActiveMutinyId);
  }

  function test_e2e_executeMutiny_reverts_whenYeasDoNotExceedMajorityOfSnapshot()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {
    _castVotes(_squadActiveMutinyId, 2);

    (,, uint64 _snapshot, uint64 _yeas,) = _squadMutiny.mutiny(_squadActiveMutinyId);
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_ThresholdNotReached.selector, _yeas, _snapshot));
    _squadMutiny.executeMutiny(_squadActiveMutinyId);
  }

  function test_e2e_executeMutiny_reverts_whenCaptainCacheDoesNotMatchRoundFromCaptain()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
    withMutinyVotesAboveMajority
  {
    vm.store(address(_squadMutiny), bytes32(uint256(4)), bytes32(uint256(uint160(_squadCrew[4]))));

    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_StaleCaptain.selector, _squadCaptain));
    _squadMutiny.executeMutiny(_squadActiveMutinyId);
  }

  function test_e2e_executeMutiny_succeeds_whenSuccessorIsEoaFormerCrewNotWearingCrewHat()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
    withMutinyVotesAboveMajority
  {
    assertFalse(IHats(HATS_PROTOCOL_V1).isWearerOfHat(_squadProposedCaptain, _squadCrewHatId));

    _squadMutiny.executeMutiny(_squadActiveMutinyId);

    assertEq(_squadMutiny.captain(), _squadProposedCaptain);
    assertEq(_squadMutiny.activeMutinyId(), 0);
    assertTrue(_squadMutiny.isQuiet());
    assertFalse(_squadQuartermaster.mutinyActive());
    assertTrue(IHats(HATS_PROTOCOL_V1).isWearerOfHat(_squadProposedCaptain, _squadMutiny.captainHatId()));
    assertTrue(IHats(HATS_PROTOCOL_V1).isWearerOfHat(_squadCaptain, _squadCrewHatId));
  }

  function test_e2e_executeMutiny_succeeds_whenSuccessorAlreadyWearsCrewHat() public withDeployedNavePirataSquad {
    address _crewSuccessor = _squadCrew[3];

    vm.prank(_squadCrew[0]);
    _squadMutiny.startMutinyToCrewMember(_crewSuccessor);
    uint256 _id = _squadMutiny.activeMutinyId();
    _castVotes(_id, 3);

    _squadMutiny.executeMutiny(_id);

    assertEq(_squadMutiny.captain(), _crewSuccessor);
    assertTrue(IHats(HATS_PROTOCOL_V1).isWearerOfHat(_crewSuccessor, _squadMutiny.captainHatId()));
    assertTrue(IHats(HATS_PROTOCOL_V1).isWearerOfHat(_squadCaptain, _squadCrewHatId));
  }

  function test_e2e_executeMutiny_succeeds_whenFormerCaptainIsContractSkipsCrewMint() public {
    E2EContractCaptain _contractCaptain = new E2EContractCaptain();
    (MutinyModule _mutiny, Quartermaster _qm,, address[] memory _crew, address _proposedCaptain) =
      _deployFreshSquadWithCaptain(address(_contractCaptain), DEPLOY_NAV_PIRATA_SALT_NONCE + 1);

    vm.prank(_crew[0]);
    _mutiny.startMutinyToArbitraryEoa(_proposedCaptain);
    uint256 _id = _mutiny.activeMutinyId();

    (,, uint64 _snapshot,,) = _mutiny.mutiny(_id);
    uint256 _minYeas = uint256(_snapshot) / 2 + 1;
    for (uint256 _i = 0; _i < _minYeas; _i++) {
      vm.prank(_crew[_i]);
      _mutiny.castVote(_id);
    }

    _mutiny.executeMutiny(_id);

    assertEq(_mutiny.captain(), _proposedCaptain);
    assertFalse(_qm.mutinyActive());
    assertFalse(IHats(HATS_PROTOCOL_V1).isWearerOfHat(address(_contractCaptain), _mutiny.crewHatId()));
  }

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

  function test_e2e_captainResign_reverts_whenNewCaptainIsZero() public withDeployedNavePirataSquad {
    vm.expectRevert(IMutinyModule.MutinyModule_ZeroAddress.selector);
    vm.prank(_squadCaptain);
    _squadMutiny.captainResign(address(0));
  }

  function test_e2e_captainResign_reverts_whenNewCaptainIsCaller() public withDeployedNavePirataSquad {
    vm.expectRevert(abi.encodeWithSelector(IMutinyModule.MutinyModule_SameCaptain.selector, _squadCaptain));
    vm.prank(_squadCaptain);
    _squadMutiny.captainResign(_squadCaptain);
  }

  function test_e2e_captainResign_reverts_whenMutinyAlreadyActive()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {
    vm.expectRevert(IMutinyModule.MutinyModule_AlreadyActive.selector);
    vm.prank(_squadCaptain);
    _squadMutiny.captainResign(_squadProposedCaptain);
  }

  function test_e2e_captainResign_reverts_whenCaptainCacheNotMsgSender() public withDeployedNavePirataSquad {
    vm.store(address(_squadMutiny), bytes32(uint256(4)), bytes32(uint256(uint160(_squadCrew[2]))));

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadMutiny.captainHatId(), _squadCaptain)
    );
    vm.prank(_squadCaptain);
    _squadMutiny.captainResign(_squadProposedCaptain);
  }

  function test_e2e_captainResign_succeeds_handoffToEoa() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    _squadMutiny.captainResign(_squadProposedCaptain);

    assertEq(_squadMutiny.captain(), _squadProposedCaptain);
    assertTrue(IHats(HATS_PROTOCOL_V1).isWearerOfHat(_squadProposedCaptain, _squadMutiny.captainHatId()));
    assertTrue(IHats(HATS_PROTOCOL_V1).isWearerOfHat(_squadCaptain, _squadCrewHatId));
  }

  /*///////////////////////////////////////////////////////////////
                        views / eligibility / isQuiet
  //////////////////////////////////////////////////////////////*/

  function test_e2e_getWearerStatus_eligibleOnlyForTrackedCaptain() public withDeployedNavePirataSquad {
    (bool _captainEligible, bool _captainStanding) =
      _squadMutiny.getWearerStatus(_squadCaptain, _squadMutiny.captainHatId());
    assertTrue(_captainEligible);
    assertTrue(_captainStanding);

    (bool _crewEligible,) = _squadMutiny.getWearerStatus(_squadCrew[0], _squadMutiny.captainHatId());
    assertFalse(_crewEligible);
  }

  function test_e2e_isQuiet_trueWhenNoMutiny_falseWhenRoundOpen() public withDeployedNavePirataSquad {
    assertTrue(_squadMutiny.isQuiet());
    _ensureOpenRound();
    assertFalse(_squadMutiny.isQuiet());
  }

  function test_e2e_isInSnapshot_reflectsCurrentCrewWearershipDuringActiveRound()
    public
    withDeployedNavePirataSquad
    withOpenMutinyRound
  {
    assertTrue(_squadMutiny.isInSnapshot(_squadActiveMutinyId, _squadCrew[1]));
    assertFalse(_squadMutiny.isInSnapshot(_squadActiveMutinyId, _squadProposedCaptain));
  }

  /*///////////////////////////////////////////////////////////////
                        default deploy wiring
  //////////////////////////////////////////////////////////////*/

  function test_integration_registryFactoryIsWiredAndMutinyMasterDeployed() public view {
    assertEq(NavePirataRegistry(_infra.registry).factory(), _infra.navePirataFactory);
    MutinyModule _master = MutinyModule(_masters.mutinyModule);
    assertGt(address(_master).code.length, 0);
  }
}
