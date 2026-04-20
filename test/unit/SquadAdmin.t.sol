// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SquadAdmin} from 'contracts/SquadAdmin.sol';
import {Test} from 'forge-std/Test.sol';
import {ISquadAdmin} from 'interfaces/ISquadAdmin.sol';

contract UnitSquadAdmin is Test {
  address internal _admin = makeAddr('admin');
  address internal _stranger = makeAddr('stranger');
  SquadAdmin internal _squadAdmin;

  function setUp() external {
    _squadAdmin = new SquadAdmin(_admin);
  }

  function test_Constructor_StoresAdmin() external view {
    assertEq(_squadAdmin.ADMIN(), _admin);
  }

  function test_Constructor_RevertsOnZeroAdmin() external {
    vm.expectRevert(ISquadAdmin.SquadAdmin_InvalidAdmin.selector);
    new SquadAdmin(address(0));
  }

  function test_MockSetFiller_WhenCallerIsAdmin() external {
    vm.prank(_admin);
    _squadAdmin.mockSetFiller(42);
    assertEq(_squadAdmin.fillerCounter(), 42);
  }

  function test_MockBumpFiller_WhenCallerIsAdmin() external {
    vm.prank(_admin);
    _squadAdmin.mockBumpFiller();
    assertEq(_squadAdmin.fillerCounter(), 1);
    vm.prank(_admin);
    _squadAdmin.mockBumpFiller();
    assertEq(_squadAdmin.fillerCounter(), 2);
  }

  function test_MockSetFiller_RevertsWhenNotAdmin() external {
    vm.prank(_stranger);
    vm.expectRevert(ISquadAdmin.SquadAdmin_OnlyAdmin.selector);
    _squadAdmin.mockSetFiller(1);
  }

  function test_MockBumpFiller_RevertsWhenNotAdmin() external {
    vm.prank(_stranger);
    vm.expectRevert(ISquadAdmin.SquadAdmin_OnlyAdmin.selector);
    _squadAdmin.mockBumpFiller();
  }
}
