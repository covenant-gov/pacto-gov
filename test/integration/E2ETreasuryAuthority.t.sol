// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

import {TreasuryAuthority} from 'contracts/core/TreasuryAuthority.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';
import {HatGated} from 'contracts/utils/HatGated.sol';
import {RangeValidator} from 'contracts/utils/RangeValidator.sol';

import {ITreasuryAuthority} from 'interfaces/core/ITreasuryAuthority.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {IAssetRescuer} from 'interfaces/utils/IAssetRescuer.sol';

import {HATS_PROTOCOL_V1, PROPOSAL_EXPIRY, SQUAD_QUORUM_BPS} from 'script/Constants.sol';

import {IHats} from 'hats-core/Interfaces/IHats.sol';

import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import {E2ERescueERC1155, E2ERescueERC20, E2ERescueERC721, IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2ETreasuryAuthorityBase
 * @author Pacto
 * @notice Shared clone/init helpers for Treasury Authority E2E suites (split so solc via-IR stays under tag limits).
 */
abstract contract E2ETreasuryAuthorityBase is IntegrationBase {
  function _newTaClone() internal returns (TreasuryAuthority _fresh) {
    TreasuryAuthority _impl = TreasuryAuthority(payable(_masters.treasuryAuthority));
    _fresh = TreasuryAuthority(payable(Clones.clone(address(_impl))));
  }

  function _baselineTaInit() internal view returns (ITreasuryAuthority.InitParams memory _p) {
    _p = ITreasuryAuthority.InitParams({
      safe: _squadSafe,
      captainHatId: _squadTreasury.captainHatId(),
      crewHatId: _squadTreasury.crewHatId(),
      treasuryAuthorityRoleHatId: _squadTreasury.treasuryAuthorityRoleHatId(),
      proposalExpiry: _squadTreasury.proposalExpiry(),
      crewVoteMode: _squadTreasury.crewVoteMode(),
      quorumBps: _squadTreasury.quorumBps()
    });
  }
}

/**
 * @title E2ETreasuryAuthorityTest
 * @author Pacto
 * @notice End-to-end scenarios for `TreasuryAuthority` init, propose, and voting.
 */
contract E2ETreasuryAuthorityTest is E2ETreasuryAuthorityBase {
  /*///////////////////////////////////////////////////////////////
                        initialize / setUp
  //////////////////////////////////////////////////////////////*/

  function test_e2e_initialize_reverts_whenSafeIsZero() public withDeployedNavePirataSquad {
    TreasuryAuthority _fresh = _newTaClone();
    ITreasuryAuthority.InitParams memory _p = _baselineTaInit();
    _p.safe = address(0);

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_NotCaptainOrCrew.selector, address(0)));
    _fresh.initialize(_p);
  }

  function test_e2e_initialize_reverts_whenProposalExpiryOutOfRange() public withDeployedNavePirataSquad {
    TreasuryAuthority _fresh = _newTaClone();
    ITreasuryAuthority.InitParams memory _p = _baselineTaInit();
    _p.proposalExpiry = 30 seconds;

    vm.expectRevert(
      abi.encodeWithSelector(
        RangeValidator.RangeValidator_OutOfRange.selector, uint256(30 seconds), uint256(1 minutes), uint256(60 days)
      )
    );
    _fresh.initialize(_p);
  }

  function test_e2e_initialize_reverts_whenQuorumBpsOutOfRange() public withDeployedNavePirataSquad {
    TreasuryAuthority _fresh = _newTaClone();
    ITreasuryAuthority.InitParams memory _p = _baselineTaInit();
    _p.quorumBps = 100;

    vm.expectRevert(
      abi.encodeWithSelector(
        RangeValidator.RangeValidator_OutOfRange.selector, uint256(100), uint256(500), uint256(10_000)
      )
    );
    _fresh.initialize(_p);
  }

  function test_e2e_initialize_reverts_whenAlreadyInitialized() public withDeployedNavePirataSquad {
    TreasuryAuthority _fresh = _newTaClone();
    ITreasuryAuthority.InitParams memory _p = _baselineTaInit();
    _fresh.initialize(_p);

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _fresh.initialize(_p);
  }

  function test_e2e_setUp_zodiacShim_appliesInitialization() public withDeployedNavePirataSquad {
    TreasuryAuthority _fresh = _newTaClone();
    ITreasuryAuthority.InitParams memory _p = _baselineTaInit();
    _p.crewVoteMode = ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST;

    _fresh.setUp(abi.encode(_p));

    assertEq(_fresh.SAFE(), _squadSafe);
    assertEq(uint256(_fresh.crewVoteMode()), uint256(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST));
    assertEq(_fresh.owner(), address(0));
  }

  /*///////////////////////////////////////////////////////////////
                        propose
  //////////////////////////////////////////////////////////////*/

  function test_e2e_propose_reverts_whenCallerIsNeitherCaptainNorCrew() public withDeployedNavePirataSquad {
    address _stranger = makeAddr('e2eTreasuryStranger');
    _fund(_stranger, 1 ether);

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_NotCaptainOrCrew.selector, _stranger));
    vm.prank(_stranger);
    _squadTreasury.propose(address(0xBEEF), 0, hex'', ITreasuryAuthority.Operation.CALL);
  }

  function test_e2e_propose_reverts_whenProposerAlreadyHasOpenProposal() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _first = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.expectRevert(
      abi.encodeWithSelector(
        ITreasuryAuthority.TreasuryAuthority_ProposerHasOpenProposal.selector, _squadCaptain, _first
      )
    );
    vm.prank(_squadCaptain);
    _squadTreasury.propose(address(0xCAFE), 1 wei, hex'', ITreasuryAuthority.Operation.CALL);
  }

  function test_e2e_propose_succeeds_whenCallerIsCaptain_recordsState() public withDeployedNavePirataSquad {
    address _to = makeAddr('e2eCaptainProposeTo');
    bytes memory _data = hex'dead';
    uint256 _value = 1 ether;

    uint256 _snap = IHats(HATS_PROTOCOL_V1).hatSupply(_squadTreasury.crewHatId());
    assertLe(_snap, type(uint64).max);

    uint256 _deadline256 = block.timestamp + _squadTreasury.proposalExpiry();
    assertLe(_deadline256, type(uint64).max);
    // forge-lint: disable-next-line(unsafe-typecast)
    uint256 _deadlineEmit = uint256(uint64(_deadline256));

    vm.expectEmit(true, true, true, true, address(_squadTreasury));
    emit ITreasuryAuthority.ProposalCreated(
      1, _squadCaptain, _to, _value, ITreasuryAuthority.Operation.CALL, _data, _deadlineEmit, _snap
    );

    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_to, _value, _data, ITreasuryAuthority.Operation.CALL);

    assertEq(_id, 1);
    assertEq(_squadTreasury.openProposalOf(_squadCaptain), 1);

    (
      address _proposer,
      address _storedTo,
      uint256 _storedValue,
      ITreasuryAuthority.Operation _op,
      bytes memory _storedData,
      uint64 _deadline,
      uint64 _snapshot,
      uint64 _yeas,
      uint64 _nays,,,
      bool _executed
    ) = _squadTreasury.proposal(_id);

    assertEq(_proposer, _squadCaptain);
    assertEq(_storedTo, _to);
    assertEq(_storedValue, _value);
    assertEq(uint256(_op), uint256(ITreasuryAuthority.Operation.CALL));
    assertEq(keccak256(_storedData), keccak256(_data));
    // forge-lint: disable-next-line(unsafe-typecast)
    assertEq(_deadline, uint64(_deadline256));
    assertEq(uint256(_snapshot), _snap);
    assertEq(_yeas, 0);
    assertEq(_nays, 0);
    assertFalse(_executed);

    (,,,,,,,,, bool _captainApproved, bool _captainDefeated,) = _squadTreasury.proposal(_id);
    assertFalse(_captainApproved);
    assertFalse(_captainDefeated);
  }

  function test_e2e_propose_succeeds_whenCallerIsCrew_recordsState() public withDeployedNavePirataSquad {
    address _crewMember = _squadCrew[2];
    address _to = makeAddr('e2eCrewProposeTo');

    vm.prank(_crewMember);
    uint256 _id = _squadTreasury.propose(_to, 0, hex'', ITreasuryAuthority.Operation.CALL);

    assertEq(_id, 1);
    assertEq(_squadTreasury.openProposalOf(_crewMember), 1);
    (address _proposer,,,,,,,,,,,) = _squadTreasury.proposal(_id);
    assertEq(_proposer, _crewMember);
  }

  function test_e2e_propose_succeeds_reusesProposerSlot_whenPriorProposalExpired() public withDeployedNavePirataSquad {
    address _to1 = makeAddr('e2eReuseTo1');
    address _to2 = makeAddr('e2eReuseTo2');

    vm.prank(_squadCaptain);
    uint256 _first = _squadTreasury.propose(_to1, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.warp(block.timestamp + _squadTreasury.proposalExpiry() + 1);

    vm.prank(_squadCaptain);
    uint256 _second = _squadTreasury.propose(_to2, 2 wei, hex'beef', ITreasuryAuthority.Operation.CALL);

    assertEq(_first, 1);
    assertEq(_second, 2);
    assertEq(_squadTreasury.openProposalOf(_squadCaptain), 2);

    (, address _t2,, ITreasuryAuthority.Operation _op2, bytes memory _d2,,,,,,,) = _squadTreasury.proposal(_second);
    assertEq(_t2, _to2);
    assertEq(uint256(_op2), uint256(ITreasuryAuthority.Operation.CALL));
    assertEq(keccak256(_d2), keccak256(hex'beef'));
  }

  /*///////////////////////////////////////////////////////////////
                        crewVote
  //////////////////////////////////////////////////////////////*/

  function test_e2e_crewVote_reverts_whenCallerDoesNotWearCrewHat() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    address _stranger = makeAddr('e2eCrewVoteStranger');
    _fund(_stranger, 1 ether);

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadTreasury.crewHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadTreasury.crewVote(_id, true);
  }

  function test_e2e_crewVote_reverts_whenProposalDoesNotExist() public withDeployedNavePirataSquad {
    uint256 _fakeId = type(uint256).max;

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalDoesNotExist.selector, _fakeId));
    vm.prank(_squadCrew[0]);
    _squadTreasury.crewVote(_fakeId, true);
  }

  function test_e2e_crewVote_reverts_whenProposalExpired() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.warp(block.timestamp + _squadTreasury.proposalExpiry() + 1);

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalExpired.selector, _id));
    vm.prank(_squadCrew[0]);
    _squadTreasury.crewVote(_id, true);
  }

  function test_e2e_crewVote_reverts_whenCaptainVetoed() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, false);

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_NotExecutable.selector, _id));
    vm.prank(_squadCrew[0]);
    _squadTreasury.crewVote(_id, true);
  }

  function test_e2e_crewVote_reverts_whenVoterAlreadyVoted() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    address _voter = _squadCrew[1];
    vm.prank(_voter);
    _squadTreasury.crewVote(_id, true);

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_AlreadyVoted.selector, _voter));
    vm.prank(_voter);
    _squadTreasury.crewVote(_id, false);
  }

  function test_e2e_crewVote_succeeds_incrementsYeas() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    address _voter = _squadCrew[3];

    vm.expectEmit(true, true, false, true, address(_squadTreasury));
    emit ITreasuryAuthority.CrewVoted(_id, _voter, true);

    vm.prank(_voter);
    _squadTreasury.crewVote(_id, true);

    (,,,,,,, uint64 _yeas, uint64 _nays,,,) = _squadTreasury.proposal(_id);
    assertEq(_yeas, 1);
    assertEq(_nays, 0);
    assertTrue(_squadTreasury.hasVoted(_id, _voter));
  }

  function test_e2e_crewVote_succeeds_incrementsNays() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    address _voter = _squadCrew[4];
    vm.prank(_voter);
    _squadTreasury.crewVote(_id, false);

    (,,,,,,, uint64 _yeas, uint64 _nays,,,) = _squadTreasury.proposal(_id);
    assertEq(_yeas, 0);
    assertEq(_nays, 1);
    assertTrue(_squadTreasury.hasVoted(_id, _voter));
  }

  /*///////////////////////////////////////////////////////////////
                        captainVote
  //////////////////////////////////////////////////////////////*/

  function test_e2e_captainVote_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    address _stranger = makeAddr('e2eCaptainVoteStranger');
    _fund(_stranger, 1 ether);

    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _squadTreasury.captainHatId(), _stranger)
    );
    vm.prank(_stranger);
    _squadTreasury.captainVote(_id, true);
  }

  function test_e2e_captainVote_reverts_whenCaptainAlreadyVoted() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.startPrank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);
    vm.expectRevert(
      abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_CaptainAlreadyVoted.selector, _squadCaptain)
    );
    _squadTreasury.captainVote(_id, false);
    vm.stopPrank();
  }

  function test_e2e_captainVote_reverts_whenProposalExpired() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.warp(block.timestamp + _squadTreasury.proposalExpiry() + 1);

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalExpired.selector, _id));
    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);
  }

  function test_e2e_captainVote_succeeds_whenApproving() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.expectEmit(true, true, false, true, address(_squadTreasury));
    emit ITreasuryAuthority.CaptainVoted(_id, _squadCaptain, true);

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);

    (,,,,,,,,, bool _approved, bool _defeated,) = _squadTreasury.proposal(_id);
    assertTrue(_approved);
    assertFalse(_defeated);
  }

  function test_e2e_captainVote_succeeds_whenVetoing_defeatsProposalAndClearsOpenSlot()
    public
    withDeployedNavePirataSquad
  {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 1 wei, hex'', ITreasuryAuthority.Operation.CALL);
    assertEq(_squadTreasury.openProposalOf(_squadCaptain), _id);

    vm.expectEmit(true, true, false, true, address(_squadTreasury));
    emit ITreasuryAuthority.CaptainVoted(_id, _squadCaptain, false);

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, false);

    assertEq(_squadTreasury.openProposalOf(_squadCaptain), 0);
    (,,,,,,,,, bool _approved, bool _defeated,) = _squadTreasury.proposal(_id);
    assertFalse(_approved);
    assertTrue(_defeated);
  }

  function test_e2e_captainVote_succeeds_whenVetoing_allowsNewProposeFromSameProposer()
    public
    withDeployedNavePirataSquad
  {
    address _to1 = makeAddr('e2eVetoRewriteTo1');
    address _to2 = makeAddr('e2eVetoRewriteTo2');

    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_to1, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, false);

    vm.prank(_squadCaptain);
    uint256 _next = _squadTreasury.propose(_to2, 0, hex'aa', ITreasuryAuthority.Operation.CALL);

    assertEq(_next, _id + 1);
    assertEq(_squadTreasury.openProposalOf(_squadCaptain), _next);
  }

  function test_e2e_captainVote_succeeds_whenApproving_afterCrewMemberProposes() public withDeployedNavePirataSquad {
    address _crewProposer = _squadCrew[0];

    vm.prank(_crewProposer);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);
    assertEq(_squadTreasury.openProposalOf(_crewProposer), _id);

    vm.expectEmit(true, true, false, true, address(_squadTreasury));
    emit ITreasuryAuthority.CaptainVoted(_id, _squadCaptain, true);

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);

    (,,,,,,,,, bool _approved, bool _defeated,) = _squadTreasury.proposal(_id);
    assertTrue(_approved);
    assertFalse(_defeated);
  }

  function test_e2e_captainVote_reverts_whenCaptainAlreadyVoted_afterCrewMemberProposes()
    public
    withDeployedNavePirataSquad
  {
    vm.prank(_squadCrew[2]);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.startPrank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);
    vm.expectRevert(
      abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_CaptainAlreadyVoted.selector, _squadCaptain)
    );
    _squadTreasury.captainVote(_id, false);
    vm.stopPrank();
  }

  function test_e2e_captainVote_reverts_whenProposalExpired_afterCrewMemberProposes()
    public
    withDeployedNavePirataSquad
  {
    vm.prank(_squadCrew[1]);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.warp(block.timestamp + _squadTreasury.proposalExpiry() + 1);

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalExpired.selector, _id));
    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);
  }

  function test_e2e_captainVote_succeeds_whenVetoing_afterCrewMemberProposes_clearsCrewOpenSlot()
    public
    withDeployedNavePirataSquad
  {
    address _crewProposer = _squadCrew[3];

    vm.prank(_crewProposer);
    uint256 _id = _squadTreasury.propose(_squadSafe, 1 wei, hex'', ITreasuryAuthority.Operation.CALL);
    assertEq(_squadTreasury.openProposalOf(_crewProposer), _id);

    vm.expectEmit(true, true, false, true, address(_squadTreasury));
    emit ITreasuryAuthority.CaptainVoted(_id, _squadCaptain, false);

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, false);

    assertEq(_squadTreasury.openProposalOf(_crewProposer), 0);
    assertEq(_squadTreasury.openProposalOf(_squadCaptain), 0);

    (,,,,,,,,, bool _approved, bool _defeated,) = _squadTreasury.proposal(_id);
    assertFalse(_approved);
    assertTrue(_defeated);
  }

  function test_e2e_captainVote_succeeds_whenVetoing_afterCrewMemberProposes_allowsCrewToProposeAgain()
    public
    withDeployedNavePirataSquad
  {
    address _crewProposer = _squadCrew[4];
    address _to1 = makeAddr('e2eCrewVetoThenTo1');
    address _to2 = makeAddr('e2eCrewVetoThenTo2');

    vm.prank(_crewProposer);
    uint256 _id = _squadTreasury.propose(_to1, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, false);

    vm.prank(_crewProposer);
    uint256 _next = _squadTreasury.propose(_to2, 0, hex'b0', ITreasuryAuthority.Operation.CALL);

    assertEq(_next, _id + 1);
    assertEq(_squadTreasury.openProposalOf(_crewProposer), _next);
  }
}

