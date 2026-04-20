// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SquadAdmin} from 'contracts/SquadAdmin.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

contract Deploy is Script {
  function run() public {
    vm.startBroadcast();
    // SquadAdmin must be deployed before `INavePirataFactory.deployNavePirata(..., _squadAdmin, ...)`.
    // Optional: `SQUAD_ADMIN=0x...` sets the admin account; otherwise the broadcast `msg.sender` is used.
    address _squadAdminOwner = vm.envOr('SQUAD_ADMIN', msg.sender);
    SquadAdmin _squad = new SquadAdmin(_squadAdminOwner);
    vm.stopBroadcast();

    console.log('SquadAdmin:', address(_squad));
  }
}
