// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title GovernanceParams
 * @author Pacto
 * @notice Shared sanity bounds and revert signatures for Nave Pirata governance
 *         parameters (delays and quorums). Per-parameter events live on each
 *         role contract's own interface; only the bound errors are shared here
 *         because they're meaningful across contracts.
 * @dev Designed to be inherited by contracts that expose TreasuryAuthorityRole-gated
 *      setters (e.g. `Quartermaster.setCrewChangeDelay`, `TreasuryAuthority.setProposalExpiry`).
 *
 *      The lower bound on delays is intentionally permissive (1 minute) to support
 *      alpha testing, demos, and users learning governance hands-on. Safety comes
 *      from the two-body vote that gates every setter, not from a mandatory delay
 *      floor. Squads that want a longer floor can enforce it socially via proposal
 *      review.
 */
abstract contract GovernanceParams {
  /// @notice Minimum accepted value for any governance delay parameter (in seconds).
  uint256 internal constant _MIN_GOV_DELAY = 1 minutes;

  /// @notice Maximum accepted value for any governance delay parameter (in seconds).
  uint256 internal constant _MAX_GOV_DELAY = 60 days;

  /// @notice Minimum accepted quorum expressed in basis points (5%).
  uint256 internal constant _MIN_QUORUM_BPS = 500;

  /// @notice Maximum accepted quorum expressed in basis points (100%).
  uint256 internal constant _MAX_QUORUM_BPS = 10_000;

  /**
   * @notice Provided delay value is outside `[_MIN_GOV_DELAY, _MAX_GOV_DELAY]`.
   * @param value The rejected delay value.
   * @param min The inclusive lower bound.
   * @param max The inclusive upper bound.
   */
  error GovernanceParams_DelayOutOfRange(uint256 value, uint256 min, uint256 max);

  /**
   * @notice Provided quorum value is outside `[_MIN_QUORUM_BPS, _MAX_QUORUM_BPS]`.
   * @param value The rejected quorum value in basis points.
   * @param min The inclusive lower bound in basis points.
   * @param max The inclusive upper bound in basis points.
   */
  error GovernanceParams_QuorumOutOfRange(uint256 value, uint256 min, uint256 max);

  /**
   * @notice Reverts with `GovernanceParams_DelayOutOfRange` if `v` is outside the accepted delay range.
   * @param v Delay value in seconds.
   */
  function _validateDelay(uint256 v) internal pure {
    if (v < _MIN_GOV_DELAY || v > _MAX_GOV_DELAY) {
      revert GovernanceParams_DelayOutOfRange(v, _MIN_GOV_DELAY, _MAX_GOV_DELAY);
    }
  }

  /**
   * @notice Reverts with `GovernanceParams_QuorumOutOfRange` if `v` is outside the accepted quorum range.
   * @param v Quorum value in basis points (1 bp = 0.01%).
   */
  function _validateQuorumBps(uint256 v) internal pure {
    if (v < _MIN_QUORUM_BPS || v > _MAX_QUORUM_BPS) {
      revert GovernanceParams_QuorumOutOfRange(v, _MIN_QUORUM_BPS, _MAX_QUORUM_BPS);
    }
  }
}
