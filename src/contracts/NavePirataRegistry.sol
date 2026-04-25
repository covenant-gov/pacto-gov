// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataRegistry} from 'interfaces/INavePirataRegistry.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title NavePirataRegistry
 * @author Pacto
 * @notice Append-only on-chain registry for Nave Pirata squad deployments and their role-hat
 *         upgrade history. Writes are restricted to the two trusted protocol contracts wired at
 *         deploy time: `NavePirataFactory` (initial registration) and `RoleHatUpgrader` (upgrade
 *         records).
 * @dev Wiring pattern: the registry is deployed first, then `factory` and `upgrader` are each
 *      set once by the deploy admin (`Ownable`). Admins renounce ownership once both are set.
 *      The setters are one-shot; there is no write path to overwrite an established wiring or
 *      an existing deployment record.
 */
contract NavePirataRegistry is INavePirataRegistry, Ownable {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataRegistry
  address public override factory;
  /// @inheritdoc INavePirataRegistry
  address public override upgrader;

  /// @notice Enumerable list of registered tophat ids.
  uint256[] internal _topHats;
  /// @notice Deployment record keyed by squad tophat id.
  mapping(uint256 _topHatId => Deployment _deployment) internal _deployments;
  /// @notice Upgrade log per squad.
  mapping(uint256 _topHatId => UpgradeRecord[] _records) internal _upgradeLogs;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploys the registry owned by `_admin`.
   * @dev Zero-admin protection comes from `Ownable`, which reverts with `OwnableInvalidOwner`.
   * @param _admin Address permitted to perform the one-shot wiring setters.
   */
  constructor(address _admin) Ownable(_admin) {}

  /*///////////////////////////////////////////////////////////////
                            ADMIN WIRING
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice One-shot setter for the factory address. Reverts after the first successful call.
   * @param _factory Address of the `NavePirataFactory` authorised to register deployments.
   */
  function setFactory(address _factory) external onlyOwner {
    if (factory != address(0)) revert NavePirataRegistry_AlreadyWired();
    if (_factory == address(0)) revert NavePirataRegistry_ZeroAddress();
    factory = _factory;
  }

  /**
   * @notice One-shot setter for the upgrader address. Reverts after the first successful call.
   * @param _upgrader Address of the `RoleHatUpgrader` authorised to record upgrades.
   */
  function setUpgrader(address _upgrader) external onlyOwner {
    if (upgrader != address(0)) revert NavePirataRegistry_AlreadyWired();
    if (_upgrader == address(0)) revert NavePirataRegistry_ZeroAddress();
    upgrader = _upgrader;
  }

  /*///////////////////////////////////////////////////////////////
                            WRITES
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataRegistry
  function registerDeployment(Deployment calldata _deployment) external override {
    if (msg.sender != factory) revert NavePirataRegistry_NotFactory(msg.sender);
    uint256 _topHatId = _deployment.topHatId;
    if (_deployments[_topHatId].topHatId != 0) revert NavePirataRegistry_AlreadyRegistered(_topHatId);

    _deployments[_topHatId] = _deployment;
    _topHats.push(_topHatId);
    emit NavePirataRegistered(_topHatId, _deployment);
  }

  /// @inheritdoc INavePirataRegistry
  function recordUpgrade(uint256 _topHatId, UpgradeRecord calldata _record) external override {
    if (msg.sender != upgrader) revert NavePirataRegistry_NotUpgrader(msg.sender);
    if (_deployments[_topHatId].topHatId == 0) revert NavePirataRegistry_NotRegistered(_topHatId);

    _upgradeLogs[_topHatId].push(_record);
    emit RoleHatUpgradeRecorded(_topHatId, _record);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataRegistry
  function deployment(uint256 _topHatId) external view override returns (Deployment memory _deployment) {
    _deployment = _deployments[_topHatId];
  }

  /// @inheritdoc INavePirataRegistry
  function deploymentCount() external view override returns (uint256 _count) {
    _count = _topHats.length;
  }

  /// @inheritdoc INavePirataRegistry
  function deploymentAt(uint256 _i) external view override returns (uint256 _topHatId) {
    _topHatId = _topHats[_i];
  }

  /// @inheritdoc INavePirataRegistry
  function upgradeCount(uint256 _topHatId) external view override returns (uint256 _count) {
    _count = _upgradeLogs[_topHatId].length;
  }

  /// @inheritdoc INavePirataRegistry
  function upgradeAt(uint256 _topHatId, uint256 _i) external view override returns (UpgradeRecord memory _record) {
    _record = _upgradeLogs[_topHatId][_i];
  }
}
