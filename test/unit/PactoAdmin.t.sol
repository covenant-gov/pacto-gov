// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PactoAdmin} from 'contracts/PactoAdmin.sol';
import {Test} from 'forge-std/Test.sol';
import {IPactoAdmin} from 'interfaces/IPactoAdmin.sol';

contract UnitPactoAdmin is Test {
  address internal _admin = makeAddr('admin');
  address internal _stranger = makeAddr('stranger');
  PactoAdmin internal _pacto;

  function setUp() external {
    _pacto = new PactoAdmin(_admin);
  }

  function test_Constructor_StoresAdmin() external view {
    assertEq(_pacto.admin(), _admin);
  }

  function test_Constructor_RevertsOnZeroAdmin() external {
    vm.expectRevert(IPactoAdmin.PactoAdmin_InvalidAdmin.selector);
    new PactoAdmin(address(0));
  }

  function test_MockSetFiller_WhenCallerIsAdmin() external {
    vm.prank(_admin);
    _pacto.mockSetFiller(42);
    assertEq(_pacto.fillerCounter(), 42);
  }

  function test_MockBumpFiller_WhenCallerIsAdmin() external {
    vm.prank(_admin);
    _pacto.mockBumpFiller();
    assertEq(_pacto.fillerCounter(), 1);
    vm.prank(_admin);
    _pacto.mockBumpFiller();
    assertEq(_pacto.fillerCounter(), 2);
  }

  function test_MockSetFiller_RevertsWhenNotAdmin() external {
    vm.prank(_stranger);
    vm.expectRevert(IPactoAdmin.PactoAdmin_OnlyAdmin.selector);
    _pacto.mockSetFiller(1);
  }

  function test_MockBumpFiller_RevertsWhenNotAdmin() external {
    vm.prank(_stranger);
    vm.expectRevert(IPactoAdmin.PactoAdmin_OnlyAdmin.selector);
    _pacto.mockBumpFiller();
  }
}
