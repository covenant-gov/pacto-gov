// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

/**
 * @title SquadAdmin
 * @author Pacto
 * @notice ERC-1967 proxy; squad-admin hat points here; logic is UUPS `SquadAdminImpl`
 * @dev Captain authorizes upgrades in `_authorizeUpgrade` on the implementation
 */
contract SquadAdmin is ERC1967Proxy {
  /**
   * @notice `ERC1967Proxy(implementation, initData)` — usual `initialize(InitParams)` in `_data`
   * @param _implementation `SquadAdminImpl` (or compatible)
   * @param _data Init calldata
   */
  constructor(address _implementation, bytes memory _data) payable ERC1967Proxy(_implementation, _data) {}
}
