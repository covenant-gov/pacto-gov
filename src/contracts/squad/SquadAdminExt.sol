// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SquadAdmin} from 'contracts/squad/SquadAdmin.sol';

import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';
import {ISquadAdminExt} from 'interfaces/squad/ISquadAdminExt.sol';
import {IHatGated} from 'interfaces/utils/IHatGated.sol';

contract SquadAdminExt is SquadAdmin, ISquadAdminExt {
  /// @inheritdoc ISquadAdminExt
  address public owner;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Constructor.
   * @param hats_ Hats protocol address.
   */
  constructor(IHats hats_) SquadAdmin(hats_) {}

  /// @inheritdoc ISquadAdminExt
  function initialize(address _owner) external initializer {
    if (_owner == address(0)) revert SquadAdminBase_ZeroAddress();
    owner = _owner;
  }

  /// @inheritdoc ISquadAdmin
  function initialize(ISquadAdmin.InitParams calldata) external override(ISquadAdmin, SquadAdmin) initializer {
    revert SquadAdminExt_UseAddressInitializer();
  }

  /// @inheritdoc ISquadAdmin
  function initialize(uint256) external override(ISquadAdmin, SquadAdmin) initializer {
    revert SquadAdminExt_UseAddressInitializer();
  }

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  function postInitialize(InitParams calldata _p) external override(ISquadAdmin, SquadAdmin) isAllowed {
    _squadAdminInit(_p);
    owner = address(0);
  }

  /// @inheritdoc IHatGated
  function hats() public view override(IHatGated, SquadAdmin) returns (IHats _hats) {
    _hats = _HATS;
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/

  /// @notice Reverts unless `msg.sender` is the owner.
  function _requireOwner() internal view {
    if (msg.sender != owner) revert SquadAdminExt_NotAllowed();
  }

  /// @inheritdoc SquadAdmin
  function _requireAllowed() internal view override {
    if (owner != address(0)) _requireOwner();
    else super._requireAllowed();
  }
}
