// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Enum} from '@safe-global/safe-contracts/contracts/common/Enum.sol';

/// @notice `SafeProxyFactory.createProxyWithNonce` as deployed alongside Safe singleton 1.4.1.
interface ISafeProxyFactory {
  function createProxyWithNonce(
    address _singleton,
    bytes memory initializer,
    uint256 saltNonce
  ) external returns (address proxy);
}

/// @notice `Safe.setup` / `Safe.execTransaction` surface for proxies backed by `@safe-global/safe-contracts` v1.4.1-2 singletons (`Safe.sol`).
interface ISafe {
  function setup(
    address[] calldata _owners,
    uint256 _threshold,
    address to,
    bytes calldata data,
    address fallbackHandler,
    address paymentToken,
    uint256 payment,
    address payable paymentReceiver
  ) external;

  function execTransaction(
    address to,
    uint256 value,
    bytes calldata data,
    Enum.Operation operation,
    uint256 safeTxGas,
    uint256 baseGas,
    uint256 gasPrice,
    address gasToken,
    address payable refundReceiver,
    bytes memory signatures
  ) external payable returns (bool success);
}
