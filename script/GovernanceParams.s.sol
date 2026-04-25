// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataFactory} from 'interfaces/INavePirataFactory.sol';
import {CREW_CHANGE_DELAY, DEFAULT_CREW_VOTE_MODE, PROPOSAL_EXPIRY, SQUAD_QUORUM_BPS} from 'script/Constants.sol';

/**
 * @title ScriptGovernanceParams
 * @author Pacto
 * @notice Default squad governance values for deploy scripts and integration tests on every chain.
 * @dev Numeric defaults live in `script/Constants.sol`. Not to be confused with `contracts/abstracts/RangeValidator.sol`
 *      (on-chain min/max validation). Use `vm.warp` in tests instead of shorter Anvil-only delays.
 */
abstract contract ScriptGovernanceParams {
  /// @notice Production-style delays; same mapping is used for Anvil and live chains.
  function squadParamsProduction() internal pure returns (INavePirataFactory.SquadParams memory _p) {
    _p = INavePirataFactory.SquadParams({
      crewChangeDelay: CREW_CHANGE_DELAY,
      proposalExpiry: PROPOSAL_EXPIRY,
      crewVoteMode: DEFAULT_CREW_VOTE_MODE,
      quorumBps: SQUAD_QUORUM_BPS
    });
  }
}
