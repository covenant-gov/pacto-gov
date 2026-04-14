// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PactoAdmin} from 'contracts/PactoAdmin.sol';
import {Test} from 'forge-std/Test.sol';

contract IntegrationBase is Test {
  uint256 internal constant _FORK_BLOCK = 24_213_086;

  address internal _owner = makeAddr('owner');
  /// @dev Deployed before Nave Pirata factory runs; pass `address(_pactoAdmin)` as `_pactoAdmin` in `deployNavePirata`.
  PactoAdmin internal _pactoAdmin;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), _FORK_BLOCK);
    _pactoAdmin = new PactoAdmin(_owner);
  }
}
