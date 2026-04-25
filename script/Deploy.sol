// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title Deploy
 * @author Pacto
 * @notice Placeholder deployment script.
 * @dev Real Nave Pirata deployment logic (master copies, `NavePirataFactory`, registry, upgrader,
 *      per-chain wiring) is introduced in Phase 9 of the tech spec. This file compiles empty in
 *      the meantime so `forge build` in the repository stays green.
 */
contract Deploy is Script {
  function run() public pure {
    console.log('Deploy: Nave Pirata deployment script lands in Phase 9.');
  }
}
