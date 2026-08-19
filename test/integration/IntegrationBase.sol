// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {TreasuryAuthority} from 'contracts/core/TreasuryAuthority.sol';
import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';
import {SquadAdmin} from 'contracts/squad/SquadAdmin.sol';
import {SquadAdminExt} from 'contracts/squad/SquadAdminExt.sol';

import {IQuartermaster} from 'interfaces/core/IQuartermaster.sol';
import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {ISquadAdmin} from 'interfaces/squad/ISquadAdmin.sol';

import {
  DEFAULT_MAINNET_FORK_BLOCK,
  DEPLOY_NAV_PIRATA_SALT_NONCE,
  HATS_PROTOCOL_V1,
  SAFE_SINGLETON_141
} from 'script/Constants.sol';
import {DeployTypes} from 'script/DeployTypes.sol';
import {PactoDeploy} from 'script/PactoDeploy.sol';

import {ERC1155} from '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import {IERC1155Receiver} from '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';

import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';

import {StdStorage, stdStorage} from 'forge-std/StdStorage.sol';
import {Test} from 'forge-std/Test.sol';

/**
 * @title IntegrationBase
 * @author Pacto
 * @notice Runs the same deploy routine as `script/Deploy.sol` during `setUp`.
 * @dev Requires an Ethereum mainnet fork: `forge test --fork-url …`, env `MAINNET_RPC`, or `foundry.toml` `rpc_endpoints.mainnet`.
 *      Pin matches `DEFAULT_MAINNET_FORK_BLOCK` in `Constants.sol`. Use `_fund()`, `_freshSquadSalt()` in subclasses.
 *      Squad helpers (`withDeployedNavePirataSquad`, `_ensureSquad`) run on that fork via `deployNavePirata`.
 *      Subclasses may use `_stdstoreOzErc20Balance` / `_stdstoreOzErc1155Balance` to credit vanilla OZ getters where `stdstore` can staticcall the target.
 *      `_mockSquadSafeErc1155Receive` stubs IERC1155 acceptance on the forked Safe when its runtime return data is incomplete.
 *      Squad-admin: `_squadSquadAdmin` / `_squadSquadAdminHatId` after `_ensureSquad`; use `_newSquadAdminClone`, `_baselineSquadAdminInit`,
 *      `_newSquadAdminExtClone`, `_deployStandaloneSquadAdminExt`, `_deployStandaloneSquadAdminCaptainHat` for forked init scenarios.
 *      Override `_loadExternalAddresses` only if you deliberately target different chain infra.
 */
