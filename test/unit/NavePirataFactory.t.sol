// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';
import {SquadAdmin} from 'contracts/squad/SquadAdmin.sol';
import {SquadAdminExt} from 'contracts/squad/SquadAdminExt.sol';

import {CREW_CHANGE_DELAY, PROPOSAL_EXPIRY, SQUAD_QUORUM_BPS} from 'script/Constants.sol';

import {ModuleManager} from '@safe-global/safe-contracts/contracts/base/ModuleManager.sol';
import {OwnerManager} from '@safe-global/safe-contracts/contracts/base/OwnerManager.sol';
import {Enum} from '@safe-global/safe-contracts/contracts/common/Enum.sol';
import {ISafe, ISafeProxyFactory} from 'interfaces/safe/ISafe141.sol';

import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {ITreasuryAuthority} from 'interfaces/core/ITreasuryAuthority.sol';
import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {IRoleHatClonesFactory} from 'interfaces/factory/IRoleHatClonesFactory.sol';

/**
 * @title UnitNavePirataFactoryBase
 * @author Pacto
 * @notice Shared fixture for `NavePirataFactory` unit tests. Every external contract (Hats,
 *         `RoleHatClonesFactory`, `NavePirataRegistry`, `SafeProxyFactory`, and deployed Safes)
 *         is stubbed with `vm.mockCall` per the project's no-mock-contract rule. The only real
 *         production code deployed is `SquadAdmin`, which backs the EIP-1167 clone the
 *         factory creates on the fly (`initialize` on the clone cannot be mocked meaningfully without bytecode).
 */