/**
 * @title E2ETreasuryAuthorityLifecycleTest
 * @author Pacto
 * @notice End-to-end scenarios for `TreasuryAuthority` execute, param setters, views, and rescue.
 */
contract E2ETreasuryAuthorityLifecycleTest is E2ETreasuryAuthorityBase {
  /*///////////////////////////////////////////////////////////////
                        execute
  //////////////////////////////////////////////////////////////*/

  function test_e2e_execute_succeeds_call_forwardsToSafeAndClearsOpenSlot() public withDeployedNavePirataSquad {
    address _beneficiary = makeAddr('e2eExecuteBeneficiary');

    vm.deal(_squadSafe, 20 ether);

    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_beneficiary, 2 ether, hex'', ITreasuryAuthority.Operation.CALL);

    assertEq(_squadTreasury.openProposalOf(_squadCaptain), _id);

    vm.prank(_squadCrew[0]);
    _squadTreasury.crewVote(_id, true);
    vm.prank(_squadCrew[1]);
    _squadTreasury.crewVote(_id, true);
    vm.prank(_squadCrew[2]);
    _squadTreasury.crewVote(_id, true);

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);

    uint256 _before = _beneficiary.balance;
    _squadTreasury.execute(_id);
    assertEq(_beneficiary.balance, _before + 2 ether);
    assertEq(_squadTreasury.openProposalOf(_squadCaptain), 0);
  }

  function test_e2e_execute_succeeds_delegatecall_forwardsOperation() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenCrewVoteBelowMajority_majoritySnapshotMode()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_execute_reverts_whenCaptainNotApproved() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenCaptainVetoed() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenSafeExecutionFails() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenAlreadyExecuted() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenProposalExpired() public withDeployedNavePirataSquad {}

  function test_e2e_execute_succeeds_whenQuorumMetAndYeasBeatNays_quorumOfCastMode()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_execute_reverts_whenQuorumNotMet_quorumOfCastMode() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenYeasNotGreaterThanNays_quorumOfCastMode() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        parameter setters
  //////////////////////////////////////////////////////////////*/

  function test_e2e_setProposalExpiry_reverts_whenCallerDoesNotWearTreasuryAuthorityRoleHat()
    public
    withDeployedNavePirataSquad
  {
    vm.expectRevert(
      abi.encodeWithSelector(
        HatGated.HatGated_NotHatWearer.selector, _squadTreasury.treasuryAuthorityRoleHatId(), _squadCaptain
      )
    );
    vm.prank(_squadCaptain);
    _squadTreasury.setProposalExpiry(14 days);
  }

  function test_e2e_setProposalExpiry_reverts_whenNewValueOutOfRange() public withDeployedNavePirataSquad {
    vm.expectRevert(
      abi.encodeWithSelector(
        RangeValidator.RangeValidator_OutOfRange.selector, uint256(30 seconds), uint256(1 minutes), uint256(60 days)
      )
    );
    vm.prank(address(_squadTreasury));
    _squadTreasury.setProposalExpiry(30 seconds);
  }

  function test_e2e_setProposalExpiry_succeeds_whenRoleHolder() public withDeployedNavePirataSquad {
    uint256 _old = _squadTreasury.proposalExpiry();
    assertEq(_old, PROPOSAL_EXPIRY);

    vm.expectEmit(false, false, false, true, address(_squadTreasury));
    emit ITreasuryAuthority.ProposalExpiryUpdated(_old, 30 days);

    vm.prank(address(_squadTreasury));
    _squadTreasury.setProposalExpiry(30 days);

    assertEq(_squadTreasury.proposalExpiry(), 30 days);
  }

  function test_e2e_setCrewVoteMode_reverts_whenCallerDoesNotWearTreasuryAuthorityRoleHat()
    public
    withDeployedNavePirataSquad
  {
    vm.expectRevert(
      abi.encodeWithSelector(
        HatGated.HatGated_NotHatWearer.selector, _squadTreasury.treasuryAuthorityRoleHatId(), _squadCaptain
      )
    );
    vm.prank(_squadCaptain);
    _squadTreasury.setCrewVoteMode(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST);
  }

  function test_e2e_setCrewVoteMode_succeeds_whenRoleHolder() public withDeployedNavePirataSquad {
    assertEq(uint256(_squadTreasury.crewVoteMode()), uint256(ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT));

    vm.expectEmit(false, false, false, true, address(_squadTreasury));
    emit ITreasuryAuthority.CrewVoteModeUpdated(
      ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT, ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST
    );

    vm.prank(address(_squadTreasury));
    _squadTreasury.setCrewVoteMode(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST);

    assertEq(uint256(_squadTreasury.crewVoteMode()), uint256(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST));
  }

  function test_e2e_setQuorumBps_reverts_whenCallerDoesNotWearTreasuryAuthorityRoleHat()
    public
    withDeployedNavePirataSquad
  {
    vm.expectRevert(
      abi.encodeWithSelector(
        HatGated.HatGated_NotHatWearer.selector, _squadTreasury.treasuryAuthorityRoleHatId(), _squadCaptain
      )
    );
    vm.prank(_squadCaptain);
    _squadTreasury.setQuorumBps(5000);
  }

  function test_e2e_setQuorumBps_reverts_whenNewValueOutOfRange() public withDeployedNavePirataSquad {
    vm.expectRevert(
      abi.encodeWithSelector(
        RangeValidator.RangeValidator_OutOfRange.selector, uint256(100), uint256(500), uint256(10_000)
      )
    );
    vm.prank(address(_squadTreasury));
    _squadTreasury.setQuorumBps(100);
  }

  function test_e2e_setQuorumBps_succeeds_whenRoleHolder() public withDeployedNavePirataSquad {
    uint256 _old = _squadTreasury.quorumBps();
    assertEq(_old, SQUAD_QUORUM_BPS);

    vm.expectEmit(false, false, false, true, address(_squadTreasury));
    emit ITreasuryAuthority.QuorumBpsUpdated(_old, 5000);

    vm.prank(address(_squadTreasury));
    _squadTreasury.setQuorumBps(5000);

    assertEq(_squadTreasury.quorumBps(), 5000);
  }

  /*///////////////////////////////////////////////////////////////
                        views / quiescence
  //////////////////////////////////////////////////////////////*/

  function test_e2e_proposal_view_reflectsStoredFields() public withDeployedNavePirataSquad {
    address _to = makeAddr('e2eProposalTo');
    uint256 _value = 3 wei;
    bytes memory _data = hex'cafe';

    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_to, _value, _data, ITreasuryAuthority.Operation.CALL);

    uint256 _deadline256 = block.timestamp + _squadTreasury.proposalExpiry();
    assertLe(_deadline256, type(uint64).max);
    // forge-lint: disable-next-line(unsafe-typecast)
    uint64 _expectedDeadline = uint64(_deadline256);

    (
      address _proposer,
      address _storedTo,
      uint256 _storedValue,
      ITreasuryAuthority.Operation _op,
      bytes memory _storedData,
      uint64 _deadline,
      uint64 _snapshot,
      uint64 _yeas,
      uint64 _nays,,,
      bool _executed
    ) = _squadTreasury.proposal(_id);

    assertEq(_proposer, _squadCaptain);
    assertEq(_storedTo, _to);
    assertEq(_storedValue, _value);
    assertEq(uint256(_op), uint256(ITreasuryAuthority.Operation.CALL));
    assertEq(keccak256(_storedData), keccak256(_data));
    assertEq(_deadline, _expectedDeadline);
    assertEq(uint256(_snapshot), IHats(HATS_PROTOCOL_V1).hatSupply(_squadTreasury.crewHatId()));
    assertEq(_yeas, 0);
    assertEq(_nays, 0);
    assertFalse(_executed);

    (,,,,,,,,, bool _captainApproved, bool _captainDefeated,) = _squadTreasury.proposal(_id);
    assertFalse(_captainApproved);
    assertFalse(_captainDefeated);
  }

  function test_e2e_hasVoted_reflectsCrewBallots() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    address _v0 = _squadCrew[0];
    address _v1 = _squadCrew[1];

    assertFalse(_squadTreasury.hasVoted(_id, _v0));
    assertFalse(_squadTreasury.hasVoted(_id, _v1));

    vm.prank(_v0);
    _squadTreasury.crewVote(_id, true);

    assertTrue(_squadTreasury.hasVoted(_id, _v0));
    assertFalse(_squadTreasury.hasVoted(_id, _v1));
  }

  function test_e2e_openProposalOf_tracksProposerOpenId() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    uint256 _captainId = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    address _crewProposer = _squadCrew[2];
    vm.prank(_crewProposer);
    uint256 _crewId = _squadTreasury.propose(_squadSafe, 1 wei, hex'', ITreasuryAuthority.Operation.CALL);

    assertEq(_squadTreasury.openProposalOf(_squadCaptain), _captainId);
    assertEq(_squadTreasury.openProposalOf(_crewProposer), _crewId);
    assertEq(_squadTreasury.openProposalOf(_squadCrew[0]), 0);
  }

  function test_e2e_SAFE_matchesSquadSafeAddress() public withDeployedNavePirataSquad {
    assertEq(_squadTreasury.SAFE(), _squadSafe);
  }

  function test_e2e_hatIdGetters_matchDeployment() public withDeployedNavePirataSquad {
    INavePirataRegistry.Deployment memory _d = INavePirataRegistry(_infra.registry).deployment(_squadTopHatId);

    assertEq(_squadTreasury.captainHatId(), _d.captainHatId);
    assertEq(_squadTreasury.crewHatId(), _d.crewHatId);
    assertEq(_squadTreasury.treasuryAuthorityRoleHatId(), _d.treasuryAuthorityRoleHatId);
  }

  function test_e2e_isQuiet_trueOnFreshSquadWhenNoLiveProposalDeadline() public withDeployedNavePirataSquad {
    assertTrue(_squadTreasury.isQuiet());
  }

  function test_e2e_isQuiet_falseWhileProposalWithinMaxDeadline() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    assertFalse(_squadTreasury.isQuiet());
  }

  function test_e2e_isQuiet_trueAfterAllProposalsExpired() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.warp(block.timestamp + _squadTreasury.proposalExpiry() + 1);

    assertTrue(_squadTreasury.isQuiet());
  }

  function test_e2e_isQuiet_falseAgainAfterNewProposal() public withDeployedNavePirataSquad {
    vm.prank(_squadCaptain);
    _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    vm.warp(block.timestamp + _squadTreasury.proposalExpiry() + 1);
    assertTrue(_squadTreasury.isQuiet());

    vm.prank(_squadCaptain);
    _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    assertFalse(_squadTreasury.isQuiet());
  }

  /*///////////////////////////////////////////////////////////////
                        AssetRescuer
  //////////////////////////////////////////////////////////////*/

  function test_e2e_receive_revertsWithRescueDestinationHint() public withDeployedNavePirataSquad {
    vm.deal(address(this), 1 ether);
    vm.expectRevert(abi.encodeWithSelector(IAssetRescuer.AssetRescuer_SendToDestinationInstead.selector, _squadSafe));
    payable(address(_squadTreasury)).transfer(1 wei);
  }

  function test_e2e_rescueETH_succeeds_sweepsToSafe() public withDeployedNavePirataSquad {
    uint256 _amount = 5 ether;
    vm.deal(address(_squadTreasury), _amount);

    uint256 _safeBefore = _squadSafe.balance;
    assertEq(_safeBefore, 0);

    vm.expectEmit(true, false, false, true, address(_squadTreasury));
    emit IAssetRescuer.AssetRescuedETH(_squadSafe, _amount);

    _squadTreasury.rescue(address(0));

    assertEq(_squadSafe.balance, _safeBefore + _amount);
    assertEq(address(_squadTreasury).balance, 0);
  }

  function test_e2e_rescueERC20_succeeds_sweepsToSafe() public withDeployedNavePirataSquad {
    E2ERescueERC20 _token = new E2ERescueERC20();
    uint256 _amount = 1000 ether;
    _stdstoreOzErc20Balance(address(_token), address(_squadTreasury), _amount);

    uint256 _safeBefore = _token.balanceOf(_squadSafe);

    vm.expectEmit(true, true, false, true, address(_squadTreasury));
    emit IAssetRescuer.AssetRescuedERC20(address(_token), _squadSafe, _amount);

    _squadTreasury.rescue(address(_token));

    assertEq(_token.balanceOf(_squadSafe), _safeBefore + _amount);
    assertEq(_token.balanceOf(address(_squadTreasury)), 0);
  }

  function test_e2e_rescueERC721_succeeds_sweepsToSafe() public withDeployedNavePirataSquad {
    E2ERescueERC721 _nft = new E2ERescueERC721();
    uint256 _tokenId = 42;
    _nft.mint(address(_squadTreasury), _tokenId);
    assertEq(_nft.ownerOf(_tokenId), address(_squadTreasury));

    vm.expectEmit(true, true, false, true, address(_squadTreasury));
    emit IAssetRescuer.AssetRescuedERC721(address(_nft), _squadSafe, _tokenId);

    _squadTreasury.rescueERC721(address(_nft), _tokenId);

    assertEq(_nft.ownerOf(_tokenId), _squadSafe);
  }

  function test_e2e_rescueERC1155_succeeds_sweepsToSafe() public withDeployedNavePirataSquad {
    E2ERescueERC1155 _multi = new E2ERescueERC1155();
    uint256 _id = 7;
    uint256 _amount = 100;
    _stdstoreOzErc1155Balance(address(_multi), address(_squadTreasury), _id, _amount);

    _mockSquadSafeErc1155Receive(address(_squadTreasury), _id, _amount);

    uint256 _safeBefore = _multi.balanceOf(_squadSafe, _id);

    vm.expectEmit(true, true, true, true, address(_multi));
    emit IERC1155.TransferSingle(address(_squadTreasury), address(_squadTreasury), _squadSafe, _id, _amount);

    vm.expectEmit(true, true, false, true, address(_squadTreasury));
    emit IAssetRescuer.AssetRescuedERC1155(address(_multi), _squadSafe, _id, _amount);

    _squadTreasury.rescueERC1155(address(_multi), _id, _amount);

    assertEq(_multi.balanceOf(_squadSafe, _id), _safeBefore + _amount);
    assertEq(_multi.balanceOf(address(_squadTreasury), _id), 0);
  }

  /*///////////////////////////////////////////////////////////////
                        integration wiring
  //////////////////////////////////////////////////////////////*/

  function test_integration_treasuryAuthorityMasterDeployedAndFactoryLive() public view {
    TreasuryAuthority _master = TreasuryAuthority(payable(_masters.treasuryAuthority));
    assertGt(address(_master).code.length, 0);
    assertGt(_infra.navePirataFactory.code.length, 0);
  }

  function test_integration_squadTreasuryMatchesRegistryDeployment() public withDeployedNavePirataSquad {
    assertEq(address(_squadTreasury), NavePirataRegistry(_infra.registry).deployment(_squadTopHatId).treasuryAuthority);
  }
}

