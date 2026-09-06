// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployTypes} from 'script/DeployTypes.sol';

import {Script} from 'forge-std/Script.sol';
import {VmSafe} from 'forge-std/Vm.sol';

/**
 * @title DeploymentArtifacts
 * @author Pacto
 * @notice Writes human-readable JSON under `deployments/<chainId>/` on `--broadcast` / `--resume` only.
 * @dev Dry-run (`simulate-deploy:*`) and `forge test` do not write. Paths are relative to the repo root.
 */
abstract contract DeploymentArtifacts is Script {
  function _shouldWriteDeploymentJson() internal view returns (bool) {
    return vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) || vm.isContext(VmSafe.ForgeContext.ScriptResume);
  }

  function _deploymentJsonPath(string memory filename) internal view returns (string memory) {
    return string.concat('deployments/', vm.toString(block.chainid), '/', filename);
  }

  function _writeDeploymentJson(string memory json, string memory filename) internal {
    vm.createDir(string.concat('deployments/', vm.toString(block.chainid)), true);
    vm.writeJson(json, _deploymentJsonPath(filename));
  }

  function _writeExternalAddressesJson(DeployTypes.ExternalAddresses memory ext) internal {
    if (!_shouldWriteDeploymentJson()) return;
    string memory k = 'pacto_external';
    vm.serializeUint(k, 'chainId', block.chainid);
    vm.serializeAddress(k, 'hats', ext.hats);
    vm.serializeAddress(k, 'safeProxyFactory', ext.safeProxyFactory);
    string memory json = vm.serializeAddress(k, 'safeSingleton', ext.safeSingleton);
    _writeDeploymentJson(json, 'external.json');
  }

  function _writeMasterCopiesJson(DeployTypes.MasterCopyAddresses memory m) internal {
    if (!_shouldWriteDeploymentJson()) return;
    string memory k = 'pacto_master_copies';
    vm.serializeUint(k, 'chainId', block.chainid);
    vm.serializeAddress(k, 'quartermaster', m.quartermaster);
    vm.serializeAddress(k, 'mutinyModule', m.mutinyModule);
    vm.serializeAddress(k, 'treasuryAuthority', m.treasuryAuthority);
    vm.serializeAddress(k, 'squadAdminImpl', m.squadAdminImpl);
    string memory json = vm.serializeAddress(k, 'squadAdminExtImpl', m.squadAdminExtImpl);
    _writeDeploymentJson(json, 'master-copies.json');
  }

  function _writeInfraJson(DeployTypes.InfraAddresses memory i, address deployer) internal {
    if (!_shouldWriteDeploymentJson()) return;
    string memory k = 'pacto_infra';
    vm.serializeUint(k, 'chainId', block.chainid);
    vm.serializeAddress(k, 'roleHatClonesFactory', i.clonesFactory);
    vm.serializeAddress(k, 'navePirataRegistry', i.registry);
    vm.serializeAddress(k, 'warGameRegistry', i.warGameRegistry);
    vm.serializeAddress(k, 'roleHatUpgrader', i.upgrader);
    vm.serializeAddress(k, 'sponsorPolicyRegistry', i.sponsorPolicyRegistry);
    vm.serializeAddress(k, 'navePirataFactory', i.navePirataFactory);
    string memory json = vm.serializeAddress(k, 'deployer', deployer);
    _writeDeploymentJson(json, 'infra.json');
  }

  function _writeFullSystemJson(
    DeployTypes.ExternalAddresses memory ext,
    DeployTypes.MasterCopyAddresses memory m,
    DeployTypes.InfraAddresses memory i,
    address deployer
  ) internal {
    if (!_shouldWriteDeploymentJson()) return;
    string memory k = 'pacto_full_system';
    vm.serializeUint(k, 'chainId', block.chainid);
    vm.serializeAddress(k, 'hats', ext.hats);
    vm.serializeAddress(k, 'safeProxyFactory', ext.safeProxyFactory);
    vm.serializeAddress(k, 'safeSingleton', ext.safeSingleton);
    vm.serializeAddress(k, 'masterQuartermaster', m.quartermaster);
    vm.serializeAddress(k, 'masterMutinyModule', m.mutinyModule);
    vm.serializeAddress(k, 'masterTreasuryAuthority', m.treasuryAuthority);
    vm.serializeAddress(k, 'masterSquadAdminImpl', m.squadAdminImpl);
    vm.serializeAddress(k, 'masterSquadAdminExtImpl', m.squadAdminExtImpl);
    vm.serializeAddress(k, 'roleHatClonesFactory', i.clonesFactory);
    vm.serializeAddress(k, 'navePirataRegistry', i.registry);
    vm.serializeAddress(k, 'warGameRegistry', i.warGameRegistry);
    vm.serializeAddress(k, 'roleHatUpgrader', i.upgrader);
    vm.serializeAddress(k, 'sponsorPolicyRegistry', i.sponsorPolicyRegistry);
    vm.serializeAddress(k, 'navePirataFactory', i.navePirataFactory);
    string memory json = vm.serializeAddress(k, 'deployer', deployer);
    _writeDeploymentJson(json, 'full-system.json');
  }

  function _writeSquadDeploymentJson(
    uint256 topHatId,
    address safe,
    address quartermaster,
    address mutinyModule,
    address treasuryAuthority,
    address squadAdminProxy,
    uint256 saltNonce
  ) internal {
    if (!_shouldWriteDeploymentJson()) return;
    string memory k = 'pacto_squad';
    vm.serializeUint(k, 'chainId', block.chainid);
    vm.serializeUint(k, 'topHatId', topHatId);
    vm.serializeUint(k, 'saltNonce', saltNonce);
    vm.serializeAddress(k, 'safe', safe);
    vm.serializeAddress(k, 'quartermaster', quartermaster);
    vm.serializeAddress(k, 'mutinyModule', mutinyModule);
    vm.serializeAddress(k, 'treasuryAuthority', treasuryAuthority);
    string memory json = vm.serializeAddress(k, 'squadAdminProxy', squadAdminProxy);
    _writeDeploymentJson(json, string.concat('squad-', vm.toString(saltNonce), '.json'));
  }

  function _writeSquadAdminExtStandaloneJson(
    address clone,
    address owner,
    address implementation,
    uint256 artifactNonce
  ) internal {
    if (!_shouldWriteDeploymentJson()) return;
    string memory k = 'pacto_sa_ext_standalone';
    vm.serializeUint(k, 'chainId', block.chainid);
    vm.serializeAddress(k, 'clone', clone);
    vm.serializeAddress(k, 'owner', owner);
    string memory json = vm.serializeAddress(k, 'implementation', implementation);
    _writeDeploymentJson(json, string.concat('squad-admin-ext-standalone-', vm.toString(artifactNonce), '.json'));
  }

  function _writeSquadAdminStandaloneCaptainJson(
    address clone,
    uint256 captainHatId,
    address implementation,
    uint256 artifactNonce
  ) internal {
    if (!_shouldWriteDeploymentJson()) return;
    string memory k = 'pacto_sa_standalone_captain';
    vm.serializeUint(k, 'chainId', block.chainid);
    vm.serializeUint(k, 'captainHatId', captainHatId);
    vm.serializeAddress(k, 'clone', clone);
    string memory json = vm.serializeAddress(k, 'implementation', implementation);
    _writeDeploymentJson(json, string.concat('squad-admin-standalone-captain-', vm.toString(artifactNonce), '.json'));
  }
}