abstract contract UnitNavePirataFactoryBase is Test {
  address internal constant _HATS_ADDRESS = address(uint160(uint256(keccak256('pacto.factory.HATS'))));
  address internal constant _SAFE_PROXY_FACTORY_ADDRESS =
    address(uint160(uint256(keccak256('pacto.factory.SAFE_PROXY_FACTORY'))));
  address internal constant _SAFE_SINGLETON = address(uint160(uint256(keccak256('pacto.factory.SAFE_SINGLETON'))));
  address internal constant _CLONES_ADDRESS = address(uint160(uint256(keccak256('pacto.factory.CLONES'))));
  address internal constant _REGISTRY_ADDRESS = address(uint160(uint256(keccak256('pacto.factory.REGISTRY'))));
  address internal constant _UPGRADER_ADDRESS = address(uint160(uint256(keccak256('pacto.factory.UPGRADER'))));

  uint256 internal constant _TOP_HAT_ID = 0xff01;
  uint256 internal constant _MUTINY_ROLE_HAT_ID = 0xff02;
  uint256 internal constant _QUARTERMASTER_ROLE_HAT_ID = 0xff03;
  uint256 internal constant _TREASURY_AUTHORITY_ROLE_HAT_ID = 0xff04;
  uint256 internal constant _CAPTAIN_HAT_ID = 0xff05;
  uint256 internal constant _CREW_HAT_ID = 0xff06;
  uint256 internal constant _SQUAD_ADMIN_HAT_ID = 0xff07;

  NavePirataFactory internal _factory;
  SquadAdmin internal _squadAdminImpl;
  SquadAdminExt internal _squadAdminExtImpl;

  address internal _captain = makeAddr('captain');
  address internal _caller = makeAddr('caller');
  address internal _qmMasterCopy = makeAddr('qmMasterCopy');
  address internal _mmMasterCopy = makeAddr('mmMasterCopy');
  address internal _taMasterCopy = makeAddr('taMasterCopy');

  address internal _predQm = makeAddr('predQm');
  address internal _predMm = makeAddr('predMm');
  address internal _predTa = makeAddr('predTa');
  address internal _safe = makeAddr('safe');

  function setUp() public {
    vm.etch(_HATS_ADDRESS, hex'00');
    vm.etch(_SAFE_PROXY_FACTORY_ADDRESS, hex'00');
    vm.etch(_SAFE_SINGLETON, hex'00');
    vm.etch(_CLONES_ADDRESS, hex'00');
    vm.etch(_REGISTRY_ADDRESS, hex'00');
    vm.etch(_UPGRADER_ADDRESS, hex'00');
    vm.etch(_safe, hex'00');

    _squadAdminImpl = new SquadAdmin(IHats(_HATS_ADDRESS));
    _squadAdminExtImpl = new SquadAdminExt(IHats(_HATS_ADDRESS));

    _factory = new NavePirataFactory(
      _HATS_ADDRESS, _SAFE_PROXY_FACTORY_ADDRESS, _SAFE_SINGLETON, _CLONES_ADDRESS, _REGISTRY_ADDRESS, _UPGRADER_ADDRESS
    );
  }

  /*///////////////////////////////////////////////////////////////
                            MOCK HELPERS
  //////////////////////////////////////////////////////////////*/

  function _defaultDeployParams() internal view returns (INavePirataFactory.DeployParams memory) {
    return INavePirataFactory.DeployParams({
      captain: _captain,
      metadataURI: 'ipfs://squad',
      squadParams: INavePirataFactory.SquadParams({
        crewChangeDelay: CREW_CHANGE_DELAY,
        proposalExpiry: PROPOSAL_EXPIRY,
        crewVoteMode: ITreasuryAuthority.CrewVoteMode.QUORUM_OF_CAST,
        quorumBps: SQUAD_QUORUM_BPS
      }),
      quartermasterMasterCopy: _qmMasterCopy,
      mutinyMasterCopy: _mmMasterCopy,
      treasuryAuthorityMasterCopy: _taMasterCopy,
      squadAdminImplementation: address(_squadAdminImpl),
      saltNonce: 1
    });
  }

  function _mockPredict(address _master, address _result) internal {
    vm.mockCall(
      _CLONES_ADDRESS,
      abi.encodeWithSelector(IRoleHatClonesFactory.predictCloneAddress.selector, _master),
      abi.encode(_result)
    );
  }

  function _mockCreateClone(address _master, address _result) internal {
    vm.mockCall(
      _CLONES_ADDRESS, abi.encodeWithSelector(IRoleHatClonesFactory.createClone.selector, _master), abi.encode(_result)
    );
  }

  function _mockSafeDeploy(address _result) internal {
    vm.mockCall(
      _SAFE_PROXY_FACTORY_ADDRESS,
      abi.encodeWithSelector(ISafeProxyFactory.createProxyWithNonce.selector),
      abi.encode(_result)
    );
  }

  function _mockHatsDefaults() internal {
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintTopHat.selector), abi.encode(_TOP_HAT_ID));

    // Each createHat call is mocked by full-calldata match so each call returns its own hat id.
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeCall(IHats.createHat, (_TOP_HAT_ID, 'MutinyRole', 1, _UPGRADER_ADDRESS, _UPGRADER_ADDRESS, false, '')),
      abi.encode(_MUTINY_ROLE_HAT_ID)
    );
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeCall(
        IHats.createHat, (_TOP_HAT_ID, 'QuartermasterRole', 1, _UPGRADER_ADDRESS, _UPGRADER_ADDRESS, false, '')
      ),
      abi.encode(_QUARTERMASTER_ROLE_HAT_ID)
    );
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeCall(
        IHats.createHat, (_TOP_HAT_ID, 'TreasuryAuthorityRole', 1, _UPGRADER_ADDRESS, _UPGRADER_ADDRESS, false, '')
      ),
      abi.encode(_TREASURY_AUTHORITY_ROLE_HAT_ID)
    );
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeCall(IHats.createHat, (_MUTINY_ROLE_HAT_ID, 'Captain', 1, _predMm, _UPGRADER_ADDRESS, false, '')),
      abi.encode(_CAPTAIN_HAT_ID)
    );
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeCall(
        IHats.createHat, (_QUARTERMASTER_ROLE_HAT_ID, 'Crew', type(uint32).max, _predQm, _UPGRADER_ADDRESS, false, '')
      ),
      abi.encode(_CREW_HAT_ID)
    );
    vm.mockCall(
      _HATS_ADDRESS,
      abi.encodeCall(
        IHats.createHat, (_CAPTAIN_HAT_ID, 'SquadAdminProxy', 1, _UPGRADER_ADDRESS, _UPGRADER_ADDRESS, false, '')
      ),
      abi.encode(_SQUAD_ADMIN_HAT_ID)
    );

    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.mintHat.selector), abi.encode(true));
    vm.mockCall(_HATS_ADDRESS, abi.encodeWithSelector(IHats.transferHat.selector), abi.encode());
  }

  function _mockSafeExec(bool _ok) internal {
    vm.mockCall(_safe, abi.encodeWithSelector(ISafe.execTransaction.selector), abi.encode(_ok));
  }

  function _mockRegistryRegister() internal {
    vm.mockCall(
      _REGISTRY_ADDRESS, abi.encodeWithSelector(INavePirataRegistry.registerDeployment.selector), abi.encode()
    );
  }

  /// @notice Primes every external call needed for a successful `deployNavePirata` happy path.
  function _primeHappyPath() internal {
    _mockSafeDeploy(_safe);
    _mockHatsDefaults();

    _mockPredict(_qmMasterCopy, _predQm);
    _mockPredict(_mmMasterCopy, _predMm);
    _mockPredict(_taMasterCopy, _predTa);

    _mockCreateClone(_qmMasterCopy, _predQm);
    _mockCreateClone(_mmMasterCopy, _predMm);
    _mockCreateClone(_taMasterCopy, _predTa);

    _mockSafeExec(true);
    _mockRegistryRegister();
  }
}

