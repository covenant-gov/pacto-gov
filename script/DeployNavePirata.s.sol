// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';

import {
  DEPLOY_NAV_PIRATA_SALT_NONCE,
  MASTER_COPY_MUTINY_MODULE,
  MASTER_COPY_QUARTERMASTER,
  MASTER_COPY_SQUAD_ADMIN_IMPL,
  MASTER_COPY_TREASURY_AUTHORITY
} from 'script/Constants.sol';
import {DeploymentArtifacts} from 'script/DeploymentArtifacts.sol';
import {ScriptGovernanceParams} from 'script/GovernanceParams.s.sol';

/**
 * @title DeployNavePirata
 * @author Pacto
 * @notice Per-squad bootstrap: `NavePirataFactory.deployNavePirata`.
 * @dev Expects infra + master copies already deployed. Uses **production** squad params (same as `ScriptGovernanceParams`).
 *      Master copy addresses and `saltNonce` come from `script/Constants.sol` by default; each master copy can be
 *      overridden via environment variables: `MASTER_COPY_QUARTERMASTER`, `MASTER_COPY_MUTINY_MODULE`,
 *      `MASTER_COPY_TREASURY_AUTHORITY`, and `MASTER_COPY_SQUAD_ADMIN_IMPL`.
 *      Requires forge environment variables: `NAVE_PIRATA_FACTORY`, `CAPTAIN`, `SQUAD_METADATA_URI`.
 */
contract DeployNavePirata is DeploymentArtifacts, ScriptGovernanceParams {
  function run() external {
    uint256 _saltNonce = vm.envOr('SQUAD_SALT_NONCE', DEPLOY_NAV_PIRATA_SALT_NONCE);

    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: vm.envAddress('CAPTAIN'),
      metadataURI: vm.envString('SQUAD_METADATA_URI'),
      squadParams: _squadParamsProduction(),
      quartermasterMasterCopy: vm.envOr('MASTER_COPY_QUARTERMASTER', MASTER_COPY_QUARTERMASTER),
      mutinyMasterCopy: vm.envOr('MASTER_COPY_MUTINY_MODULE', MASTER_COPY_MUTINY_MODULE),
      treasuryAuthorityMasterCopy: vm.envOr('MASTER_COPY_TREASURY_AUTHORITY', MASTER_COPY_TREASURY_AUTHORITY),
      squadAdminImplementation: vm.envOr('MASTER_COPY_SQUAD_ADMIN_IMPL', MASTER_COPY_SQUAD_ADMIN_IMPL),
      saltNonce: _saltNonce,
      stackKind: INavePirataFactory.StackKind.Production,
      squadId: bytes32(0)
    });

    INavePirataFactory _factory = INavePirataFactory(vm.envAddress('NAVE_PIRATA_FACTORY'));

    vm.startBroadcast();
    (
      uint256 _topHatId,
      address _safe,
      address _quartermaster,
      address _mutinyModule,
      address _treasuryAuthority,
      address _squadAdminProxy
    ) = _factory.deployNavePirata(_p);
    vm.stopBroadcast();

    _writeSquadDeploymentJson(
      _topHatId, _safe, _quartermaster, _mutinyModule, _treasuryAuthority, _squadAdminProxy, _saltNonce
    );
  }
}
