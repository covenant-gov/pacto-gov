// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ISquadAdmin
 * @author Pacto
 * @notice Minimal admin-gated surface for the Squad Admin contract (stub; API will evolve).
 * @dev Intended wearer of the **Squad-admin** hat in Hats. Replace filler functions when squad / channel logic lands.
 */
interface ISquadAdmin {
  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Caller is not the configured admin
   */
  error SquadAdmin_OnlyAdmin();

  /**
   * @notice Admin address was invalid at construction
   */
  error SquadAdmin_InvalidAdmin();

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
