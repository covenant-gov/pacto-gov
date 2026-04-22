// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IQuiescent
 * @author Pacto
 * @notice Advertises the contract's compliance with the Quiet-Window Invariant.
 * @dev Every upgradeable role contract (Quartermaster, MutinyModule, TreasuryAuthority, SquadAdmin)
 *      MUST implement this interface. `RoleHatUpgrader` queries `isQuiet()` before transferring a
 *      role hat to a replacement clone; a `false` result aborts the upgrade to prevent losing
 *      in-flight state (pending crew changes, open mutinies, open proposals, etc.).
 */
interface IQuiescent {
  /**
   * @notice True iff this contract has no in-flight state that a hat transfer would orphan.
   * @return _quiet Whether it is currently safe to replace this clone.
   */
  function isQuiet() external view returns (bool _quiet);
}
