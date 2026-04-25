// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Quartermaster} from 'contracts/Quartermaster.sol';
import {RoleHatClonesFactory} from 'contracts/RoleHatClonesFactory.sol';

import {CREW_CHANGE_DELAY} from 'script/Constants.sol';

import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IQuartermaster} from 'interfaces/IQuartermaster.sol';
import {IRoleHatClonesFactory} from 'interfaces/IRoleHatClonesFactory.sol';

/**
 * @title UnitRoleHatClonesFactoryBase
 * @author Pacto
 * @notice Shared fixture for `RoleHatClonesFactory` unit tests. A real `Quartermaster` is used
 *         as the master copy so the init-call path exercises real initializer semantics (no
 *         mock helper contracts — see `.cursor/rules/solidity-unit-tests.mdc`).
 */
abstract contract UnitRoleHatClonesFactoryBase is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.clonesfactory.HATS'))));

  RoleHatClonesFactory internal _factory;
  Quartermaster internal _master;

  address internal _deployer = makeAddr('deployer');

  function setUp() public virtual {
    vm.etch(_HATS_ADDRESS, hex'00');
    _factory = new RoleHatClonesFactory();
    _master = new Quartermaster(IHats(_HATS_ADDRESS));
  }

  function _defaultQmInit() internal pure returns (bytes memory _data) {
    IQuartermaster.InitParams memory _p = IQuartermaster.InitParams({
      captainHatId: 1,
      crewHatId: 2,
      mutinyRoleHatId: 3,
      quartermasterRoleHatId: 4,
      treasuryAuthorityRoleHatId: 5,
      crewChangeDelay: CREW_CHANGE_DELAY
    });
    _data = abi.encodeCall(Quartermaster.initialize, (_p));
  }
}

contract UnitRoleHatClonesFactoryCreate is UnitRoleHatClonesFactoryBase {
  function test_CreateClone_HappyPath_InitializesAndEmits() external {
    bytes32 _salt = keccak256('squad-1');
    bytes memory _init = _defaultQmInit();

    address _predicted = _factory.predictCloneAddress(address(_master), _salt);

    vm.expectEmit(true, true, true, true, address(_factory));
    emit IRoleHatClonesFactory.CloneCreated(address(_master), _predicted, _salt, _deployer);

    vm.prank(_deployer);
    address _clone = _factory.createClone(address(_master), _init, _salt);

    assertEq(_clone, _predicted);
    assertEq(Quartermaster(_clone).captainHatId(), 1);
    assertEq(Quartermaster(_clone).crewHatId(), 2);
    assertEq(Quartermaster(_clone).crewChangeDelay(), CREW_CHANGE_DELAY);
  }

  function test_CreateClone_AcceptsEmptyInitData() external {
    bytes32 _salt = keccak256('no-init');
    address _clone = _factory.createClone(address(_master), '', _salt);

    assertEq(_clone, _factory.predictCloneAddress(address(_master), _salt));
    assertEq(Quartermaster(_clone).captainHatId(), 0);
  }

  function test_CreateClone_RevertsOnZeroMasterCopy() external {
    vm.expectRevert(IRoleHatClonesFactory.RoleHatClonesFactory_ZeroMasterCopy.selector);
    _factory.createClone(address(0), _defaultQmInit(), bytes32(0));
  }

  function test_CreateClone_RevertsIfInitializerReverts() external {
    // Init data targets a selector Quartermaster does not expose; dispatch reverts on the clone.
    bytes memory _badInit = abi.encodeWithSignature('nonExistent(uint256)', 42);
    bytes32 _salt = keccak256('bad-init');
    vm.expectRevert(IRoleHatClonesFactory.RoleHatClonesFactory_InitializationFailed.selector);
    _factory.createClone(address(_master), _badInit, _salt);
  }

  function test_CreateClone_RevertsOnSaltCollision() external {
    bytes32 _salt = keccak256('collide');
    _factory.createClone(address(_master), _defaultQmInit(), _salt);

    vm.expectRevert();
    _factory.createClone(address(_master), _defaultQmInit(), _salt);
  }

  function test_PredictCloneAddress_MatchesCreate2() external {
    bytes32 _salt = keccak256('predict');
    address _predicted = _factory.predictCloneAddress(address(_master), _salt);
    address _clone = _factory.createClone(address(_master), _defaultQmInit(), _salt);
    assertEq(_clone, _predicted);
  }

  function test_PredictCloneAddress_ChangesWithSalt() external view {
    address _a = _factory.predictCloneAddress(address(_master), bytes32(uint256(1)));
    address _b = _factory.predictCloneAddress(address(_master), bytes32(uint256(2)));
    assertTrue(_a != _b);
  }
}
