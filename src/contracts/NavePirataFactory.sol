// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MutinyModule} from 'contracts/MutinyModule.sol';
import {Quartermaster} from 'contracts/Quartermaster.sol';
import {SquadAdmin} from 'contracts/SquadAdmin.sol';
import {SquadAdminImpl} from 'contracts/SquadAdminImpl.sol';
import {TreasuryAuthority} from 'contracts/TreasuryAuthority.sol';

import {INavePirataFactory} from 'interfaces/INavePirataFactory.sol';
import {INavePirataRegistry} from 'interfaces/INavePirataRegistry.sol';
import {IRoleHatClonesFactory} from 'interfaces/IRoleHatClonesFactory.sol';
import {ISafe, ISafeProxyFactory} from 'interfaces/external/ISafeExternal.sol';

import {IHats} from 'hats-core/Interfaces/IHats.sol';

/**
 * @title NavePirataFactory
 * @author Pacto
 * @notice Full-squad deploy in one tx: Safe, hat tree, role clones, SquadAdmin, TA wiring, registry (see `INavePirataFactory`)
 * @dev 1/1 Safe owner = factory, then pre-validated `exec` to enable TA + `swapOwner` to TA. Role clone salts = `(msg.sender, saltNonce, kind)`. Placeholder
 *      role-hat eligibility/toggle → upgrader (Hats default active+eligible). `SquadParams` ≠ `GovernanceParams` base
 */
