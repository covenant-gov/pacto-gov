// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
  DEFAULT_MAINNET_FORK_BLOCK,
  DEPLOY_NAV_PIRATA_SALT_NONCE,
  HATS_PROTOCOL_V1,
  SAFE_SINGLETON_141
} from 'script/Constants.sol';
import {DeployTypes} from 'script/DeployTypes.sol';
import {PactoDeploy} from 'script/PactoDeploy.sol';

import {Test} from 'forge-std/Test.sol';

/**
 * @title IntegrationBase
 * @author Pacto
 * @notice Runs the same deploy routine as `script/Deploy.sol` during `setUp`; registry owner is the test contract.
 * @dev Requires an Ethereum mainnet fork: `forge test --fork-url …`, env `MAINNET_RPC`, or `foundry.toml` `rpc_endpoints.mainnet`.
 *      Pin matches `DEFAULT_MAINNET_FORK_BLOCK` in `Constants.sol`. Use `_fund()`, `_freshSquadSalt()` in subclasses.
 *      Override `_loadExternalAddresses` only if you deliberately target different chain infra.
 */
abstract contract IntegrationBase is PactoDeploy, Test {
  error IntegrationBase_NoMainnetFork();

  bool internal _integrationForkActive;

  function setUp() public virtual {
    _requireEthereumMainnetFork();
    DeployTypes.ExternalAddresses memory _ext = _loadExternalAddresses();
    _deployFullSystem(_ext, address(this));
    _ensureSafeSingletonBytecodeAfterFork();
  }

  /// @dev Resolves `{hats,safe singleton,factory}` for `block.chainid`; override only for forks with different infra.
  function _loadExternalAddresses() internal view virtual returns (DeployTypes.ExternalAddresses memory) {
    return _externalAddressesForCurrentChain();
  }

  /// @dev Selects Forge CLI fork (`HATS` already has code) or `vm.createSelectFork` + `_integrationForkActive`; otherwise reverts.
  function _requireEthereumMainnetFork() internal virtual {
    if (HATS_PROTOCOL_V1.code.length > 0) {
      _integrationForkActive = true;
      return;
    }
    string memory _rpc = vm.envOr('MAINNET_RPC', string(''));
    if (bytes(_rpc).length == 0) {
      try vm.rpcUrl('mainnet') returns (string memory _fromToml) {
        _rpc = _fromToml;
      } catch {}
    }
    if (bytes(_rpc).length == 0) revert IntegrationBase_NoMainnetFork();
    vm.createSelectFork(_rpc, DEFAULT_MAINNET_FORK_BLOCK);
    _integrationForkActive = true;
  }

  /// @dev Re-rolls the fork to `DEFAULT_MAINNET_FORK_BLOCK` when the pinned Safe singleton has no bytecode.
  function _ensureSafeSingletonBytecodeAfterFork() internal virtual {
    if (SAFE_SINGLETON_141.code.length > 0) return;
    vm.rollFork(DEFAULT_MAINNET_FORK_BLOCK);
  }

  /// @dev Sets native balance for EOAs/contracts that submit fork transactions.
  function _fund(address _who, uint256 _wei) internal virtual {
    vm.deal(_who, _wei);
  }

  /// @dev `saltNonce` for `deployNavePirata`; override after multiple squads from the same test contract.
  function _freshSquadSalt() internal view virtual returns (uint256 _saltNonce) {
    _saltNonce = DEPLOY_NAV_PIRATA_SALT_NONCE;
  }
}
