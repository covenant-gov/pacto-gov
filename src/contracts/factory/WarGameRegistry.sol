// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {IWarGameRegistry} from 'interfaces/factory/IWarGameRegistry.sol';

/**
 * @title WarGameRegistry
 * @author Pacto
 * @notice Throwaway war-game index; see `IWarGameRegistry`. Not the production `NavePirataRegistry`.
 * @dev `initialize` wires the factory once; no owner role after that
 */
contract WarGameRegistry is IWarGameRegistry {
  /*///////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IWarGameRegistry
  address public factory;

  /// @notice Active tophat id per squad (`0` if none).
  mapping(bytes32 _squadId => uint256 _topHatId) internal _activeTopHatIds;
  /// @notice Append-only tophat history per squad, including the current Active.
  mapping(bytes32 _squadId => uint256[] _topHatIds) internal _history;
  /// @notice Full record keyed by tophat id.
  mapping(uint256 _topHatId => Record _record) internal _records;

  /*///////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IWarGameRegistry
  function initialize(address _factory) external {
    if (factory != address(0)) revert WarGameRegistry_AlreadyWired();
    if (_factory == address(0)) revert WarGameRegistry_ZeroAddress();
    factory = _factory;
  }

  /*///////////////////////////////////////////////////////////////
                            WRITES
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IWarGameRegistry
  function register(bytes32 _squadId, INavePirataRegistry.Deployment calldata _deployment) external {
    if (msg.sender != factory) revert WarGameRegistry_NotFactory(msg.sender);
    if (_squadId == bytes32(0)) revert WarGameRegistry_ZeroSquadId();

    uint256 _topHatId = _deployment.topHatId;
    if (_records[_topHatId].deployment.topHatId != 0) revert WarGameRegistry_AlreadyRegistered(_topHatId);

    uint256 _prev = _activeTopHatIds[_squadId];
    if (_prev != 0) {
      _records[_prev].status = Status.Retired;
      emit WarGameRetired(_squadId, _prev);
    }

    _records[_topHatId] = Record({deployment: _deployment, squadId: _squadId, status: Status.Active});
    _history[_squadId].push(_topHatId);
    _activeTopHatIds[_squadId] = _topHatId;
    emit WarGameRegistered(_squadId, _topHatId, _deployment);
  }

  /// @inheritdoc IWarGameRegistry
  function retire(bytes32 _squadId) external {
    if (msg.sender != factory) revert WarGameRegistry_NotFactory(msg.sender);
    uint256 _topHatId = _activeTopHatIds[_squadId];
    if (_topHatId == 0) revert WarGameRegistry_NoActive(_squadId);

    _records[_topHatId].status = Status.Retired;
    _activeTopHatIds[_squadId] = 0;
    emit WarGameRetired(_squadId, _topHatId);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IWarGameRegistry
  function active(bytes32 _squadId) external view returns (INavePirataRegistry.Deployment memory _deployment) {
    uint256 _topHatId = _activeTopHatIds[_squadId];
    if (_topHatId == 0) return _deployment;
    _deployment = _records[_topHatId].deployment;
  }

  /// @inheritdoc IWarGameRegistry
  function activeTopHatId(bytes32 _squadId) external view returns (uint256 _topHatId) {
    _topHatId = _activeTopHatIds[_squadId];
  }

  /// @inheritdoc IWarGameRegistry
  function history(bytes32 _squadId) external view returns (uint256[] memory _topHatIds) {
    _topHatIds = _history[_squadId];
  }

  /// @inheritdoc IWarGameRegistry
  function record(uint256 _topHatId) external view returns (Record memory _record) {
    _record = _records[_topHatId];
  }

  /// @inheritdoc IWarGameRegistry
  function deployment(uint256 _topHatId) external view returns (INavePirataRegistry.Deployment memory _deployment) {
    _deployment = _records[_topHatId].deployment;
  }
}
