// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {IQuiescent} from 'interfaces/IQuiescent.sol';
import {ISquadAdmin} from 'interfaces/ISquadAdmin.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title SquadAdminImpl
 * @author Pacto
 * @notice v1 implementation behind the SquadAdmin UUPS proxy. Exposes a captain-gated executor
 *         roster and the single gasless governance predicate (`isExecutor`) used by the
 *         application layer. Richer product surface (EIP-712 signed app actions, channel-scoped
 *         policy, role / permission enumeration) is intentionally deferred to Phase 11 and will
 *         ship as `SquadAdminImplV2` installed via captain-authorised `upgradeToAndCall`.
 * @dev Storage follows ERC-7201 ([EIP-7201](https://eips.ethereum.org/EIPS/eip-7201)) under the
 *      namespace `pacto.squadadmin.v1`, so future implementation versions may append fields
 *      without colliding with existing state or the inherited `Initializable` /
 *      `UUPSUpgradeable` storage. Upgrade authorisation is captain-hat-gated via
 *      `_authorizeUpgrade`, matching the "SquadAdmin changes do not flow through the two-body
 *      vote" architectural rule — the captain alone controls the product surface.
 */
contract SquadAdminImpl is ISquadAdmin, HatGated, Initializable, UUPSUpgradeable {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Parameters required to initialize a SquadAdmin proxy.
   * @param captainHatId Captain hat id that gates executor management and UUPS upgrades.
   * @param squadAdminHatId Squad-admin hat id worn by this proxy (informational for v1; used
   *        in Phase 11 predicates).
   */
  struct InitParams {
    uint256 captainHatId;
    uint256 squadAdminHatId;
  }

  /**
   * @notice ERC-7201 namespaced storage layout for SquadAdmin v1.
   * @dev New fields may be appended in later implementation versions; never reordered or
   *      removed, so existing proxies upgrade-in-place without state migration.
   * @param captainHatId Captain hat id used for gate checks.
   * @param squadAdminHatId Squad-admin hat id worn by this proxy.
   * @param executors Mapping of address → enabled-flag for v1's single predicate.
   * @custom:storage-location erc7201:pacto.squadadmin.v1
   */
  struct SquadAdminStorageV1 {
    uint256 captainHatId;
    uint256 squadAdminHatId;
    mapping(address _executor => bool _enabled) executors;
  }

  /*///////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice ERC-7201 slot for `SquadAdminStorageV1`.
   * @dev Computed as `keccak256(abi.encode(uint256(keccak256("pacto.squadadmin.v1")) - 1)) & ~bytes32(uint256(0xff))`.
   */
  bytes32 private constant _SQUAD_ADMIN_STORAGE_V1 = 0xbc98e12076e749742801736ca484b4a7be0cea42f395e3487d1ecb57f6c45400;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Master-copy constructor; bakes the Hats singleton into implementation runtime code
   *         and locks direct initialization of the implementation.
   * @param hats_ Hats Protocol address for this chain.
   */
  constructor(IHats hats_) HatGated(hats_) {
    _disableInitializers();
  }

  /**
   * @notice One-shot proxy initializer. Seeds the captain and squad-admin hat ids.
   * @param _p Bootstrap parameters.
   */
  function initialize(InitParams calldata _p) external initializer {
    // OZ v5 UUPSUpgradeable is stateless; no initializer needs to run.
    SquadAdminStorageV1 storage _s = _getStorage();
    _s.captainHatId = _p.captainHatId;
    _s.squadAdminHatId = _p.squadAdminHatId;
  }

  /*///////////////////////////////////////////////////////////////
                            CAPTAIN-GATED LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  function enableExecutor(address _executor) external override {
    _requireCaptain();
    if (_executor == address(0)) revert SquadAdmin_ZeroAddress();
    SquadAdminStorageV1 storage _s = _getStorage();
    if (_s.executors[_executor]) revert SquadAdmin_AlreadyExecutor();
    _s.executors[_executor] = true;
    emit ExecutorEnabled(_executor);
  }

  /// @inheritdoc ISquadAdmin
  function disableExecutor(address _executor) external override {
    _requireCaptain();
    SquadAdminStorageV1 storage _s = _getStorage();
    if (!_s.executors[_executor]) revert SquadAdmin_NotExecutor();
    _s.executors[_executor] = false;
    emit ExecutorDisabled(_executor);
  }

  /*///////////////////////////////////////////////////////////////
                            UPGRADE AUTHORISATION
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice UUPS upgrade authorisation hook. Captain-hat-gated — SquadAdmin changes bypass the
   *         two-body vote by design.
   * @param _newImplementation Address of the proposed new implementation.
   */
  function _authorizeUpgrade(address _newImplementation) internal view override {
    _requireCaptain();
    if (_newImplementation == address(0)) revert SquadAdmin_ZeroAddress();
  }

  /// @inheritdoc ISquadAdmin
  function upgradeToAndCall(
    address _newImplementation,
    bytes memory _data
  ) public payable override(ISquadAdmin, UUPSUpgradeable) {
    super.upgradeToAndCall(_newImplementation, _data);
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc ISquadAdmin
  function isExecutor(address _executor) external view override returns (bool _enabled) {
    return _getStorage().executors[_executor];
  }

  /// @inheritdoc ISquadAdmin
  function CAPTAIN_HAT_ID() external view override returns (uint256 _captainHatId) {
    return _getStorage().captainHatId;
  }

  /// @inheritdoc ISquadAdmin
  function SQUAD_ADMIN_HAT_ID() external view override returns (uint256 _squadAdminHatId) {
    return _getStorage().squadAdminHatId;
  }

  /// @inheritdoc IQuiescent
  function isQuiet() external pure override returns (bool _quiet) {
    // v1 has no timelocked, pending, or in-flight state; always quiet. When Phase 11 introduces
    // asynchronous flows (EIP-712 nonces with windows, scheduled policy changes, etc.) this
    // returns the relevant emptiness.
    return true;
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns a pointer to the ERC-7201 `SquadAdminStorageV1` struct.
   * @return _s Storage-pointer to the v1 namespaced storage.
   */
  function _getStorage() internal pure returns (SquadAdminStorageV1 storage _s) {
    bytes32 _slot = _SQUAD_ADMIN_STORAGE_V1;
    assembly {
      _s.slot := _slot
    }
  }

  /**
   * @notice Reverts with `SquadAdmin_NotCaptain` if `msg.sender` does not wear the captain hat.
   * @dev Uses the v1-specific error surface instead of `HatGated_NotHatWearer` to match the
   *      `ISquadAdmin` contract and keep captain-gated reverts uniform across the product surface.
   */
  function _requireCaptain() internal view {
    uint256 _captainHatId = _getStorage().captainHatId;
    if (!_HATS.isWearerOfHat(msg.sender, _captainHatId)) revert SquadAdmin_NotCaptain();
  }
}
