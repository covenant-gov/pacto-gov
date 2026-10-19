// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title VoteThresholdLib
 * @author Pacto
 * @notice Pure pass predicates: majority of snapshot, or quorum-of-cast
 */
library VoteThresholdLib {
  /**
   * @notice Strict majority of a fixed snapshot (`yeas * 2 > snapshot`).
   * @param yeas Yea tally.
   * @param snapshot Roster size at round open.
   * @return passed True iff yeas strictly exceed half the snapshot.
   */
  function majoritySnapshot(uint256 yeas, uint256 snapshot) internal pure returns (bool passed) {
    passed = yeas * 2 > snapshot;
  }

  /**
   * @notice Turnout reaches `quorumBps` of snapshot and yeas strictly exceed nays.
   * @param yeas Yea tally.
   * @param nays Nay tally.
   * @param snapshot Roster size at round open.
   * @param quorumBps Required cast / snapshot in basis points.
   * @return passed True iff quorum and yea > nay both hold.
   */
  function quorumOfCast(
    uint256 yeas,
    uint256 nays,
    uint256 snapshot,
    uint256 quorumBps
  ) internal pure returns (bool passed) {
    uint256 cast = yeas + nays;
    if (cast * 10_000 < snapshot * quorumBps) passed = false;
    else passed = yeas > nays;
  }
}
