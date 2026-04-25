// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAvatar} from '@gnosis-guild/zodiac/contracts/interfaces/IAvatar.sol';
import {Enum} from '@gnosis.pm/safe-contracts/contracts/common/Enum.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import {TreasuryAuthority} from 'contracts/TreasuryAuthority.sol';
import {GovernanceParams} from 'contracts/abstracts/GovernanceParams.sol';
import {HatGated} from 'contracts/abstracts/HatGated.sol';

import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {IAssetRescuer} from 'interfaces/IAssetRescuer.sol';
import {ITreasuryAuthority} from 'interfaces/ITreasuryAuthority.sol';

/**
 * @title UnitTreasuryAuthorityBase
 * @author Pacto
 * @notice Shared fixture for TreasuryAuthority unit tests. Deploys a master copy, clones it,
 *         and initializes the clone directly. All external contract calls (Hats, Safe avatar)
 *         are stubbed with `vm.mockCall`.
 */
abstract contract UnitTreasuryAuthorityBase is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.treasury.HATS'))));
  address internal constant _SAFE_ADDRESS = address(uint160(uint256(keccak256('pacto.treasury.SAFE'))));

  uint256 internal constant _CAPTAIN_HAT = 1;
  uint256 internal constant _CREW_HAT = 2;
  uint256 internal constant _TREASURY_AUTHORITY_ROLE_HAT = 3;

  uint256 internal constant _DEFAULT_EXPIRY = 7 days;
  uint256 internal constant _DEFAULT_QUORUM_BPS = 3000;

  TreasuryAuthority internal _master;
  TreasuryAuthority internal _ta;

  address internal _captain = makeAddr('captain');
  address internal _crewA = makeAddr('crewA');
  address internal _crewB = makeAddr('crewB');
  address internal _crewC = makeAddr('crewC');
  address internal _crewD = makeAddr('crewD');
  address internal _stranger = makeAddr('stranger');
  address internal _dest = makeAddr('callTarget');

  function setUp() public virtual {
    vm.etch(_HATS_ADDRESS, hex'00');
    vm.etch(_SAFE_ADDRESS, hex'00');
    _master = new TreasuryAuthority(IHats(_HATS_ADDRESS));
    _ta = TreasuryAuthority(payable(Clones.clone(address(_master))));
    _initDefault(ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT);
  }

  function _initDefault(ITreasuryAuthority.CrewVoteMode _mode) internal {
    TreasuryAuthority.InitParams memory _p = TreasuryAuthority.InitParams({
      safe: _SAFE_ADDRESS,
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT,
      proposalExpiry: _DEFAULT_EXPIRY,
      crewVoteMode: _mode,
      quorumBps: _DEFAULT_QUORUM_BPS
    });
    _ta.initialize(_p);
  }

  function _mockWearer(address _account, uint256 _hatId, bool _isWearer) internal {
    vm.mockCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _account, _hatId), abi.encode(_isWearer)
    );
  }

  function _mockCrewSupply(uint64 _supply) internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.hatSupply.selector, _CREW_HAT), abi.encode(_supply));
  }

  function _mockSafeExec(bool _ok) internal {
    vm.mockCall(_SAFE_ADDRESS, abi.encodeWithSelector(IAvatar.execTransactionFromModule.selector), abi.encode(_ok));
  }

  /// @notice Gate-check setup so `_who` passes `_requireCaptainOrCrew`.
  function _mockCaptainOrCrew(address _who, bool _isCaptain, bool _isCrew) internal {
    _mockWearer(_who, _CAPTAIN_HAT, _isCaptain);
    _mockWearer(_who, _CREW_HAT, _isCrew);
  }

  function _mockTaRole(address _who, bool _isWearer) internal {
    _mockWearer(_who, _TREASURY_AUTHORITY_ROLE_HAT, _isWearer);
  }

  /// @notice Convenience: captain creates a proposal with `_data` targeting `_dest`.
  function _propose(address _proposer, bool _isCaptain) internal returns (uint256 _id) {
    _mockCaptainOrCrew(_proposer, _isCaptain, !_isCaptain);
    _mockCrewSupply(10);
    vm.prank(_proposer);
    _id = _ta.propose(_dest, 1 ether, hex'dead', ITreasuryAuthority.Operation.CALL);
  }
}

