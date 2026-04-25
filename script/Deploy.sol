// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployTypes} from 'script/DeployTypes.sol';
import {PactoDeploy} from 'script/PactoDeploy.sol';

/**
 * @title Deploy
 * @author Pacto
 * @notice One-shot chain bootstrap: master copies + infra + registry wiring (tech spec §11 P9.1 + P9.2).
 * @dev Chain singletons come from `script/Constants.sol` via `PactoDeploy._externalByChain` (`block.chainid`).
 */
contract Deploy is PactoDeploy {
  function run() external {
    DeployTypes.ExternalAddresses memory _ext = _externalAddressesForCurrentChain();
    vm.startBroadcast();
    _deployFullSystem(_ext, msg.sender);
    vm.stopBroadcast();
    _logDeployment();
  }
}
