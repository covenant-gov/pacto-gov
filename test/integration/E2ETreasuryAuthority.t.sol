// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TreasuryAuthority} from 'contracts/core/TreasuryAuthority.sol';

import {IntegrationBase} from './IntegrationBase.sol';

/**
 * @title E2ETreasuryAuthorityTest
 * @author Pacto
 * @notice End-to-end scenarios for `TreasuryAuthority`; inherits `IntegrationBase` (mainnet fork required).
 */
contract E2ETreasuryAuthorityTest is IntegrationBase {
  function test_integration_treasuryAuthorityMasterDeployedAndFactoryLive() public view {
    TreasuryAuthority _master = TreasuryAuthority(payable(masters.treasuryAuthority));
    assertGt(address(_master).code.length, 0);
    assertGt(infra.navePirataFactory.code.length, 0);
  }
}
