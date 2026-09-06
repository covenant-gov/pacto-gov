// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISponsorPolicyRegistry} from 'interfaces/external/ISponsorPolicyRegistry.sol';

/// @dev Integration-only stand-in for username-nft `SponsorPolicyRegistry` registrar surface.
contract SponsorPolicyRegistryHarness is ISponsorPolicyRegistry {
  mapping(uint256 topHatId => bool sponsored) internal _topHats;
  mapping(address module => uint256 topHatId) internal _moduleToTopHat;
  mapping(address registrar => bool authorized) internal _authorizedRegistrars;

  function setAuthorizedRegistrar(address registrar, bool authorized) external {
    _authorizedRegistrars[registrar] = authorized;
  }

  function registerTopHat(uint256 topHatId) external {
    if (!_authorizedRegistrars[msg.sender]) {
      revert SponsorPolicyRegistry_UnauthorizedRegistrar(msg.sender);
    }
    _topHats[topHatId] = true;
  }

  function registerModulesForTopHat(uint256 topHatId, address[] calldata modules) external {
    if (!_authorizedRegistrars[msg.sender]) {
      revert SponsorPolicyRegistry_UnauthorizedRegistrar(msg.sender);
    }
    for (uint256 _i = 0; _i < modules.length; _i++) {
      address _module = modules[_i];
      uint256 _existing = _moduleToTopHat[_module];
      if (_existing != 0 && _existing != topHatId) {
        revert SponsorPolicyRegistry_ModuleAlreadyIndexed(_module, _existing);
      }
      _moduleToTopHat[_module] = topHatId;
    }
  }

  function moduleToTopHat(address module) external view returns (uint256 topHatId) {
    topHatId = _moduleToTopHat[module];
  }

  function isTopHatSponsored(uint256 topHatId) external view returns (bool sponsored) {
    sponsored = _topHats[topHatId];
  }
}
