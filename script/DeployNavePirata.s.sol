// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataFactory} from 'interfaces/INavePirataFactory.sol';

import {ScriptGovernanceParams} from 'script/GovernanceParams.s.sol';

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title DeployNavePirata
 * @author Pacto
 * @notice Per-squad bootstrap: `NavePirataFactory.deployNavePirata` (tech spec §11 P9.3).
 * @dev Expects infra + master copies already deployed. Uses **production** squad params (same as `ScriptGovernanceParams`).
 *      Env: `NAVE_PIRATA_FACTORY`, `CAPTAIN`, `SQUAD_METADATA_URI`, `MASTER_QUARTERMASTER`, `MASTER_MUTINY`,
 *      `MASTER_TREASURY_AUTHORITY`, `SQUAD_ADMIN_IMPLEMENTATION`, `SALT_NONCE`.
 */
contract DeployNavePirata is Script, ScriptGovernanceParams {
  function run() external {
    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: vm.envAddress('CAPTAIN'),
      metadataURI: vm.envString('SQUAD_METADATA_URI'),
      squadParams: squadParamsProduction(),
      quartermasterMasterCopy: vm.envAddress('MASTER_QUARTERMASTER'),
      mutinyMasterCopy: vm.envAddress('MASTER_MUTINY'),
      treasuryAuthorityMasterCopy: vm.envAddress('MASTER_TREASURY_AUTHORITY'),
      squadAdminImplementation: vm.envAddress('SQUAD_ADMIN_IMPLEMENTATION'),
      saltNonce: vm.envUint('SALT_NONCE')
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

    console.log('topHatId:', _topHatId);
    console.log('safe:', _safe);
    console.log('quartermaster:', _quartermaster);
    console.log('mutinyModule:', _mutinyModule);
    console.log('treasuryAuthority:', _treasuryAuthority);
    console.log('squadAdminProxy:', _squadAdminProxy);
  }
}
