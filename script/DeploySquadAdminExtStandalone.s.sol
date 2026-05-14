// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';

import {MASTER_COPY_SQUAD_ADMIN_EXT_IMPL} from 'script/Constants.sol';
import {DeploymentArtifacts} from 'script/DeploymentArtifacts.sol';

import {console} from 'forge-std/console.sol';

/**
 * @title DeploySquadAdminExtStandalone
 * @author Pacto
 * @notice One-off: `NavePirataFactory.deploySquadAdminExtStandalone` (EIP-1167 + `initialize(owner)`).
 * @dev Requires `NAVE_PIRATA_FACTORY`, `SQUAD_ADMIN_EXT_OWNER`. Implementation is `MASTER_COPY_SQUAD_ADMIN_EXT_IMPL`
 *      when non-zero, otherwise `SQUAD_ADMIN_EXT_IMPLEMENTATION`. Optional `STANDALONE_ARTIFACT_NONCE` (default `1`)
 *      selects `deployments/<chainId>/squad-admin-ext-standalone-<nonce>.json`.
 */
contract DeploySquadAdminExtStandalone is DeploymentArtifacts {
  error DeploySquadAdminExtStandalone_UnsetImplementation();

  function run() external {
    address _factoryAddr = vm.envAddress('NAVE_PIRATA_FACTORY');
    address _owner = vm.envAddress('SQUAD_ADMIN_EXT_OWNER');

    address _impl = MASTER_COPY_SQUAD_ADMIN_EXT_IMPL;
    if (_impl == address(0)) {
      _impl = vm.envAddress('SQUAD_ADMIN_EXT_IMPLEMENTATION');
    }
    if (_impl == address(0)) revert DeploySquadAdminExtStandalone_UnsetImplementation();

    uint256 _artifactNonce = vm.envOr('STANDALONE_ARTIFACT_NONCE', uint256(1));

    vm.startBroadcast();
    address _clone = INavePirataFactory(_factoryAddr).deploySquadAdminExtStandalone(_impl, _owner);
    vm.stopBroadcast();

    _writeSquadAdminExtStandaloneJson(_clone, _owner, _impl, _artifactNonce);

    console.log('squadAdminExtStandalone:', _clone);
    console.log('owner:', _owner);
    console.log('implementation:', _impl);
  }
}
