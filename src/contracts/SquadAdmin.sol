// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

/**
 * @title SquadAdmin
 * @author Pacto
 * @notice ERC-1967 proxy for a SquadAdmin implementation. Thin constructor wrapper so the
 *         squad-admin hat can be minted to a stable address (this proxy) while the underlying
 *         implementation upgrades in-place via UUPS. Every squad gets its own instance.
 * @dev The proxy has no logic of its own — all calls delegate to the current
 *      `SquadAdminImpl(V{n})` behind ERC-1967. Upgrades are captain-gated inside the
 *      implementation's `_authorizeUpgrade`, so ownership of the captain hat fully determines
 *      who can swap the logic.
 */
contract SquadAdmin is ERC1967Proxy {
  /**
   * @notice Deploys the proxy and delegate-calls `implementation` with `data` for one-shot init.
   * @param _implementation SquadAdmin implementation (typically `SquadAdminImpl`) address.
   * @param _data Initializer calldata (ABI-encoded `initialize(InitParams)` payload).
   */
  constructor(address _implementation, bytes memory _data) payable ERC1967Proxy(_implementation, _data) {}
}
