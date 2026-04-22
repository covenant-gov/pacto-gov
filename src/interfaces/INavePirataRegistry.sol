// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title INavePirataRegistry
 * @author Pacto
 * @notice Append-only, on-chain discovery registry for deployed Nave Pirata squads and their
 *         role-hat upgrade history.
 * @dev Writes come exclusively from two trusted contracts wired at deploy time: `NavePirataFactory`
 *      (initial registration) and `RoleHatUpgrader` (upgrade records). Pacto-app consumes this
 *      registry to discover per-squad addresses and hat ids without rescanning events.
 */
interface INavePirataRegistry {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Initial deployment record for a squad.
   * @param safe Squad Safe address.
   * @param quartermaster Quartermaster clone address.
   * @param mutinyModule MutinyModule clone address.
   * @param treasuryAuthority TreasuryAuthority clone address.
   * @param squadAdminProxy SquadAdmin UUPS proxy address.
   * @param topHatId Tophat id worn by the squad Safe.
   * @param captainHatId Captain hat id.
   * @param crewHatId Crew hat id.
   * @param squadAdminHatId Squad-admin hat id.
   * @param mutinyRoleHatId MutinyRole hat id.
   * @param quartermasterRoleHatId QuartermasterRole hat id.
   * @param treasuryAuthorityRoleHatId TreasuryAuthorityRole hat id.
   * @param deployedAt Timestamp of the bootstrap transaction.
   * @param deployer Address that called `NavePirataFactory.deployNavePirata`.
   */
  struct Deployment {
    address safe;
    address quartermaster;
    address mutinyModule;
    address treasuryAuthority;
    address squadAdminProxy;
    uint256 topHatId;
    uint256 captainHatId;
    uint256 crewHatId;
    uint256 squadAdminHatId;
    uint256 mutinyRoleHatId;
    uint256 quartermasterRoleHatId;
    uint256 treasuryAuthorityRoleHatId;
    uint64 deployedAt;
    address deployer;
  }

  /**
   * @notice Per-upgrade audit record.
   * @param roleHatId Role hat id that changed wearer.
   * @param oldClone Previous clone address.
   * @param newClone New clone address.
   * @param masterCopy Implementation used for `newClone`.
   * @param upgradedAt Timestamp of the upgrade transaction.
   */
  struct UpgradeRecord {
    uint256 roleHatId;
    address oldClone;
    address newClone;
    address masterCopy;
    uint64 upgradedAt;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A new squad was registered.
   * @param _topHatId Tophat id used as the squad key.
   * @param _deployment Full deployment record.
   */
  event NavePirataRegistered(uint256 indexed _topHatId, Deployment _deployment);

  /**
   * @notice A role-hat upgrade was recorded against an existing squad.
   * @param _topHatId Tophat id of the squad.
   * @param _record Upgrade audit record.
   */
  event RoleHatUpgradeRecorded(uint256 indexed _topHatId, UpgradeRecord _record);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Caller is not the registered factory.
   * @param _caller Calling address.
   */
  error NavePirataRegistry_NotFactory(address _caller);

  /**
   * @notice Caller is not the registered upgrader.
   * @param _caller Calling address.
   */
  error NavePirataRegistry_NotUpgrader(address _caller);

  /**
   * @notice A squad with that `topHatId` is already registered.
   * @param _topHatId The duplicated tophat id.
   */
  error NavePirataRegistry_AlreadyRegistered(uint256 _topHatId);

  /**
   * @notice No squad is registered under that `topHatId`.
   * @param _topHatId The missing tophat id.
   */
  error NavePirataRegistry_NotRegistered(uint256 _topHatId);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Record a new squad deployment. Factory-only.
   * @param _deployment The deployment record to store.
   */
  function registerDeployment(Deployment calldata _deployment) external;

  /**
   * @notice Append an upgrade record to an existing squad's audit trail. Upgrader-only.
   * @param _topHatId Squad tophat id.
   * @param _record Upgrade record.
   */
  function recordUpgrade(uint256 _topHatId, UpgradeRecord calldata _record) external;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The factory authorised to register deployments.
   * @return _factory Factory address.
   */
  function factory() external view returns (address _factory);

  /**
   * @notice The upgrader authorised to record upgrades.
   * @return _upgrader Upgrader address.
   */
  function upgrader() external view returns (address _upgrader);

  /**
   * @notice Read the deployment for a given squad.
   * @param _topHatId Squad tophat id.
   * @return _deployment The stored record (zeroed if unknown).
   */
  function deployment(uint256 _topHatId) external view returns (Deployment memory _deployment);

  /**
   * @notice Count of registered squads.
   * @return _count The count.
   */
  function deploymentCount() external view returns (uint256 _count);

  /**
   * @notice Enumerate registered squads.
   * @param _i Zero-based index (`_i < deploymentCount()`).
   * @return _topHatId The tophat id of the squad at that index.
   */
  function deploymentAt(uint256 _i) external view returns (uint256 _topHatId);

  /**
   * @notice Count of upgrade records for a squad.
   * @param _topHatId Squad tophat id.
   * @return _count The count.
   */
  function upgradeCount(uint256 _topHatId) external view returns (uint256 _count);

  /**
   * @notice Read an upgrade record by index.
   * @param _topHatId Squad tophat id.
   * @param _i Zero-based index (`_i < upgradeCount(_topHatId)`).
   * @return _record The stored upgrade record.
   */
  function upgradeAt(uint256 _topHatId, uint256 _i) external view returns (UpgradeRecord memory _record);
}
