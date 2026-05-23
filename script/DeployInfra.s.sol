// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployTypes} from 'script/DeployTypes.sol';
import {PactoDeploy} from 'script/PactoDeploy.sol';

import {console} from 'forge-std/console.sol';

/**
 * @title DeployInfra
 * @author Pacto
 * @notice Deploys `RoleHatClonesFactory`, `NavePirataRegistry`, `RoleHatUpgrader`, `NavePirataFactory` and wires registry.
 * @dev Does **not** deploy role master copies — run `DeployMasterCopies` first if masters are not yet on chain.
 *      Uses `script/Constants.sol` + `block.chainid` for Hats / Safe singletons.
 */
contract DeployInfra is PactoDeploy {
  function run() external {
    DeployTypes.ExternalAddresses memory _ext = _externalAddressesForCurrentChain();
    vm.startBroadcast();
    _deployInfra(_ext, _broadcastDeployer());
    vm.stopBroadcast();
    _writeExternalAddressesJson(_ext);
    _writeInfraJson(_infra);
    console.log('RoleHatClonesFactory:', _infra.clonesFactory);
    console.log('NavePirataRegistry:', _infra.registry);
    console.log('RoleHatUpgrader:', _infra.upgrader);
    console.log('NavePirataFactory:', _infra.navePirataFactory);
  }
}
