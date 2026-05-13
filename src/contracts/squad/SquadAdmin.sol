// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {SquadAdminBase} from 'contracts/abstracts/SquadAdminBase.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title SquadAdmin
 * @author Pacto
 * @notice v1: captain-gated per-role executors, `bytes32("FULL")`, and `bytes32("PAUSE")` kill-switch.
 * @dev Deploy behind an EIP-1167 minimal proxy (see `Clones`); immutable `_HATS` lives on this master copy; clones delegate here.
 */
contract SquadAdmin is ISquadAdmin, SquadAdminBase, HatGated, Initializable {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  uint256 public captainHatId;
  /// @inheritdoc ISquadAdmin
  uint256 public squadAdminHatId;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Master-copy constructor; bakes the Hats singleton into implementation runtime code
   *         and locks direct initialization of the implementation.
   * @param hats_ Hats Protocol address for this chain.
   */
  constructor(IHats hats_) HatGated(hats_) {
    _disableInitializers();
  }

  /// @inheritdoc ISquadAdmin
  function initialize(InitParams calldata _p) external override initializer {
    __SquadAdmin_init(_p);
  }

  /**
   * @notice Hat ids for this clone; only callable while `initializer` is running (`onlyInitializing`).
   * @param _p Bootstrap parameters.
   */
  // forge-lint: disable-next-line(mixed-case-function)
  function __SquadAdmin_init(InitParams calldata _p) internal onlyInitializing {
    captainHatId = _p.captainHatId;
    squadAdminHatId = _p.squadAdminHatId;
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/

  /// @notice Requires `msg.sender` to wear the captain hat; otherwise `SquadAdminBase_NotAllowed`.
  function _requireAllowed() internal view override {
    if (!_HATS.isWearerOfHat(msg.sender, captainHatId)) revert SquadAdminBase_NotAllowed();
  }
}
