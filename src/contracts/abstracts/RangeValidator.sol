// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title RangeValidator
 * @author Pacto
 * @notice Shared min/max for delays and quorum bps, plus `RangeValidator_OutOfRange`. Consuming contracts emit their own events
 * @dev Mixed into TA / QM (and similar) for bounded setters; 1 minute min delay is intentional for testing
 */
abstract contract RangeValidator {
  /// @notice Minimum accepted value for any governance delay parameter (in seconds).
  uint256 internal constant _MIN_GOV_DELAY = 1 minutes;
  /// @notice Maximum accepted value for any governance delay parameter (in seconds).
  uint256 internal constant _MAX_GOV_DELAY = 60 days;
  /// @notice Minimum accepted quorum expressed in basis points (5%).
  uint256 internal constant _MIN_QUORUM_BPS = 500;
  /// @notice Maximum accepted quorum expressed in basis points (100%).
  uint256 internal constant _MAX_QUORUM_BPS = 10_000;

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
    if (v < _MIN_GOV_DELAY || v > _MAX_GOV_DELAY) {
      revert RangeValidator_OutOfRange(v, _MIN_GOV_DELAY, _MAX_GOV_DELAY);
    }
  }

  /**
   * @notice Reverts with `RangeValidator_OutOfRange` if `v` is outside the accepted quorum range.
   * @param v Quorum value in basis points (1 bp = 0.01%).
   */
  function _validateQuorumBps(uint256 v) internal pure {
    if (v < _MIN_QUORUM_BPS || v > _MAX_QUORUM_BPS) {
      revert RangeValidator_OutOfRange(v, _MIN_QUORUM_BPS, _MAX_QUORUM_BPS);
    }
  }
}
