// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {QuartermasterUnitTest} from './QuartermasterUnitTest.sol';
import {Quartermaster} from 'contracts/Quartermaster.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';

contract UnitQuartermaster is QuartermasterUnitTest {
  function test_ConstructorWhenDeployed() external view {
    assertEq(_qm.HATS(), _HATS_ADDRESS);
    assertEq(_qm.CREW_HAT_ID(), _CREW_HAT);
    assertEq(_qm.CAPTAIN_HAT_ID(), _CAPTAIN_HAT);
    assertEq(_qm.CREW_CHANGE_DELAY(), _DELAY);
    assertEq(_qm.MUTINY_MODULE(), _mutiny);
    assertEq(_qm.mutinyActive(), false);
  }

  modifier whenCaptainRequestsAddForAValidCandidate() {
    _mockIsCaptain(_captain);
    _mockValidCrewCandidate(_candidate);
    vm.prank(_captain);
    _qm.requestAddCrew(_candidate);
    _;
  }

  function test_RequestAddCrewWhenCaptainRequestsAddForAValidCandidate()
    external
    whenCaptainRequestsAddForAValidCandidate
  {
    assertEq(_qm.pendingCrewAddAt(_candidate), block.timestamp + _DELAY);
  }

  function test_RequestAddCrewWhenExecuteAddCrewIsCalledBeforeDelayElapses()
    external
    whenCaptainRequestsAddForAValidCandidate
  {
    _mockValidCrewCandidate(_candidate);
    _mockMintCrewOk(_candidate, 0);
    vm.expectRevert(IQuartermaster.Quartermaster_NotExecutable.selector);
    _qm.executeAddCrew(_candidate);
  }

  function test_RequestAddCrewWhenDelayElapses() external whenCaptainRequestsAddForAValidCandidate {
    uint256 _at = _qm.pendingCrewAddAt(_candidate);
    vm.warp(_at);
    _mockValidCrewCandidate(_candidate);
    _mockMintCrewOk(_candidate, 0);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _CREW_HAT, _candidate));
    _qm.executeAddCrew(_candidate);
    assertEq(_qm.pendingCrewAddAt(_candidate), 0);
  }

  function test_RequestAddCrewWhenCallerIsNotCaptain() external {
    _mockBalanceOf(_crew, _CAPTAIN_HAT, 0);
    vm.prank(_crew);
    vm.expectRevert(IQuartermaster.Quartermaster_OnlyCaptain.selector);
    _qm.requestAddCrew(_candidate);
  }

  function test_RequestAddCrewWhenMutinyIsActive() external {
    vm.prank(_mutiny);
    _qm.setMutinyActive(true);

    _mockIsCaptain(_captain);
    _mockValidCrewCandidate(_candidate);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.requestAddCrew(_candidate);
  }

  function test_RequestAddCrewWhenCandidateIsTheCaptain() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_captain, _CREW_HAT, 0);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.requestAddCrew(_captain);
  }

  function test_RequestAddCrewWhenCandidateAlreadyWearsCrew() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_candidate, _CAPTAIN_HAT, 0);
    _mockBalanceOf(_candidate, _CREW_HAT, 1);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.requestAddCrew(_candidate);
  }

  modifier whenCaptainRequestsRemoveForCrewMember() {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_crew, _CREW_HAT, 1);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_crew);
    _;
  }

  function test_RequestRemoveCrewWhenCaptainRequestsRemoveForCrewMember()
    external
    whenCaptainRequestsRemoveForCrewMember
  {
    assertEq(_qm.pendingCrewRemoveAt(_crew), block.timestamp + _DELAY);
  }

  function test_RequestRemoveCrewWhenExecuteRemoveCrewIsCalledBeforeDelayElapses()
    external
    whenCaptainRequestsRemoveForCrewMember
  {
    _mockBalanceOf(_crew, _CREW_HAT, 1);
    _mockSetHatWearerStatus(_CREW_HAT, _crew, false, false);
    vm.expectRevert(IQuartermaster.Quartermaster_NotExecutable.selector);
    _qm.executeRemoveCrew(_crew);
  }

  function test_RequestRemoveCrewWhenDelayElapses() external whenCaptainRequestsRemoveForCrewMember {
    uint256 _at = _qm.pendingCrewRemoveAt(_crew);
    vm.warp(_at);
    _mockBalanceOf(_crew, _CREW_HAT, 1);
    _mockSetHatWearerStatus(_CREW_HAT, _crew, false, false);
    vm.expectCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.setHatWearerStatus.selector, _CREW_HAT, _crew, false, false)
    );
    _qm.executeRemoveCrew(_crew);
    assertEq(_qm.pendingCrewRemoveAt(_crew), 0);
  }

  function test_RequestRemoveCrewWhenMutinyIsActive() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_crew, _CREW_HAT, 1);

    vm.prank(_mutiny);
    _qm.setMutinyActive(true);

    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.requestRemoveCrew(_crew);
  }

  function test_ExecuteAddCrewWhenThereIsNoPendingAdd() external {
    vm.expectRevert(IQuartermaster.Quartermaster_NoPendingOperation.selector);
    _qm.executeAddCrew(_candidate);
  }

  function test_MintCrewFromMutinyWhenCallerIsNotMutinyModule() external {
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_OnlyMutinyModule.selector);
    _qm.mintCrewFromMutiny(_candidate);
  }

  function test_MintCrewFromMutinyWhenCallerIsMutinyModuleAndRecipientIsValid() external {
    _mockBalanceOf(_candidate, _CAPTAIN_HAT, 0);
    _mockMintCrewOk(_candidate, 0);
    vm.prank(_mutiny);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _CREW_HAT, _candidate));
    _qm.mintCrewFromMutiny(_candidate);
  }

  function test_MintCrewFromMutinyWhenRecipientIsCaptain() external {
    _mockBalanceOf(_captain, _CAPTAIN_HAT, 1);
    vm.prank(_mutiny);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.mintCrewFromMutiny(_captain);
  }

  function test_MintCrewFromMutinyWhenCrewHatIsAtMaxSupply() external {
    _mockBalanceOf(_candidate, _CAPTAIN_HAT, 0);
    _mockHatSupply(_CREW_HAT, 0);
    _mockHatMaxSupply(_CREW_HAT, 1);
    _mockMintHat(_CREW_HAT, _candidate);

    vm.prank(_mutiny);
    _qm.mintCrewFromMutiny(_candidate);

    address _other = makeAddr('other');
    _mockBalanceOf(_other, _CAPTAIN_HAT, 0);
    _mockHatSupply(_CREW_HAT, 1);
    _mockHatMaxSupply(_CREW_HAT, 1);

    vm.prank(_mutiny);
    vm.expectRevert(IQuartermaster.Quartermaster_CrewHatMaxSupply.selector);
    _qm.mintCrewFromMutiny(_other);
  }

  function test_SetMutinyActiveWhenCallerIsNotMutinyModule() external {
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_OnlyMutinyModule.selector);
    _qm.setMutinyActive(true);
  }

  function test_SetMutinyActiveWhenCallerIsMutinyModule() external {
    vm.prank(_mutiny);
    _qm.setMutinyActive(true);
    assertEq(_qm.mutinyActive(), true);
  }

  function test_CrewHandoffForMutinyWhenNewCaptainAlreadyHasCrew() external {
    address _former = makeAddr('former');
    _mockBalanceOf(_candidate, _CREW_HAT, 1);
    _mockTransferHat(_CREW_HAT, _candidate, _former);

    vm.prank(_mutiny);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _CREW_HAT, _candidate, _former));
    _qm.crewHandoffForMutiny(_former, _candidate);
  }

  function test_CrewHandoffForMutinyWhenNewCaptainHasNoCrew() external {
    address _former = makeAddr('former');
    _mockBalanceOf(_candidate, _CREW_HAT, 0);
    _mockMintCrewOk(_former, 0);

    vm.prank(_mutiny);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _CREW_HAT, _former));
    _qm.crewHandoffForMutiny(_former, _candidate);
  }

  function test_Constructor_RevertsOnZeroHats() external {
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    new Quartermaster(address(0), _CREW_HAT, _CAPTAIN_HAT, _DELAY, _mutiny);
  }

  function test_Constructor_RevertsOnZeroMutinyModule() external {
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    new Quartermaster(_HATS_ADDRESS, _CREW_HAT, _CAPTAIN_HAT, _DELAY, address(0));
  }

  function test_RequestAddCrew_RevertsZeroCandidate() external {
    _mockIsCaptain(_captain);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.requestAddCrew(address(0));
  }

  function test_RequestRemoveCrew_RevertsWhenTargetNotCrew() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_crew, _CREW_HAT, 0);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.requestRemoveCrew(_crew);
  }

  function test_ExecuteRemoveCrew_RevertsNoPending() external {
    vm.expectRevert(IQuartermaster.Quartermaster_NoPendingOperation.selector);
    _qm.executeRemoveCrew(_crew);
  }

  function test_ExecuteRemoveCrew_RevertsWhenCrewLostHatBeforeExecute() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_crew, _CREW_HAT, 1);
    vm.prank(_captain);
    _qm.requestRemoveCrew(_crew);
    uint256 _at = _qm.pendingCrewRemoveAt(_crew);

    vm.warp(_at);
    _mockBalanceOf(_crew, _CREW_HAT, 0);
    vm.expectRevert(IQuartermaster.Quartermaster_NoPendingOperation.selector);
    _qm.executeRemoveCrew(_crew);
  }

  function test_CrewHandoffForMutiny_RevertsZeroFormerCaptain() external {
    vm.prank(_mutiny);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.crewHandoffForMutiny(address(0), _candidate);
  }

  function test_CrewHandoffForMutiny_RevertsZeroNewCaptain() external {
    address _former = makeAddr('former');
    vm.prank(_mutiny);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.crewHandoffForMutiny(_former, address(0));
  }

  function test_SetMutinyActive_CanClearFlag() external {
    vm.startPrank(_mutiny);
    _qm.setMutinyActive(true);
    assertEq(_qm.mutinyActive(), true);
    _qm.setMutinyActive(false);
    vm.stopPrank();
    assertEq(_qm.mutinyActive(), false);
  }
}
