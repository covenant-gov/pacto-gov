// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployTypes} from 'script/DeployTypes.sol';
import {PactoDeploy} from 'script/PactoDeploy.sol';

import {Test} from 'forge-std/Test.sol';

/**
 * @title IntegrationBase
 * @author Pacto
 * @notice Runs the same deploy routine as `script/Deploy.sol` during `setUp`; registry owner is the test contract.
 * @dev Chain singletons resolve from `PactoDeploy._externalByChain` (`script/Constants.sol`). Override
 *      `_loadExternalAddresses` when a forked scenario must point at different infra.
 */
abstract contract IntegrationBase is PactoDeploy, Test {
  function setUp() public virtual {
    DeployTypes.ExternalAddresses memory _ext = _loadExternalAddresses();
    _deployFullSystem(_ext, address(this));
  }

  function _loadExternalAddresses() internal view virtual returns (DeployTypes.ExternalAddresses memory) {
    return _externalAddressesForCurrentChain();
  }
}
