// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SquadAdmin} from 'contracts/squad/SquadAdmin.sol';

import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';
import {ISquadAdminExt} from 'interfaces/squad/ISquadAdminExt.sol';

contract SquadAdminExt is SquadAdmin, ISquadAdminExt {
  /// @inheritdoc ISquadAdminExt
  address public owner;

  /**
   * @notice Constructor.
   * @param hats_ Hats protocol address.
   */
  constructor(IHats hats_) SquadAdmin(hats_) {}

  /// @inheritdoc ISquadAdminExt
  function initialize(address _owner) external override(ISquadAdminExt) initializer {
    if (_owner == address(0)) revert SquadAdminBase_ZeroAddress();
    owner = _owner;
  }

  /// @inheritdoc ISquadAdmin
  function initialize(ISquadAdmin.InitParams calldata) external pure override(ISquadAdmin, SquadAdmin) {
    revert SquadAdminExt_UseAddressInitializer();
  }

  /// @inheritdoc ISquadAdmin
  function initialize(uint256) external pure override(ISquadAdmin, SquadAdmin) {
    revert SquadAdminExt_UseAddressInitializer();
  }

  /// @inheritdoc SquadAdmin
  function _requireAllowed() internal view override {
    if (msg.sender != owner) revert SquadAdminBase_NotAllowed();
  }
}
