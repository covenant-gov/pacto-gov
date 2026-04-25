// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataRegistry} from 'interfaces/INavePirataRegistry.sol';
import {IQuiescent} from 'interfaces/IQuiescent.sol';
import {IRoleHatClonesFactory} from 'interfaces/IRoleHatClonesFactory.sol';
import {IRoleHatUpgrader} from 'interfaces/IRoleHatUpgrader.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title RoleHatUpgrader
 * @author Pacto
 * @notice Hats admin + `isQuiet` → new clone + `transferHat` + registry. Optional allow-list. See `IRoleHatUpgrader`
 * @dev `salt` mixes with `roleHatId` for CREATE2. UUPS `SquadAdmin` is out of scope here
 */
contract RoleHatUpgrader is IRoleHatUpgrader, Ownable {
  /*///////////////////////////////////////////////////////////////
                            IMMUTABLES
  //////////////////////////////////////////////////////////////*/

  /// @notice Hats Protocol singleton used for admin checks and hat transfers.
  IHats internal immutable _HATS;
  /// @notice Generic EIP-1167 CREATE2 factory used to deploy new role-clone replacements.
  IRoleHatClonesFactory internal immutable _CLONES;
  /// @notice On-chain registry receiving upgrade audit records.
  INavePirataRegistry internal immutable _REGISTRY;

  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IRoleHatUpgrader
  bool public override allowListEnabled;

  /// @notice Per-kind master-copy allow-list map.
  mapping(RoleKind _kind => mapping(address _masterCopy => bool _allowed)) internal _allowedMasterCopies;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploys the upgrader owned by `_admin` and wires immutable dependencies.
   * @param _hats Hats Protocol address for this chain.
   * @param _clones EIP-1167 clones factory.
   * @param _registry Nave Pirata registry.
   * @param _admin Address permitted to toggle enforcement and manage the allow-list.
   */
  constructor(
    IHats _hats,
    IRoleHatClonesFactory _clones,
    INavePirataRegistry _registry,
    address _admin
  ) Ownable(_admin) {
    if (address(_hats) == address(0) || address(_clones) == address(0) || address(_registry) == address(0)) {
      revert RoleHatUpgrader_ZeroAddress();
    }
    _HATS = _hats;
    _CLONES = _clones;
    _REGISTRY = _registry;
  }

  /*///////////////////////////////////////////////////////////////
                            UPGRADE CEREMONY
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IRoleHatUpgrader
  function upgradeRole(
    RoleKind _kind,
    uint256 _roleHatId,
    address _oldClone,
    address _masterCopy,
    bytes calldata _initData,
    bytes32 _salt
  ) external override returns (address _newClone) {
    if (_oldClone == address(0) || _masterCopy == address(0)) revert RoleHatUpgrader_ZeroAddress();
    if (!_HATS.isAdminOfHat(msg.sender, _roleHatId)) revert RoleHatUpgrader_NotAdmin(_roleHatId, msg.sender);
    if (allowListEnabled && !_allowedMasterCopies[_kind][_masterCopy]) {
      revert RoleHatUpgrader_MasterCopyNotAllowed(_kind, _masterCopy);
    }
    if (!IQuiescent(_oldClone).isQuiet()) revert RoleHatUpgrader_NotQuiet(_oldClone);

    bytes32 _namespaced = keccak256(abi.encode(_roleHatId, _salt));
    _newClone = _CLONES.createClone(_masterCopy, _initData, _namespaced);

    try _HATS.transferHat(_roleHatId, _oldClone, _newClone) {}
    catch {
      revert RoleHatUpgrader_TransferFailed();
    }

    uint256 _topHatId = _HATS.getAdminAtLevel(_roleHatId, 0);
    _REGISTRY.recordUpgrade(
      _topHatId,
      INavePirataRegistry.UpgradeRecord({
        roleHatId: _roleHatId,
        oldClone: _oldClone,
        newClone: _newClone,
        masterCopy: _masterCopy,
        upgradedAt: uint64(block.timestamp)
      })
    );

    emit RoleHatUpgraded(_roleHatId, _oldClone, _newClone, _masterCopy, _kind);
  }

  /*///////////////////////////////////////////////////////////////
                            ADMIN: ALLOW-LIST
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IRoleHatUpgrader
  function setAllowListEnabled(bool _enabled) external override onlyOwner {
    allowListEnabled = _enabled;
    emit AllowListEnabledSet(_enabled);
  }

  /// @inheritdoc IRoleHatUpgrader
  function setMasterCopyAllowed(RoleKind _kind, address _masterCopy, bool _allowed) external override onlyOwner {
    if (_masterCopy == address(0)) revert RoleHatUpgrader_ZeroAddress();
    _allowedMasterCopies[_kind][_masterCopy] = _allowed;
    emit MasterCopyAllowListUpdated(_kind, _masterCopy, _allowed);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IRoleHatUpgrader
  function isMasterCopyAllowed(RoleKind _kind, address _masterCopy) external view override returns (bool _allowed) {
    _allowed = _allowedMasterCopies[_kind][_masterCopy];
  }

  /// @inheritdoc IRoleHatUpgrader
  function hats() external view override returns (IHats _hats) {
    _hats = _HATS;
  }

  /// @inheritdoc IRoleHatUpgrader
  function clonesFactory() external view override returns (IRoleHatClonesFactory _clones) {
    _clones = _CLONES;
  }

  /// @inheritdoc IRoleHatUpgrader
  function registry() external view override returns (INavePirataRegistry _registry) {
    _registry = _REGISTRY;
  }
}
