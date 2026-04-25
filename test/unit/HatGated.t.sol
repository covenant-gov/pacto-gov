// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {HatGated} from 'contracts/abstracts/HatGated.sol';
import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title HatGatedHarness
 * @author Pacto
 * @notice Concrete subclass of `HatGated` that exposes a gated external and the
 *         internal helper under test.
 */
contract HatGatedHarness is HatGated {
  /// @notice Last value written by `bump`. Used to prove the modifier admits the call.
  uint256 public flag;

  constructor(IHats hats_) HatGated(hats_) {}

  /// @notice Hat-gated no-op; increments `flag` iff `msg.sender` wears `hatId`.
  function bump(uint256 hatId) external onlyHatWearer(hatId) {
    unchecked {
      flag += 1;
    }
  }

  /// @notice Exposes `_requireHatWearer` for direct testing.
  function requireHatWearerExposed(uint256 hatId, address account) external view {
    _requireHatWearer(hatId, account);
  }

  /// @notice Exposes the immutable Hats singleton captured by the base constructor.
  function hatsExposed() external view returns (address) {
    return address(_HATS);
  }
}

contract UnitHatGated is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.hatgated.HATS'))));
  uint256 internal constant _HAT_ID = 42;

  HatGatedHarness internal _harness;
  address internal _wearer = makeAddr('wearer');
  address internal _stranger = makeAddr('stranger');

  function setUp() external {
    _harness = new HatGatedHarness(IHats(_HATS_ADDRESS));
  }

  function _mockIsWearer(address account, uint256 hatId, bool isWearer) internal {
    vm.mockCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, account, hatId), abi.encode(isWearer)
    );
  }

  function test_Constructor_StoresHats() external view {
    assertEq(_harness.hatsExposed(), _HATS_ADDRESS);
  }

  function test_OnlyHatWearer_AllowsWearer() external {
    _mockIsWearer(_wearer, _HAT_ID, true);
    vm.expectCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _wearer, _HAT_ID));
    vm.prank(_wearer);
    _harness.bump(_HAT_ID);
    assertEq(_harness.flag(), 1);
  }

  function test_OnlyHatWearer_RevertsOnNonWearer() external {
    _mockIsWearer(_stranger, _HAT_ID, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _HAT_ID, _stranger));
    _harness.bump(_HAT_ID);
    assertEq(_harness.flag(), 0);
  }

  function test_OnlyHatWearer_ChecksPerHatId() external {
    uint256 _otherHat = _HAT_ID + 1;
    _mockIsWearer(_wearer, _HAT_ID, true);
    _mockIsWearer(_wearer, _otherHat, false);

    vm.prank(_wearer);
    _harness.bump(_HAT_ID);
    assertEq(_harness.flag(), 1);

    vm.prank(_wearer);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _otherHat, _wearer));
    _harness.bump(_otherHat);
    assertEq(_harness.flag(), 1);
  }

  function test_RequireHatWearerExposed_AllowsWearer() external {
    _mockIsWearer(_wearer, _HAT_ID, true);
    _harness.requireHatWearerExposed(_HAT_ID, _wearer);
  }

  function test_RequireHatWearerExposed_RevertsOnNonWearer() external {
    _mockIsWearer(_stranger, _HAT_ID, false);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _HAT_ID, _stranger));
    _harness.requireHatWearerExposed(_HAT_ID, _stranger);
  }
}