/*///////////////////////////////////////////////////////////////
                    INITIALIZATION
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthorityInit is UnitTreasuryAuthorityBase {
  function test_Constructor_DisablesInitializersOnMaster() external {
    TreasuryAuthority.InitParams memory _p = TreasuryAuthority.InitParams({
      safe: _SAFE_ADDRESS,
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT,
      proposalExpiry: _DEFAULT_EXPIRY,
      crewVoteMode: ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT,
      quorumBps: _DEFAULT_QUORUM_BPS
    });
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _master.initialize(_p);
  }

  function test_Initialize_SetsStateAndWiresSafe() external view {
    assertEq(_ta.CAPTAIN_HAT_ID(), _CAPTAIN_HAT);
    assertEq(_ta.CREW_HAT_ID(), _CREW_HAT);
    assertEq(_ta.TREASURY_AUTHORITY_ROLE_HAT_ID(), _TREASURY_AUTHORITY_ROLE_HAT);
    assertEq(_ta.proposalExpiry(), _DEFAULT_EXPIRY);
    assertEq(uint256(_ta.crewVoteMode()), uint256(ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT));
    assertEq(_ta.quorumBps(), _DEFAULT_QUORUM_BPS);
    assertEq(_ta.SAFE(), _SAFE_ADDRESS);
    assertEq(_ta.avatar(), _SAFE_ADDRESS);
    assertEq(_ta.target(), _SAFE_ADDRESS);
    assertEq(_ta.owner(), address(0));
  }

  function test_Initialize_RevertsIfAlreadyInitialized() external {
    TreasuryAuthority.InitParams memory _p = TreasuryAuthority.InitParams({
      safe: _SAFE_ADDRESS,
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT,
      proposalExpiry: _DEFAULT_EXPIRY,
      crewVoteMode: ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT,
      quorumBps: _DEFAULT_QUORUM_BPS
    });
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    _ta.initialize(_p);
  }

  function test_Initialize_RevertsOnZeroSafe() external {
    TreasuryAuthority _fresh = TreasuryAuthority(payable(Clones.clone(address(_master))));
    TreasuryAuthority.InitParams memory _p = TreasuryAuthority.InitParams({
      safe: address(0),
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT,
      proposalExpiry: _DEFAULT_EXPIRY,
      crewVoteMode: ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT,
      quorumBps: _DEFAULT_QUORUM_BPS
    });
    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_NotCaptainOrCrew.selector, address(0)));
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsOnOutOfBoundsDelay() external {
    TreasuryAuthority _fresh = TreasuryAuthority(payable(Clones.clone(address(_master))));
    TreasuryAuthority.InitParams memory _p = TreasuryAuthority.InitParams({
      safe: _SAFE_ADDRESS,
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT,
      proposalExpiry: 30 seconds,
      crewVoteMode: ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT,
      quorumBps: _DEFAULT_QUORUM_BPS
    });
    vm.expectRevert(
      abi.encodeWithSelector(
        GovernanceParams.GovernanceParams_DelayOutOfRange.selector,
        uint256(30 seconds),
        uint256(1 minutes),
        uint256(60 days)
      )
    );
    _fresh.initialize(_p);
  }

  function test_Initialize_RevertsOnOutOfBoundsQuorumBps() external {
    TreasuryAuthority _fresh = TreasuryAuthority(payable(Clones.clone(address(_master))));
    TreasuryAuthority.InitParams memory _p = TreasuryAuthority.InitParams({
      safe: _SAFE_ADDRESS,
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT,
      proposalExpiry: _DEFAULT_EXPIRY,
      crewVoteMode: ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT,
      quorumBps: 100
    });
    vm.expectRevert(
      abi.encodeWithSelector(
        GovernanceParams.GovernanceParams_QuorumOutOfRange.selector, uint256(100), uint256(500), uint256(10_000)
      )
    );
    _fresh.initialize(_p);
  }

  function test_SetUp_ZodiacShimAppliesInitialization() external {
    TreasuryAuthority _fresh = TreasuryAuthority(payable(Clones.clone(address(_master))));
    TreasuryAuthority.InitParams memory _p = TreasuryAuthority.InitParams({
      safe: _SAFE_ADDRESS,
      captainHatId: _CAPTAIN_HAT,
      crewHatId: _CREW_HAT,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT,
      proposalExpiry: _DEFAULT_EXPIRY,
      crewVoteMode: ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST,
      quorumBps: _DEFAULT_QUORUM_BPS
    });
    _fresh.setUp(abi.encode(_p));
    assertEq(_fresh.SAFE(), _SAFE_ADDRESS);
    assertEq(uint256(_fresh.crewVoteMode()), uint256(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST));
    assertEq(_fresh.owner(), address(0));
  }
}

/*///////////////////////////////////////////////////////////////
                    PROPOSE
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthorityPropose is UnitTreasuryAuthorityBase {
  function test_Propose_ByCaptain_HappyPath_RecordsState() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(10);

    uint64 _expectedDeadline = uint64(block.timestamp + _DEFAULT_EXPIRY);

    vm.expectEmit();
    emit ITreasuryAuthority.ProposalCreated(
      1, _captain, _dest, 1 ether, ITreasuryAuthority.Operation.CALL, hex'dead', _expectedDeadline, 10
    );

    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 1 ether, hex'dead', ITreasuryAuthority.Operation.CALL);

    assertEq(_id, 1);
    assertEq(_ta.openProposalOf(_captain), 1);

    (
      address _proposer,
      address _to,
      uint256 _value,
      ITreasuryAuthority.Operation _op,
      bytes memory _data,
      uint64 _deadline,
      uint64 _snap,
      uint64 _yeas,
      uint64 _nays,
      bool _capApproved,
      bool _exec
    ) = _ta.proposal(1);
    assertEq(_proposer, _captain);
    assertEq(_to, _dest);
    assertEq(_value, 1 ether);
    assertEq(uint256(_op), uint256(ITreasuryAuthority.Operation.CALL));
    assertEq(_data, hex'dead');
    assertEq(_deadline, _expectedDeadline);
    assertEq(_snap, 10);
    assertEq(_yeas, 0);
    assertEq(_nays, 0);
    assertFalse(_capApproved);
    assertFalse(_exec);
  }

  function test_Propose_ByCrew_HappyPath() external {
    _mockCaptainOrCrew(_crewA, false, true);
    _mockCrewSupply(5);
    vm.prank(_crewA);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);
    assertEq(_id, 1);
    assertEq(_ta.openProposalOf(_crewA), 1);
  }

  function test_Propose_RevertsIfNeitherCaptainNorCrew() external {
    _mockCaptainOrCrew(_stranger, false, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_NotCaptainOrCrew.selector, _stranger));
    _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);
  }

  function test_Propose_OneOpenPerProposer() external {
    _propose(_captain, true);
    vm.prank(_captain);
    vm.expectRevert(
      abi.encodeWithSelector(
        ITreasuryAuthority.TreasuryAuthority_ProposerHasOpenProposal.selector, _captain, uint256(1)
      )
    );
    _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);
  }

  function test_Propose_ReusesSlot_AfterPriorExpired() external {
    uint256 _first = _propose(_captain, true);
    vm.warp(block.timestamp + _DEFAULT_EXPIRY + 1);

    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(10);
    vm.prank(_captain);
    uint256 _second = _ta.propose(_dest, 2, hex'beef', ITreasuryAuthority.Operation.CALL);
    assertEq(_first, 1);
    assertEq(_second, 2);
    assertEq(_ta.openProposalOf(_captain), 2);
  }
}

