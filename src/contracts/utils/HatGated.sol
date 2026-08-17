// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IHatGated} from 'interfaces/utils/IHatGated.sol';

import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title HatGated
 * @author Pacto
 * @notice Hats is the source of truth for gates; `_HATS` is immutable in the master so clones share it
 * @dev EIP-1167 min proxies delegate to the same runtime that holds the immutable
 */
abstract contract HatGated is IHatGated {
  /// @notice Hats singleton for `isWearerOfHat` checks
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
    _requireHatWearer(msg.sender, hatId);
    _;
  }

  /**
   * @notice Sets the Hats Protocol singleton for this contract's gate checks.
   * @param hats_ Hats Protocol contract address for this chain.
   */
  constructor(IHats hats_) {
    _HATS = hats_;
  }

  /// @inheritdoc IHatGated
  function hats() public view virtual returns (IHats _hats) {
    _hats = _HATS;
  }

  /**
   * @notice Internal gate helper. Reverts unless `account` wears `hatId`.
   * @dev Factored out of the modifier to keep modifier bytecode small; composable
   *      from other internal helpers when multiple hat checks compose.
   * @param account The address to gate-check.
   * @param hatId The hat id the account must wear.
   */
  function _requireHatWearer(address account, uint256 hatId) internal view {
    if (!_HATS.isWearerOfHat(account, hatId)) revert HatGated_NotHatWearer(hatId, account);
  }
}