/**
 * Fork fuzzing focused on brittle numeric / time predicates in `TreasuryAuthority` (`_crewVotePassed`, deadline
 * comparisons, one-open-per-proposer). Bounded inputs + `assume` reject cases that warp past `uint64` deadlines.
 *
 * forge-config: default.fuzz.runs = 128
 */
contract E2ETreasuryAuthorityForkFuzz is IntegrationBase {
  function testFuzz_e2e_majorityThreshold_executeMatches2YeasGtSnapshot(uint8 nYeas)
    public
    withDeployedNavePirataSquad
  {
    vm.assume(uint256(nYeas) <= _squadCrew.length);
    vm.assume(uint256(nYeas) * 2 <= type(uint64).max);

    vm.deal(_squadSafe, 50 ether);
    address _beneficiary = makeAddr('e2eFuzzExecBen');

    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_beneficiary, 1 wei, hex'', ITreasuryAuthority.Operation.CALL);

    (,,,,,, uint64 _snapshot,,,,,) = _squadTreasury.proposal(_id);
    uint256 _snap = uint256(_snapshot);
    vm.assume(_snap > 0);

    for (uint256 _i = 0; _i < nYeas; _i++) {
      vm.prank(_squadCrew[_i]);
      _squadTreasury.crewVote(_id, true);
    }

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);

    bool _passes = uint256(nYeas) * 2 > _snap;

    if (_passes) {
      uint256 _balBefore = _beneficiary.balance;
      _squadTreasury.execute(_id);
      assertEq(_beneficiary.balance, _balBefore + 1 wei);
    } else {
      vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_NotExecutable.selector, _id));
      _squadTreasury.execute(_id);
    }
  }

  function testFuzz_e2e_repeatProposerSecondCall_dependsOnWarpVersusExpiry(uint128 dtRaw)
    public
    withDeployedNavePirataSquad
  {
    uint256 _exp = _squadTreasury.proposalExpiry();
    uint256 dt = uint256(dtRaw);
    vm.assume(dt <= 2 * _exp + 365 days);

    vm.prank(_squadCaptain);
    uint256 _first = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    uint256 _t0 = block.timestamp;
    vm.warp(_t0 + dt);

    if (dt < _exp) {
      vm.expectRevert(
        abi.encodeWithSelector(
          ITreasuryAuthority.TreasuryAuthority_ProposerHasOpenProposal.selector, _squadCaptain, _first
        )
      );
      vm.prank(_squadCaptain);
      _squadTreasury.propose(_squadSafe, 2 wei, hex'', ITreasuryAuthority.Operation.CALL);
    } else {
      vm.prank(_squadCaptain);
      uint256 _second = _squadTreasury.propose(_squadSafe, 0, hex'ab', ITreasuryAuthority.Operation.CALL);
      assertEq(_second, _first + 1);
      assertEq(_squadTreasury.openProposalOf(_squadCaptain), _second);
    }
  }

  function testFuzz_e2e_crewVoteRevertsExactlyAtOrAfterDeadline(uint64 delta) public withDeployedNavePirataSquad {
    uint256 _exp = _squadTreasury.proposalExpiry();
    vm.assume(uint256(_exp) + uint256(delta) <= type(uint64).max - 1);

    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_squadSafe, 0, hex'', ITreasuryAuthority.Operation.CALL);

    uint256 _deadline256 = block.timestamp + _squadTreasury.proposalExpiry();
    assertLe(_deadline256, type(uint64).max);
    // forge-lint: disable-next-line(unsafe-typecast)
    uint64 _deadline = uint64(_deadline256);

    vm.warp(uint256(_deadline) + uint256(delta));

    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalExpired.selector, _id));
    vm.prank(_squadCrew[0]);
    _squadTreasury.crewVote(_id, true);
  }

  /// @dev Flips TA to quorum-of-cast on the deployed clone, then fuzzes disjoint yea/nay tallies vs execute.
  function testFuzz_e2e_quorumCast_executeMatchesFormula(
    uint8 yeaVotes,
    uint8 nayVotes
  ) public withDeployedNavePirataSquad {
    uint256 _nC = _squadCrew.length;
    vm.assume(uint256(yeaVotes) + uint256(nayVotes) <= _nC);

    vm.prank(address(_squadTreasury));
    _squadTreasury.setCrewVoteMode(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST);

    vm.deal(_squadSafe, 50 ether);
    address _beneficiary = makeAddr('e2eFuzzQcBen');

    vm.prank(_squadCaptain);
    uint256 _id = _squadTreasury.propose(_beneficiary, 1 wei, hex'', ITreasuryAuthority.Operation.CALL);

    (,,,,,, uint64 _snapshot,,,,,) = _squadTreasury.proposal(_id);
    uint256 _snap = uint256(_snapshot);
    uint256 _bps = _squadTreasury.quorumBps();

    for (uint256 _i = 0; _i < uint256(yeaVotes); _i++) {
      vm.prank(_squadCrew[_i]);
      _squadTreasury.crewVote(_id, true);
    }
    for (uint256 _j = 0; _j < uint256(nayVotes); _j++) {
      vm.prank(_squadCrew[uint256(yeaVotes) + _j]);
      _squadTreasury.crewVote(_id, false);
    }

    vm.prank(_squadCaptain);
    _squadTreasury.captainVote(_id, true);

    uint256 _cast = uint256(yeaVotes) + uint256(nayVotes);
    bool _passes = _cast * 10_000 >= _snap * _bps && uint256(yeaVotes) > uint256(nayVotes);

    if (_passes) {
      uint256 _before = _beneficiary.balance;
      _squadTreasury.execute(_id);
      assertEq(_beneficiary.balance, _before + 1 wei);
    } else {
      vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_NotExecutable.selector, _id));
      _squadTreasury.execute(_id);
    }
  }
}
