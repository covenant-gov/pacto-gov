// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {NavePirataFactory} from 'contracts/factory/NavePirataFactory.sol';

import {ISponsorPolicyRegistry} from 'interfaces/external/ISponsorPolicyRegistry.sol';
import {INavePirataFactory} from 'interfaces/factory/INavePirataFactory.sol';

import {IntegrationBase} from 'test/integration/IntegrationBase.sol';

/**
 * @title E2ESponsorPolicyRegistryTest
 * @author Pacto
 * @notice Forked E2E: `deployNavePirata` registers topHat + module index on the wired policy registry.
 */
contract E2ESponsorPolicyRegistryTest is IntegrationBase {
  bytes32 internal constant _WAR_GAME_SQUAD_ID = keccak256('pacto.e2e.sponsor.wargame');
  uint256 internal _saltCursor = 20_000;

  function test_e2e_productionDeploy_indexesModulesOnPolicyRegistry() public withDeployedNavePirataSquad {
    ISponsorPolicyRegistry _policy = ISponsorPolicyRegistry(address(_policyHarness));

    assertTrue(_policy.isTopHatSponsored(_squadTopHatId));
    assertEq(_policy.moduleToTopHat(_squadSafe), _squadTopHatId);
    assertEq(_policy.moduleToTopHat(address(_squadQuartermaster)), _squadTopHatId);
    assertEq(_policy.moduleToTopHat(address(_squadMutiny)), _squadTopHatId);
    assertEq(_policy.moduleToTopHat(address(_squadTreasury)), _squadTopHatId);
    assertEq(_policy.moduleToTopHat(address(_squadSquadAdmin)), _squadTopHatId);
  }

  function test_e2e_warGameDeploy_indexesModulesOnPolicyRegistry() public {
    (uint256 _topHat, address _safe, address _qm, address _mm, address _ta, address _squadAdmin) =
      _deployWarGame(_WAR_GAME_SQUAD_ID, _nextSalt());

    ISponsorPolicyRegistry _policy = ISponsorPolicyRegistry(address(_policyHarness));

    assertTrue(_policy.isTopHatSponsored(_topHat));
    assertEq(_policy.moduleToTopHat(_safe), _topHat);
    assertEq(_policy.moduleToTopHat(_qm), _topHat);
    assertEq(_policy.moduleToTopHat(_mm), _topHat);
    assertEq(_policy.moduleToTopHat(_ta), _topHat);
    assertEq(_policy.moduleToTopHat(_squadAdmin), _topHat);
  }

  function _nextSalt() internal returns (uint256 _salt) {
    _saltCursor += 1;
    _salt = _saltCursor;
  }

  function _deployWarGame(
    bytes32 _squadId,
    uint256 _saltNonce
  ) internal returns (uint256 _topHat, address _safe, address _qm, address _mm, address _ta, address _squadAdmin) {
    address _captain = makeAddr(string.concat('e2eSpCaptain', vm.toString(_saltNonce)));
    _fund(_captain, 50 ether);

    INavePirataFactory.DeployParams memory _p = INavePirataFactory.DeployParams({
      captain: _captain,
      metadataURI: string.concat('ipfs://e2e-sponsor-wargame-', vm.toString(_saltNonce)),
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
    (_topHat, _safe, _qm, _mm, _ta, _squadAdmin) = NavePirataFactory(_infra.navePirataFactory).deployNavePirata(_p);
  }
}