/*///////////////////////////////////////////////////////////////
                    CREW VOTE
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthorityCrewVote is UnitTreasuryAuthorityBase {
  function test_CrewVote_YeaIncrementsYeas() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_crewA, _CREW_HAT, true);

    vm.expectEmit();
    emit ITreasuryAuthority.CrewVoted(_id, _crewA, true);

    vm.prank(_crewA);
    _ta.crewVote(_id, true);

    (,,,,,,, uint64 _yeas, uint64 _nays,,) = _ta.proposal(_id);
    assertEq(_yeas, 1);
    assertEq(_nays, 0);
    assertTrue(_ta.hasVoted(_id, _crewA));
  }

  function test_CrewVote_NayIncrementsNays() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_crewA, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, false);
    (,,,,,,, uint64 _yeas, uint64 _nays,,) = _ta.proposal(_id);
    assertEq(_yeas, 0);
    assertEq(_nays, 1);
  }

  function test_CrewVote_RevertsIfNotCrew() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_stranger, _CREW_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CREW_HAT, _stranger));
    _ta.crewVote(_id, true);
  }

  function test_CrewVote_RevertsIfAlreadyVoted() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_crewA, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_crewA);
    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_AlreadyVoted.selector, _crewA));
    _ta.crewVote(_id, true);
  }

  function test_CrewVote_RevertsIfExpired() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_crewA, _CREW_HAT, true);
    vm.warp(block.timestamp + _DEFAULT_EXPIRY + 1);
    vm.prank(_crewA);
    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalExpired.selector, _id));
    _ta.crewVote(_id, true);
  }

  function test_CrewVote_RevertsIfNonExistent() external {
    _mockWearer(_crewA, _CREW_HAT, true);
    vm.prank(_crewA);
    vm.expectRevert(
      abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalDoesNotExist.selector, uint256(42))
    );
    _ta.crewVote(42, true);
  }
}

/*///////////////////////////////////////////////////////////////
                    CAPTAIN APPROVE
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthorityCaptainApprove is UnitTreasuryAuthorityBase {
  function test_CaptainApprove_HappyPath() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_captain, _CAPTAIN_HAT, true);

    vm.expectEmit();
    emit ITreasuryAuthority.CaptainApproved(_id, _captain);

    vm.prank(_captain);
    _ta.captainApprove(_id);

    (,,,,,,,,, bool _approved,) = _ta.proposal(_id);
    assertTrue(_approved);
  }

  function test_CaptainApprove_RevertsIfNotCaptain() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_stranger, _CAPTAIN_HAT, false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _CAPTAIN_HAT, _stranger));
    _ta.captainApprove(_id);
  }

  function test_CaptainApprove_RevertsOnDoubleApproval() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);
    vm.prank(_captain);
    vm.expectRevert(ITreasuryAuthority.TreasuryAuthority_CaptainAlreadyApproved.selector);
    _ta.captainApprove(_id);
  }

  function test_CaptainApprove_RevertsIfExpired() external {
    uint256 _id = _propose(_captain, true);
    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.warp(block.timestamp + _DEFAULT_EXPIRY + 1);
    vm.prank(_captain);
    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalExpired.selector, _id));
    _ta.captainApprove(_id);
  }
}

