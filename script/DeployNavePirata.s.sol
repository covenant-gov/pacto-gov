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
 * @dev Expects infra + master copies already deployed. Defaults to **production** squad params
 *      (`ScriptGovernanceParams._squadParamsProduction`). Set `STACK_KIND=WarGame` and a non-zero
 *      `SQUAD_ID` (`0x` + `keccak256(parentId)`, already hashed) for a throwaway war-game stack
 *      with 5-minute delays. Master copy addresses and `saltNonce` come from `script/Constants.sol`
 *      by default; each master copy can be overridden via environment variables:
 *      `MASTER_COPY_QUARTERMASTER`, `MASTER_COPY_MUTINY_MODULE`, `MASTER_COPY_TREASURY_AUTHORITY`,
 *      and `MASTER_COPY_SQUAD_ADMIN_IMPL`.
 *      Requires forge environment variables: `NAVE_PIRATA_FACTORY`, `CAPTAIN`, `SQUAD_METADATA_URI`.
 */
contract DeployNavePirata is DeploymentArtifacts, ScriptGovernanceParams {
  /// @notice `STACK_KIND` was neither `Production` nor `WarGame`.
  /// @param kind The rejected `STACK_KIND` value.
  error DeployNavePirata_InvalidStackKind(string kind);
  /// @notice War-game deploy requires a non-zero `SQUAD_ID`.
  error DeployNavePirata_ZeroSquadId();

  function run() external {
    uint256 _saltNonce = vm.envOr('SQUAD_SALT_NONCE', DEPLOY_NAV_PIRATA_SALT_NONCE);
    (INavePirataFactory.StackKind _stackKind, INavePirataFactory.SquadParams memory _squadParams, bytes32 _squadId) =
      _stackFromEnv();

    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: vm.envAddress('CAPTAIN'),
      metadataURI: vm.envString('SQUAD_METADATA_URI'),
      squadParams: _squadParams,
      quartermasterMasterCopy: vm.envOr('MASTER_COPY_QUARTERMASTER', MASTER_COPY_QUARTERMASTER),
      mutinyMasterCopy: vm.envOr('MASTER_COPY_MUTINY_MODULE', MASTER_COPY_MUTINY_MODULE),
      treasuryAuthorityMasterCopy: vm.envOr('MASTER_COPY_TREASURY_AUTHORITY', MASTER_COPY_TREASURY_AUTHORITY),
      squadAdminImplementation: vm.envOr('MASTER_COPY_SQUAD_ADMIN_IMPL', MASTER_COPY_SQUAD_ADMIN_IMPL),
      saltNonce: _saltNonce,
      stackKind: _stackKind,
      squadId: _squadId
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

  /**
   * @notice Reads `STACK_KIND` (`Production` default) and war-game `SQUAD_ID`.
   * @return _kind Production or WarGame.
   * @return _params Matching `SquadParams` (5-minute delays when WarGame).
   * @return _squadId Zero for production; non-zero hashed squad key for WarGame.
   */
  function _stackFromEnv()
    internal
    view
    returns (INavePirataFactory.StackKind _kind, INavePirataFactory.SquadParams memory _params, bytes32 _squadId)
  {
    string memory _raw = vm.envOr('STACK_KIND', string('Production'));
    if (keccak256(bytes(_raw)) == keccak256('Production')) {
      return (INavePirataFactory.StackKind.Production, _squadParamsProduction(), bytes32(0));
    }
    if (keccak256(bytes(_raw)) == keccak256('WarGame')) {
      _squadId = vm.envBytes32('SQUAD_ID');
      if (_squadId == bytes32(0)) revert DeployNavePirata_ZeroSquadId();
      return (INavePirataFactory.StackKind.WarGame, _squadParamsWarGame(), _squadId);
    }
    revert DeployNavePirata_InvalidStackKind(_raw);
  }
}
