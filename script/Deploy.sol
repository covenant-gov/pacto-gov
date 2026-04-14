// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PactoAdmin} from 'contracts/PactoAdmin.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

contract Deploy is Script {
  function run() public {
    vm.startBroadcast();
    // PactoAdmin must be deployed before `INavePirataFactory.deployNavePirata(..., _pactoAdmin, ...)`.
    // Optional: `PACTO_ADMIN=0x...` sets the admin account; otherwise the broadcast `msg.sender` is used.
    address _pactoAdminOwner = vm.envOr('PACTO_ADMIN', msg.sender);
    PactoAdmin _pacto = new PactoAdmin(_pactoAdminOwner);
    vm.stopBroadcast();

    console.log('PactoAdmin:', address(_pacto));
  }
}