/*///////////////////////////////////////////////////////////////
                    EXECUTE — MAJORITY_SNAPSHOT MODE
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthorityExecuteMajority is UnitTreasuryAuthorityBase {
  function test_Execute_HappyPath_ForwardsToSafeAndClearsOpenSlot() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(3);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 1 ether, hex'cafe', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_crewA, _CREW_HAT, true);
    _mockWearer(_crewB, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_crewB);
    _ta.crewVote(_id, true);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);

    _mockSafeExec(true);
    vm.expectCall(
      _SAFE_ADDRESS,
      abi.encodeWithSelector(IAvatar.execTransactionFromModule.selector, _dest, 1 ether, hex'cafe', Enum.Operation.Call)
    );
    vm.expectEmit();
    emit ITreasuryAuthority.ProposalExecuted(_id, true);

    _ta.execute(_id);

    (,,,,,,,,,, bool _exec) = _ta.proposal(_id);
    assertTrue(_exec);
    assertEq(_ta.openProposalOf(_captain), 0);
  }

  function test_Execute_Delegatecall_ForwardsOperation() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(1);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'01', ITreasuryAuthority.Operation.DELEGATECALL);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_crewA, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);

    _mockSafeExec(true);
    vm.expectCall(
      _SAFE_ADDRESS,
      abi.encodeWithSelector(
        IAvatar.execTransactionFromModule.selector, _dest, uint256(0), hex'01', Enum.Operation.DelegateCall
      )
    );
    _ta.execute(_id);
  }

  function test_Execute_RevertsIfCrewVoteBelowMajority() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(4);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_crewA, _CREW_HAT, true);
    _mockWearer(_crewB, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_crewB);
    _ta.crewVote(_id, true);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);

    vm.expectRevert(ITreasuryAuthority.TreasuryAuthority_CrewVoteNotPassed.selector);
    _ta.execute(_id);
  }

  function test_Execute_RevertsIfCaptainNotApproved() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(1);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_crewA, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);

    vm.expectRevert(ITreasuryAuthority.TreasuryAuthority_CaptainNotApproved.selector);
    _ta.execute(_id);
  }

  function test_Execute_RevertsIfSafeExecutionFails() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(1);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_crewA, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);

    _mockSafeExec(false);
    vm.expectRevert(ITreasuryAuthority.TreasuryAuthority_SafeExecutionFailed.selector);
    _ta.execute(_id);
  }

  function test_Execute_RevertsOnDoubleExecute() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(1);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    _mockWearer(_crewA, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);

    _mockSafeExec(true);
    _ta.execute(_id);
    vm.expectRevert(ITreasuryAuthority.TreasuryAuthority_AlreadyExecuted.selector);
    _ta.execute(_id);
  }

  function test_Execute_RevertsIfExpired() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(1);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);
    vm.warp(block.timestamp + _DEFAULT_EXPIRY + 1);
    vm.expectRevert(abi.encodeWithSelector(ITreasuryAuthority.TreasuryAuthority_ProposalExpired.selector, _id));
    _ta.execute(_id);
  }
}

/*///////////////////////////////////////////////////////////////
                    EXECUTE — QUORUM_OF_CAST MODE
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthorityExecuteQuorum is UnitTreasuryAuthorityBase {
  function setUp() public override {
    super.setUp();
    // Re-init a fresh clone in QUORUM_OF_CAST mode.
    _ta = TreasuryAuthority(payable(Clones.clone(address(_master))));
    _initDefault(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST);
  }

  function test_Execute_Passes_WhenQuorumMetAndYeasBeatNays() external {
    // snapshot = 10, quorum = 30% = 3 cast votes, yeas must > nays
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(10);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_crewA, _CREW_HAT, true);
    _mockWearer(_crewB, _CREW_HAT, true);
    _mockWearer(_crewC, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_crewB);
    _ta.crewVote(_id, true);
    vm.prank(_crewC);
    _ta.crewVote(_id, false);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);

    _mockSafeExec(true);
    _ta.execute(_id);

    (,,,,,,,,,, bool _exec) = _ta.proposal(_id);
    assertTrue(_exec);
  }

  function test_Execute_Fails_WhenQuorumNotMet() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(10);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_crewA, _CREW_HAT, true);
    _mockWearer(_crewB, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_crewB);
    _ta.crewVote(_id, true);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);

    vm.expectRevert(ITreasuryAuthority.TreasuryAuthority_CrewVoteNotPassed.selector);
    _ta.execute(_id);
  }

  function test_Execute_Fails_WhenYeasNotGreaterThanNays() external {
    _mockCaptainOrCrew(_captain, true, false);
    _mockCrewSupply(10);
    vm.prank(_captain);
    uint256 _id = _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);

    _mockWearer(_crewA, _CREW_HAT, true);
    _mockWearer(_crewB, _CREW_HAT, true);
    _mockWearer(_crewC, _CREW_HAT, true);
    _mockWearer(_crewD, _CREW_HAT, true);
    vm.prank(_crewA);
    _ta.crewVote(_id, true);
    vm.prank(_crewB);
    _ta.crewVote(_id, true);
    vm.prank(_crewC);
    _ta.crewVote(_id, false);
    vm.prank(_crewD);
    _ta.crewVote(_id, false);

    _mockWearer(_captain, _CAPTAIN_HAT, true);
    vm.prank(_captain);
    _ta.captainApprove(_id);

    vm.expectRevert(ITreasuryAuthority.TreasuryAuthority_CrewVoteNotPassed.selector);
    _ta.execute(_id);
  }
}

