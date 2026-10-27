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
 * @notice Owner-only: authorize `NavePirataFactory` and register it as a policy target on username-nft.
 * @dev Pins from `SponsorPolicyPins` for `block.chainid`. Override factory via `NAVE_PIRATA_FACTORY`
 *      and registry via `SPONSOR_POLICY_REGISTRY`. Caller must be `SponsorPolicyRegistry` owner
 *      (username-nft ops key).
 */
contract WireSponsorPolicyFactory is Script {
  /// @notice Policy registry pin is zero on this chain.
  error WireSponsorPolicyFactory_UnsetRegistry(uint256 chainId);

  function run() external {
    address _registryAddr = _resolveRegistry();
    if (_registryAddr == address(0)) revert WireSponsorPolicyFactory_UnsetRegistry(block.chainid);

    address _factory = _resolveFactory();

    ISponsorPolicyRegistry _registry = ISponsorPolicyRegistry(_registryAddr);

    vm.startBroadcast();
    SponsorPolicyOps.WireResult memory _result = SponsorPolicyOps.wireFactory(_registry, _factory);
    vm.stopBroadcast();

    console.log('sponsorPolicyRegistry:', _registryAddr);
    console.log('navePirataFactory:', _factory);
    console.log('registrarAuthorized:', _result.registrarAuthorized);
    console.log('targetRegistered:', _result.targetRegistered);
    console.log('authorizedRegistrars:', _registry.authorizedRegistrars(_factory));
    console.log('isContractAllowed:', _registry.isContractAllowed(_factory));
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
}
