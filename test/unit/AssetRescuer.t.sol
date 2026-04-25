// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AssetRescuer} from 'contracts/abstracts/AssetRescuer.sol';
import {Test} from 'forge-std/Test.sol';
import {IAssetRescuer} from 'interfaces/IAssetRescuer.sol';

import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

/**
 * @title AssetRescuerHarness
 * @author Pacto
 * @notice Concrete subclass with a mutable rescue destination for test isolation.
 */
contract AssetRescuerHarness is AssetRescuer {
  /// @notice Destination override returned by `_rescueDestination`.
  address public destination;

  constructor(address destination_) {
    destination = destination_;
  }

  /// @notice Update the destination (used to test the zero-destination path without redeploying).
  function setDestination(address destination_) external {
    destination = destination_;
  }

  function _rescueDestination() internal view override returns (address) {
    return destination;
  }
}

/**
 * @title AssetRescuerUnitTest
 * @author Pacto
 * @notice Unit tests for `AssetRescuer`. All external token/recipient interactions are modelled
 *         with `vm.mockCall` / `vm.mockCallRevert` against fixed pseudo-addresses derived from
 *         keccak constants — no concrete mock contracts are deployed.
 */
contract UnitAssetRescuer is Test {
  /// @dev Pseudo-addresses receive no code; calls against them are satisfied via `vm.mockCall`.
  address internal constant _TOKEN_ERC20 = address(uint160(uint256(keccak256('pacto.assetrescuer.ERC20'))));
  address internal constant _TOKEN_ERC721 = address(uint160(uint256(keccak256('pacto.assetrescuer.ERC721'))));
  address internal constant _TOKEN_ERC1155 = address(uint160(uint256(keccak256('pacto.assetrescuer.ERC1155'))));

  AssetRescuerHarness internal _rescuer;
  address internal _destination = makeAddr('destination');
  address internal _stranger = makeAddr('stranger');

  function setUp() external {
    _rescuer = new AssetRescuerHarness(_destination);
  }

  /*//////////////////////////////////////////////////////////////
                         MOCK HELPERS
  //////////////////////////////////////////////////////////////*/

  function _mockErc20BalanceOf(address _token, address _account, uint256 _balance) internal {
    vm.mockCall(_token, abi.encodeWithSelector(IERC20.balanceOf.selector, _account), abi.encode(_balance));
  }

  function _mockErc20TransferOk(address _token, address _to, uint256 _amount) internal {
    vm.mockCall(_token, abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount), abi.encode(true));
  }

  function _mockErc721TransferFrom(address _token, address _from, address _to, uint256 _tokenId) internal {
    vm.mockCall(_token, abi.encodeWithSelector(IERC721.transferFrom.selector, _from, _to, _tokenId), '');
  }

  function _mockErc1155SafeTransferFrom(
    address _token,
    address _from,
    address _to,
    uint256 _id,
    uint256 _amount
  ) internal {
    vm.mockCall(_token, abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, _from, _to, _id, _amount, ''), '');
  }

  /*//////////////////////////////////////////////////////////////
                               ETH
  //////////////////////////////////////////////////////////////*/

  function test_RescueETH_SweepsFullBalanceToDestination() external {
    uint256 _amount = 2.5 ether;
    vm.deal(address(_rescuer), _amount);
    uint256 _destBefore = _destination.balance;

    vm.prank(_stranger);
    vm.expectEmit(true, false, false, true, address(_rescuer));
    emit IAssetRescuer.AssetRescuedETH(_destination, _amount);
    _rescuer.rescue(address(0));

    assertEq(address(_rescuer).balance, 0);
    assertEq(_destination.balance, _destBefore + _amount);
  }

  function test_RescueETH_ZeroBalanceEmitsZeroAndDoesNotRevert() external {
    vm.expectEmit(true, false, false, true, address(_rescuer));
    emit IAssetRescuer.AssetRescuedETH(_destination, 0);
    _rescuer.rescue(address(0));
  }

  function test_RescueETH_RevertsWhenDestinationRejectsETH() external {
    address _badDest = makeAddr('badDestination');
    _rescuer.setDestination(_badDest);
    vm.deal(address(_rescuer), 1 ether);

    vm.mockCallRevert(_badDest, '', bytes('no thanks'));

    vm.expectRevert(IAssetRescuer.AssetRescuer_RescueFailed.selector);
    _rescuer.rescue(address(0));
  }

  function test_Rescue_RevertsOnZeroDestination() external {
    _rescuer.setDestination(address(0));
    vm.deal(address(_rescuer), 1 ether);

    vm.expectRevert(IAssetRescuer.AssetRescuer_ZeroDestination.selector);
    _rescuer.rescue(address(0));
  }

  /*//////////////////////////////////////////////////////////////
                               ERC-20
  //////////////////////////////////////////////////////////////*/

  function test_RescueERC20_SweepsFullBalanceToDestination() external {
    uint256 _amount = 1000e18;
    _mockErc20BalanceOf(_TOKEN_ERC20, address(_rescuer), _amount);
    _mockErc20TransferOk(_TOKEN_ERC20, _destination, _amount);

    vm.expectCall(_TOKEN_ERC20, abi.encodeWithSelector(IERC20.balanceOf.selector, address(_rescuer)));
    vm.expectCall(_TOKEN_ERC20, abi.encodeWithSelector(IERC20.transfer.selector, _destination, _amount));
    vm.expectEmit(true, true, false, true, address(_rescuer));
    emit IAssetRescuer.AssetRescuedERC20(_TOKEN_ERC20, _destination, _amount);
    _rescuer.rescue(_TOKEN_ERC20);
  }

  function test_RescueERC20_ZeroBalanceSucceedsEmittingZero() external {
    _mockErc20BalanceOf(_TOKEN_ERC20, address(_rescuer), 0);
    _mockErc20TransferOk(_TOKEN_ERC20, _destination, 0);

    vm.expectEmit(true, true, false, true, address(_rescuer));
    emit IAssetRescuer.AssetRescuedERC20(_TOKEN_ERC20, _destination, 0);
    _rescuer.rescue(_TOKEN_ERC20);
  }

  function test_RescueERC20_RevertsOnZeroDestination() external {
    _rescuer.setDestination(address(0));
    _mockErc20BalanceOf(_TOKEN_ERC20, address(_rescuer), 1);

    vm.expectRevert(IAssetRescuer.AssetRescuer_ZeroDestination.selector);
    _rescuer.rescue(_TOKEN_ERC20);
  }

  /*//////////////////////////////////////////////////////////////
                               ERC-721
  //////////////////////////////////////////////////////////////*/

  function test_RescueERC721_TransfersTokenToDestination() external {
    uint256 _id = 7;
    _mockErc721TransferFrom(_TOKEN_ERC721, address(_rescuer), _destination, _id);

    vm.expectCall(
      _TOKEN_ERC721, abi.encodeWithSelector(IERC721.transferFrom.selector, address(_rescuer), _destination, _id)
    );
    vm.expectEmit(true, true, false, true, address(_rescuer));
    emit IAssetRescuer.AssetRescuedERC721(_TOKEN_ERC721, _destination, _id);
    _rescuer.rescueERC721(_TOKEN_ERC721, _id);
  }

  function test_RescueERC721_RevertsOnZeroDestination() external {
    _rescuer.setDestination(address(0));

    vm.expectRevert(IAssetRescuer.AssetRescuer_ZeroDestination.selector);
    _rescuer.rescueERC721(_TOKEN_ERC721, 1);
  }

  /*//////////////////////////////////////////////////////////////
                               ERC-1155
  //////////////////////////////////////////////////////////////*/

  function test_RescueERC1155_TransfersBalanceToDestination() external {
    uint256 _id = 3;
    uint256 _amount = 10;
    _mockErc1155SafeTransferFrom(_TOKEN_ERC1155, address(_rescuer), _destination, _id, _amount);

    vm.expectCall(
      _TOKEN_ERC1155,
      abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, address(_rescuer), _destination, _id, _amount, '')
    );
    vm.expectEmit(true, true, false, true, address(_rescuer));
    emit IAssetRescuer.AssetRescuedERC1155(_TOKEN_ERC1155, _destination, _id, _amount);
    _rescuer.rescueERC1155(_TOKEN_ERC1155, _id, _amount);
  }

  function test_RescueERC1155_RevertsOnZeroDestination() external {
    _rescuer.setDestination(address(0));

    vm.expectRevert(IAssetRescuer.AssetRescuer_ZeroDestination.selector);
    _rescuer.rescueERC1155(_TOKEN_ERC1155, 1, 1);
  }

  /*//////////////////////////////////////////////////////////////
                       RECEIVE / FALLBACK
  //////////////////////////////////////////////////////////////*/

  function test_Receive_RevertsDirectETHSend() external {
    vm.deal(_stranger, 1 ether);
    vm.prank(_stranger);
    // `transfer` only forwards 2300 gas; this `receive` path needs more to return the custom error.
    (bool _ok, bytes memory _data) = payable(address(_rescuer)).call{value: 1 wei}('');
    assertFalse(_ok);
    assertEq(_data, abi.encodeWithSelector(IAssetRescuer.AssetRescuer_SendToDestinationInstead.selector, _destination));
  }

  function test_Fallback_RevertsUnknownCalldata() external {
    vm.deal(_stranger, 1 ether);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(IAssetRescuer.AssetRescuer_SendToDestinationInstead.selector, _destination));
    (bool _ok,) = address(_rescuer).call{value: 0}(hex'deadbeef');
    _ok;
  }
}
