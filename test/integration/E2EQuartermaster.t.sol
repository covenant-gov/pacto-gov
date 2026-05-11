// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2EQuartermasterTest
 * @author Pacto
 * @notice End-to-end scenarios for `Quartermaster`; inherits `IntegrationBase` (mainnet fork required).
 */
contract E2EQuartermasterTest is IntegrationBase {
  function test_integration_registryUpgraderIsWiredAndQuartermasterMasterDeployed() public view {
    assertEq(NavePirataRegistry(_infra.registry).upgrader(), _infra.upgrader);
    Quartermaster _master = Quartermaster(_masters.quartermaster);
    assertGt(address(_master).code.length, 0);
  }
}
