// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {QuartermasterUnitTest} from './QuartermasterUnitTest.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';

contract UnitQuartermaster is QuartermasterUnitTest {
  function test_Constructor_StoresConfig() external view {
    assertEq(_qm.HATS(), _HATS_ADDRESS);
    assertEq(_qm.CREW_HAT_ID(), _CREW_HAT);
    assertEq(_qm.CAPTAIN_HAT_ID(), _CAPTAIN_HAT);
    assertEq(_qm.crewChangeDelay(), _DELAY);
    assertEq(_qm.mutinyModule(), _mutiny);
    assertEq(_qm.mutinyActive(), false);
  }

  function test_RequestAddCrew_SchedulesAndExecutes() external {
    _mockIsCaptain(_captain);
    _mockValidCrewCandidate(_candidate);

    vm.prank(_captain);
    _qm.requestAddCrew(_candidate);
    uint256 _at = _qm.pendingCrewAddAt(_candidate);
    assertEq(_at, block.timestamp + _DELAY);

    _mockValidCrewCandidate(_candidate);
    _mockMintCrewOk(_candidate, 0);

    vm.expectRevert(IQuartermaster.Quartermaster_NotExecutable.selector);
    _qm.executeAddCrew(_candidate);

    vm.warp(_at);
    _mockValidCrewCandidate(_candidate);
    _mockMintCrewOk(_candidate, 0);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _CREW_HAT, _candidate));
    _qm.executeAddCrew(_candidate);
    assertEq(_qm.pendingCrewAddAt(_candidate), 0);
  }

  function test_RequestAddCrew_RevertsWhenNotCaptain() external {
    _mockBalanceOf(_crew, _CAPTAIN_HAT, 0);
    vm.prank(_crew);
    vm.expectRevert(IQuartermaster.Quartermaster_OnlyCaptain.selector);
    _qm.requestAddCrew(_candidate);
  }

  function test_RequestAddCrew_RevertsWhenMutinyActive() external {
    vm.prank(_mutiny);
    _qm.setMutinyActive(true);

    _mockIsCaptain(_captain);
    _mockValidCrewCandidate(_candidate);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.requestAddCrew(_candidate);
  }

  function test_RequestRemoveCrew_RevertsWhenMutinyActive() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_crew, _CREW_HAT, 1);

    vm.prank(_mutiny);
    _qm.setMutinyActive(true);

    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_MutinyActive.selector);
    _qm.requestRemoveCrew(_crew);
  }

  function test_ExecuteAddCrew_RevertsNoPending() external {
    vm.expectRevert(IQuartermaster.Quartermaster_NoPendingOperation.selector);
    _qm.executeAddCrew(_candidate);
  }

  function test_RequestAddCrew_RevertsCaptainAsCandidate() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_captain, _CREW_HAT, 0);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.requestAddCrew(_captain);
  }

  function test_RequestAddCrew_RevertsIfAlreadyCrew() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_candidate, _CAPTAIN_HAT, 0);
    _mockBalanceOf(_candidate, _CREW_HAT, 1);
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.requestAddCrew(_candidate);
  }

  function test_RequestRemoveCrew_SchedulesAndExecutes() external {
    _mockIsCaptain(_captain);
    _mockBalanceOf(_crew, _CREW_HAT, 1);

    vm.prank(_captain);
    _qm.requestRemoveCrew(_crew);
    uint256 _at = _qm.pendingCrewRemoveAt(_crew);

    _mockBalanceOf(_crew, _CREW_HAT, 1);
    _mockSetHatWearerStatus(_CREW_HAT, _crew, false, false);

    vm.expectRevert(IQuartermaster.Quartermaster_NotExecutable.selector);
    _qm.executeRemoveCrew(_crew);

    vm.warp(_at);
    vm.expectCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.setHatWearerStatus.selector, _CREW_HAT, _crew, false, false)
    );
    _qm.executeRemoveCrew(_crew);
    assertEq(_qm.pendingCrewRemoveAt(_crew), 0);
  }

  function test_MintCrewFromMutiny_OnlyMutiny() external {
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_OnlyMutinyModule.selector);
    _qm.mintCrewFromMutiny(_candidate);

    _mockBalanceOf(_candidate, _CAPTAIN_HAT, 0);
    _mockMintCrewOk(_candidate, 0);
    vm.prank(_mutiny);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _CREW_HAT, _candidate));
    _qm.mintCrewFromMutiny(_candidate);
  }

  function test_MintCrewFromMutiny_RevertsIfRecipientIsCaptain() external {
    _mockBalanceOf(_captain, _CAPTAIN_HAT, 1);
    vm.prank(_mutiny);
    vm.expectRevert(IQuartermaster.Quartermaster_InvalidCandidate.selector);
    _qm.mintCrewFromMutiny(_captain);
  }

  function test_SetMutinyActive_OnlyMutiny() external {
    vm.prank(_captain);
    vm.expectRevert(IQuartermaster.Quartermaster_OnlyMutinyModule.selector);
    _qm.setMutinyActive(true);

    vm.prank(_mutiny);
    _qm.setMutinyActive(true);
    assertEq(_qm.mutinyActive(), true);
  }

  function test_CrewHandoffForMutiny_TransfersWhenNewHasCrew() external {
    address _former = makeAddr('former');
    _mockBalanceOf(_candidate, _CREW_HAT, 1);
    _mockTransferHat(_CREW_HAT, _candidate, _former);

    vm.prank(_mutiny);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _CREW_HAT, _candidate, _former));
    _qm.crewHandoffForMutiny(_former, _candidate);
  }

  function test_CrewHandoffForMutiny_MintsWhenNewHasNoCrew() external {
    address _former = makeAddr('former');
    _mockBalanceOf(_candidate, _CREW_HAT, 0);
    _mockMintCrewOk(_former, 0);

    vm.prank(_mutiny);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _CREW_HAT, _former));
    _qm.crewHandoffForMutiny(_former, _candidate);
  }

  function test_MintCrew_RevertsAtMaxSupply() external {
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
}
