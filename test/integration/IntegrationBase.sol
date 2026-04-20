// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SquadAdmin} from 'contracts/SquadAdmin.sol';
import {Test} from 'forge-std/Test.sol';

abstract contract IntegrationBase is Test {
  /// @dev Deployed before Nave Pirata factory runs; pass `address(_squadAdmin)` as `_squadAdmin` in `deployNavePirata`.
  SquadAdmin internal _squadAdmin;

  function setUp() public virtual {
    address _owner = address(this);
    _squadAdmin = new SquadAdmin(_owner);
  }
}
