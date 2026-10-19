// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title BitFlagLib
 * @author Pacto
 * @notice Set or clear a bit in a `uint8` flags word; reports whether the word changed
 */
library BitFlagLib {
  /**
   * @notice Apply `mask` to `flags` (set if `enable`, clear otherwise).
   * @param flags Current flags word.
   * @param mask Single-bit (or multi-bit) mask to set or clear.
   * @param enable True to set bits in `mask`; false to clear them.
   * @return next Updated flags word.
   * @return changed Whether `next` differs from `flags`.
   */
  function setFlag(uint8 flags, uint8 mask, bool enable) internal pure returns (uint8 next, bool changed) {
    next = enable ? uint8(flags | mask) : uint8(flags & ~mask);
    changed = next != flags;
  }
}
