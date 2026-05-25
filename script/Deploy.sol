// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployTypes} from 'script/DeployTypes.sol';
import {PactoDeploy} from 'script/PactoDeploy.sol';

/**
 * @title Deploy
 * @author Pacto
 * @notice One-shot chain bootstrap: master copies + infra + registry wiring.
 * @dev Chain singletons come from `script/Constants.sol` via `PactoDeploy._externalByChain` (`block.chainid`).
 */
contract Deploy is PactoDeploy {
  function run() external {
    DeployTypes.ExternalAddresses memory _ext = _externalAddressesForCurrentChain();
    vm.startBroadcast();
    _deployFullSystem(_ext, _broadcastDeployer());
    vm.stopBroadcast();
    _logDeployment();
    _writeFullSystemJson(_ext, _masters, _infra, _broadcastDeployer());
  }
}
