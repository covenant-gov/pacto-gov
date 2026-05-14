// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';

import {MASTER_COPY_SQUAD_ADMIN_IMPL} from 'script/Constants.sol';
import {DeploymentArtifacts} from 'script/DeploymentArtifacts.sol';

import {console} from 'forge-std/console.sol';

/**
 * @title DeploySquadAdminStandaloneCaptainHat
 * @author Pacto
 * @notice One-off: `NavePirataFactory.deploySquadAdminStandaloneCaptainHat` (EIP-1167 + `initialize(captainHatId)`).
 * @dev Requires `NAVE_PIRATA_FACTORY`, `CAPTAIN_HAT_ID`. Implementation is `MASTER_COPY_SQUAD_ADMIN_IMPL` when non-zero,
 *      otherwise `SQUAD_ADMIN_IMPLEMENTATION`. Optional `STANDALONE_ARTIFACT_NONCE` (default `1`) selects
 *      `deployments/<chainId>/squad-admin-standalone-captain-<nonce>.json`.
 */
contract DeploySquadAdminStandaloneCaptainHat is DeploymentArtifacts {
  error DeploySquadAdminStandaloneCaptainHat_UnsetImplementation();

  function run() external {
    address _factoryAddr = vm.envAddress('NAVE_PIRATA_FACTORY');
    uint256 _captainHatId = vm.envUint('CAPTAIN_HAT_ID');

    address _impl = MASTER_COPY_SQUAD_ADMIN_IMPL;
    if (_impl == address(0)) {
      _impl = vm.envAddress('SQUAD_ADMIN_IMPLEMENTATION');
    }
    if (_impl == address(0)) revert DeploySquadAdminStandaloneCaptainHat_UnsetImplementation();

    uint256 _artifactNonce = vm.envOr('STANDALONE_ARTIFACT_NONCE', uint256(1));

    vm.startBroadcast();
    address _clone = INavePirataFactory(_factoryAddr).deploySquadAdminStandaloneCaptainHat(_impl, _captainHatId);
    vm.stopBroadcast();

    _writeSquadAdminStandaloneCaptainJson(_clone, _captainHatId, _impl, _artifactNonce);

    console.log('squadAdminStandaloneCaptainHat:', _clone);
    console.log('captainHatId:', _captainHatId);
    console.log('implementation:', _impl);
  }
}