/**
 * @title UnitNavePirataFactoryConstructor
 * @author Pacto
 * @notice Constructor validation for `NavePirataFactory`.
 */
contract UnitNavePirataFactoryConstructor is UnitNavePirataFactoryBase {
  function test_Constructor_StoresImmutables() public view {
    assertEq(_factory.HATS(), _HATS_ADDRESS, 'HATS');
    assertEq(_factory.SAFE_PROXY_FACTORY(), _SAFE_PROXY_FACTORY_ADDRESS, 'SAFE_PROXY_FACTORY');
    assertEq(_factory.SAFE_SINGLETON(), _SAFE_SINGLETON, 'SAFE_SINGLETON');
    assertEq(_factory.CLONES_FACTORY(), _CLONES_ADDRESS, 'CLONES_FACTORY');
    assertEq(_factory.REGISTRY(), _REGISTRY_ADDRESS, 'REGISTRY');
    assertEq(_factory.UPGRADER(), _UPGRADER_ADDRESS, 'UPGRADER');
  }

  function test_Constructor_RevertsIfHatsZero() public {
    vm.expectRevert(abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'hats'));
    new NavePirataFactory(
      address(0), _SAFE_PROXY_FACTORY_ADDRESS, _SAFE_SINGLETON, _CLONES_ADDRESS, _REGISTRY_ADDRESS, _UPGRADER_ADDRESS
    );
  }

  function test_Constructor_RevertsIfSafeProxyFactoryZero() public {
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'safeProxyFactory')
    );
    new NavePirataFactory(
      _HATS_ADDRESS, address(0), _SAFE_SINGLETON, _CLONES_ADDRESS, _REGISTRY_ADDRESS, _UPGRADER_ADDRESS
    );
  }

  function test_Constructor_RevertsIfSafeSingletonZero() public {
    vm.expectRevert(abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'safeSingleton'));
    new NavePirataFactory(
      _HATS_ADDRESS, _SAFE_PROXY_FACTORY_ADDRESS, address(0), _CLONES_ADDRESS, _REGISTRY_ADDRESS, _UPGRADER_ADDRESS
    );
  }

  function test_Constructor_RevertsIfClonesFactoryZero() public {
    vm.expectRevert(abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'clonesFactory'));
    new NavePirataFactory(
      _HATS_ADDRESS, _SAFE_PROXY_FACTORY_ADDRESS, _SAFE_SINGLETON, address(0), _REGISTRY_ADDRESS, _UPGRADER_ADDRESS
    );
  }

  function test_Constructor_RevertsIfRegistryZero() public {
    vm.expectRevert(abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'registry'));
    new NavePirataFactory(
      _HATS_ADDRESS, _SAFE_PROXY_FACTORY_ADDRESS, _SAFE_SINGLETON, _CLONES_ADDRESS, address(0), _UPGRADER_ADDRESS
    );
  }

  function test_Constructor_RevertsIfUpgraderZero() public {
    vm.expectRevert(abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'upgrader'));
    new NavePirataFactory(
      _HATS_ADDRESS, _SAFE_PROXY_FACTORY_ADDRESS, _SAFE_SINGLETON, _CLONES_ADDRESS, _REGISTRY_ADDRESS, address(0)
    );
  }
}

