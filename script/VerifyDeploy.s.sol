// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
  CHAIN_ID_ARBITRUM_ONE,
  CHAIN_ID_BASE,
  CHAIN_ID_ETHEREUM,
  CHAIN_ID_OPTIMISM,
  CHAIN_ID_SEPOLIA
} from 'script/Constants.sol';

import {Script} from 'forge-std/Script.sol';
import {stdJson} from 'forge-std/StdJson.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title VerifyDeploy
 * @author Pacto
 * @notice Etherscan verification for full-system bootstrap contracts from `deployments/<chainId>/full-system.json`.
 * @dev Requires `FOUNDRY_PROFILE=verify` (`ffi = true` in `[profile.verify]` only). Run after `Deploy`.
 */
contract VerifyDeploy is Script {
  using stdJson for string;

  error UnsupportedChain(uint256 chainId);

  string internal constant _QM = 'src/contracts/core/Quartermaster.sol:Quartermaster';
  string internal constant _MM = 'src/contracts/core/MutinyModule.sol:MutinyModule';
  string internal constant _TA = 'src/contracts/core/TreasuryAuthority.sol:TreasuryAuthority';
  string internal constant _SA = 'src/contracts/squad/SquadAdmin.sol:SquadAdmin';
  string internal constant _SA_EXT = 'src/contracts/squad/SquadAdminExt.sol:SquadAdminExt';
  string internal constant _CLONES = 'src/contracts/factory/RoleHatClonesFactory.sol:RoleHatClonesFactory';
  string internal constant _REGISTRY = 'src/contracts/factory/NavePirataRegistry.sol:NavePirataRegistry';
  string internal constant _UPGRADER = 'src/contracts/factory/RoleHatUpgrader.sol:RoleHatUpgrader';
  string internal constant _FACTORY = 'src/contracts/factory/NavePirataFactory.sol:NavePirataFactory';

  function run() external {
    string memory _chain = _chainSlug();
    string memory _path = string.concat('deployments/', vm.toString(block.chainid), '/full-system.json');
    string memory _json = vm.readFile(_path);

    address _hats = _json.readAddress('.hats');
    address _safePf = _json.readAddress('.safeProxyFactory');
    address _safeSingle = _json.readAddress('.safeSingleton');
    address _clones = _json.readAddress('.roleHatClonesFactory');
    address _registry = _json.readAddress('.navePirataRegistry');
    address _upgrader = _json.readAddress('.roleHatUpgrader');

    bytes memory _encHats = abi.encode(_hats);
    bytes memory _encFactory = abi.encode(_hats, _safePf, _safeSingle, _clones, _registry, _upgrader);

    console.log('Verifying full-system contracts on', _chain);

    _verify(_json.readAddress('.masterQuartermaster'), _QM, _chain, _encHats);
    _verify(_json.readAddress('.masterMutinyModule'), _MM, _chain, _encHats);
    _verify(_json.readAddress('.masterTreasuryAuthority'), _TA, _chain, _encHats);
    _verify(_json.readAddress('.masterSquadAdminImpl'), _SA, _chain, _encHats);
    _verify(_json.readAddress('.masterSquadAdminExtImpl'), _SA_EXT, _chain, _encHats);
    _verifyNoArgs(_json.readAddress('.roleHatClonesFactory'), _CLONES, _chain);
    _verifyNoArgs(_json.readAddress('.navePirataRegistry'), _REGISTRY, _chain);
    _verifyUpgrader(_json, _hats, _clones, _registry, _chain);
    _verify(_json.readAddress('.navePirataFactory'), _FACTORY, _chain, _encFactory);
  }

  function _verifyUpgrader(
    string memory json,
    address hats,
    address clones,
    address registry,
    string memory chain
  ) internal {
    address _deployer = _resolveDeployer(json);
    if (_deployer == address(0)) {
      console.log('warn: deployer unknown; RoleHatUpgrader uses --guess-constructor-args');
      _verifyGuessArgs(json.readAddress('.roleHatUpgrader'), _UPGRADER, chain);
      return;
    }
    _verify(json.readAddress('.roleHatUpgrader'), _UPGRADER, chain, abi.encode(hats, clones, registry, _deployer));
  }

  function _resolveDeployer(string memory json) internal view returns (address _deployer) {
    if (_jsonHasKey(json, '"deployer"')) {
      return json.readAddress('.deployer');
    }
    return vm.envOr('DEPLOYER_ADDRESS', address(0));
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

  function _verifyNoArgs(address addr, string memory contractId, string memory chain) internal {
    console.log('==>', contractId, addr);
    string[] memory _inputs = new string[](7);
    _inputs[0] = 'forge';
    _inputs[1] = 'verify-contract';
    _inputs[2] = vm.toString(addr);
    _inputs[3] = contractId;
    _inputs[4] = '--chain';
    _inputs[5] = chain;
    _inputs[6] = '--watch';
    console.log(string(vm.ffi(_inputs)));
  }

  function _verifyGuessArgs(address addr, string memory contractId, string memory chain) internal {
    console.log('==>', contractId, addr);
    string[] memory _inputs = new string[](8);
    _inputs[0] = 'forge';
    _inputs[1] = 'verify-contract';
    _inputs[2] = vm.toString(addr);
    _inputs[3] = contractId;
    _inputs[4] = '--chain';
    _inputs[5] = chain;
    _inputs[6] = '--guess-constructor-args';
    _inputs[7] = '--watch';
    console.log(string(vm.ffi(_inputs)));
  }

  function _verify(address addr, string memory contractId, string memory chain, bytes memory constructorArgs) internal {
    console.log('==>', contractId, addr);
    string[] memory _inputs = new string[](9);
    _inputs[0] = 'forge';
    _inputs[1] = 'verify-contract';
    _inputs[2] = vm.toString(addr);
    _inputs[3] = contractId;
    _inputs[4] = '--chain';
    _inputs[5] = chain;
    _inputs[6] = '--constructor-args';
    _inputs[7] = vm.toString(constructorArgs);
    _inputs[8] = '--watch';
    console.log(string(vm.ffi(_inputs)));
  }

  function _chainSlug() internal view returns (string memory) {
    uint256 _id = block.chainid;
    if (_id == CHAIN_ID_SEPOLIA) return 'sepolia';
    if (_id == CHAIN_ID_ETHEREUM) return 'mainnet';
    if (_id == CHAIN_ID_ARBITRUM_ONE) return 'arbitrum';
    if (_id == CHAIN_ID_OPTIMISM) return 'optimism';
    if (_id == CHAIN_ID_BASE) return 'base';
    revert UnsupportedChain(_id);
  }
}