contract NavePirataFactory is INavePirataFactory {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Internal bundle of every hat id produced by `_createHatTree`, threaded through the
   *         subsequent clone-init and mint calls. Exists only to keep `deployNavePirata`
   *         under the stack-depth limit and to make cross-helper dataflow explicit.
   * @param topHatId Squad tophat id (initially worn by the factory, transferred to the Safe
   *        at the end of the ceremony).
   * @param mutinyRoleHatId MutinyRole hat id (worn by the MutinyModule clone).
   * @param quartermasterRoleHatId QuartermasterRole hat id (worn by the Quartermaster clone).
   * @param treasuryAuthorityRoleHatId TreasuryAuthorityRole hat id (worn by the TreasuryAuthority clone).
   * @param captainHatId Captain hat id (worn by `DeployParams.captain`).
   * @param crewHatId Crew hat id (empty at bootstrap; filled by Quartermaster onboarding).
   * @param squadAdminHatId Squad-admin hat id (worn by the SquadAdmin UUPS proxy).
   */
  struct _HatTree {
    uint256 topHatId;
    uint256 mutinyRoleHatId;
    uint256 quartermasterRoleHatId;
    uint256 treasuryAuthorityRoleHatId;
    uint256 captainHatId;
    uint256 crewHatId;
    uint256 squadAdminHatId;
  }

  /*///////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Crew-hat max supply; `type(uint32).max` gives squads an effectively uncapped roster.
  uint32 internal constant _MAX_CREW_SUPPLY = type(uint32).max;
  /// @notice Linked-list sentinel used by Safe's owner list (Safe's `SENTINEL_OWNERS`).
  address internal constant _SENTINEL_OWNERS = address(0x1);
  /// @notice Safe `Enum.Operation.Call` selector (0 = Call, 1 = DelegateCall).
  uint8 internal constant _OP_CALL = 0;
  /// @notice Quartermaster clone-kind tag (ASCII `"QM"` left-padded), mixed into the CREATE2 salt.
  bytes32 internal constant _KIND_QM = 0x514d000000000000000000000000000000000000000000000000000000000000;
  /// @notice MutinyModule clone-kind tag (ASCII `"MM"` left-padded).
  bytes32 internal constant _KIND_MM = 0x4d4d000000000000000000000000000000000000000000000000000000000000;
  /// @notice TreasuryAuthority clone-kind tag (ASCII `"TA"` left-padded).
  bytes32 internal constant _KIND_TA = 0x5441000000000000000000000000000000000000000000000000000000000000;

  /*///////////////////////////////////////////////////////////////
                            IMMUTABLES
  //////////////////////////////////////////////////////////////*/

  /// @notice Hats Protocol singleton.
  IHats internal immutable _HATS;
  /// @notice Safe proxy factory singleton used to deploy per-squad Safes.
  ISafeProxyFactory internal immutable _SAFE_PROXY_FACTORY;
  /// @notice Safe singleton backing every deployed Safe proxy.
  address internal immutable _SAFE_SINGLETON;
  /// @notice Role-hat clones factory used for Quartermaster / MutinyModule / TreasuryAuthority clones.
  IRoleHatClonesFactory internal immutable _CLONES_FACTORY;
  /// @notice Registry receiving every squad's `Deployment` record.
  INavePirataRegistry internal immutable _REGISTRY;
  /// @notice Role-hat upgrader wired into each deployment's non-semantic hat slots.
  address internal immutable _UPGRADER;

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Wires every external dependency for the factory. All fields are immutable.
   * @param _hats Hats Protocol singleton for this chain.
   * @param _safeProxyFactory Safe proxy factory used by `deployNavePirata` to spawn Safes.
   * @param _safeSingleton Safe singleton backing each proxy.
   * @param _clonesFactory Role-hat clones factory for clone deploys and address prediction.
   * @param _registry Registry that this factory is authorised to `registerDeployment` into.
   * @param _upgrader Role-hat upgrader used as the non-semantic eligibility/toggle target.
   */
  constructor(
    address _hats,
    address _safeProxyFactory,
    address _safeSingleton,
    address _clonesFactory,
    address _registry,
    address _upgrader
  ) {
    if (_hats == address(0)) revert NavePirataFactory_ZeroAddress('hats');
    if (_safeProxyFactory == address(0)) revert NavePirataFactory_ZeroAddress('safeProxyFactory');
    if (_safeSingleton == address(0)) revert NavePirataFactory_ZeroAddress('safeSingleton');
    if (_clonesFactory == address(0)) revert NavePirataFactory_ZeroAddress('clonesFactory');
    if (_registry == address(0)) revert NavePirataFactory_ZeroAddress('registry');
    if (_upgrader == address(0)) revert NavePirataFactory_ZeroAddress('upgrader');

    _HATS = IHats(_hats);
    _SAFE_PROXY_FACTORY = ISafeProxyFactory(_safeProxyFactory);
    _SAFE_SINGLETON = _safeSingleton;
    _CLONES_FACTORY = IRoleHatClonesFactory(_clonesFactory);
    _REGISTRY = INavePirataRegistry(_registry);
    _UPGRADER = _upgrader;
  }

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataFactory
  function deployNavePirata(DeployParams calldata _params)
    external
    override
    returns (
      uint256 _topHatId,
      address _safe,
      address _quartermaster,
      address _mutinyModule,
      address _treasuryAuthority,
      address _squadAdminProxy
    )
  {
    _validateParams(_params);

    _safe = _deploySafe(_params.saltNonce);

    (bytes32 _qmSalt, bytes32 _mmSalt, bytes32 _taSalt) = _cloneSalts(_params.saltNonce);
    address _predQuartermaster = _CLONES_FACTORY.predictCloneAddress(_params.quartermasterMasterCopy, _qmSalt);
    address _predMutinyModule = _CLONES_FACTORY.predictCloneAddress(_params.mutinyMasterCopy, _mmSalt);

    _HatTree memory _hats = _createHatTree(_params.metadataURI, _predMutinyModule, _predQuartermaster);
    _topHatId = _hats.topHatId;

    _quartermaster = _CLONES_FACTORY.createClone(
      _params.quartermasterMasterCopy,
      abi.encodeCall(
        Quartermaster.initialize,
        (Quartermaster.InitParams({
            captainHatId: _hats.captainHatId,
            crewHatId: _hats.crewHatId,
            mutinyRoleHatId: _hats.mutinyRoleHatId,
            quartermasterRoleHatId: _hats.quartermasterRoleHatId,
            treasuryAuthorityRoleHatId: _hats.treasuryAuthorityRoleHatId,
            crewChangeDelay: _params.squadParams.crewChangeDelay
          }))
      ),
      _qmSalt
    );

    _mutinyModule = _CLONES_FACTORY.createClone(
      _params.mutinyMasterCopy,
      abi.encodeCall(
        MutinyModule.initialize,
        (MutinyModule.InitParams({
            captainHatId: _hats.captainHatId,
            crewHatId: _hats.crewHatId,
            mutinyRoleHatId: _hats.mutinyRoleHatId,
            quartermasterRoleHatId: _hats.quartermasterRoleHatId,
            captain: _params.captain,
            quartermaster: _quartermaster
          }))
      ),
      _mmSalt
    );

    _treasuryAuthority = _CLONES_FACTORY.createClone(
      _params.treasuryAuthorityMasterCopy,
      abi.encodeCall(
        TreasuryAuthority.initialize,
        (TreasuryAuthority.InitParams({
            safe: _safe,
            captainHatId: _hats.captainHatId,
            crewHatId: _hats.crewHatId,
            treasuryAuthorityRoleHatId: _hats.treasuryAuthorityRoleHatId,
            proposalExpiry: _params.squadParams.proposalExpiry,
            crewVoteMode: _params.squadParams.crewVoteMode,
            quorumBps: _params.squadParams.quorumBps
          }))
      ),
      _taSalt
    );

    _squadAdminProxy = address(
      new SquadAdmin(
        _params.squadAdminImplementation,
        abi.encodeCall(
          SquadAdminImpl.initialize,
          (SquadAdminImpl.InitParams({captainHatId: _hats.captainHatId, squadAdminHatId: _hats.squadAdminHatId}))
        )
      )
    );

    _mintRoleHats(_hats, _quartermaster, _mutinyModule, _treasuryAuthority, _squadAdminProxy, _params.captain);

    _bootstrapSafe(_safe, _treasuryAuthority);

    _HATS.transferHat(_topHatId, address(this), _safe);

    _REGISTRY.registerDeployment(
      INavePirataRegistry.Deployment({
        safe: _safe,
        quartermaster: _quartermaster,
        mutinyModule: _mutinyModule,
        treasuryAuthority: _treasuryAuthority,
        squadAdminProxy: _squadAdminProxy,
        topHatId: _topHatId,
        captainHatId: _hats.captainHatId,
        crewHatId: _hats.crewHatId,
        squadAdminHatId: _hats.squadAdminHatId,
        mutinyRoleHatId: _hats.mutinyRoleHatId,
        quartermasterRoleHatId: _hats.quartermasterRoleHatId,
        treasuryAuthorityRoleHatId: _hats.treasuryAuthorityRoleHatId,
        deployedAt: uint64(block.timestamp),
        deployer: msg.sender
      })
    );

    emit NavePirataDeployed(
      _topHatId, _params.captain, _safe, _quartermaster, _mutinyModule, _treasuryAuthority, _squadAdminProxy
    );
  }

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc INavePirataFactory
  function HATS() external view override returns (address _hats) {
    _hats = address(_HATS);
  }

  /// @inheritdoc INavePirataFactory
  function SAFE_PROXY_FACTORY() external view override returns (address _factory) {
    _factory = address(_SAFE_PROXY_FACTORY);
  }

  /// @inheritdoc INavePirataFactory
  function SAFE_SINGLETON() external view override returns (address _singleton) {
    _singleton = _SAFE_SINGLETON;
  }

  /// @inheritdoc INavePirataFactory
  function CLONES_FACTORY() external view override returns (address _clones) {
    _clones = address(_CLONES_FACTORY);
  }

  /// @inheritdoc INavePirataFactory
  function REGISTRY() external view override returns (address _registry) {
    _registry = address(_REGISTRY);
  }

  /// @inheritdoc INavePirataFactory
  function UPGRADER() external view override returns (address _upgrader) {
    _upgrader = _UPGRADER;
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploys a Safe proxy owned solely by this factory (threshold = 1). Safe setup is
   *         deliberately minimal: no setup-time delegatecall, no fallback handler, no refund.
   *         Module-enable and owner-swap happen after clone deploy.
   * @dev The Safe salt is namespaced by `(msg.sender, saltNonce)` so different callers with the
   *      same `saltNonce` do not collide.
   * @param _saltNonce Caller-supplied determinism nonce.
   * @return _safe Deployed Safe proxy address.
   */
  function _deploySafe(uint256 _saltNonce) internal returns (address _safe) {
    address[] memory _owners = new address[](1);
    _owners[0] = address(this);

    bytes memory _setupData =
      abi.encodeCall(ISafe.setup, (_owners, 1, address(0), '', address(0), address(0), 0, payable(address(0))));

    uint256 _namespacedNonce = uint256(keccak256(abi.encode(msg.sender, _saltNonce)));

    try _SAFE_PROXY_FACTORY.createProxyWithNonce(
      _SAFE_SINGLETON, _setupData, _namespacedNonce
    ) returns (address _proxy) {
      if (_proxy == address(0)) {
        revert NavePirataFactory_SafeDeployFailed();
      }
      _safe = _proxy;
    } catch {
      revert NavePirataFactory_SafeDeployFailed();
    }
  }

  /**
   * @notice Mints the tophat (to this factory) and creates every child hat. Eligibility on
   *         the captain and crew hats is wired to the predicted MutinyModule / Quartermaster
   *         clone addresses; eligibility and toggle on role and squad-admin hats default to
   *         the upgrader (non-implementing contract => Hats falls back to `!badStandings`).
   * @param _metadataURI Squad metadata URI stored on the tophat.
   * @param _predMutinyModule Predicted MutinyModule clone address (captain-hat eligibility).
   * @param _predQuartermaster Predicted Quartermaster clone address (crew-hat eligibility).
   * @return _hats Fully populated `_HatTree` struct.
   */
  function _createHatTree(
    string memory _metadataURI,
    address _predMutinyModule,
    address _predQuartermaster
  ) internal returns (_HatTree memory _hats) {
    address _placeholder = _UPGRADER;

    _hats.topHatId = _HATS.mintTopHat(address(this), _metadataURI, '');
    _hats.mutinyRoleHatId = _HATS.createHat(_hats.topHatId, 'MutinyRole', 1, _placeholder, _placeholder, false, '');
    _hats.quartermasterRoleHatId =
      _HATS.createHat(_hats.topHatId, 'QuartermasterRole', 1, _placeholder, _placeholder, false, '');
    _hats.treasuryAuthorityRoleHatId =
      _HATS.createHat(_hats.topHatId, 'TreasuryAuthorityRole', 1, _placeholder, _placeholder, false, '');
    _hats.captainHatId =
      _HATS.createHat(_hats.mutinyRoleHatId, 'Captain', 1, _predMutinyModule, _placeholder, false, '');
    _hats.crewHatId = _HATS.createHat(
      _hats.quartermasterRoleHatId, 'Crew', _MAX_CREW_SUPPLY, _predQuartermaster, _placeholder, false, ''
    );
    _hats.squadAdminHatId = _HATS.createHat(_hats.captainHatId, 'SquadAdmin', 1, _placeholder, _placeholder, false, '');
  }

  /**
   * @notice Mints every role hat to its target clone/proxy and the captain hat to the initial
   *         captain. The crew hat is intentionally left empty; onboarding happens post-bootstrap
   *         through the Quartermaster.
   * @param _tree Hat-id bundle produced by `_createHatTree`.
   * @param _quartermaster Quartermaster clone.
   * @param _mutinyModule MutinyModule clone.
   * @param _treasuryAuthority TreasuryAuthority clone.
   * @param _squadAdminProxy SquadAdmin UUPS proxy.
   * @param _captain Initial captain address.
   */
  function _mintRoleHats(
    _HatTree memory _tree,
    address _quartermaster,
    address _mutinyModule,
    address _treasuryAuthority,
    address _squadAdminProxy,
    address _captain
  ) internal {
    _HATS.mintHat(_tree.mutinyRoleHatId, _mutinyModule);
    _HATS.mintHat(_tree.quartermasterRoleHatId, _quartermaster);
    _HATS.mintHat(_tree.treasuryAuthorityRoleHatId, _treasuryAuthority);
    _HATS.mintHat(_tree.squadAdminHatId, _squadAdminProxy);
    _HATS.mintHat(_tree.captainHatId, _captain);
  }

  /**
   * @notice Uses the factory's transient sole-owner status to enable the TreasuryAuthority as
   *         the Safe's only Zodiac module and then swap itself out as owner, leaving the
   *         TreasuryAuthority as the Safe's only authority on both slots.
   * @dev Authenticates both `execTransaction` calls with a pre-validated signature (`v = 1`,
   *      `r = address(this)`, `s = 0`) per Safe's checkSignatures path for contract owners
   *      that are also `msg.sender`.
   * @param _safe Deployed Safe proxy.
   * @param _treasuryAuthority TreasuryAuthority clone that will take over both slots.
   */
  function _bootstrapSafe(address _safe, address _treasuryAuthority) internal {
    bytes memory _sig = abi.encodePacked(bytes32(uint256(uint160(address(this)))), bytes32(uint256(0)), uint8(1));

    bool _okEnable = ISafe(_safe)
      .execTransaction(
        _safe,
        0,
        abi.encodeCall(ISafe.enableModule, (_treasuryAuthority)),
        _OP_CALL,
        0,
        0,
        0,
        address(0),
        payable(address(0)),
        _sig
      );
    if (!_okEnable) revert NavePirataFactory_BootstrapTeardownFailed();

    bool _okSwap = ISafe(_safe)
      .execTransaction(
        _safe,
        0,
        abi.encodeCall(ISafe.swapOwner, (_SENTINEL_OWNERS, address(this), _treasuryAuthority)),
        _OP_CALL,
        0,
        0,
        0,
        address(0),
        payable(address(0)),
        _sig
      );
    if (!_okSwap) revert NavePirataFactory_BootstrapTeardownFailed();
  }

  /**
   * @notice Derives the three clone salts for this deployment. The salt is mixed with
   *         `msg.sender` and `saltNonce` so that, within `RoleHatClonesFactory`, no two squad
   *         bootstraps can collide on a single clone kind.
   * @param _saltNonce Caller-supplied determinism nonce.
   * @return _qmSalt Salt for the Quartermaster clone.
   * @return _mmSalt Salt for the MutinyModule clone.
   * @return _taSalt Salt for the TreasuryAuthority clone.
   */
  function _cloneSalts(uint256 _saltNonce) internal view returns (bytes32 _qmSalt, bytes32 _mmSalt, bytes32 _taSalt) {
    _qmSalt = keccak256(abi.encode(msg.sender, _saltNonce, _KIND_QM));
    _mmSalt = keccak256(abi.encode(msg.sender, _saltNonce, _KIND_MM));
    _taSalt = keccak256(abi.encode(msg.sender, _saltNonce, _KIND_TA));
  }

  /**
   * @notice Validates non-zero-address preconditions on `DeployParams`. Delay / quorum bounds
   *         are re-validated inside the role clones' initializers.
   * @param _params Deployment parameters.
   */
  function _validateParams(DeployParams calldata _params) internal pure {
    if (_params.captain == address(0)) revert NavePirataFactory_ZeroAddress('captain');
    if (_params.quartermasterMasterCopy == address(0)) revert NavePirataFactory_ZeroAddress('quartermasterMasterCopy');
    if (_params.mutinyMasterCopy == address(0)) revert NavePirataFactory_ZeroAddress('mutinyMasterCopy');
    if (_params.treasuryAuthorityMasterCopy == address(0)) {
      revert NavePirataFactory_ZeroAddress('treasuryAuthorityMasterCopy');
    }
    if (_params.squadAdminImplementation == address(0)) {
      revert NavePirataFactory_ZeroAddress('squadAdminImplementation');
    }
  }
}