/*///////////////////////////////////////////////////////////////
                    PARAMETER SETTERS
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthoritySetters is UnitTreasuryAuthorityBase {
  function test_SetProposalExpiry_HappyPath() external {
    _mockTaRole(address(this), true);
    vm.expectEmit();
    emit ITreasuryAuthority.ProposalExpiryUpdated(_DEFAULT_EXPIRY, 30 days);
    _ta.setProposalExpiry(30 days);
    assertEq(_ta.proposalExpiry(), 30 days);
  }

  function test_SetProposalExpiry_RevertsIfNotRoleHolder() external {
    _mockTaRole(address(this), false);
    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _TREASURY_AUTHORITY_ROLE_HAT, address(this))
    );
    _ta.setProposalExpiry(30 days);
  }

  function test_SetProposalExpiry_RevertsIfOutOfRange() external {
    _mockTaRole(address(this), true);
    vm.expectRevert(
      abi.encodeWithSelector(
        GovernanceParams.GovernanceParams_DelayOutOfRange.selector,
        uint256(30 seconds),
        uint256(1 minutes),
        uint256(60 days)
      )
    );
    _ta.setProposalExpiry(30 seconds);
  }

  function test_SetCrewVoteMode_HappyPath() external {
    _mockTaRole(address(this), true);
    vm.expectEmit();
    emit ITreasuryAuthority.CrewVoteModeUpdated(
      ITreasuryAuthority.CrewVoteMode.MAJORITY_SNAPSHOT, ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST
    );
    _ta.setCrewVoteMode(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST);
    assertEq(uint256(_ta.crewVoteMode()), uint256(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST));
  }

  function test_SetCrewVoteMode_RevertsIfNotRoleHolder() external {
    _mockTaRole(address(this), false);
    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _TREASURY_AUTHORITY_ROLE_HAT, address(this))
    );
    _ta.setCrewVoteMode(ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST);
  }

  function test_SetQuorumBps_HappyPath() external {
    _mockTaRole(address(this), true);
    vm.expectEmit();
    emit ITreasuryAuthority.QuorumBpsUpdated(_DEFAULT_QUORUM_BPS, 5000);
    _ta.setQuorumBps(5000);
    assertEq(_ta.quorumBps(), 5000);
  }

  function test_SetQuorumBps_RevertsIfNotRoleHolder() external {
    _mockTaRole(address(this), false);
    vm.expectRevert(
      abi.encodeWithSelector(HatGated.HatGated_NotHatWearer.selector, _TREASURY_AUTHORITY_ROLE_HAT, address(this))
    );
    _ta.setQuorumBps(5000);
  }

  function test_SetQuorumBps_RevertsIfOutOfRange() external {
    _mockTaRole(address(this), true);
    vm.expectRevert(
      abi.encodeWithSelector(
        GovernanceParams.GovernanceParams_QuorumOutOfRange.selector, uint256(100), uint256(500), uint256(10_000)
      )
    );
    _ta.setQuorumBps(100);
  }
}

/*///////////////////////////////////////////////////////////////
                    QUIET-WINDOW
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthorityQuiet is UnitTreasuryAuthorityBase {
  function test_IsQuiet_TrueOnFreshClone() external view {
    assertTrue(_ta.isQuiet());
  }

  function test_IsQuiet_FalseWhileOpenProposalAlive() external {
    _propose(_captain, true);
    assertFalse(_ta.isQuiet());
  }

  function test_IsQuiet_TrueAfterAllProposalsExpired() external {
    _propose(_captain, true);
    vm.warp(block.timestamp + _DEFAULT_EXPIRY);
    assertTrue(_ta.isQuiet());
  }

  function test_IsQuiet_FalseAgainAfterNewProposal() external {
    _propose(_captain, true);
    vm.warp(block.timestamp + _DEFAULT_EXPIRY);
    assertTrue(_ta.isQuiet());

    // Crew member creates another proposal
    _mockCaptainOrCrew(_crewA, false, true);
    _mockCrewSupply(5);
    vm.prank(_crewA);
    _ta.propose(_dest, 0, hex'', ITreasuryAuthority.Operation.CALL);
    assertFalse(_ta.isQuiet());
  }
}