/**
 * @title UnitNavePirataFactoryDeployValidation
 * @author Pacto
 * @notice Parameter validation on `deployNavePirata`.
 */
contract UnitNavePirataFactoryDeployValidation is UnitNavePirataFactoryBase {
  function test_Deploy_RevertsIfCaptainZero() public {
    INavePirataFactory.DeployParams memory _params = _defaultDeployParams();
    _params.captain = address(0);
    vm.prank(_caller);
    vm.expectRevert(abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'captain'));
    _factory.deployNavePirata(_params);
  }

  function test_Deploy_RevertsIfQuartermasterMasterCopyZero() public {
    INavePirataFactory.DeployParams memory _params = _defaultDeployParams();
    _params.quartermasterMasterCopy = address(0);
    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'quartermasterMasterCopy')
    );
    _factory.deployNavePirata(_params);
  }

  function test_Deploy_RevertsIfMutinyMasterCopyZero() public {
    INavePirataFactory.DeployParams memory _params = _defaultDeployParams();
    _params.mutinyMasterCopy = address(0);
    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'mutinyMasterCopy')
    );
    _factory.deployNavePirata(_params);
  }

  function test_Deploy_RevertsIfTreasuryAuthorityMasterCopyZero() public {
    INavePirataFactory.DeployParams memory _params = _defaultDeployParams();
    _params.treasuryAuthorityMasterCopy = address(0);
    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'treasuryAuthorityMasterCopy')
    );
    _factory.deployNavePirata(_params);
  }

  function test_Deploy_RevertsIfSquadAdminImplementationZero() public {
    INavePirataFactory.DeployParams memory _params = _defaultDeployParams();
    _params.squadAdminImplementation = address(0);
    vm.prank(_caller);
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'squadAdminImplementation')
    );
    _factory.deployNavePirata(_params);
  }
}

/**
 * @title UnitNavePirataFactoryDeployFailureModes
 * @author Pacto
 * @notice Reverts from the ceremony itself — Safe deploy, Safe bootstrap, etc.
 */
