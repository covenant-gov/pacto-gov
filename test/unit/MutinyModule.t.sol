// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MutinyModuleUnitTest} from './MutinyModuleUnitTest.sol';
import {MutinyModule} from 'contracts/MutinyModule.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IMutinyModule} from 'interfaces/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';

contract UnitMutinyModule is MutinyModuleUnitTest {
  function test_ConstructorWhenDeployedWithValidParams() external view {
    assertEq(_mutiny.QUARTERMASTER(), _QM_ADDRESS);
    assertEq(_mutiny.HATS(), _HATS_ADDRESS);
    assertEq(_mutiny.CAPTAIN_HAT_ID(), _CAPTAIN_HAT);
    assertEq(_mutiny.CREW_HAT_ID(), _CREW_HAT);
    assertEq(_mutiny.latestMutinyId(), 0);
  }

  function test_ConstructorWhenParamsAreInvalid() external {
    vm.expectRevert(IMutinyModule.MutinyModule_InvalidSuccessor.selector);
    new MutinyModule(IQuartermaster(address(0)), IHats(_HATS_ADDRESS), _CAPTAIN_HAT, _CREW_HAT, _captain0);

    vm.expectRevert(IMutinyModule.MutinyModule_InvalidSuccessor.selector);
    new MutinyModule(IQuartermaster(_QM_ADDRESS), IHats(address(0)), _CAPTAIN_HAT, _CREW_HAT, _captain0);

    vm.expectRevert(IMutinyModule.MutinyModule_InvalidSuccessor.selector);
    new MutinyModule(IQuartermaster(_QM_ADDRESS), IHats(_HATS_ADDRESS), _CAPTAIN_HAT, _CREW_HAT, address(0));

    vm.expectRevert(IMutinyModule.MutinyModule_InvalidSuccessor.selector);
    new MutinyModule(IQuartermaster(_QM_ADDRESS), IHats(_HATS_ADDRESS), 0, _CREW_HAT, _captain0);

    vm.expectRevert(IMutinyModule.MutinyModule_InvalidSuccessor.selector);
    new MutinyModule(IQuartermaster(_QM_ADDRESS), IHats(_HATS_ADDRESS), _CAPTAIN_HAT, 0, _captain0);
  }

  function test_StartMutinyWhenCrewOpensMutinyWithValidSuccessorAndPositiveCrewSupply() external {
    _mockStartMutinyHappyPath(_crew1, _successor, 4);
    vm.expectCall(_QM_ADDRESS, abi.encodeWithSelector(IQuartermaster.setMutinyActive.selector, true));
    vm.prank(_crew1);
    _mutiny.startMutiny(_successor);

    assertEq(_mutiny.latestMutinyId(), 1);
    (address _proposed, uint256 _snap, uint256 _eligible,,) = _mutiny.rounds(1);
    assertEq(_proposed, _successor);
    assertEq(_eligible, 4);
    assertEq(_snap, block.number);
    assertTrue(_mutiny.isMutinyOpen(1));
  }

  function test_StartMutinyWhenAMutinyIsAlreadyOpen() external {
    _mockStartMutinyHappyPath(_crew1, _successor, 4);
    vm.startPrank(_crew1);
    _mutiny.startMutiny(_successor);
    vm.expectRevert(IMutinyModule.MutinyModule_MutinyAlreadyActive.selector);
    _mutiny.startMutiny(makeAddr('otherSuccessor'));
    vm.stopPrank();
  }

  function test_StartMutinyWhenProposedSuccessorIsZero() external {
    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    _mockHatSupply(_CREW_HAT, 4);
    vm.prank(_crew1);
    vm.expectRevert(IMutinyModule.MutinyModule_InvalidSuccessor.selector);
    _mutiny.startMutiny(address(0));
  }

  function test_StartMutinyWhenProposedIsCurrentCaptain() external {
    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 0);
    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    _mockHatSupply(_CREW_HAT, 4);
    vm.prank(_crew1);
    vm.expectRevert(IMutinyModule.MutinyModule_InvalidSuccessor.selector);
    _mutiny.startMutiny(_captain0);
  }

  function test_StartMutinyWhenProposedAlreadyWearsCaptainHat() external {
    _mockBalanceOf(_successor, _CAPTAIN_HAT, 1);
    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    _mockHatSupply(_CREW_HAT, 4);
    vm.prank(_crew1);
    vm.expectRevert(IMutinyModule.MutinyModule_InvalidSuccessor.selector);
    _mutiny.startMutiny(_successor);
  }

  function test_StartMutinyWhenCallerIsNotCrew() external {
    _mockBalanceOf(_successor, _CAPTAIN_HAT, 0);
    _mockBalanceOf(_crew1, _CREW_HAT, 0);
    _mockHatSupply(_CREW_HAT, 4);
    vm.prank(_crew1);
    vm.expectRevert(IMutinyModule.MutinyModule_NotEligibleCrew.selector);
    _mutiny.startMutiny(_successor);
  }

  function test_StartMutinyWhenCrewHatSupplyIsZero() external {
    _mockBalanceOf(_successor, _CAPTAIN_HAT, 0);
    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    _mockHatSupply(_CREW_HAT, 0);
    vm.prank(_crew1);
    vm.expectRevert(IMutinyModule.MutinyModule_InvalidMutiny.selector);
    _mutiny.startMutiny(_successor);
  }

  modifier whenRoundIsOpen() {
    _mockStartMutinyHappyPath(_crew1, _successor, 4);
    vm.prank(_crew1);
    _mutiny.startMutiny(_successor);
    _;
  }

  function test_CastVoteWhenVoterCastsNay() external whenRoundIsOpen {
    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    vm.prank(_crew1);
    _mutiny.castVote(1, false);
    assertEq(_mutiny.yeaVotes(1), 0);
    assertTrue(_mutiny.hasVoted(1, _crew1));
  }

  function test_CastVoteWhenAnotherVoterCastsYea() external whenRoundIsOpen {
    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    vm.prank(_crew1);
    _mutiny.castVote(1, false);

    _mockBalanceOf(_crew2, _CREW_HAT, 1);
    vm.prank(_crew2);
    _mutiny.castVote(1, true);
    assertEq(_mutiny.yeaVotes(1), 1);
    assertTrue(_mutiny.hasVoted(1, _crew2));
  }

  function test_CastVoteWhenVoterVotesTwice() external {
    _mockStartMutinyHappyPath(_crew1, _successor, 4);
    vm.prank(_crew1);
    _mutiny.startMutiny(_successor);

    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    vm.startPrank(_crew1);
    _mutiny.castVote(1, true);
    vm.expectRevert(IMutinyModule.MutinyModule_AlreadyVoted.selector);
    _mutiny.castVote(1, true);
    vm.stopPrank();
  }

  function test_CastVoteWhenVoterIsNotCrew() external {
    _mockStartMutinyHappyPath(_crew1, _successor, 4);
    vm.prank(_crew1);
    _mutiny.startMutiny(_successor);

    address _outsider = makeAddr('outsider');
    _mockBalanceOf(_outsider, _CREW_HAT, 0);
    vm.prank(_outsider);
    vm.expectRevert(IMutinyModule.MutinyModule_NotEligibleCrew.selector);
    _mutiny.castVote(1, true);
  }

  function test_CastVoteWhenMutinyIdIsNotOpen() external {
    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    vm.prank(_crew1);
    vm.expectRevert(IMutinyModule.MutinyModule_InvalidMutiny.selector);
    _mutiny.castVote(1, true);
  }

  function test_ExecuteMutinyWhenStrictMajorityYeaAndEOASuccessorWithoutCrew() external {
    _startOpenMutinyWithThreeYeas(_successor);

    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 1);
    _mockTransferHat(_CAPTAIN_HAT, _captain0, _successor);
    _mockBalanceOf(_successor, _CREW_HAT, 0);
    _mockQmMintCrewFromMutiny(_captain0);
    _mockQmSetMutinyActive(false);

    vm.expectCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _CAPTAIN_HAT, _captain0, _successor)
    );
    vm.expectCall(_QM_ADDRESS, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _captain0));
    _mutiny.executeMutiny(1);

    (,,,, bool _executed) = _mutiny.rounds(1);
    assertTrue(_executed);
    assertFalse(_mutiny.isMutinyOpen(1));
  }

  function test_ExecuteMutinyWhenEOASuccessorAlreadyHasCrew() external {
    address _succCrew = makeAddr('succCrew');
    _startOpenMutinyWithThreeYeas(_succCrew);

    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 1);
    _mockTransferHat(_CAPTAIN_HAT, _captain0, _succCrew);
    _mockBalanceOf(_succCrew, _CREW_HAT, 1);
    _mockQmCrewHandoffForMutiny(_captain0, _succCrew);
    _mockQmSetMutinyActive(false);

    vm.expectCall(
      _QM_ADDRESS, abi.encodeWithSelector(IQuartermaster.crewHandoffForMutiny.selector, _captain0, _succCrew)
    );
    _mutiny.executeMutiny(1);
  }

  function test_ExecuteMutinyWhenSuccessorIsAContract() external {
    address _contractSucc = address(new EmptySuccessor());
    _startOpenMutinyWithThreeYeas(_contractSucc);

    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 1);
    _mockTransferHat(_CAPTAIN_HAT, _captain0, _contractSucc);
    _mockQmMintCrewFromMutiny(_captain0);
    _mockQmSetMutinyActive(false);

    vm.expectCall(_QM_ADDRESS, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _captain0));
    _mutiny.executeMutiny(1);
  }

  function test_ExecuteMutinyWhenYeaVotesDoNotExceedHalfOfEligibleCrewCount() external {
    _mockStartMutinyHappyPath(_crew1, _successor, 4);
    vm.prank(_crew1);
    _mutiny.startMutiny(_successor);

    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    _mockBalanceOf(_crew2, _CREW_HAT, 1);
    vm.prank(_crew1);
    _mutiny.castVote(1, true);
    vm.prank(_crew2);
    _mutiny.castVote(1, true);

    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 1);
    vm.expectRevert(IMutinyModule.MutinyModule_NotExecutable.selector);
    _mutiny.executeMutiny(1);
  }

  function test_ExecuteMutinyWhenTrackedCaptainDoesNotHoldCaptainHat() external {
    _startOpenMutinyWithThreeYeas(_successor);

    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 0);
    vm.expectRevert(IMutinyModule.MutinyModule_NotExecutable.selector);
    _mutiny.executeMutiny(1);
  }

  function test_LifecycleWhenExecuteCompletesAndCrewStartsANewMutiny() external {
    _startOpenMutinyWithThreeYeas(_successor);
    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 1);
    _mockTransferHat(_CAPTAIN_HAT, _captain0, _successor);
    _mockBalanceOf(_successor, _CREW_HAT, 0);
    _mockQmMintCrewFromMutiny(_captain0);
    _mockQmSetMutinyActive(false);
    _mutiny.executeMutiny(1);

    address _nextSucc = makeAddr('nextSucc');
    _mockBalanceOf(_nextSucc, _CAPTAIN_HAT, 0);
    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    _mockHatSupply(_CREW_HAT, 4);
    _mockQmSetMutinyActive(true);
    vm.prank(_crew1);
    _mutiny.startMutiny(_nextSucc);

    assertEq(_mutiny.latestMutinyId(), 2);
    assertTrue(_mutiny.isMutinyOpen(2));
  }

  function test_CastVote_RevertsWhenRoundAlreadyExecuted() external {
    _startOpenMutinyWithThreeYeas(_successor);
    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 1);
    _mockTransferHat(_CAPTAIN_HAT, _captain0, _successor);
    _mockBalanceOf(_successor, _CREW_HAT, 0);
    _mockQmMintCrewFromMutiny(_captain0);
    _mockQmSetMutinyActive(false);
    _mutiny.executeMutiny(1);

    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    vm.prank(_crew1);
    vm.expectRevert(IMutinyModule.MutinyModule_InvalidMutiny.selector);
    _mutiny.castVote(1, true);
  }

  function test_ExecuteMutiny_RevertsWhenMutinyIdNeverOpened() external {
    vm.expectRevert(IMutinyModule.MutinyModule_InvalidMutiny.selector);
    _mutiny.executeMutiny(1);
  }

  function test_ExecuteMutiny_RevertsWhenAlreadyExecuted() external {
    _startOpenMutinyWithThreeYeas(_successor);
    _mockBalanceOf(_captain0, _CAPTAIN_HAT, 1);
    _mockTransferHat(_CAPTAIN_HAT, _captain0, _successor);
    _mockBalanceOf(_successor, _CREW_HAT, 0);
    _mockQmMintCrewFromMutiny(_captain0);
    _mockQmSetMutinyActive(false);
    _mutiny.executeMutiny(1);

    vm.expectRevert(IMutinyModule.MutinyModule_InvalidMutiny.selector);
    _mutiny.executeMutiny(1);
  }
}

contract EmptySuccessor {}
