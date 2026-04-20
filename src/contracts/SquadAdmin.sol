// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISquadAdmin} from 'interfaces/ISquadAdmin.sol';

/**
 * @title SquadAdmin
 * @author Pacto
 * @notice Stub admin contract: single on-chain admin and filler mutators for deploy / factory / test wiring.
 * @dev Replace filler logic when `ISquadAdmin` expands. Hats mint target for **Squad-admin** hat in Nave Pirata.
 */
contract SquadAdmin is ISquadAdmin {
  /*///////////////////////////////////////////////////////////////
                            IMMUTABLES
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  address public immutable ADMIN;

  /*///////////////////////////////////////////////////////////////
                            STATE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  uint256 public fillerCounter;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier onlyAdmin() {
    if (msg.sender != ADMIN) revert SquadAdmin_OnlyAdmin();
    _;
  }

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @param _admin Account that may call `onlyAdmin` functions
   */
  constructor(address _admin) {
    if (_admin == address(0)) revert SquadAdmin_InvalidAdmin();
    ADMIN = _admin;
  }

  /*///////////////////////////////////////////////////////////////
                            EXTERNAL
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  function mockSetFiller(uint256 _value) external onlyAdmin {
    fillerCounter = _value;
  }

  /// @inheritdoc ISquadAdmin
  function mockBumpFiller() external onlyAdmin {
    unchecked {
      ++fillerCounter;
    }
  }
}
