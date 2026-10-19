// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title DeadlineLib
 * @author Pacto
 * @notice `block.timestamp + duration` packed to `uint64`, or `DeadlineLib_Overflow`
 */
library DeadlineLib {
  /// @notice `block.timestamp + durationSeconds` exceeds `type(uint64).max`.
  error DeadlineLib_Overflow();

  /**
   * @notice `block.timestamp + durationSeconds` as `uint64`.
   * @param durationSeconds Seconds to add to `block.timestamp`.
   * @return deadline Packed deadline / ETA.
   */
  function fromDuration(uint256 durationSeconds) internal view returns (uint64 deadline) {
    uint256 deadline256 = block.timestamp + durationSeconds;
    if (deadline256 > type(uint64).max) revert DeadlineLib_Overflow();
    // casting to 'uint64' is safe because `deadline256` is checked against `type(uint64).max` above.
    // forge-lint: disable-next-line(unsafe-typecast)
    deadline = uint64(deadline256);
  }
}
