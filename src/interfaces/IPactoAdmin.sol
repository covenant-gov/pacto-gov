// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IPactoAdmin
 * @author Pacto
 * @notice Minimal admin-gated surface for the Pacto Admin contract (stub; API will evolve).
 * @dev Intended wearer of the **Pacto-admin** hat in Hats. Replace filler functions when squad / channel logic lands.
 */
interface IPactoAdmin {
  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Caller is not the configured admin
   */
  error PactoAdmin_OnlyAdmin();

  /**
   * @notice Admin address was invalid at construction
   */
  error PactoAdmin_InvalidAdmin();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets the filler counter (placeholder for future state writes)
   * @param _value New counter value
   */
  function mockSetFiller(uint256 _value) external;

  /**
   * @notice Increments the filler counter by one
   */
  function mockBumpFiller() external;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Address that may call admin-gated functions
   * @return _admin The admin account
   */
  function ADMIN() external view returns (address _admin);

  /**
   * @notice Placeholder counter read by integration / unit tests
   * @return _counter Current filler value
   */
  function fillerCounter() external view returns (uint256 _counter);
}
