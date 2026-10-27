// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISponsorPolicyRegistry} from 'interfaces/external/ISponsorPolicyRegistry.sol';

import {SponsorPolicyOps} from 'script/SponsorPolicyOps.sol';
import {SponsorPolicyPins} from 'script/SponsorPolicyPins.sol';

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title WireSponsorPolicyFactory
 * @author Pacto
 * @notice Owner-only: authorize `NavePirataFactory` and `RoleHatUpgrader`, and register the factory
 *         as a policy target on username-nft.
 * @dev Pins from `SponsorPolicyPins` for `block.chainid`. Override factory via `NAVE_PIRATA_FACTORY`,
 *      registry via `SPONSOR_POLICY_REGISTRY`, and upgrader via `ROLE_HAT_UPGRADER`. When the env
 *      is unset, the upgrader is read from `infra.json` / `full-system.json` under `deployments/`
 *      then `simulations/`. Caller must be `SponsorPolicyRegistry` owner (username-nft ops key).
 */
contract WireSponsorPolicyFactory is Script {
  /// @notice Policy registry pin is zero on this chain.
  error WireSponsorPolicyFactory_UnsetRegistry(uint256 chainId);

  /// @notice `RoleHatUpgrader` was not in env or deployment artifacts.
  error WireSponsorPolicyFactory_UnsetUpgrader(uint256 chainId);

  function run() external {
    address _registryAddr = _resolveRegistry();
    if (_registryAddr == address(0)) revert WireSponsorPolicyFactory_UnsetRegistry(block.chainid);

    address _factory = _resolveFactory();
    address _upgrader = _resolveUpgrader();

    ISponsorPolicyRegistry _registry = ISponsorPolicyRegistry(_registryAddr);

    vm.startBroadcast();
    SponsorPolicyOps.WireResult memory _result = SponsorPolicyOps.wireFactoryAndUpgrader(_registry, _factory, _upgrader);
    vm.stopBroadcast();

    console.log('sponsorPolicyRegistry:', _registryAddr);
    console.log('navePirataFactory:', _factory);
    console.log('roleHatUpgrader:', _upgrader);
    console.log('registrarAuthorized:', _result.registrarAuthorized);
    console.log('targetRegistered:', _result.targetRegistered);
    console.log('upgraderRegistrarAuthorized:', _result.upgraderRegistrarAuthorized);
    console.log('factoryAuthorizedRegistrar:', _registry.authorizedRegistrars(_factory));
    console.log('upgraderAuthorizedRegistrar:', _registry.authorizedRegistrars(_upgrader));
    console.log('factoryIsContractAllowed:', _registry.isContractAllowed(_factory));
    console.log('upgraderIsContractAllowed:', _registry.isContractAllowed(_upgrader));
  }

  function _resolveRegistry() internal view returns (address registry) {
    try vm.envAddress('SPONSOR_POLICY_REGISTRY') returns (address _fromEnv) {
      return _fromEnv;
    } catch {
      return SponsorPolicyPins.sponsorPolicyRegistry(block.chainid);
    }
  }

  function _resolveFactory() internal view returns (address factory) {
    try vm.envAddress('NAVE_PIRATA_FACTORY') returns (address _fromEnv) {
      return _fromEnv;
    } catch {
      return SponsorPolicyPins.navePirataFactory(block.chainid);
    }
  }

  function _resolveUpgrader() internal returns (address upgrader) {
    try vm.envAddress('ROLE_HAT_UPGRADER') returns (address _fromEnv) {
      if (_fromEnv != address(0)) return _fromEnv;
    } catch {
      upgrader = address(0);
    }

    string memory _chain = vm.toString(block.chainid);
    upgrader = _tryReadUpgrader(string.concat('deployments/', _chain, '/infra.json'));
    if (upgrader != address(0)) return upgrader;
    upgrader = _tryReadUpgrader(string.concat('deployments/', _chain, '/full-system.json'));
    if (upgrader != address(0)) return upgrader;
    upgrader = _tryReadUpgrader(string.concat('simulations/', _chain, '/infra.json'));
    if (upgrader != address(0)) return upgrader;
    upgrader = _tryReadUpgrader(string.concat('simulations/', _chain, '/full-system.json'));
    if (upgrader != address(0)) return upgrader;

    revert WireSponsorPolicyFactory_UnsetUpgrader(block.chainid);
  }

  function _tryReadUpgrader(string memory path) internal returns (address upgrader) {
    try vm.readFile(path) returns (string memory json) {
      try vm.parseJsonAddress(json, '.roleHatUpgrader') returns (address _fromJson) {
        return _fromJson;
      } catch {
        return address(0);
      }
    } catch {
      return address(0);
    }
  }
}
