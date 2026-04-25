// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ITreasuryAuthority} from 'interfaces/ITreasuryAuthority.sol';

/**
 * @title INavePirataFactory
 * @author Pacto
 * @notice One-shot bootstrap factory that deploys a full Nave Pirata squad in a single transaction.
 * @dev Deploys the Safe, mints the hat tree (tophat, captain, crew, squad-admin, and role hats),
 *      clones Quartermaster / MutinyModule / TreasuryAuthority from approved master copies, creates
 *      the SquadAdmin UUPS proxy, initializes each role contract, mints each role hat to its clone,
 *      wires TreasuryAuthority as both the Safe's sole owner and sole Zodiac module, and registers
 *      the deployment in `NavePirataRegistry`. The tophat is transferred to the Safe at the end of
 *      the ceremony.
 */
interface INavePirataFactory {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Governance defaults for a new squad.
   * @param crewChangeDelay Seconds between scheduling and executing a crew add / remove.
   * @param proposalExpiry Seconds after creation before a TreasuryAuthority proposal expires.
   * @param crewVoteMode Crew vote counting mode (snapshot-majority or quorum-of-cast).
   * @param quorumBps Quorum in basis points, only applied when `crewVoteMode == QUORUM_OF_CAST`.
   */
  struct SquadParams {
    uint256 crewChangeDelay;
    uint256 proposalExpiry;
    ITreasuryAuthority.CrewVoteMode crewVoteMode;
    uint256 quorumBps;
  }

  /**
   * @notice Deployment parameters supplied by the caller.
   * @param captain Initial captain (EOA or contract; non-zero).
   * @param metadataURI Squad metadata URI (surfaced by pacto-app).
   * @param squadParams Initial governance values (validated by each role’s initializer).
   * @param quartermasterMasterCopy Approved Quartermaster master copy to clone.
   * @param mutinyMasterCopy Approved MutinyModule master copy to clone.
   * @param treasuryAuthorityMasterCopy Approved TreasuryAuthority master copy to clone.
   * @param squadAdminImplementation SquadAdmin UUPS implementation to back the proxy.
   * @param saltNonce CREATE2 nonce for Safe + clone determinism.
   */
  struct DeployParams {
    address captain;
    string metadataURI;
    SquadParams squadParams;
    address quartermasterMasterCopy;
    address mutinyMasterCopy;
    address treasuryAuthorityMasterCopy;
    address squadAdminImplementation;
    uint256 saltNonce;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A new Nave Pirata squad was deployed.
   * @param _topHatId Squad tophat id (registry key).
   * @param _captain Initial captain.
   * @param _safe Deployed Safe.
   * @param _quartermaster Quartermaster clone.
   * @param _mutinyModule MutinyModule clone.
   * @param _treasuryAuthority TreasuryAuthority clone.
   * @param _squadAdminProxy SquadAdmin UUPS proxy.
   */
  event NavePirataDeployed(
    uint256 indexed _topHatId,
    address indexed _captain,
    address _safe,
    address _quartermaster,
    address _mutinyModule,
    address _treasuryAuthority,
    address _squadAdminProxy
  );

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A required deployment field was the zero address.
   * @param _field Name of the zero field (for debugging).
   */
  error NavePirataFactory_ZeroAddress(string _field);
  /// @notice The Safe deployment call failed.
  error NavePirataFactory_SafeDeployFailed();
  /// @notice Teardown of the factory's temporary ownership at the end of the ceremony failed.
  error NavePirataFactory_BootstrapTeardownFailed();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy a full Nave Pirata squad in one transaction.
   * @param _params Deployment parameters.
   * @return _topHatId Tophat id minted for this squad.
   * @return _safe Deployed Safe.
   * @return _quartermaster Quartermaster clone.
   * @return _mutinyModule MutinyModule clone.
   * @return _treasuryAuthority TreasuryAuthority clone.
   * @return _squadAdminProxy SquadAdmin UUPS proxy.
   */
  function deployNavePirata(DeployParams calldata _params)
    external
    returns (
      uint256 _topHatId,
      address _safe,
      address _quartermaster,
      address _mutinyModule,
      address _treasuryAuthority,
      address _squadAdminProxy
    );

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Hats Protocol singleton.
   * @return _hats The Hats contract address.
   */
  function HATS() external view returns (address _hats);

  /**
   * @notice Safe proxy factory used to deploy squad Safes.
   * @return _factory The Safe proxy factory.
   */
  function SAFE_PROXY_FACTORY() external view returns (address _factory);

  /**
   * @notice Safe singleton backing deployed proxies.
   * @return _singleton The Safe singleton.
   */
  function SAFE_SINGLETON() external view returns (address _singleton);

  /**
   * @notice Role-hat clones factory used during bootstrap.
   * @return _clones The clones factory address.
   */
  function CLONES_FACTORY() external view returns (address _clones);

  /**
   * @notice Registry recording each deployment.
   * @return _registry The registry address.
   */
  function REGISTRY() external view returns (address _registry);

  /**
   * @notice Upgrader wired into each deployment.
   * @return _upgrader The upgrader address.
   */
  function UPGRADER() external view returns (address _upgrader);
}