abstract contract IntegrationBase is PactoDeploy, Test {
  using stdStorage for StdStorage;

  error IntegrationBase_NoMainnetFork();

  bool internal _integrationForkActive;

  Quartermaster internal _squadQuartermaster;
  MutinyModule internal _squadMutiny;
  TreasuryAuthority internal _squadTreasury;
  SquadAdmin internal _squadSquadAdmin;
  address internal _squadSafe;
  uint256 internal _squadTopHatId;
  uint256 internal _squadCrewHatId;
  uint256 internal _squadSquadAdminHatId;
  address internal _squadCaptain;
  address internal _squadProposedCaptain;
  address[] internal _squadCrew;

  bool internal _fixtureHasSquad;

  modifier withDeployedNavePirataSquad() {
    _ensureSquad();
    _;
  }

  function setUp() public {
    _requireEthereumMainnetFork();
    DeployTypes.ExternalAddresses memory _ext = _loadExternalAddresses();
    _deployFullSystem(_ext, address(this));
    _ensureSafeSingletonBytecodeAfterFork();
  }

  /// @dev Resolves `{hats,safe singleton,factory}` for `block.chainid`; override only for forks with different infra.
  function _loadExternalAddresses() internal view returns (DeployTypes.ExternalAddresses memory) {
    return _externalAddressesForCurrentChain();
  }

  /// @dev Selects Forge CLI fork (`HATS` already has code) or `vm.createSelectFork` + `_integrationForkActive`; otherwise reverts.
  function _requireEthereumMainnetFork() internal {
    if (HATS_PROTOCOL_V1.code.length > 0) {
      _integrationForkActive = true;
      return;
    }
    string memory _rpc = vm.envOr('MAINNET_RPC', string(''));
    if (bytes(_rpc).length == 0) {
      try vm.rpcUrl('mainnet') returns (string memory _fromToml) {
        _rpc = _fromToml;
      } catch {}
    }
    if (bytes(_rpc).length == 0) revert IntegrationBase_NoMainnetFork();
    vm.createSelectFork(_rpc, DEFAULT_MAINNET_FORK_BLOCK);
    _integrationForkActive = true;
  }

  /// @dev Re-rolls the fork to `DEFAULT_MAINNET_FORK_BLOCK` when the pinned Safe singleton has no bytecode.
  function _ensureSafeSingletonBytecodeAfterFork() internal {
    if (SAFE_SINGLETON_141.code.length > 0) return;
    vm.rollFork(DEFAULT_MAINNET_FORK_BLOCK);
  }

  /// @dev Sets native balance for EOAs/contracts that submit fork transactions.
  function _fund(address _who, uint256 _wei) internal {
    vm.deal(_who, _wei);
  }

  /// @dev `saltNonce` for `deployNavePirata`; override after multiple squads from the same test contract.
  function _freshSquadSalt() internal pure returns (uint256 _saltNonce) {
    _saltNonce = DEPLOY_NAV_PIRATA_SALT_NONCE;
  }

  /// @dev Fresh `SquadAdmin` minimal proxy for init / revert scenarios (mirrors `_newTaClone` pattern in E2E suites).
  function _newSquadAdminClone() internal returns (SquadAdmin _fresh) {
    SquadAdmin _impl = SquadAdmin(payable(_masters.squadAdminImpl));
    _fresh = SquadAdmin(payable(Clones.clone(address(_impl))));
  }

  /// @dev Fresh `SquadAdminExt` minimal proxy for owner-bootstrap / `postInitialize` scenarios.
  function _newSquadAdminExtClone() internal returns (SquadAdminExt _fresh) {
    SquadAdminExt _impl = SquadAdminExt(payable(_masters.squadAdminExtImpl));
    _fresh = SquadAdminExt(payable(Clones.clone(address(_impl))));
  }

  /// @dev `InitParams` aligned with the deployed Nave Pirata squad-admin clone (requires `_ensureSquad` first).
  function _baselineSquadAdminInit() internal view returns (ISquadAdmin.InitParams memory _p) {
    _p = ISquadAdmin.InitParams({
      captainHatId: _squadSquadAdmin.captainHatId(), squadAdminHatId: _squadSquadAdmin.squadAdminHatId()
    });
  }

  /// @dev Permissionless factory path; caller should `_fund(_owner, …)` if the owner must send txs.
  function _deployStandaloneSquadAdminExt(address _owner) internal returns (SquadAdminExt _clone) {
    _clone = SquadAdminExt(
      payable(NavePirataFactory(_infra.navePirataFactory)
          .deploySquadAdminExtStandalone(_masters.squadAdminExtImpl, _owner))
    );
  }

  /// @dev Permissionless factory path for `SquadAdmin` with captain hat id only (no squad-admin hat id until `postInitialize`).
  function _deployStandaloneSquadAdminCaptainHat(uint256 _captainHatId) internal returns (SquadAdmin _clone) {
    _clone = SquadAdmin(
      payable(NavePirataFactory(_infra.navePirataFactory)
          .deploySquadAdminStandaloneCaptainHat(_masters.squadAdminImpl, _captainHatId))
    );
  }

  /// @dev Idempotent squad bootstrap shared by forked E2E suites; exposes `_squad*` storage including `TreasuryAuthority`.
  function _ensureSquad() internal {
    if (_fixtureHasSquad) return;

    _squadCaptain = makeAddr('integrationSquadCaptain');
    _squadProposedCaptain = makeAddr('integrationProposedCaptain');
    _fund(_squadCaptain, 50 ether);
    _fund(_squadProposedCaptain, 1 ether);

    _squadCrew.push(makeAddr('integrationCrew0'));
    _squadCrew.push(makeAddr('integrationCrew1'));
    _squadCrew.push(makeAddr('integrationCrew2'));
    _squadCrew.push(makeAddr('integrationCrew3'));
    _squadCrew.push(makeAddr('integrationCrew4'));
    for (uint256 _i = 0; _i < _squadCrew.length; _i++) {
      _fund(_squadCrew[_i], 50 ether);
    }

    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: _squadCaptain,
      metadataURI: 'ipfs://integration-nave-pirata-squad',
      squadParams: _squadParamsProduction(),
      quartermasterMasterCopy: _masters.quartermaster,
      mutinyMasterCopy: _masters.mutinyModule,
      treasuryAuthorityMasterCopy: _masters.treasuryAuthority,
      squadAdminImplementation: _masters.squadAdminImpl,
      saltNonce: _freshSquadSalt(),
      stackKind: INavePirataFactory.StackKind.Production,
      squadId: bytes32(0)
    });

    _fund(address(this), 200 ether);
    (uint256 _topHat,, address _qm, address _mm, address _ta, address _sa) =
      NavePirataFactory(_infra.navePirataFactory).deployNavePirata(_p);

    _squadTopHatId = _topHat;
    _squadQuartermaster = Quartermaster(_qm);
    _squadMutiny = MutinyModule(_mm);
    _squadTreasury = TreasuryAuthority(payable(_ta));
    _squadSquadAdmin = SquadAdmin(payable(_sa));

    INavePirataRegistry.Deployment memory _d = NavePirataRegistry(_infra.registry).deployment(_topHat);
    _squadSafe = _d.safe;
    _squadCrewHatId = _d.crewHatId;
    _squadSquadAdminHatId = _d.squadAdminHatId;

    uint256 _n = _squadCrew.length;
    address[] memory _crewBatch = new address[](_n);
    for (uint256 _c = 0; _c < _n; _c++) {
      _crewBatch[_c] = _squadCrew[_c];
    }
    vm.prank(_squadCaptain);
    IQuartermaster(address(_squadQuartermaster)).bootstrapCrew(_crewBatch);

    vm.startPrank(_squadCaptain);
    _squadSquadAdmin.createRole(keccak256('pacto.e2e.squadadmin.role.app'));
    _squadSquadAdmin.createRole(keccak256('pacto.e2e.squadadmin.role.other'));
    vm.stopPrank();

    _fixtureHasSquad = true;
  }

  /// @dev OpenZeppelin `balanceOf` getters; `ERC721.ownerOf` reverts when unset so it is not used here.
  function _stdstoreOzErc20Balance(address token, address holder, uint256 amount) internal {
    stdstore.target(token).sig('balanceOf(address)').with_key(holder).checked_write(amount);
  }

  function _stdstoreOzErc1155Balance(address token, address holder, uint256 id, uint256 amount) internal {
    stdstore.target(token).sig('balanceOf(address,uint256)').with_key(holder).with_key(id).checked_write(amount);
  }

  /// @dev IERC1155 inbound check on `_squadSafe` for the rescue path (operator and `from` are `treasuryAuthority`).
  function _mockSquadSafeErc1155Receive(address treasuryAuthority, uint256 id, uint256 amount) internal {
    vm.mockCall(
      _squadSafe,
      abi.encodeCall(IERC1155Receiver.onERC1155Received, (treasuryAuthority, treasuryAuthority, id, amount, bytes(''))),
      abi.encode(IERC1155Receiver.onERC1155Received.selector)
    );
  }
}

/// @dev E2E test contracts for asset rescues; OZ `_mint` to `TreasuryAuthority` invokes `onERC1155Received` (rejected here).
contract E2ERescueERC20 is ERC20 {
  constructor() ERC20('E2ERescue20', 'E2R20') {}
}

/// @dev E2E test contracts for asset rescues; OZ `_mint` to `TreasuryAuthority` invokes `onERC1155Received` (rejected here).
contract E2ERescueERC721 is ERC721 {
  constructor() ERC721('E2ERescue721', 'E2R721') {}

  /// @dev OZ `ownerOf` reverts for unset ids, so forge `stdstore` cannot seed ownership through that getter.
  function mint(address to, uint256 tokenId) external {
    _mint(to, tokenId);
  }
}

/// @dev OZ `_mint` to `TreasuryAuthority` invokes `onERC1155Received` (rejected here). Crediting balances via `_stdstoreOzErc1155Balance`.
contract E2ERescueERC1155 is ERC1155 {
  constructor() ERC1155('') {}
}
