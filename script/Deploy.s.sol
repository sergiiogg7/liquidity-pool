// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../src/SwapApp.sol";

/// @notice Deploys SwapApp using addresses read from the environment.
contract Deploy is Script {
    function run() external returns (SwapApp app) {
        address router = vm.envAddress("V2_ROUTER");
        address factory = vm.envAddress("V2_FACTORY");
        address usdt = vm.envAddress("USDT");
        address dai = vm.envAddress("DAI");

        vm.startBroadcast();
        app = new SwapApp(router, factory, usdt, dai);
        vm.stopBroadcast();

        console.log("SwapApp deployed at:", address(app));
    }
}
