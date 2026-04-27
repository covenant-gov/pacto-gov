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
  function createClone(
    address _masterCopy,
    bytes calldata _initData,
    bytes32 _salt
  ) external override returns (address _clone) {
    if (_masterCopy == address(0)) revert RoleHatClonesFactory_ZeroMasterCopy();

    _clone = Clones.cloneDeterministic(_masterCopy, _salt);

    if (_initData.length != 0) {
      (bool _ok,) = _clone.call(_initData);
      if (!_ok) revert RoleHatClonesFactory_InitializationFailed();
    }

    emit CloneCreated(_masterCopy, _clone, _salt, msg.sender);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IRoleHatClonesFactory
  function predictCloneAddress(address _masterCopy, bytes32 _salt) external view override returns (address _predicted) {
    _predicted = Clones.predictDeterministicAddress(_masterCopy, _salt, address(this));
  }
}
