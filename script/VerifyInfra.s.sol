// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VerifyOps} from 'script/VerifyOps.sol';

import {Script} from 'forge-std/Script.sol';
import {stdJson} from 'forge-std/StdJson.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title VerifyInfra
 * @author Pacto
 * @notice Etherscan verification for infra contracts from `deployments/<chainId>/infra.json`.
 * @dev Requires `FOUNDRY_PROFILE=verify` (`ffi = true`). Reads `external.json` for Hats / Safe singletons.
 */
contract VerifyInfra is Script {
  using stdJson for string;

  /// @notice `infra.json` or `external.json` missing `deployer` and `DEPLOYER_ADDRESS` unset.
  error VerifyInfra_UnsetDeployer();

  string internal constant _CLONES = 'src/contracts/factory/RoleHatClonesFactory.sol:RoleHatClonesFactory';
  string internal constant _REGISTRY = 'src/contracts/factory/NavePirataRegistry.sol:NavePirataRegistry';
  string internal constant _WAR_GAME_REGISTRY = 'src/contracts/factory/WarGameRegistry.sol:WarGameRegistry';
  string internal constant _UPGRADER = 'src/contracts/factory/RoleHatUpgrader.sol:RoleHatUpgrader';
  string internal constant _FACTORY = 'src/contracts/factory/NavePirataFactory.sol:NavePirataFactory';

  function run() external {
    string memory _chain = VerifyOps.chainSlug(block.chainid);
    string memory _base = string.concat('deployments/', vm.toString(block.chainid), '/');
    string memory _infraJson = vm.readFile(string.concat(_base, 'infra.json'));
    string memory _externalJson = vm.readFile(string.concat(_base, 'external.json'));

    address _hats = _externalJson.readAddress('.hats');
    address _safePf = _externalJson.readAddress('.safeProxyFactory');
    address _safeSingle = _externalJson.readAddress('.safeSingleton');

    address _clones = _infraJson.readAddress('.roleHatClonesFactory');
    address _registry = _infraJson.readAddress('.navePirataRegistry');
    address _warGameRegistry = _infraJson.readAddress('.warGameRegistry');
    address _upgrader = _infraJson.readAddress('.roleHatUpgrader');
    address _factory = _infraJson.readAddress('.navePirataFactory');
    address _sponsorPolicyRegistry = _infraJson.readAddress('.sponsorPolicyRegistry');

    address _deployer = _resolveDeployer(_infraJson);

    console.log('Verifying infra contracts on', _chain);

    VerifyOps.verifyNoArgs(vm, _clones, _CLONES, _chain);
    VerifyOps.verifyNoArgs(vm, _registry, _REGISTRY, _chain);
    VerifyOps.verifyNoArgs(vm, _warGameRegistry, _WAR_GAME_REGISTRY, _chain);
    VerifyOps.verifyWithArgs(vm, _upgrader, _UPGRADER, _chain, abi.encode(_hats, _clones, _registry, _deployer));
    VerifyOps.verifyWithArgs(
      vm,
      _factory,
      _FACTORY,
      _chain,
      abi.encode(_hats, _safePf, _safeSingle, _clones, _registry, _warGameRegistry, _upgrader, _sponsorPolicyRegistry)
    );
  }

  function _resolveDeployer(string memory infraJson) internal view returns (address deployer) {
    if (_jsonHasKey(infraJson, '"deployer"')) {
      return infraJson.readAddress('.deployer');
    }
    deployer = vm.envOr('DEPLOYER_ADDRESS', address(0));
    if (deployer == address(0)) revert VerifyInfra_UnsetDeployer();
  }

  function _jsonHasKey(string memory json, bytes memory key) internal pure returns (bool found) {
    bytes memory _data = bytes(json);
    if (key.length == 0 || _data.length < key.length) return false;
    for (uint256 i = 0; i <= _data.length - key.length; i++) {
      bool _match = true;
      for (uint256 j = 0; j < key.length; j++) {
        if (_data[i + j] != key[j]) {
          _match = false;
          break;
        }
      }
      if (_match) return true;
    }
    return false;
  }
}
