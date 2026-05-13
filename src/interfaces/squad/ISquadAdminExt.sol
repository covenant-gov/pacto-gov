// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';

/**
 * @title ISquadAdminExt
 * @author Pacto
 * @notice `ISquadAdmin` clone that gates roster ops with a single controller until optional hat migration.
 */
interface ISquadAdminExt is ISquadAdmin {
  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Reverts if the `initialize` function is called with the wrong parameters.
  error SquadAdminExt_UseAddressInitializer();

  /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice One-shot initializer; seeds the controller (`owner`). Hat-style `initialize` overloads revert.
   * @param _owner Controller address (e.g. DAO treasury or Moloch).
   */
  function initialize(address _owner) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Controller address.
   * @return _owner Controller address.
   */
  function owner() external view returns (address _owner);
}
