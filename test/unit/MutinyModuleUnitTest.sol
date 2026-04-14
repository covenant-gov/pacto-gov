// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MutinyModule} from 'contracts/MutinyModule.sol';
import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';

/**
 * @title MutinyModuleUnitTest
 * @author Pacto
 * @notice Shared setup and `vm.mockCall` helpers for MutinyModule tests (no mock Hats or Quartermaster contracts).
 */
contract MutinyModuleUnitTest is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.mutiny.HATS'))));
  address internal constant _QM_ADDRESS = address(uint160(uint256(keccak256('pacto.mutiny.QUARTERMASTER'))));

  uint256 internal constant _CREW_HAT = 1;
  uint256 internal constant _CAPTAIN_HAT = 2;

  MutinyModule internal _mutiny;
  address internal _captain0 = makeAddr('captain0');
  address internal _crew1 = makeAddr('crew1');
  address internal _crew2 = makeAddr('crew2');
  address internal _crew3 = makeAddr('crew3');
  address internal _successor = makeAddr('successor');

  function setUp() public virtual {
    _mutiny = new MutinyModule(IQuartermaster(_QM_ADDRESS), IHats(_HATS_ADDRESS), _CAPTAIN_HAT, _CREW_HAT, _captain0);
  }

  function _mockBalanceOf(address _wearer, uint256 _hatId, uint256 _balance) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.balanceOf.selector, _wearer, _hatId), abi.encode(_balance));
  }

  function _mockHatSupply(uint256 _hatId, uint32 _supply) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.hatSupply.selector, _hatId), abi.encode(_supply));
  }

  function _mockTransferHat(uint256 _hatId, address _from, address _to) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector, _hatId, _from, _to), '');
  }

  function _mockQmSetMutinyActive(bool _active) internal {
    vm.mockCall(_QM_ADDRESS, abi.encodeWithSelector(IQuartermaster.setMutinyActive.selector, _active), '');
  }

  function _mockQmMintCrewFromMutiny(address _to) internal {
    vm.mockCall(_QM_ADDRESS, abi.encodeWithSelector(IQuartermaster.mintCrewFromMutiny.selector, _to), '');
  }

  function _mockQmCrewHandoffForMutiny(address _former, address _newCaptain) internal {
    vm.mockCall(
      _QM_ADDRESS, abi.encodeWithSelector(IQuartermaster.crewHandoffForMutiny.selector, _former, _newCaptain), ''
    );
  }

  /// @notice Mocks for `startMutiny`: crew starter, supply > 0, successor valid (not captain, no captain hat).
  function _mockStartMutinyHappyPath(address _starter, address _proposed, uint32 _crewSupply) internal {
    _mockBalanceOf(_proposed, _CAPTAIN_HAT, 0);
    _mockBalanceOf(_starter, _CREW_HAT, 1);
    _mockHatSupply(_CREW_HAT, _crewSupply);
    _mockQmSetMutinyActive(true);
  }

  /// @notice Open round id 1 with supply 4; cast 3 yea from _crew1,_crew2,_crew3; ready for execute after execute mocks.
  function _startOpenMutinyWithThreeYeas(address _proposed) internal {
    _mockStartMutinyHappyPath(_crew1, _proposed, 4);
    vm.prank(_crew1);
    _mutiny.startMutiny(_proposed);

    _mockBalanceOf(_crew1, _CREW_HAT, 1);
    _mockBalanceOf(_crew2, _CREW_HAT, 1);
    _mockBalanceOf(_crew3, _CREW_HAT, 1);
    vm.prank(_crew1);
    _mutiny.castVote(1, true);
    vm.prank(_crew2);
    _mutiny.castVote(1, true);
    vm.prank(_crew3);
    _mutiny.castVote(1, true);
  }
}