/*///////////////////////////////////////////////////////////////
                    ASSET RESCUER INTEGRATION
//////////////////////////////////////////////////////////////*/

contract UnitTreasuryAuthorityRescue is UnitTreasuryAuthorityBase {
  function test_Receive_RevertsWithDestination() external {
    vm.deal(_stranger, 1 ether);
    vm.prank(_stranger);
    (bool _ok, bytes memory _data) = address(_ta).call{value: 1 ether}('');
    assertFalse(_ok);
    assertEq(_data, abi.encodeWithSelector(IAssetRescuer.AssetRescuer_SendToDestinationInstead.selector, _SAFE_ADDRESS));
  }

  function test_RescueETH_SweepsToSafe() external {
    vm.deal(address(_ta), 3 ether);

    vm.expectEmit();
    emit IAssetRescuer.AssetRescuedETH(_SAFE_ADDRESS, 3 ether);

    _ta.rescue(address(0));

    assertEq(address(_ta).balance, 0);
    assertEq(_SAFE_ADDRESS.balance, 3 ether);
  }

  function test_RescueERC20_SweepsToSafe() external {
    address _token = makeAddr('erc20');
    vm.etch(_token, hex'00');
    vm.mockCall(_token, abi.encodeWithSelector(IERC20.balanceOf.selector, address(_ta)), abi.encode(uint256(7 ether)));
    vm.mockCall(
      _token, abi.encodeWithSelector(IERC20.transfer.selector, _SAFE_ADDRESS, uint256(7 ether)), abi.encode(true)
    );
    vm.expectCall(_token, abi.encodeWithSelector(IERC20.transfer.selector, _SAFE_ADDRESS, uint256(7 ether)));
    vm.expectEmit();
    emit IAssetRescuer.AssetRescuedERC20(_token, _SAFE_ADDRESS, 7 ether);
    _ta.rescue(_token);
  }

  function test_RescueERC721_SweepsToSafe() external {
    address _token = makeAddr('erc721');
    vm.etch(_token, hex'00');
    vm.mockCall(
      _token,
      abi.encodeWithSelector(IERC721.transferFrom.selector, address(_ta), _SAFE_ADDRESS, uint256(42)),
      abi.encode()
    );
    vm.expectCall(
      _token, abi.encodeWithSelector(IERC721.transferFrom.selector, address(_ta), _SAFE_ADDRESS, uint256(42))
    );
    vm.expectEmit();
    emit IAssetRescuer.AssetRescuedERC721(_token, _SAFE_ADDRESS, 42);
    _ta.rescueERC721(_token, 42);
  }

  function test_RescueERC1155_SweepsToSafe() external {
    address _token = makeAddr('erc1155');
    vm.etch(_token, hex'00');
    vm.mockCall(
      _token,
      abi.encodeWithSelector(
        IERC1155.safeTransferFrom.selector, address(_ta), _SAFE_ADDRESS, uint256(1), uint256(3), bytes('')
      ),
      abi.encode()
    );
    vm.expectCall(
      _token,
      abi.encodeWithSelector(
        IERC1155.safeTransferFrom.selector, address(_ta), _SAFE_ADDRESS, uint256(1), uint256(3), bytes('')
      )
    );
    vm.expectEmit();
    emit IAssetRescuer.AssetRescuedERC1155(_token, _SAFE_ADDRESS, 1, 3);
    _ta.rescueERC1155(_token, 1, 3);
  }
}
