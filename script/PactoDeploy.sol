// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {TreasuryAuthority} from 'contracts/core/TreasuryAuthority.sol';
import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';
import {RoleHatClonesFactory} from 'contracts/factory/RoleHatClonesFactory.sol';
import {RoleHatUpgrader} from 'contracts/factory/RoleHatUpgrader.sol';
import {SquadAdminImpl} from 'contracts/squad/SquadAdminImpl.sol';

import {INavePirataFactory} from 'interfaces/INavePirataFactory.sol';
import {INavePirataRegistry} from 'interfaces/INavePirataRegistry.sol';
import {IRoleHatClonesFactory} from 'interfaces/IRoleHatClonesFactory.sol';

import {
  CHAIN_ID_ANVIL,
  CHAIN_ID_ARBITRUM_ONE,
  CHAIN_ID_BASE,
  CHAIN_ID_ETHEREUM,
  CHAIN_ID_OPTIMISM,
  CHAIN_ID_SEPOLIA,
  HATS_PROTOCOL_V1,
  SAFE_PROXY_FACTORY_141,
  SAFE_SINGLETON_141
} from 'script/Constants.sol';
import {DeployTypes} from 'script/DeployTypes.sol';
import {DeploymentArtifacts} from 'script/DeploymentArtifacts.sol';
import {ScriptGovernanceParams} from 'script/GovernanceParams.s.sol';

import {console} from 'forge-std/console.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title PactoDeploy
 * @author Pacto
 * @notice Shared deployment routine: master copies, infra, registry wiring.
 * @dev `forge script` entrypoints inherit this; integration tests inherit `IntegrationBase` for the same deploy path.
 */
abstract contract PactoDeploy is DeploymentArtifacts, ScriptGovernanceParams {
  /// @notice No `ExternalAddresses` entry for `block.chainid` (extend `_initExternalByChain` after adding `Constants`).
  error UnsupportedChain(uint256 chainId);

  DeployTypes.MasterCopyAddresses internal masters;
  DeployTypes.InfraAddresses internal infra;

  mapping(uint256 chainId => DeployTypes.ExternalAddresses ext) internal _externalByChain;

  constructor() {
    _initExternalByChain();
  }

  /// @dev Breadchain-style chain → infra map; every supported id currently shares the same public singletons.
  function _initExternalByChain() internal virtual {
    DeployTypes.ExternalAddresses memory _e = DeployTypes.ExternalAddresses({
      hats: HATS_PROTOCOL_V1, safeProxyFactory: SAFE_PROXY_FACTORY_141, safeSingleton: SAFE_SINGLETON_141
    });
    _externalByChain[CHAIN_ID_ETHEREUM] = _e;
    _externalByChain[CHAIN_ID_OPTIMISM] = _e;
    _externalByChain[CHAIN_ID_BASE] = _e;
    _externalByChain[CHAIN_ID_ARBITRUM_ONE] = _e;
    _externalByChain[CHAIN_ID_SEPOLIA] = _e;
    _externalByChain[CHAIN_ID_ANVIL] = _e;
  }

  /// @notice Squad params for `deployNavePirata` call sites; same on all chains (use `vm.warp` in tests).
  function _squadParams() internal view virtual returns (INavePirataFactory.SquadParams memory) {
    return squadParamsProduction();
  }

  function _externalAddressesForCurrentChain() internal view returns (DeployTypes.ExternalAddresses memory _ext) {
    _ext = _externalByChain[block.chainid];
    if (_ext.hats == address(0)) revert UnsupportedChain(block.chainid);
  }

  function _deployMasterCopies(IHats _hats) internal virtual returns (DeployTypes.MasterCopyAddresses memory _m) {
    _m.quartermaster = address(new Quartermaster(_hats));
    _m.mutinyModule = address(new MutinyModule(_hats));
    _m.treasuryAuthority = address(new TreasuryAuthority(_hats));
    _m.squadAdminImpl = address(new SquadAdminImpl(_hats));
    masters = _m;
  }

  function _deployInfra(
    DeployTypes.ExternalAddresses memory _ext,
    address _admin
  ) internal virtual returns (DeployTypes.InfraAddresses memory _i) {
    _i.clonesFactory = address(new RoleHatClonesFactory());
    _i.registry = address(new NavePirataRegistry(_admin));
    _i.upgrader = address(
      new RoleHatUpgrader(
        IHats(_ext.hats), IRoleHatClonesFactory(_i.clonesFactory), INavePirataRegistry(_i.registry), _admin
      )
    );
    _i.navePirataFactory = address(
      new NavePirataFactory(
        _ext.hats, address(_ext.safeProxyFactory), _ext.safeSingleton, _i.clonesFactory, _i.registry, _i.upgrader
      )
    );
    infra = _i;
  }

  function _wireRegistry(address _registry, address _factory, address _upgrader, address _admin) internal virtual {
    vm.prank(_admin);
    NavePirataRegistry(_registry).setFactory(_factory);
    vm.prank(_admin);
    NavePirataRegistry(_registry).setUpgrader(_upgrader);
  }

  /// @notice Full chain bootstrap: masters → infra → `setFactory` / `setUpgrader`.
  function _deployFullSystem(DeployTypes.ExternalAddresses memory _ext, address _admin) internal virtual {
    _deployMasterCopies(IHats(_ext.hats));
    _deployInfra(_ext, _admin);
    _wireRegistry(infra.registry, infra.navePirataFactory, infra.upgrader, _admin);
  }

  function _logDeployment() internal view virtual {
    console.log('Master Quartermaster:', masters.quartermaster);
    console.log('Master MutinyModule:', masters.mutinyModule);
    console.log('Master TreasuryAuthority:', masters.treasuryAuthority);
    console.log('Master SquadAdminImpl:', masters.squadAdminImpl);
    console.log('RoleHatClonesFactory:', infra.clonesFactory);
    console.log('NavePirataRegistry:', infra.registry);
    console.log('RoleHatUpgrader:', infra.upgrader);
    console.log('NavePirataFactory:', infra.navePirataFactory);
  }
}
