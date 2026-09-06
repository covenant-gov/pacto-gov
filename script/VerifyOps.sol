// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
  CHAIN_ID_ARBITRUM_ONE,
  CHAIN_ID_BASE,
  CHAIN_ID_ETHEREUM,
  CHAIN_ID_OPTIMISM,
  CHAIN_ID_SEPOLIA
} from 'script/Constants.sol';

import {Vm} from 'forge-std/Vm.sol';
import {console} from 'forge-std/console.sol';

/**
 * @title VerifyOps
 * @author Pacto
 * @notice Shared Etherscan verification helpers for deployment scripts.
 */
library VerifyOps {
  /// @notice No Etherscan chain slug for `chainId`.
  error VerifyOps_UnsupportedChain(uint256 chainId);

  function chainSlug(uint256 chainId) internal pure returns (string memory slug) {
    if (chainId == CHAIN_ID_SEPOLIA) return 'sepolia';
    if (chainId == CHAIN_ID_ETHEREUM) return 'mainnet';
    if (chainId == CHAIN_ID_ARBITRUM_ONE) return 'arbitrum';
    if (chainId == CHAIN_ID_OPTIMISM) return 'optimism';
    if (chainId == CHAIN_ID_BASE) return 'base';
    revert VerifyOps_UnsupportedChain(chainId);
  }

  function verifyNoArgs(Vm vm, address addr, string memory contractId, string memory chain) internal {
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

  function verifyGuessArgs(Vm vm, address addr, string memory contractId, string memory chain) internal {
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

  function verifyWithArgs(
    Vm vm,
    address addr,
    string memory contractId,
    string memory chain,
    bytes memory constructorArgs
  ) internal {
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
}
