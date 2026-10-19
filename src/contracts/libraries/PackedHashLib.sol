// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title PackedHashLib
 * @author Pacto
 * @notice `keccak256` over ABI-encoded `(uint256, bytes32)` without allocating `abi.encode` memory
 */
library PackedHashLib {
  /**
   * @notice Byte-identical to `keccak256(abi.encode(a, b))`.
   * @param a First 32-byte word.
   * @param b Second 32-byte word.
   * @return digest Keccak digest of the two words.
   */
  function hashUint256Bytes32(uint256 a, bytes32 b) internal pure returns (bytes32 digest) {
    assembly ('memory-safe') {
      mstore(0x00, a)
      mstore(0x20, b)
      digest := keccak256(0x00, 0x40)
    }
  }
}
