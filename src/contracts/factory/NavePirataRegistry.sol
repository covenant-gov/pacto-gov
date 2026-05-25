// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';

/**
 * @title NavePirataRegistry
 * @author Pacto
 * @notice On-chain, append-only squad + upgrade log; see `INavePirataRegistry`
 * @dev `initialize` wires factory/upgrader once; no owner role after that
 */
contract NavePirataRegistry is INavePirataRegistry {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataRegistry
  address public factory;
  /// @inheritdoc INavePirataRegistry
  address public upgrader;

  /// @notice Enumerable list of registered tophat ids.
  uint256[] internal _topHats;
  /// @notice Deployment record keyed by squad tophat id.
  mapping(uint256 _topHatId => Deployment _deployment) internal _deployments;
  /// @notice Upgrade log per squad.
  mapping(uint256 _topHatId => UpgradeRecord[] _records) internal _upgradeLogs;

  /*///////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataRegistry
  function initialize(address _factory, address _upgrader) external {
    if (factory != address(0) || upgrader != address(0)) revert NavePirataRegistry_AlreadyWired();
    if (_factory == address(0) || _upgrader == address(0)) revert NavePirataRegistry_ZeroAddress();
    factory = _factory;
    upgrader = _upgrader;
  }

  /*///////////////////////////////////////////////////////////////
                            WRITES
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataRegistry
  function registerDeployment(Deployment calldata _deployment) external {
    if (msg.sender != factory) revert NavePirataRegistry_NotFactory(msg.sender);
    uint256 _topHatId = _deployment.topHatId;
    if (_deployments[_topHatId].topHatId != 0) revert NavePirataRegistry_AlreadyRegistered(_topHatId);

    _deployments[_topHatId] = _deployment;
    _topHats.push(_topHatId);
    emit NavePirataRegistered(_topHatId, _deployment);
  }

  /// @inheritdoc INavePirataRegistry
  function recordUpgrade(uint256 _topHatId, UpgradeRecord calldata _record) external {
    if (msg.sender != upgrader) revert NavePirataRegistry_NotUpgrader(msg.sender);
    if (_deployments[_topHatId].topHatId == 0) revert NavePirataRegistry_NotRegistered(_topHatId);

    _upgradeLogs[_topHatId].push(_record);
    emit RoleHatUpgradeRecorded(_topHatId, _record);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataRegistry
  function deployment(uint256 _topHatId) external view returns (Deployment memory _deployment) {
    _deployment = _deployments[_topHatId];
  }

  /// @inheritdoc INavePirataRegistry
  function deploymentCount() external view returns (uint256 _count) {
    _count = _topHats.length;
  }

  /// @inheritdoc INavePirataRegistry
  function deploymentAt(uint256 _i) external view returns (uint256 _topHatId) {
    _topHatId = _topHats[_i];
  }

  /// @inheritdoc INavePirataRegistry
  function upgradeCount(uint256 _topHatId) external view returns (uint256 _count) {
    _count = _upgradeLogs[_topHatId].length;
  }

  /// @inheritdoc INavePirataRegistry
  function upgradeAt(uint256 _topHatId, uint256 _i) external view returns (UpgradeRecord memory _record) {
    _record = _upgradeLogs[_topHatId][_i];
  }
}
