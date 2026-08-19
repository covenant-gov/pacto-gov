// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IRangeValidator} from 'interfaces/utils/IRangeValidator.sol';

/**
 * @title RangeValidator
 * @author Pacto
 * @notice Shared min/max for delays and quorum bps, plus `RangeValidator_OutOfRange`. Consuming contracts emit their own events
 * @dev Mixed into TA / QM / MM for bounded setters; 1 minute min delay is intentional for testing
 */
abstract contract RangeValidator is IRangeValidator {
  /// @inheritdoc IRangeValidator
  uint256 public constant MIN_GOV_DELAY = 1 minutes;
  /// @inheritdoc IRangeValidator
  uint256 public constant MAX_GOV_DELAY = 60 days;
  /// @inheritdoc IRangeValidator
  uint256 public constant MIN_QUORUM_BPS = 500;
  /// @inheritdoc IRangeValidator
  uint256 public constant MAX_QUORUM_BPS = 10_000;

  /**
   * @notice Value is outside the inclusive `min`–`max` range for a governance parameter.
   * @param value The rejected value.
   * @param min The inclusive lower bound.
   * @param max The inclusive upper bound.
   */
  error RangeValidator_OutOfRange(uint256 value, uint256 min, uint256 max);

  /**
   * @notice Reverts with `RangeValidator_OutOfRange` if `v` is outside the accepted delay range.
   * @param v Delay value in seconds.
   */
  function _validateDelay(uint256 v) internal pure {
    if (v < MIN_GOV_DELAY || v > MAX_GOV_DELAY) {
      revert RangeValidator_OutOfRange(v, MIN_GOV_DELAY, MAX_GOV_DELAY);
    }
  }

  /**
   * @notice Reverts with `RangeValidator_OutOfRange` if `v` is outside the accepted quorum range.
   * @param v Quorum value in basis points (1 bp = 0.01%).
   */
  function _validateQuorumBps(uint256 v) internal pure {
    if (v < MIN_QUORUM_BPS || v > MAX_QUORUM_BPS) {
      revert RangeValidator_OutOfRange(v, MIN_QUORUM_BPS, MAX_QUORUM_BPS);
    }
  }
}
