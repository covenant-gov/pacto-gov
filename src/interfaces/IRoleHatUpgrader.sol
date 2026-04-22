// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IRoleHatUpgrader
 * @author Pacto
 * @notice Ceremony contract that orchestrates Nave Pirata role-hat upgrades.
 * @dev Upgrades are performed by deploying a new clone of an approved master copy, verifying the
 *      old clone is quiet (`IQuiescent.isQuiet()`), then transferring the role hat from the old
 *      clone to the new one. For infra role hats (MutinyRole, QuartermasterRole,
 *      TreasuryAuthorityRole) the admin hat is the tophat worn by the Safe — so the effective
 *      caller is the Safe (via a passing TreasuryAuthority proposal). For the squad-admin hat,
 *      the admin is the captain hat, so the captain calls directly. A governance-gated allow-list
 *      of approved master copies is optionally enforced.
 */
interface IRoleHatUpgrader {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The kind of role being upgraded.
   * @dev SquadAdmin is intentionally not included: it upgrades in-place via UUPS, never via this ceremony.
   * @param QUARTERMASTER Quartermaster clone.
   * @param MUTINY_MODULE MutinyModule clone.
   * @param TREASURY_AUTHORITY TreasuryAuthority clone.
   */
  enum RoleKind {
    QUARTERMASTER,
    MUTINY_MODULE,
    TREASURY_AUTHORITY
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A role hat was successfully upgraded from `_oldClone` to `_newClone`.
   * @param _roleHatId Role hat id that was transferred.
   * @param _oldClone Previous clone that wore the role hat.
   * @param _newClone New clone that wears the role hat.
   * @param _masterCopy Implementation cloned for `_newClone`.
   * @param _kind Role kind.
   */
  event RoleHatUpgraded(
    uint256 indexed _roleHatId,
    address indexed _oldClone,
    address indexed _newClone,
    address _masterCopy,
    RoleKind _kind
  );

  /**
   * @notice A master copy's allow-list flag was updated.
   * @param _kind Role kind the entry applies to.
   * @param _masterCopy Implementation address.
   * @param _allowed New allow state.
   */
  event MasterCopyAllowListUpdated(RoleKind indexed _kind, address indexed _masterCopy, bool _allowed);

  /**
   * @notice The master-copy allow-list enforcement toggle was updated.
   * @param _enabled New enforcement state.
   */
  event AllowListEnabledSet(bool _enabled);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Caller is not the admin of the role hat and cannot authorise the upgrade.
   * @param _roleHatId The role hat id in question.
   * @param _caller The calling address.
   */
  error RoleHatUpgrader_NotAdmin(uint256 _roleHatId, address _caller);

  /**
   * @notice The old clone is not quiet; upgrade aborted to avoid losing in-flight state.
   * @param _clone The non-quiet clone.
   */
  error RoleHatUpgrader_NotQuiet(address _clone);

  /**
   * @notice The supplied master copy is not on the allow-list for `_kind`.
   * @param _kind Role kind.
   * @param _masterCopy Rejected master copy address.
   */
  error RoleHatUpgrader_MasterCopyNotAllowed(RoleKind _kind, address _masterCopy);

  /**
   * @notice The `Hats.transferHat` call failed during the ceremony.
   */
  error RoleHatUpgrader_TransferFailed();

  /**
   * @notice A required address argument was zero.
   */
  error RoleHatUpgrader_ZeroAddress();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy a new clone of `_masterCopy`, initialize it with `_initData`, and transfer
   *         `_roleHatId` from `_oldClone` to the newly deployed clone.
   * @dev Reverts unless (a) caller wears the admin hat of `_roleHatId`, (b) `_oldClone` reports
   *      `isQuiet() == true`, and (c) `_masterCopy` is allow-listed when enforcement is enabled.
   * @param _kind Role kind.
   * @param _roleHatId Role hat id to transfer.
   * @param _oldClone Currently-wearing clone.
   * @param _masterCopy Implementation to clone for the replacement.
   * @param _initData Encoded `initialize(...)` calldata for the new clone.
   * @param _salt CREATE2 salt passed to the clones factory.
   * @return _newClone Address of the newly deployed clone.
   */
  function upgradeRole(
    RoleKind _kind,
    uint256 _roleHatId,
    address _oldClone,
    address _masterCopy,
    bytes calldata _initData,
    bytes32 _salt
  ) external returns (address _newClone);

  /*///////////////////////////////////////////////////////////////
                            PARAMETER SETTERS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Toggle allow-list enforcement. TreasuryAuthorityRole-gated.
   * @param _enabled New enforcement state.
   */
  function setAllowListEnabled(bool _enabled) external;

  /**
   * @notice Allow or disallow `_masterCopy` for `_kind`. TreasuryAuthorityRole-gated.
   * @param _kind Role kind the entry applies to.
   * @param _masterCopy Implementation address.
   * @param _allowed New allow state.
   */
  function setMasterCopyAllowed(RoleKind _kind, address _masterCopy, bool _allowed) external;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Whether the master-copy allow-list is enforced.
   * @return _enabled Current enforcement state.
   */
  function allowListEnabled() external view returns (bool _enabled);

  /**
   * @notice Whether `_masterCopy` is allow-listed for `_kind`.
   * @param _kind Role kind.
   * @param _masterCopy Implementation address.
   * @return _allowed True if allowed.
   */
  function isMasterCopyAllowed(RoleKind _kind, address _masterCopy) external view returns (bool _allowed);
}
