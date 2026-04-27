// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IQuiescent
 * @author Pacto
 * @notice `isQuiet` gate for `RoleHatUpgrader` hat transfers. Implemented on QM, MM, TA, SquadAdmin
 */
interface IQuiescent {
  /**
   * @notice True when the clone is safe to replace (no in-flight state that a hat transfer would strand)
   * @return _quiet Safe to replace
   */
  function isQuiet() external view returns (bool _quiet);
}
