// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IRoleHatClonesFactory} from 'interfaces/factory/IRoleHatClonesFactory.sol';

import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

/**
 * @title RoleHatClonesFactory
 * @author Pacto
 * @notice Stateless `Clones` wrapper; caller is responsible for which master and salt. See `IRoleHatClonesFactory`
 */
contract RoleHatClonesFactory is IRoleHatClonesFactory {
  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IRoleHatClonesFactory
  function createClone(address _masterCopy, bytes calldata _initData, bytes32 _salt) external returns (address _clone) {
    _clone = _createClone(_masterCopy, _initData, _salt);
  }

  /// @inheritdoc IRoleHatClonesFactory
  function createClones(
    address[] calldata _masterCopies,
    bytes[] calldata _initDatas,
    bytes32[] calldata _salts
  ) external returns (address[] memory _clones) {
    uint256 _len = _masterCopies.length;
    if (_len != _initDatas.length || _len != _salts.length) revert RoleHatClonesFactory_LengthMismatch();

    _clones = new address[](_len);
    for (uint256 _i; _i < _len; ++_i) {
      _clones[_i] = _createClone(_masterCopies[_i], _initDatas[_i], _salts[_i]);
    }
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IRoleHatClonesFactory
  function predictCloneAddress(address _masterCopy, bytes32 _salt) external view returns (address _predicted) {
    _predicted = Clones.predictDeterministicAddress(_masterCopy, _salt, address(this));
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice CREATE2 clone + optional initializer.
   * @param _masterCopy Master implementation.
   * @param _initData Encoded initializer calldata (empty skips the call).
   * @param _salt CREATE2 salt.
   * @return _clone New clone address.
   */
  function _createClone(
    address _masterCopy,
    bytes calldata _initData,
    bytes32 _salt
  ) internal returns (address _clone) {
    if (_masterCopy == address(0)) revert RoleHatClonesFactory_ZeroMasterCopy();

    _clone = Clones.cloneDeterministic(_masterCopy, _salt);

    if (_initData.length != 0) {
      (bool _ok,) = _clone.call(_initData);
      if (!_ok) revert RoleHatClonesFactory_InitializationFailed();
    }

    emit CloneCreated(_masterCopy, _clone, _salt, msg.sender);
  }
}
