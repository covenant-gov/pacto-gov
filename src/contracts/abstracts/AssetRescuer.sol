// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAssetRescuer} from 'interfaces/abstracts/IAssetRescuer.sol';

import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

/**
 * @title AssetRescuer
 * @author Pacto
 * @notice Receive/fallback revert with `_rescueDestination()`. Public sweeps for ETH/ERC20/721/1155; safe after a role hat has moved
 * @dev Override `_rescueDestination` (e.g. Safe) — funds never meant to sit on this address
 */
abstract contract AssetRescuer is IAssetRescuer {
  using SafeERC20 for IERC20;

  /// @notice Reject value + empty calldata; revert names `_rescueDestination`
  receive() external payable {
    revert AssetRescuer_SendToDestinationInstead(_rescueDestination());
  }

  /// @notice Reject unknown calldata; revert names `_rescueDestination`
  fallback() external payable {
    revert AssetRescuer_SendToDestinationInstead(_rescueDestination());
  }

  /// @inheritdoc IAssetRescuer
  function rescue(address token) external {
    address _dest = _rescueDestination();
    if (_dest == address(0)) revert AssetRescuer_ZeroDestination();

    if (token == address(0)) {
      uint256 _amount = address(this).balance;
      (bool _ok,) = _dest.call{value: _amount}('');
      if (!_ok) revert AssetRescuer_RescueFailed();
      emit AssetRescuedETH(_dest, _amount);
    } else {
      uint256 _amount = IERC20(token).balanceOf(address(this));
      IERC20(token).safeTransfer(_dest, _amount);
      emit AssetRescuedERC20(token, _dest, _amount);
    }
  }

  /// @inheritdoc IAssetRescuer
  function rescueERC721(address token, uint256 tokenId) external {
    address _dest = _rescueDestination();
    if (_dest == address(0)) revert AssetRescuer_ZeroDestination();

    IERC721(token).transferFrom(address(this), _dest, tokenId);
    emit AssetRescuedERC721(token, _dest, tokenId);
  }

  /// @inheritdoc IAssetRescuer
  function rescueERC1155(address token, uint256 id, uint256 amount) external {
    address _dest = _rescueDestination();
    if (_dest == address(0)) revert AssetRescuer_ZeroDestination();

    IERC1155(token).safeTransferFrom(address(this), _dest, id, amount, '');
    emit AssetRescuedERC1155(token, _dest, id, amount);
  }

  /**
   * @notice Resolve the rescue destination for this contract.
   * @dev Must be overridden. For `TreasuryAuthority` this returns the Zodiac `avatar` (the Safe).
   * @return _destination The address to which rescued assets are forwarded.
   */
  function _rescueDestination() internal view virtual returns (address _destination);
}