contract UnitNavePirataFactoryDeployFailureModes is UnitNavePirataFactoryBase {
  function test_Deploy_RevertsIfSafeDeployReturnsZero() public {
    _mockSafeDeploy(address(0));
    vm.prank(_caller);
    vm.expectRevert(INavePirataFactory.NavePirataFactory_SafeDeployFailed.selector);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  function test_Deploy_RevertsIfSafeDeployThrows() public {
    vm.mockCallRevert(
      _SAFE_PROXY_FACTORY_ADDRESS,
      abi.encodeWithSelector(ISafeProxyFactory.createProxyWithNonce.selector),
      bytes('safe-boom')
    );
    vm.prank(_caller);
    vm.expectRevert(INavePirataFactory.NavePirataFactory_SafeDeployFailed.selector);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  function test_Deploy_RevertsIfSafeEnableModuleReturnsFalse() public {
    _primeHappyPath();
    _mockSafeExec(false);

    vm.prank(_caller);
    vm.expectRevert(INavePirataFactory.NavePirataFactory_BootstrapTeardownFailed.selector);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  function test_Deploy_RevertsIfSafeSwapOwnerReturnsFalse() public {
    _primeHappyPath();

    // Make enableModule succeed but swapOwner fail via argument-specific mock.
    bytes memory _swapOwnerCall = abi.encodeCall(OwnerManager.swapOwner, (address(0x1), address(_factory), _predTa));
    vm.mockCall(
      _safe,
      abi.encodeCall(
        ISafe.execTransaction,
        (_safe, 0, _swapOwnerCall, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), _buildSig())
      ),
      abi.encode(false)
    );

    vm.prank(_caller);
    vm.expectRevert(INavePirataFactory.NavePirataFactory_BootstrapTeardownFailed.selector);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  function _buildSig() internal view returns (bytes memory) {
    return abi.encodePacked(bytes32(uint256(uint160(address(_factory)))), bytes32(uint256(0)), uint8(1));
  }
}

/**
 * @title UnitNavePirataFactoryDeployHappyPath
 * @author Pacto
 * @notice Happy-path: verifies returned addresses, event, and that every external side-effect fires.
 */
contract UnitNavePirataFactoryDeployHappyPath is UnitNavePirataFactoryBase {
  function test_Deploy_ReturnsAddressesAndEmitsEvent() public {
    _primeHappyPath();

    vm.expectEmit(true, true, false, true, address(_factory));
    emit INavePirataFactory.NavePirataDeployed(
      _TOP_HAT_ID, _captain, _safe, _predQm, _predMm, _predTa, _expectedSquadAdminProxy()
    );

    vm.prank(_caller);
    (
      uint256 _topHatId,
      address _safeOut,
      address _quartermaster,
      address _mutinyModule,
      address _treasuryAuthority,
      address _squadAdminProxy
    ) = _factory.deployNavePirata(_defaultDeployParams());

    assertEq(_topHatId, _TOP_HAT_ID, 'topHatId');
    assertEq(_safeOut, _safe, 'safe');
    assertEq(_quartermaster, _predQm, 'quartermaster');
    assertEq(_mutinyModule, _predMm, 'mutinyModule');
    assertEq(_treasuryAuthority, _predTa, 'treasuryAuthority');
    assertTrue(_squadAdminProxy.code.length > 0, 'squadAdminProxy has code');
  }

  function test_Deploy_CallsSafeProxyFactoryWithNamespacedNonce() public {
    _primeHappyPath();

    uint256 _expectedNonce = uint256(keccak256(abi.encode(_caller, uint256(1))));

    vm.expectCall(
      _SAFE_PROXY_FACTORY_ADDRESS,
      abi.encodeCall(
        ISafeProxyFactory.createProxyWithNonce,
        (
          _SAFE_SINGLETON,
          abi.encodeCall(
            ISafe.setup,
            (_factorySelfOwners(), 1, address(0), new bytes(0), address(0), address(0), 0, payable(address(0)))
          ),
          _expectedNonce
        )
      )
    );

    vm.prank(_caller);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  function test_Deploy_EnablesModuleThenSwapsOwner() public {
    _primeHappyPath();

    bytes memory _sig = abi.encodePacked(bytes32(uint256(uint160(address(_factory)))), bytes32(uint256(0)), uint8(1));

    vm.expectCall(
      _safe,
      abi.encodeCall(
        ISafe.execTransaction,
        (
          _safe,
          0,
          abi.encodeCall(ModuleManager.enableModule, (_predTa)),
          Enum.Operation.Call,
          0,
          0,
          0,
          address(0),
          payable(address(0)),
          _sig
        )
      )
    );

    vm.expectCall(
      _safe,
      abi.encodeCall(
        ISafe.execTransaction,
        (
          _safe,
          0,
          abi.encodeCall(OwnerManager.swapOwner, (address(0x1), address(_factory), _predTa)),
          Enum.Operation.Call,
          0,
          0,
          0,
          address(0),
          payable(address(0)),
          _sig
        )
      )
    );

    vm.prank(_caller);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  function test_Deploy_TransfersTopHatToSafe() public {
    _primeHappyPath();

    vm.expectCall(_HATS_ADDRESS, abi.encodeCall(IHats.transferHat, (_TOP_HAT_ID, address(_factory), _safe)));

    vm.prank(_caller);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  function test_Deploy_RegistersDeployment() public {
    _primeHappyPath();

    INavePirataRegistry.Deployment memory _expected = INavePirataRegistry.Deployment({
      safe: _safe,
      quartermaster: _predQm,
      mutinyModule: _predMm,
      treasuryAuthority: _predTa,
      squadAdminProxy: _expectedSquadAdminProxy(),
      topHatId: _TOP_HAT_ID,
      captainHatId: _CAPTAIN_HAT_ID,
      crewHatId: _CREW_HAT_ID,
      squadAdminHatId: _SQUAD_ADMIN_HAT_ID,
      mutinyRoleHatId: _MUTINY_ROLE_HAT_ID,
      quartermasterRoleHatId: _QUARTERMASTER_ROLE_HAT_ID,
      treasuryAuthorityRoleHatId: _TREASURY_AUTHORITY_ROLE_HAT_ID,
      deployedAt: uint64(block.timestamp),
      deployer: _caller
    });

    vm.expectCall(_REGISTRY_ADDRESS, abi.encodeCall(INavePirataRegistry.registerDeployment, (_expected)));

    vm.prank(_caller);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  function test_Deploy_MintsEveryRoleHat() public {
    _primeHappyPath();

    vm.expectCall(_HATS_ADDRESS, abi.encodeCall(IHats.mintHat, (_MUTINY_ROLE_HAT_ID, _predMm)));
    vm.expectCall(_HATS_ADDRESS, abi.encodeCall(IHats.mintHat, (_QUARTERMASTER_ROLE_HAT_ID, _predQm)));
    vm.expectCall(_HATS_ADDRESS, abi.encodeCall(IHats.mintHat, (_TREASURY_AUTHORITY_ROLE_HAT_ID, _predTa)));
    vm.expectCall(_HATS_ADDRESS, abi.encodeCall(IHats.mintHat, (_CAPTAIN_HAT_ID, _captain)));

    vm.prank(_caller);
    _factory.deployNavePirata(_defaultDeployParams());
  }

  /*///////////////////////////////////////////////////////////////
                            HELPERS
  //////////////////////////////////////////////////////////////*/

  function _factorySelfOwners() internal view returns (address[] memory _owners) {
    _owners = new address[](1);
    _owners[0] = address(_factory);
  }

  /// @notice Predicts the squad-admin clone: next factory `CREATE` (`Clones.clone` uses one nonce step).
  function _expectedSquadAdminProxy() internal view returns (address _proxy) {
    _proxy = vm.computeCreateAddress(address(_factory), vm.getNonce(address(_factory)));
  }
}

contract UnitNavePirataFactoryStandaloneSquadAdmin is UnitNavePirataFactoryBase {
  address internal _standaloneOwner = makeAddr('standaloneOwner');

  function test_DeploySquadAdminExtStandalone_InitializesOwner() external {
    address _clone = _factory.deploySquadAdminExtStandalone(address(_squadAdminExtImpl), _standaloneOwner);
    assertEq(SquadAdminExt(_clone).owner(), _standaloneOwner);
  }

  function test_DeploySquadAdminExtStandalone_OwnerCanEnableExecutor() external {
    bytes32 _role = keccak256('pacto.factory.standalone.role');
    address _alice = makeAddr('standaloneAlice');
    address _clone = _factory.deploySquadAdminExtStandalone(address(_squadAdminExtImpl), _standaloneOwner);
    vm.startPrank(_standaloneOwner);
    SquadAdminExt(_clone).createRole(_role);
    SquadAdminExt(_clone).enableExecutor(_alice, _role);
    vm.stopPrank();
    assertTrue(SquadAdminExt(_clone).hasExecutorRole(_alice, _role));
  }

  function test_DeploySquadAdminExtStandalone_RevertsZeroImplementation() external {
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'squadAdminExtImplementation')
    );
    _factory.deploySquadAdminExtStandalone(address(0), _standaloneOwner);
  }

  function test_DeploySquadAdminExtStandalone_RevertsZeroOwner() external {
    vm.expectRevert(abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'owner'));
    _factory.deploySquadAdminExtStandalone(address(_squadAdminExtImpl), address(0));
  }

  function test_DeploySquadAdminExtStandalone_Emits() external {
    address _expectedClone = vm.computeCreateAddress(address(_factory), vm.getNonce(address(_factory)));
    vm.expectEmit(true, true, true, true, address(_factory));
    emit INavePirataFactory.SquadAdminExtStandaloneDeployed(
      _expectedClone, _standaloneOwner, address(_squadAdminExtImpl)
    );
    _factory.deploySquadAdminExtStandalone(address(_squadAdminExtImpl), _standaloneOwner);
  }

  function test_DeploySquadAdminStandaloneCaptainHat_SetsCaptainHat() external {
    uint256 _hat = 4242;
    address _clone = _factory.deploySquadAdminStandaloneCaptainHat(address(_squadAdminImpl), _hat);
    assertEq(SquadAdmin(_clone).captainHatId(), _hat);
    assertEq(SquadAdmin(_clone).squadAdminHatId(), 0);
  }

  function test_DeploySquadAdminStandaloneCaptainHat_CaptainCanEnableExecutor() external {
    uint256 _hat = 999;
    address _standaloneCaptain = makeAddr('standaloneCaptain');
    address _alice = makeAddr('standaloneAliceB');
    bytes32 _role = keccak256('pacto.factory.standalone.role2');
    vm.mockCall(
      _HATS_ADDRESS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, _standaloneCaptain, _hat), abi.encode(true)
    );
    address _clone = _factory.deploySquadAdminStandaloneCaptainHat(address(_squadAdminImpl), _hat);
    vm.startPrank(_standaloneCaptain);
    SquadAdmin(_clone).createRole(_role);
    SquadAdmin(_clone).enableExecutor(_alice, _role);
    vm.stopPrank();
    assertTrue(SquadAdmin(_clone).hasExecutorRole(_alice, _role));
  }

  function test_DeploySquadAdminStandaloneCaptainHat_RevertsZeroImplementation() external {
    vm.expectRevert(
      abi.encodeWithSelector(INavePirataFactory.NavePirataFactory_ZeroAddress.selector, 'squadAdminImplementation')
    );
    _factory.deploySquadAdminStandaloneCaptainHat(address(0), 1);
  }

  function test_DeploySquadAdminStandaloneCaptainHat_RevertsZeroCaptainHatId() external {
    vm.expectRevert(INavePirataFactory.NavePirataFactory_InvalidCaptainHat.selector);
    _factory.deploySquadAdminStandaloneCaptainHat(address(_squadAdminImpl), 0);
  }

  function test_DeploySquadAdminStandaloneCaptainHat_Emits() external {
    uint256 _hat = 777;
    address _expectedClone = vm.computeCreateAddress(address(_factory), vm.getNonce(address(_factory)));
    vm.expectEmit(true, true, true, true, address(_factory));
    emit INavePirataFactory.SquadAdminStandaloneDeployed(_expectedClone, address(_squadAdminImpl), _hat);
    _factory.deploySquadAdminStandaloneCaptainHat(address(_squadAdminImpl), _hat);
  }
}
