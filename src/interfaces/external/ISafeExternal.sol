// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ISafeProxyFactory
 * @author Pacto
 * @notice Minimal ABI for Safe's proxy factory used by `NavePirataFactory` to deploy per-squad
 *         Safes with deterministic CREATE2 addresses.
 */
interface ISafeProxyFactory {
  /**
   * @notice Deploys a Safe proxy via CREATE2 and invokes `initializer` on it.
   * @param _singleton Safe singleton backing the new proxy.
   * @param _initializer ABI-encoded `setup(...)` call executed on the fresh proxy.
   * @param _saltNonce Salt nonce used in CREATE2 derivation.
   * @return _proxy Address of the deployed Safe proxy.
   */
  function createProxyWithNonce(
    address _singleton,
    bytes memory _initializer,
    uint256 _saltNonce
  ) external returns (address _proxy);
}

/**
 * @title ISafe
 * @author Pacto
 * @notice Minimal ABI for a Safe proxy covering the surface `NavePirataFactory` and
 *         `TreasuryAuthority` need to interact with at bootstrap and runtime. Full Safe source
 *         uses `Enum.Operation`; the ABI-level type is `uint8`.
 */
interface ISafe {
  /**
   * @notice One-shot initializer called on a freshly deployed Safe proxy.
   * @param _owners Initial Safe owners.
   * @param _threshold Required number of owner signatures per transaction.
   * @param _to Optional delegatecall target invoked during setup; `address(0)` for none.
   * @param _data Optional delegatecall data paired with `_to`.
   * @param _fallbackHandler Fallback handler; `address(0)` for none.
   * @param _paymentToken Token used to refund the setup payer; `address(0)` for ETH.
   * @param _payment Payment amount.
   * @param _paymentReceiver Payment recipient; `address(0)` for `tx.origin`.
   */
  function setup(
    address[] calldata _owners,
    uint256 _threshold,
    address _to,
    bytes calldata _data,
    address _fallbackHandler,
    address _paymentToken,
    uint256 _payment,
    address payable _paymentReceiver
  ) external;

  /**
   * @notice Executes a Safe transaction authenticated by owner signatures (or ERC-1271 / pre-approved).
   * @param _to Target address of the inner transaction.
   * @param _value ETH value of the inner transaction.
   * @param _data Calldata of the inner transaction.
   * @param _operation Inner operation kind: `0` = Call, `1` = DelegateCall.
   * @param _safeTxGas Gas limit for the inner transaction.
   * @param _baseGas Fixed overhead included in the gas refund.
   * @param _gasPrice Gas price used for refund accounting.
   * @param _gasToken Token used for the refund; `address(0)` for ETH.
   * @param _refundReceiver Refund recipient; `address(0)` for `tx.origin`.
   * @param _signatures Concatenated owner signatures; for pre-validated sigs `v == 1`,
   *        `r == ownerAddress`, `s == 0` and `msg.sender` must equal the owner.
   * @return _success Whether the inner transaction succeeded.
   */
  function execTransaction(
    address _to,
    uint256 _value,
    bytes calldata _data,
    uint8 _operation,
    uint256 _safeTxGas,
    uint256 _baseGas,
    uint256 _gasPrice,
    address _gasToken,
    address payable _refundReceiver,
    bytes memory _signatures
  ) external payable returns (bool _success);

  /**
   * @notice Enable `_module` as a Zodiac module on the Safe. Callable only via self-call.
   * @param _module Module address to enable.
   */
  function enableModule(address _module) external;

  /**
   * @notice Swap `_oldOwner` for `_newOwner`. Callable only via self-call.
   * @param _prevOwner Linked-list predecessor of `_oldOwner` (use sentinel `0x1` for the head).
   * @param _oldOwner Owner to replace.
   * @param _newOwner Incoming owner.
   */
  function swapOwner(address _prevOwner, address _oldOwner, address _newOwner) external;

  /**
   * @notice Check whether `_module` is enabled as a module on the Safe.
   * @param _module Module address.
   * @return _enabled True iff enabled.
   */
  function isModuleEnabled(address _module) external view returns (bool _enabled);

  /**
   * @notice List current Safe owners in linked-list order.
   * @return _owners Owner array.
   */
  function getOwners() external view returns (address[] memory _owners);
}
