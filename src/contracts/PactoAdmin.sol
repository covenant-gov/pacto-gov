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
  address public immutable admin;

  /*///////////////////////////////////////////////////////////////
                            STATE
  //////////////////////////////////////////////////////////////*/

  uint256 internal _fillerCounter;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier onlyAdmin() {
    if (msg.sender != admin) revert PactoAdmin_OnlyAdmin();
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
    admin = _admin;
  }

  /*///////////////////////////////////////////////////////////////
                            EXTERNAL
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IPactoAdmin
  function mockSetFiller(uint256 _value) external onlyAdmin {
    _fillerCounter = _value;
  }

  /// @inheritdoc IPactoAdmin
  function mockBumpFiller() external onlyAdmin {
    unchecked {
      ++_fillerCounter;
    }
  }

  /// @inheritdoc IPactoAdmin
  function fillerCounter() external view returns (uint256 _counter) {
    return _fillerCounter;
  }
}
