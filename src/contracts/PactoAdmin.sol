// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPactoAdmin} from 'interfaces/IPactoAdmin.sol';

/**
 * @title PactoAdmin
 * @author Pacto
 * @notice Stub admin contract: single on-chain admin and filler mutators for deploy / factory / test wiring.
 * @dev Replace filler logic when `IPactoAdmin` expands. Hats mint target for **Pacto-admin** hat in Nave Pirata.
 */
contract PactoAdmin is IPactoAdmin {
  /*///////////////////////////////////////////////////////////////
                            IMMUTABLES
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IPactoAdmin
  address public immutable ADMIN;

  /*///////////////////////////////////////////////////////////////
                            STATE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IPactoAdmin
  uint256 public fillerCounter;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier onlyAdmin() {
    if (msg.sender != ADMIN) revert PactoAdmin_OnlyAdmin();
    _;
  }

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @param _admin Account that may call `onlyAdmin` functions
   */
  constructor(address _admin) {
    if (_admin == address(0)) revert PactoAdmin_InvalidAdmin();
    ADMIN = _admin;
  }

  /*///////////////////////////////////////////////////////////////
                            EXTERNAL
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IPactoAdmin
  function mockSetFiller(uint256 _value) external onlyAdmin {
    fillerCounter = _value;
  }

  /// @inheritdoc IPactoAdmin
  function mockBumpFiller() external onlyAdmin {
    unchecked {
      ++fillerCounter;
    }
  }
}
