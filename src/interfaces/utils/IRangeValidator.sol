// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IRangeValidator
 * @author Pacto
 * @notice Inclusive bounds for governance delays and quorum bps.
 */
interface IRangeValidator {
  /**
   * @notice Minimum accepted governance delay, in seconds.
   * @return _min Delay lower bound.
   */
  function MIN_GOV_DELAY() external view returns (uint256 _min);

  /**
   * @notice Maximum accepted governance delay, in seconds.
   * @return _max Delay upper bound.
   */
  function MAX_GOV_DELAY() external view returns (uint256 _max);

  /**
   * @notice Minimum accepted quorum, in basis points.
   * @return _min Quorum lower bound.
   */
  function MIN_QUORUM_BPS() external view returns (uint256 _min);

  /**
   * @notice Maximum accepted quorum, in basis points.
   * @return _max Quorum upper bound.
   */
  function MAX_QUORUM_BPS() external view returns (uint256 _max);
}
