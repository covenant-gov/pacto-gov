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
    _deployInfra(_ext, msg.sender);
    _wireRegistry(infra.registry, infra.navePirataFactory, infra.upgrader, msg.sender);
    vm.stopBroadcast();
    _writeExternalAddressesJson(_ext);
    _writeInfraJson(infra);
    console.log('RoleHatClonesFactory:', infra.clonesFactory);
    console.log('NavePirataRegistry:', infra.registry);
    console.log('RoleHatUpgrader:', infra.upgrader);
    console.log('NavePirataFactory:', infra.navePirataFactory);
  }
}
