// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PactoDeploy} from 'script/PactoDeploy.sol';

import {console} from 'forge-std/console.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title DeployMasterCopies
 * @author Pacto
 * @notice Deploys Quartermaster, MutinyModule, TreasuryAuthority, and SquadAdminImpl masters only (tech spec §11 P9.1).
 * @dev `IHats` address is resolved from `script/Constants.sol` for the current `block.chainid`.
 */
contract DeployMasterCopies is PactoDeploy {
  function run() external {
    address _hats = _externalAddressesForCurrentChain().hats;
    vm.startBroadcast();
    _deployMasterCopies(IHats(_hats));
    vm.stopBroadcast();
    console.log('Master Quartermaster:', masters.quartermaster);
    console.log('Master MutinyModule:', masters.mutinyModule);
    console.log('Master TreasuryAuthority:', masters.treasuryAuthority);
    console.log('Master SquadAdminImpl:', masters.squadAdminImpl);
  }
}
