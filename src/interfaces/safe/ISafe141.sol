// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Enum} from '@safe-global/safe-contracts/contracts/common/Enum.sol';

/// @notice Canonical `SafeProxyFactory` API for deterministic Safe proxies (`@safe-global/safe-contracts` 1.4.1 factories).
interface ISafeProxyFactory {
  /// @notice CREATE2-deploy a minimal proxy to `_singleton`, optionally calling `initializer` on deploy.
  /// @param _singleton Safe logic singleton backing the proxy.
  /// @param initializer Calldata for the first call on the proxy (typically `Safe.setup`); may be empty.
  /// @param saltNonce Combined with `initializer` hash for CREATE2 salt.
  /// @return proxy Address of the new proxy contract.
  function createProxyWithNonce(
    address _singleton,
    bytes memory initializer,
    uint256 saltNonce
  ) external returns (address proxy);
}

/// @notice Canonical Safe 1.4.1 `setup` / `execTransaction` API for EIP-1167 proxies (`Safe.sol`).
interface ISafe {
  /// @notice One-shot initializer after proxy deploy; callable once per proxy.
  /// @param _owners Initial multisig owners.
  /// @param _threshold Confirmation threshold.
  /// @param to Optional delegatecall target during setup modules phase.
  /// @param data Calldata paired with `to` for delegatecall.
  /// @param fallbackHandler Optional fallback handler (`address(0)` for none).
  /// @param paymentToken ERC-20 for setup refund (`address(0)` for ETH).
  /// @param payment Refund amount in `paymentToken`.
  /// @param paymentReceiver Refund recipient (`address(0)` uses `tx.origin`).
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

  /// @notice Execute an inner tx after signature validation; success/failure is reflected in return and implementation events.
  /// @param to Inner call target (often the Safe itself for owner/module actions).
  /// @param value Native value for the inner call.
  /// @param data Inner calldata.
  /// @param operation `Enum.Operation.Call` or `DelegateCall`.
  /// @param safeTxGas Gas forwarded to the inner call.
  /// @param baseGas Overhead billed for refunds.
  /// @param gasPrice Unit price used in refund arithmetic.
  /// @param gasToken Token paying gas refund (`address(0)` for ETH).
  /// @param refundReceiver Refund sink (`address(0)` defaults per Safe rules).
  /// @param signatures Packed owner / contract approvals for the EIP-712 Safe tx hash.
  /// @return success Whether the inner call returned without bubbling revert.
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
