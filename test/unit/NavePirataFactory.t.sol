// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {NavePirataFactory} from 'contracts/NavePirataFactory.sol';
import {SquadAdminImpl} from 'contracts/SquadAdminImpl.sol';

import {CREW_CHANGE_DELAY, PROPOSAL_EXPIRY, SQUAD_QUORUM_BPS} from 'script/Constants.sol';

import {Test} from 'forge-std/Test.sol';
import {IHats} from 'hats-core/Interfaces/IHats.sol';
import {INavePirataFactory} from 'interfaces/INavePirataFactory.sol';
import {INavePirataRegistry} from 'interfaces/INavePirataRegistry.sol';
import {IRoleHatClonesFactory} from 'interfaces/IRoleHatClonesFactory.sol';
import {ITreasuryAuthority} from 'interfaces/ITreasuryAuthority.sol';
import {ISafe, ISafeProxyFactory} from 'interfaces/external/ISafeExternal.sol';

/**
 * @title UnitNavePirataFactoryBase
 * @author Pacto
 * @notice Shared fixture for `NavePirataFactory` unit tests. Every external contract (Hats,
 *         `RoleHatClonesFactory`, `NavePirataRegistry`, `SafeProxyFactory`, and deployed Safes)
 *         is stubbed with `vm.mockCall` per the project's no-mock-contract rule. The only real
 *         production code deployed is `SquadAdminImpl`, which backs the ERC-1967 proxy the
 *         factory creates on the fly (delegatecall init cannot be mocked).
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
  SquadAdminImpl internal _squadAdminImpl;

  address internal _captain = makeAddr('captain');
  address internal _caller = makeAddr('caller');
  address internal _qmMasterCopy = makeAddr('qmMasterCopy');
  address internal _mmMasterCopy = makeAddr('mmMasterCopy');
  address internal _taMasterCopy = makeAddr('taMasterCopy');

  address internal _predQm = makeAddr('predQm');
  address internal _predMm = makeAddr('predMm');
  address internal _predTa = makeAddr('predTa');
  address internal _safe = makeAddr('safe');

  function setUp() public virtual {
    vm.etch(_HATS_ADDRESS, hex'00');
    vm.etch(_SAFE_PROXY_FACTORY_ADDRESS, hex'00');
    vm.etch(_SAFE_SINGLETON, hex'00');
    vm.etch(_CLONES_ADDRESS, hex'00');
    vm.etch(_REGISTRY_ADDRESS, hex'00');
    vm.etch(_UPGRADER_ADDRESS, hex'00');
    vm.etch(_safe, hex'00');

    _squadAdminImpl = new SquadAdminImpl(IHats(_HATS_ADDRESS));

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
        IHats.createHat, (_CAPTAIN_HAT_ID, 'SquadAdmin', 1, _UPGRADER_ADDRESS, _UPGRADER_ADDRESS, false, '')
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
    bytes memory _swapOwnerCall = abi.encodeCall(ISafe.swapOwner, (address(0x1), address(_factory), _predTa));
    vm.mockCall(
      _safe,
      abi.encodeCall(
        ISafe.execTransaction, (_safe, 0, _swapOwnerCall, 0, 0, 0, 0, address(0), payable(address(0)), _buildSig())
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
            ISafe.setup, (_factorySelfOwners(), 1, address(0), '', address(0), address(0), 0, payable(address(0)))
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
        (_safe, 0, abi.encodeCall(ISafe.enableModule, (_predTa)), 0, 0, 0, 0, address(0), payable(address(0)), _sig)
      )
    );

    vm.expectCall(
      _safe,
      abi.encodeCall(
        ISafe.execTransaction,
        (
          _safe,
          0,
          abi.encodeCall(ISafe.swapOwner, (address(0x1), address(_factory), _predTa)),
          0,
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

  /// @notice Predicts the SquadAdmin proxy address the factory will deploy under `_caller` with
  ///         the default params, by advancing `vm.getNonce(factory)` to account for the exact
  ///         `new SquadAdmin(...)` create-nonce. Called before the actual deployment so we can
  ///         match against it in event assertions.
  function _expectedSquadAdminProxy() internal view returns (address _proxy) {
    _proxy = vm.computeCreateAddress(address(_factory), vm.getNonce(address(_factory)));
  }
}
