// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployTypes} from 'script/DeployTypes.sol';
import {PactoDeploy} from 'script/PactoDeploy.sol';

import {console} from 'forge-std/console.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title DeployMasterCopies
 * @author Pacto
 * @notice Deploys Quartermaster, MutinyModule, TreasuryAuthority, and SquadAdminImpl masters only.
 * @dev `IHats` address is resolved from `script/Constants.sol` for the current `block.chainid`.
 */
contract DeployMasterCopies is PactoDeploy {
  function run() external {
    DeployTypes.ExternalAddresses memory _ext = _externalAddressesForCurrentChain();
    vm.startBroadcast();
    _deployMasterCopies(IHats(_ext.hats));
    vm.stopBroadcast();
    _writeExternalAddressesJson(_ext);
    _writeMasterCopiesJson(_masters);
    console.log('Master Quartermaster:', _masters.quartermaster);
    console.log('Master MutinyModule:', _masters.mutinyModule);
    console.log('Master TreasuryAuthority:', _masters.treasuryAuthority);
    console.log('Master SquadAdminImpl:', _masters.squadAdminImpl);
  }
}
