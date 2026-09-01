// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SwapApp.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract SwapAppTest is Test {

    SwapApp app;

    address uniswapV2SwapRouterAddress = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address user = 0xB45323118e29e3C33c4a906dD8ce9d9CF443D380; // Address with USDT in Arbitrum Mainnet
    address USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT address in Arbitrum Mainnet
    address DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // USDT address in Arbitrum Mainnet

    function setUp() public {
        app = new SwapApp(uniswapV2SwapRouterAddress);
    }

    function testHasBeenDeployedCorrectly() public view {
        assert(app.V2Router02Address() == uniswapV2SwapRouterAddress);
    }
        
    function testSwapTokensCorrectly() public {
        uint256 amountIn = 5 * 1e6;
        uint256 amountOutMin = 4 * 1e18;
        uint256 deadline = 1738499328 + 100000000;

        deal(USDT, user, amountIn);

        vm.startPrank(user);
        IERC20(USDT).approve(address(app), amountIn);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;

        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(user);

        app.swapTokens(amountIn, amountOutMin, path, deadline);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceAfter = IERC20(DAI).balanceOf(user);

        assert(usdtBalanceAfter == usdtBalanceBefore - amountIn);
        assert(daiBalanceAfter > daiBalanceBefore);

        vm.stopPrank();
    }
}