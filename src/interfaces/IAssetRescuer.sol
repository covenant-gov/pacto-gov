// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IAssetRescuer
 * @author Pacto
 * @notice Permissionless sweeps to `_rescueDestination()`; receive/fallback revert with that address. ETH + ERC20/721/1155
 */
interface IAssetRescuer {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted after a successful native ETH rescue.
   * @param destination The address that received the ETH.
   * @param amount The amount of ETH transferred, in wei.
   */
  event AssetRescuedETH(address indexed destination, uint256 amount);

  /**
   * @notice Emitted after a successful ERC-20 rescue.
   * @param token The ERC-20 token address that was swept.
   * @param destination The address that received the tokens.
   * @param amount The amount of tokens transferred, in the token's smallest unit.
   */
  event AssetRescuedERC20(address indexed token, address indexed destination, uint256 amount);

  /**
   * @notice Emitted after a successful ERC-721 rescue.
   * @param token The ERC-721 collection address.
   * @param destination The address that received the token.
   * @param tokenId The token id transferred.
   */
  event AssetRescuedERC721(address indexed token, address indexed destination, uint256 tokenId);

  /**
   * @notice Emitted after a successful ERC-1155 rescue.
   * @param token The ERC-1155 collection address.
   * @param destination The address that received the tokens.
   * @param id The ERC-1155 id transferred.
   * @param amount The amount transferred.
   */
  event AssetRescuedERC1155(address indexed token, address indexed destination, uint256 id, uint256 amount);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown by `receive` / `fallback` to block voluntary ETH sends to the
   *         contract. Included in the revert so wallets can surface the correct destination.
   * @param destination The intended destination (i.e., the Safe or other configured address).
   */
  error AssetRescuer_SendToDestinationInstead(address destination);
  /// @notice The underlying transfer call failed during a rescue.
  error AssetRescuer_RescueFailed();
  /// @notice The inheriting contract returned `address(0)` from `_rescueDestination()`.
  error AssetRescuer_ZeroDestination();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sweep this contract's full balance of `token` to the rescue destination.
   * @dev Use `address(0)` as `token` to sweep native ETH instead of an ERC-20 balance.
   *      Permissionless: anyone may trigger the sweep since the destination is fixed.
   * @param token ERC-20 token address, or `address(0)` for native ETH.
   */
  function rescue(address token) external;

  /**
   * @notice Sweep a specific ERC-721 `tokenId` held by this contract to the rescue destination.
   * @dev Permissionless.
   * @param token ERC-721 collection address.
   * @param tokenId Token id to transfer.
   */
  function rescueERC721(address token, uint256 tokenId) external;

  /**
   * @notice Sweep an ERC-1155 balance held by this contract to the rescue destination.
   * @dev Permissionless.
   * @param token ERC-1155 collection address.
   * @param id ERC-1155 id to transfer.
   * @param amount Amount to transfer.
   */
  function rescueERC1155(address token, uint256 id, uint256 amount) external;
}
