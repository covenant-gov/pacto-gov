// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title IHatGated
 * @author Pacto
 * @notice Hats singleton pointer shared by hat-gated clones.
 */
interface IHatGated {
  /**
   * @notice Hats Protocol singleton used for gate checks.
   * @return _hats Hats address.
   */
  function hats() external view returns (IHats _hats);
}
