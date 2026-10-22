// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAvatar} from '@gnosis-guild/zodiac/contracts/interfaces/IAvatar.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {TreasuryAuthority} from 'contracts/core/TreasuryAuthority.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';
import {SquadAdmin} from 'contracts/squad/SquadAdmin.sol';

import {CREW_CHANGE_DELAY, PROPOSAL_EXPIRY, SQUAD_QUORUM_BPS} from 'script/Constants.sol';

import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IMutinyModule} from 'interfaces/core/IMutinyModule.sol';
import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';
import {ITreasuryAuthority} from 'interfaces/core/ITreasuryAuthority.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';

/**
 * @title UnitGasHotPaths
 * @author Pacto
 * @notice Hermetic happy-path gas baselines for governance hot writes. Staging uses
 *         `pauseGasMetering` so `.gas-snapshot` reflects the measured call. Refresh with
 *         `pnpm snapshot:gas`; compare with `pnpm test:gas`.
 */
contract UnitGasHotPaths is Test {
  address internal constant _HATS = address(uint160(uint256(keccak256('pacto.gas.HATS'))));
  address internal constant _SAFE = address(uint160(uint256(keccak256('pacto.gas.SAFE'))));

  uint256 internal constant _CAPTAIN_HAT = 1;
  uint256 internal constant _CREW_HAT = 2;
  uint256 internal constant _MUTINY_ROLE_HAT = 3;
  uint256 internal constant _QM_ROLE_HAT = 4;
  uint256 internal constant _TA_ROLE_HAT = 5;
  uint256 internal constant _SQUAD_ADMIN_HAT = 6;

  bytes32 internal constant _ROLE_APP = keccak256('pacto.gas.role.app');

  TreasuryAuthority internal _ta;
  Quartermaster internal _qm;
  MutinyModule internal _mm;
  SquadAdmin internal _squadAdmin;
  NavePirataRegistry internal _registry;

  address internal _captain = makeAddr('gasCaptain');
  address internal _crewA = makeAddr('gasCrewA');
  address internal _crewB = makeAddr('gasCrewB');
  address internal _crewC = makeAddr('gasCrewC');
  address internal _alice = makeAddr('gasAlice');
  address internal _dest = makeAddr('gasDest');
  address internal _qmPeer = makeAddr('gasQmPeer');
  address internal _safePeer = makeAddr('gasSafePeer');
  address internal _factory = makeAddr('gasFactory');
  address internal _upgrader = makeAddr('gasUpgrader');

  function setUp() public {
    vm.etch(_HATS, hex'00');
    vm.etch(_SAFE, hex'00');
    vm.etch(_qmPeer, hex'00');

    _ta = TreasuryAuthority(payable(Clones.clone(address(new TreasuryAuthority(IHats(_HATS))))));
    _ta.initialize(
      ITreasuryAuthority.InitParams({
        safe: _SAFE,
        captainHatId: _CAPTAIN_HAT,
        crewHatId: _CREW_HAT,
        treasuryAuthorityRoleHatId: _TA_ROLE_HAT,
        proposalExpiry: PROPOSAL_EXPIRY,
        crewVoteMode: ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT,
        quorumBps: SQUAD_QUORUM_BPS
      })
    );

    _qm = Quartermaster(Clones.clone(address(new Quartermaster(IHats(_HATS)))));
    vm.mockCall(_qmPeer, abi.encodeWithSelector(IMutinyModule.activeMutinyId.selector), abi.encode(uint256(0)));
    _qm.initialize(
      IQuartermaster.InitParams({
        captainHatId: _CAPTAIN_HAT,
        crewHatId: _CREW_HAT,
        mutinyRoleHatId: _MUTINY_ROLE_HAT,
        quartermasterRoleHatId: _QM_ROLE_HAT,
        treasuryAuthorityRoleHatId: _TA_ROLE_HAT,
        mutinyModule: _qmPeer,
        crewChangeDelay: CREW_CHANGE_DELAY,
        crewOffboardExpiry: PROPOSAL_EXPIRY,
        crewOffboardQuorumBps: SQUAD_QUORUM_BPS
      })
    );

    _mm = MutinyModule(Clones.clone(address(new MutinyModule(IHats(_HATS)))));
    _mockWearer(_qmPeer, _QM_ROLE_HAT, true);
    _mm.initialize(
      IMutinyModule.InitParams({
        captainHatId: _CAPTAIN_HAT,
        crewHatId: _CREW_HAT,
        mutinyRoleHatId: _MUTINY_ROLE_HAT,
        quartermasterRoleHatId: _QM_ROLE_HAT,
        captain: _captain,
        quartermaster: _qmPeer,
        safe: _safePeer,
        treasuryAuthorityRoleHatId: _TA_ROLE_HAT,
        mutinyExpiry: PROPOSAL_EXPIRY
      })
    );

    _squadAdmin = SquadAdmin(payable(Clones.clone(address(new SquadAdmin(IHats(_HATS))))));
    _squadAdmin.initialize(ISquadAdmin.InitParams({captainHatId: _CAPTAIN_HAT, squadAdminHatId: _SQUAD_ADMIN_HAT}));
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    _squadAdmin.createRole(_ROLE_APP);

    _registry = new NavePirataRegistry();
    _registry.initialize(_factory, _upgrader);
  }

  function test_Gas_TreasuryPropose() external {
    vm.pauseGasMetering();
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_captain, _CREW_HAT, false);
    vm.mockCall(_HATS, abi.encodeWithSelector(IHats.hatSupply.selector, _CREW_HAT), abi.encode(uint64(10)));
    vm.resumeGasMetering();

    vm.prank(_captain);
    _ta.propose(_dest, 1 ether, hex'dead', ITreasuryAuthority.Operation.CALL);
  }

  function test_Gas_TreasuryExecute() external {
    vm.pauseGasMetering();
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_captain, _CREW_HAT, false);
    vm.mockCall(_HATS, abi.encodeWithSelector(IHats.hatSupply.selector, _CREW_HAT), abi.encode(uint64(3)));
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 1 ether, hex'cafe', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_crewA, _CREW_HAT, true);
    _mockWearer(_crewB, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_crewB);
    _ta.crewVote(_id, true);
    vm.prank(_captain);
    _ta.captainVote(_id, true);
    vm.mockCall(_SAFE, abi.encodeWithSelector(IAvatar.execTransactionFromModule.selector), abi.encode(true));
    vm.resumeGasMetering();

    _ta.execute(_id, hex'cafe');
  }

  function test_Gas_QuartermasterRequestAddCrew() external {
    vm.pauseGasMetering();
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_alice, _CAPTAIN_HAT, false);
    _mockWearer(_alice, _CREW_HAT, false);
    vm.mockCall(_HATS, abi.encodeWithSelector(IHats.hatSupply.selector, _CREW_HAT), abi.encode(uint32(0)));
    vm.mockCall(_HATS, abi.encodeWithSelector(IHats.getHatMaxSupply.selector, _CREW_HAT), abi.encode(uint32(10_000)));
    vm.resumeGasMetering();

    vm.prank(_captain);
    _qm.requestAddCrew(_alice);
  }

  function test_Gas_MutinyCastVote() external {
    vm.pauseGasMetering();
    uint256 _id = _stageOpenMutiny();
    vm.resumeGasMetering();

    vm.prank(_crewB);
    _mm.castVote(_id);
  }

  function test_Gas_MutinyExecute() external {
    vm.pauseGasMetering();
    address _successor = makeAddr('gasSuccessor');
    uint256 _id = _stageWinningMutinyFor(_successor, false);
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_successor, _CREW_HAT, false);
    vm.resumeGasMetering();

    _mm.executeMutiny(_id);
  }

  function test_Gas_SquadAdminEnableExecutor() external {
    vm.pauseGasMetering();
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.resumeGasMetering();

    vm.prank(_captain);
    _squadAdmin.enableExecutor(_alice, _ROLE_APP);
  }

  function test_Gas_RegistryRegisterDeployment() external {
    vm.pauseGasMetering();
    INavePirataRegistry.Deployment memory _d = INavePirataRegistry.Deployment({
      safe: makeAddr('gasSafe'),
      quartermaster: makeAddr('gasQm'),
      mutinyModule: makeAddr('gasMm'),
      treasuryAuthority: makeAddr('gasTa'),
      squadAdminProxy: makeAddr('gasSa'),
      captainHatId: 10,
      crewHatId: 11,
      squadAdminHatId: 12,
      mutinyRoleHatId: 13,
      quartermasterRoleHatId: 14,
      treasuryAuthorityRoleHatId: 15,
      deployedAt: uint64(block.timestamp),
      deployer: makeAddr('gasDeployer')
    });
    vm.resumeGasMetering();

    vm.prank(_factory);
    _registry.registerDeployment(1, _d);
  }

  function test_Gas_RegistryCrewAndCaptainHats() external {
    vm.pauseGasMetering();
    _registerGasSquad(2);
    vm.resumeGasMetering();

    _registry.crewAndCaptainHats(2);
  }

  function test_Gas_RegistryDeployment() external {
    vm.pauseGasMetering();
    _registerGasSquad(3);
    vm.resumeGasMetering();

    _registry.deployment(3);
  }

  function _registerGasSquad(uint256 _topHatId) internal {
    INavePirataRegistry.Deployment memory _d = INavePirataRegistry.Deployment({
      safe: makeAddr('gasSafe'),
      quartermaster: makeAddr('gasQm'),
      mutinyModule: makeAddr('gasMm'),
      treasuryAuthority: makeAddr('gasTa'),
      squadAdminProxy: makeAddr('gasSa'),
      captainHatId: 10,
      crewHatId: 11,
      squadAdminHatId: 12,
      mutinyRoleHatId: 13,
      quartermasterRoleHatId: 14,
      treasuryAuthorityRoleHatId: 15,
      deployedAt: uint64(block.timestamp),
      deployer: makeAddr('gasDeployer')
    });
    vm.prank(_factory);
    _registry.registerDeployment(_topHatId, _d);
  }

  function _mockWearer(address _account, uint256 _hatId, bool _isWearer) internal {
    vm.mockCall(_HATS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _account, _hatId), abi.encode(_isWearer));
  }

  function _stageOpenMutiny() internal returns (uint256 _id) {
    address _successor = makeAddr('gasOpenSuccessor');
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_crewA, _CREW_HAT, true);
    _mockWearer(_crewB, _CREW_HAT, true);
    vm.mockCall(_HATS, abi.encodeWithSelector(IHats.hatSupply.selector, _CREW_HAT), abi.encode(uint32(5)));
    vm.mockCall(_qmPeer, abi.encodeWithSelector(IQuartermaster.activeCrewOffboardId.selector), abi.encode(uint256(0)));

    vm.prank(_crewA);
    _mm.startMutinyToArbitraryEoa(_successor, false);
    _id = _mm.activeMutinyId();

    vm.prank(_crewA);
    _mm.castVote(_id);
  }

  function _stageWinningMutinyFor(address _successor, bool _seatFormer) internal returns (uint256 _id) {
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_crewA, _CREW_HAT, true);
    _mockWearer(_crewB, _CREW_HAT, true);
    _mockWearer(_crewC, _CREW_HAT, true);
    vm.mockCall(_HATS, abi.encodeWithSelector(IHats.hatSupply.selector, _CREW_HAT), abi.encode(uint32(5)));
    vm.mockCall(_qmPeer, abi.encodeWithSelector(IQuartermaster.activeCrewOffboardId.selector), abi.encode(uint256(0)));
    vm.mockCall(
      _qmPeer,
      abi.encodeWithSelector(IQuartermaster.applySuccessionCrew.selector, _captain, _successor, _seatFormer),
      abi.encode()
    );
    vm.mockCall(
      _HATS, abi.encodeWithSelector(IHats.transferHat.selector, _CAPTAIN_HAT, _captain, _successor), abi.encode()
    );

    vm.prank(_crewA);
    _mm.startMutinyToArbitraryEoa(_successor, _seatFormer);
    _id = _mm.activeMutinyId();

    vm.prank(_crewA);
    _mm.castVote(_id);
    vm.prank(_crewB);
    _mm.castVote(_id);
    vm.prank(_crewC);
    _mm.castVote(_id);
  }
}
