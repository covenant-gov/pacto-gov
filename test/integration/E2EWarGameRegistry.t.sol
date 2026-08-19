// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MutinyModule} from 'contracts/core/MutinyModule.sol';
import {Quartermaster} from 'contracts/core/Quartermaster.sol';
import {TreasuryAuthority} from 'contracts/core/TreasuryAuthority.sol';
import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';
import {WarGameRegistry} from 'contracts/factory/WarGameRegistry.sol';

import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';
import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';
import {IWarGameRegistry} from 'interfaces/factory/IWarGameRegistry.sol';

import {WAR_GAME_CREW_CHANGE_DELAY, WAR_GAME_PROPOSAL_EXPIRY} from 'script/Constants.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2EWarGameRegistryTest
 * @author Pacto
 * @notice Forked E2E: war-game stacks register only in `WarGameRegistry`; production index is unchanged.
 */
contract E2EWarGameRegistryTest is IntegrationBase {
  bytes32 internal constant _SQUAD_ID = keccak256('pacto.e2e.wargame.squad');
  uint256 internal _saltCursor = 10_000;

  function test_e2e_warGameDeploy_doesNotTouchProductionRegistry() public {
    uint256 _before = NavePirataRegistry(_infra.registry).deploymentCount();
    (uint256 _topHat,,,) = _deployWarGame(_SQUAD_ID, _nextSalt());

    assertEq(NavePirataRegistry(_infra.registry).deploymentCount(), _before);
    assertEq(NavePirataRegistry(_infra.registry).deployment(_topHat).topHatId, 0);
    assertEq(WarGameRegistry(_infra.warGameRegistry).activeTopHatId(_SQUAD_ID), _topHat);
  }

  function test_e2e_warGameDeploy_recordsActiveAndHistory() public {
    (uint256 _topHat, address _qm,,) = _deployWarGame(_SQUAD_ID, _nextSalt());

    WarGameRegistry _games = WarGameRegistry(_infra.warGameRegistry);
    INavePirataRegistry.Deployment memory _active = _games.active(_SQUAD_ID);
    assertEq(_active.topHatId, _topHat);
    assertEq(_active.quartermaster, _qm);

    IWarGameRegistry.Record memory _record = _games.record(_topHat);
    assertEq(_record.squadId, _SQUAD_ID);
    assertEq(uint8(_record.status), uint8(IWarGameRegistry.Status.Active));

    uint256[] memory _history = _games.history(_SQUAD_ID);
    assertEq(_history.length, 1);
    assertEq(_history[0], _topHat);
  }

  function test_e2e_warGameRedeploy_autoRetiresPreviousActive() public {
    (uint256 _first,,,) = _deployWarGame(_SQUAD_ID, _nextSalt());
    (uint256 _second,,,) = _deployWarGame(_SQUAD_ID, _nextSalt());

    WarGameRegistry _games = WarGameRegistry(_infra.warGameRegistry);
    assertEq(_games.activeTopHatId(_SQUAD_ID), _second);
    assertEq(uint8(_games.record(_first).status), uint8(IWarGameRegistry.Status.Retired));
    assertEq(uint8(_games.record(_second).status), uint8(IWarGameRegistry.Status.Active));

    uint256[] memory _history = _games.history(_SQUAD_ID);
    assertEq(_history.length, 2);
    assertEq(_history[0], _first);
    assertEq(_history[1], _second);
  }

  function test_e2e_retireWarGame_clearsActive() public {
    (uint256 _topHat,,,) = _deployWarGame(_SQUAD_ID, _nextSalt());
    NavePirataFactory(_infra.navePirataFactory).retireWarGame(_SQUAD_ID);

    WarGameRegistry _games = WarGameRegistry(_infra.warGameRegistry);
    assertEq(_games.activeTopHatId(_SQUAD_ID), 0);
    assertEq(_games.active(_SQUAD_ID).topHatId, 0);
    assertEq(uint8(_games.record(_topHat).status), uint8(IWarGameRegistry.Status.Retired));
    assertEq(_games.history(_SQUAD_ID).length, 1);
  }

  function test_e2e_productionDeploy_stillHitsNavePirataRegistry() public withDeployedNavePirataSquad {
    assertEq(NavePirataRegistry(_infra.registry).deployment(_squadTopHatId).topHatId, _squadTopHatId);
    uint256 _prodCount = NavePirataRegistry(_infra.registry).deploymentCount();

    _deployWarGame(_SQUAD_ID, _nextSalt());

    assertEq(NavePirataRegistry(_infra.registry).deploymentCount(), _prodCount);
    assertTrue(WarGameRegistry(_infra.warGameRegistry).active(_SQUAD_ID).topHatId != 0);
  }

  function test_e2e_warGameDeploy_seedsFiveMinuteDelays() public {
    (, address _qm, address _mm, address _ta) = _deployWarGame(_SQUAD_ID, _nextSalt());

    assertEq(Quartermaster(_qm).crewChangeDelay(), WAR_GAME_CREW_CHANGE_DELAY);
    assertEq(Quartermaster(_qm).crewOffboardExpiry(), WAR_GAME_PROPOSAL_EXPIRY);
    assertEq(MutinyModule(_mm).mutinyExpiry(), WAR_GAME_PROPOSAL_EXPIRY);
    assertEq(TreasuryAuthority(payable(_ta)).proposalExpiry(), WAR_GAME_PROPOSAL_EXPIRY);
  }

  function _nextSalt() internal returns (uint256 _salt) {
    _saltCursor += 1;
    _salt = _saltCursor;
  }

  function _deployWarGame(
    bytes32 _squadId,
    uint256 _saltNonce
  ) internal returns (uint256 _topHat, address _qm, address _mm, address _ta) {
    address _captain = makeAddr(string.concat('e2eWgCaptain', vm.toString(_saltNonce)));
    _fund(_captain, 50 ether);

    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: _captain,
      metadataURI: string.concat('ipfs://e2e-wargame-', vm.toString(_saltNonce)),
      squadParams: _squadParamsWarGame(),
      quartermasterMasterCopy: _masters.quartermaster,
      mutinyMasterCopy: _masters.mutinyModule,
      treasuryAuthorityMasterCopy: _masters.treasuryAuthority,
      squadAdminImplementation: _masters.squadAdminImpl,
      saltNonce: _saltNonce,
      stackKind: INavePirataFactory.StackKind.WarGame,
      squadId: _squadId
    });

    _fund(address(this), 200 ether);
    (_topHat,, _qm, _mm, _ta,) = NavePirataFactory(_infra.navePirataFactory).deployNavePirata(_p);
  }
}
