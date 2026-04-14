// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Quartermaster} from 'contracts/Quartermaster.sol';
import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title QuartermasterUnitTest
 * @author Pacto
 * @notice Shared setup and `vm.mockCall` helpers for Quartermaster tests (no mock Hats contract).
 * @dev Pattern aligned with [delegated-security-manager/test/unit](https://github.com/covenant-gov/delegated-security-manager/tree/main/test/unit): fixed Hats address, encode exact calldata.
 */
contract QuartermasterUnitTest is Test {
  /// @dev Placeholder Hats address; calls are satisfied via `vm.mockCall`, not a deployed mock.
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.quartermaster.HATS'))));

  uint256 internal constant _CREW_HAT = 1;
  uint256 internal constant _CAPTAIN_HAT = 2;
  uint256 internal constant _DELAY = 100;
  uint32 internal constant _CREW_MAX = 10_000;

  Quartermaster internal _qm;
  address internal _captain = makeAddr('captain');
  address internal _mutiny = makeAddr('mutiny');
  address internal _crew = makeAddr('crew');
  address internal _candidate = makeAddr('candidate');

  function setUp() public virtual {
    _qm = new Quartermaster(_HATS_ADDRESS, _CREW_HAT, _CAPTAIN_HAT, _DELAY, _mutiny);
  }

  function _mockBalanceOf(address _wearer, uint256 _hatId, uint256 _balance) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.balanceOf.selector, _wearer, _hatId), abi.encode(_balance));
  }

  function _mockHatSupply(uint256 _hatId, uint32 _supply) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.hatSupply.selector, _hatId), abi.encode(_supply));
  }

  function _mockHatMaxSupply(uint256 _hatId, uint32 _max) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.getHatMaxSupply.selector, _hatId), abi.encode(_max));
  }

  function _mockMintHat(uint256 _hatId, address _wearer) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector, _hatId, _wearer), abi.encode(true));
  }

  function _mockTransferHat(uint256 _hatId, address _from, address _to) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _hatId, _from, _to), '');
  }

  function _mockSetHatWearerStatus(uint256 _hatId, address _wearer, bool _eligible, bool _standing) internal {
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeWithSelector(IHats.setHatWearerStatus.selector, _hatId, _wearer, _eligible, _standing),
      abi.encode(true)
    );
  }

  /// @notice Mocks Hats reads for a valid non-captain crew candidate (no crew hat, not captain).
  function _mockValidCrewCandidate(address _who) internal {
    _mockBalanceOf(_who, _CAPTAIN_HAT, 0);
    _mockBalanceOf(_who, _CREW_HAT, 0);
  }

  /// @notice Mocks captain checks for `msg.sender == _who`.
  function _mockIsCaptain(address _who) internal {
    _mockBalanceOf(_who, _CAPTAIN_HAT, 1);
  }

  /// @notice Mints path: supply below cap, `mintHat` succeeds for this wearer.
  function _mockMintCrewOk(address _wearer, uint32 _supply) internal {
    _mockHatSupply(_CREW_HAT, _supply);
    _mockHatMaxSupply(_CREW_HAT, _CREW_MAX);
    _mockMintHat(_CREW_HAT, _wearer);
  }
}
