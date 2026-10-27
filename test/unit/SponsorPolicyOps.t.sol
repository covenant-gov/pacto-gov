// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISponsorPolicyRegistry} from 'interfaces/external/ISponsorPolicyRegistry.sol';

import {SponsorPolicyOps} from 'script/SponsorPolicyOps.sol';
import {SponsorPolicyRegistryHarness} from 'test/integration/SponsorPolicyRegistryHarness.sol';

import {Test} from 'forge-std/Test.sol';

/**
 * @title SponsorPolicyOpsHarness
 * @author Pacto
 * @notice External wrapper so library reverts sit below the cheatcode call depth.
 */
contract SponsorPolicyOpsHarness {
  function wireFactoryAndUpgrader(
    ISponsorPolicyRegistry registry,
    address factory,
    address upgrader
  ) external returns (SponsorPolicyOps.WireResult memory result) {
    result = SponsorPolicyOps.wireFactoryAndUpgrader(registry, factory, upgrader);
  }
}

/**
 * @title UnitSponsorPolicyOps
 * @author Pacto
 * @notice Unit tests for `SponsorPolicyOps` factory + upgrader wiring on the policy harness.
 */
contract UnitSponsorPolicyOps is Test {
  SponsorPolicyRegistryHarness internal _registry;
  SponsorPolicyOpsHarness internal _ops;
  address internal _factory = makeAddr('factory');
  address internal _upgrader = makeAddr('upgrader');

  function setUp() public {
    _registry = new SponsorPolicyRegistryHarness();
    _ops = new SponsorPolicyOpsHarness();
  }

  function test_WireFactoryAndUpgrader_AuthorizesBoth_RegistersFactoryOnly() external {
    SponsorPolicyOps.WireResult memory _result =
      _ops.wireFactoryAndUpgrader(ISponsorPolicyRegistry(address(_registry)), _factory, _upgrader);

    assertTrue(_result.registrarAuthorized);
    assertTrue(_result.targetRegistered);
    assertTrue(_result.upgraderRegistrarAuthorized);
    assertTrue(_registry.authorizedRegistrars(_factory));
    assertTrue(_registry.authorizedRegistrars(_upgrader));
    assertTrue(_registry.isContractAllowed(_factory));
    assertFalse(_registry.isContractAllowed(_upgrader));
  }

  function test_WireFactoryAndUpgrader_IsIdempotent() external {
    _ops.wireFactoryAndUpgrader(ISponsorPolicyRegistry(address(_registry)), _factory, _upgrader);

    SponsorPolicyOps.WireResult memory _result =
      _ops.wireFactoryAndUpgrader(ISponsorPolicyRegistry(address(_registry)), _factory, _upgrader);

    assertFalse(_result.registrarAuthorized);
    assertFalse(_result.targetRegistered);
    assertFalse(_result.upgraderRegistrarAuthorized);
    assertTrue(_registry.authorizedRegistrars(_factory));
    assertTrue(_registry.authorizedRegistrars(_upgrader));
    assertTrue(_registry.isContractAllowed(_factory));
    assertFalse(_registry.isContractAllowed(_upgrader));
  }

  function test_WireFactoryAndUpgrader_RevertsOnZeroUpgrader() external {
    vm.expectRevert(SponsorPolicyOps.SponsorPolicyOps_ZeroUpgrader.selector);
    _ops.wireFactoryAndUpgrader(ISponsorPolicyRegistry(address(_registry)), _factory, address(0));
  }
}
