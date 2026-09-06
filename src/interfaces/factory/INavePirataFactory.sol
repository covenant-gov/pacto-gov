// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ITreasuryAuthority} from 'interfaces/core/ITreasuryAuthority.sol';

/**
 * @title INavePirataFactory
 * @author Pacto
 * @notice Full squad: `deployNavePirata` (`stackKind` routes Production to `NavePirataRegistry` and WarGame to
 *         `WarGameRegistry`). When a sponsor policy registry is wired, the same tx registers `topHatId` and indexes
 *         deployed module addresses for global paymaster sponsorship. Standalone squad-admin helpers:
 *         `deploySquadAdminExtStandalone`, `deploySquadAdminStandaloneCaptainHat`. Governance migration after deploy
 *         uses `postInitialize` on the clone (called by the controller / captain), not the factory.
 */
interface INavePirataFactory {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Which registry receives the deployment record.
   * @param Production `NavePirataRegistry` (real-gov index). `squadId` must be zero.
   * @param WarGame `WarGameRegistry` only. `squadId` must be non-zero; auto-retires the previous Active.
   */
  enum StackKind {
    Production,
    WarGame
  }

  /**
   * @notice Governance defaults for a new squad.
   * @param crewChangeDelay Seconds between scheduling and executing a crew add / remove.
   * @param proposalExpiry Seconds after creation before a TreasuryAuthority proposal expires. Also seeds MutinyModule `mutinyExpiry` and Quartermaster `crewOffboardExpiry`.
   * @param crewVoteMode Crew vote counting mode (snapshot-majority or quorum-of-cast). Treasury Authority only; mutiny stays 51% snapshot; crew offboard always uses `QUORUM_OF_CAST`.
   * @param quorumBps Quorum in basis points for TA `QUORUM_OF_CAST` and Quartermaster crew-led offboard.
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
   * @param squadAdminImplementation `SquadAdmin` master copy to clone (EIP-1167).
   * @param saltNonce CREATE2 nonce for Safe + clone determinism.
   * @param stackKind Production vs war-game registry routing.
   * @param squadId MLS-parent key for war-game (`keccak256`); must be zero for Production.
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
    StackKind stackKind;
    bytes32 squadId;
  }

  /**
   * @notice Hat id bundle produced while building a squad's tree, threaded through clone-init and mints.
   * @param topHatId Squad tophat id (initially worn by the factory, transferred to the Safe at the end of the ceremony).
   * @param mutinyRoleHatId MutinyRole hat id (worn by the MutinyModule clone).
   * @param quartermasterRoleHatId QuartermasterRole hat id (worn by the Quartermaster clone).
   * @param treasuryAuthorityRoleHatId TreasuryAuthorityRole hat id (worn by the TreasuryAuthority clone).
   * @param captainHatId Captain hat id (worn by `DeployParams.captain`).
   * @param crewHatId Crew hat id (empty at bootstrap; filled by Quartermaster onboarding).
   * @param squadAdminHatId Squad-admin hat id (worn by the squad-admin clone).
   */
  struct HatTree {
    uint256 topHatId;
    uint256 mutinyRoleHatId;
    uint256 quartermasterRoleHatId;
    uint256 treasuryAuthorityRoleHatId;
    uint256 captainHatId;
    uint256 crewHatId;
    uint256 squadAdminHatId;
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
   * @param _squadAdminProxy Squad-admin minimal proxy (clone).
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

  /**
   * @notice EIP-1167 clone of `SquadAdminExt` initialized with `owner` (address-gated roster).
   * @param clone Minimal proxy address.
   * @param owner Controller seeded by `initialize(address)`.
   * @param implementation Master copy cloned.
   */
  event SquadAdminExtStandaloneDeployed(address indexed clone, address indexed owner, address indexed implementation);

  /**
   * @notice EIP-1167 clone of `SquadAdmin` initialized with a single captain hat (no squad-admin hat id yet).
   * @param clone Minimal proxy address.
   * @param implementation Master copy cloned.
   * @param captainHatId Hat id that gates roster mutations until `postInitialize`.
   */
  event SquadAdminStandaloneDeployed(address indexed clone, address indexed implementation, uint256 captainHatId);

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
  /// @notice `deploySquadAdminStandaloneCaptainHat` requires a non-zero captain hat id.
  error NavePirataFactory_InvalidCaptainHat();
  /// @notice Production requires zero `squadId`; WarGame requires a non-zero `squadId`.
  error NavePirataFactory_InvalidSquadId();

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
   * @return _squadAdminProxy Squad-admin minimal proxy (clone).
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

  /**
   * @notice Permissionless one-off: clone `SquadAdminExt` and `initialize(_owner)`. Does not register in `REGISTRY`.
   * @param squadAdminExtImplementation `SquadAdminExt` master copy (same `IHats` chain singleton as protocol).
   * @param owner Non-zero controller (DAO, multisig, Moloch, etc.).
   * @return clone Minimal proxy address.
   */
  function deploySquadAdminExtStandalone(
    address squadAdminExtImplementation,
    address owner
  ) external returns (address clone);

  /**
   * @notice Permissionless one-off: clone `SquadAdmin` and `initialize(captainHatId)` for an existing captain hat.
   * @param squadAdminImplementation `SquadAdmin` master copy.
   * @param captainHatId Non-zero hat id worn by captains for roster ops; full protocol ids via `postInitialize` later.
   * @return clone Minimal proxy address.
   */
  function deploySquadAdminStandaloneCaptainHat(
    address squadAdminImplementation,
    uint256 captainHatId
  ) external returns (address clone);

  /**
   * @notice Permissionless: retire the Active war-game for `_squadId` without deploying a replacement.
   * @param squadId Squad key currently Active in `WarGameRegistry`.
   */
  function retireWarGame(bytes32 squadId) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
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
   * @notice Production registry recording real-gov deployments.
   * @return _registry The production `NavePirataRegistry` address.
   */
  function REGISTRY() external view returns (address _registry);

  /**
   * @notice War-game registry for throwaway stacks (`stackKind == WarGame`).
   * @return _registry The `WarGameRegistry` address.
   */
  function WAR_GAME_REGISTRY() external view returns (address _registry);

  /**
   * @notice Upgrader wired into each deployment.
   * @return _upgrader The upgrader address.
   */
  function UPGRADER() external view returns (address _upgrader);

  /**
   * @notice Optional username global sponsor policy registry.
   * @return _registry The policy registry address (zero when unwired).
   */
  function SPONSOR_POLICY_REGISTRY() external view returns (address _registry);
}
