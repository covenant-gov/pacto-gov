// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from 'forge-std/Test.sol';

/**
 * @title IntegrationBase
 * @author Pacto
 * @notice Placeholder base for integration tests.
 * @dev Phase 8 of the tech spec adds the full integration harness (forked Safe + Hats + full
 *      Nave Pirata bootstrap). This stub exists so `forge build` stays green while Phases 1–7
 *      land.
 */
abstract contract IntegrationBase is Test {
  function setUp() public virtual {}
}
