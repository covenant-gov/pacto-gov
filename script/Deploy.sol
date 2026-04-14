// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Greeter} from 'contracts/Greeter.sol';
import {PactoAdmin} from 'contracts/PactoAdmin.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {IERC20} from 'forge-std/interfaces/IERC20.sol';

contract Deploy is Script {
  struct DeploymentParams {
    string greeting;
    IERC20 token;
  }

  /// @notice Deployment parameters for each chain
  mapping(uint256 _chainId => DeploymentParams _params) internal _deploymentParams;

  function setUp() public {
    // Mainnet
    _deploymentParams[1] = DeploymentParams('Hello, Mainnet!', IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    // Sepolia
    _deploymentParams[11_155_111] =
      DeploymentParams('Hello, Sepolia!', IERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14));
  }

  function run() public {
    DeploymentParams memory _params = _deploymentParams[block.chainid];

    vm.startBroadcast();
    // PactoAdmin must be deployed before `INavePirataFactory.deployNavePirata(..., _pactoAdmin, ...)`.
    // Optional: `PACTO_ADMIN=0x...` sets the admin account; otherwise the broadcast `msg.sender` is used.
    address _pactoAdminOwner = vm.envOr('PACTO_ADMIN', msg.sender);
    PactoAdmin _pacto = new PactoAdmin(_pactoAdminOwner);
    new Greeter(_params.greeting, _params.token);
    vm.stopBroadcast();

    // Log for operators / factory wiring (addresses also available from broadcast receipts)
    console.log('PactoAdmin:', address(_pacto));
  }
}
