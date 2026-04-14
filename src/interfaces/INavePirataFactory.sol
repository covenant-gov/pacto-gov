// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title INavePirataFactory
 * @author Pacto
 * @notice One-shot deployment of Nave Pirata contracts and Hats tree wiring (implementation-specific).
 * @dev Parameters may grow; keep this interface minimal until `Quartermaster` and `MutinyModule` constructors are fixed.
 */
interface INavePirataFactory {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A full Nave Pirata deployment was completed
   * @param _quartermaster Deployed Quartermaster
   * @param _mutinyModule Deployed mutiny module
   * @param _topHatId Tophat id in Hats
   * @param _captainHatId Captain hat id
   * @param _crewHatId Crew hat id
   */
  event NavePirataDeployed(
    address indexed _quartermaster,
    address indexed _mutinyModule,
    uint256 _topHatId,
    uint256 _captainHatId,
    uint256 _crewHatId
  );

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy parameters failed validation
   */
  error NavePirataFactory_InvalidParams();

  /**
   * @notice Hats interaction failed during deploy
   */
  error NavePirataFactory_HatsError();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy Quartermaster + Mutiny module, create tophat/captain/crew hats, wire admins and initial captain mint
   * @param _hats Hats Protocol contract
   * @param _safeTophatWearer Safe that will wear the tophat
   * @param _deployerCaptain Address receiving the captain hat at bootstrap (initial captain)
   * @param _crewChangeDelay Delay for Quartermaster schedule/execute crew changes
   * @param _crewHatMaxSupply Max supply for crew hat (e.g. 10_000)
   * @param _topHatDetails Metadata/details string for tophat
   * @param _captainHatDetails Metadata/details string for captain hat
   * @param _crewHatDetails Metadata/details string for crew hat
   * @return _quartermaster Deployed Quartermaster
   * @return _mutinyModule Deployed mutiny module
   * @return _topHatId Created tophat id
   * @return _captainHatId Created captain hat id
   * @return _crewHatId Created crew hat id
   */
  function deployNavePirata(
    address _hats,
    address _safeTophatWearer,
    address _deployerCaptain,
    uint256 _crewChangeDelay,
    uint256 _crewHatMaxSupply,
    string calldata _topHatDetails,
    string calldata _captainHatDetails,
    string calldata _crewHatDetails
  )
    external
    returns (
      address _quartermaster,
      address _mutinyModule,
      uint256 _topHatId,
      uint256 _captainHatId,
      uint256 _crewHatId
    );

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Hats Protocol used by deployments from this factory
   * @return _hats The Hats contract address
   */
  function hats() external view returns (address _hats);

  /**
   * @notice Most recently deployed Quartermaster from this factory
   * @return _quartermaster Address or zero if none
   */
  function lastQuartermaster() external view returns (address _quartermaster);

  /**
   * @notice Most recently deployed mutiny module from this factory
   * @return _mutinyModule Address or zero if none
   */
  function lastMutinyModule() external view returns (address _mutinyModule);
}
