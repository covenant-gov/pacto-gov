// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IRoleHatUpgrader
 * @author Pacto
 * @notice Role-hat upgrade: `isQuiet`, new clone, `transferHat`, `recordUpgrade`. Infra roles use Safe/tophat admin path; SquadAdmin
 *         is UUPS-only here. Optional allow-list
 */
interface IRoleHatUpgrader {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Clonable role kinds (SquadAdmin is UUPS, not in this set)
   * @param QUARTERMASTER Quartermaster clone
   * @param MUTINY_MODULE MutinyModule clone
   * @param TREASURY_AUTHORITY TreasuryAuthority clone
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

  /// @notice The `Hats.transferHat` call failed during the ceremony.
  error RoleHatUpgrader_TransferFailed();
  /// @notice A required address argument was zero.
  error RoleHatUpgrader_ZeroAddress();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Clone `_masterCopy`, init, move `_roleHatId` from `_oldClone` to the new address
   * @dev Reverts if not admin of the hat, `_oldClone` not quiet, or allow-list rejects `masterCopy`
   * @param _kind Discriminant for allow-list
   * @param _roleHatId Hat to repoint
   * @param _oldClone Wearer to replace
   * @param _masterCopy New logic master
   * @param _initData `initialize` calldata
   * @param _salt CREATE2 input (upgrader may namespace)
   * @return _newClone New clone
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
   * @notice Toggle allow-list enforcement. Admin-gated (Ownable).
   * @param _enabled New enforcement state.
   */
  function setAllowListEnabled(bool _enabled) external;

  /**
   * @notice Allow or disallow `_masterCopy` for `_kind`. Admin-gated (Ownable).
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
