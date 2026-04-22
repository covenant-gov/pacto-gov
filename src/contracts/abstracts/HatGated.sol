// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title HatGated
 * @author Pacto
 * @notice Shared base for hat-gated access control. Implements the "Authority Lookup"
 *         pattern by resolving gate checks against Hats Protocol at call time rather
 *         than caching peer addresses.
 * @dev The address of the Hats singleton is baked into the deploying contract's
 *      runtime code as an `immutable`. For EIP-1167 clones this value is inherited
 *      from the master copy (clones delegate-call into the master's runtime code),
 *      so one master copy per chain is sufficient even though the `_HATS` address
 *      differs per chain.
 */
abstract contract HatGated {
  /**
   * @notice Hats Protocol singleton used for all gate checks.
   * @dev Immutable for gas-efficient reads and for inclusion in the master copy runtime code of clones.
   */
  IHats internal immutable _HATS;

  /**
   * @notice Caller does not wear the hat required to call the gated function.
   * @param hatId The hat id that the caller must wear.
   * @param caller The caller that failed the gate check.
   */
  error HatGated_NotHatWearer(uint256 hatId, address caller);

  /**
   * @notice Reverts unless `msg.sender` currently wears `hatId`.
   * @dev Wraps `IHats.isWearerOfHat` which checks both ownership and eligibility/standing.
   * @param hatId The hat id the caller must wear.
   */
  modifier onlyHatWearer(uint256 hatId) {
    _requireHatWearer(hatId, msg.sender);
    _;
  }

  /**
   * @notice Sets the Hats Protocol singleton for this contract's gate checks.
   * @param hats_ Hats Protocol contract address for this chain.
   */
  constructor(IHats hats_) {
    _HATS = hats_;
  }

  /**
   * @notice Internal gate helper. Reverts unless `account` wears `hatId`.
   * @dev Factored out of the modifier to keep modifier bytecode small; composable
   *      from other internal helpers when multiple hat checks compose.
   * @param hatId The hat id the account must wear.
   * @param account The address to gate-check.
   */
  function _requireHatWearer(uint256 hatId, address account) internal view {
    if (!_HATS.isWearerOfHat(account, hatId)) revert HatGated_NotHatWearer(hatId, account);
  }
}
