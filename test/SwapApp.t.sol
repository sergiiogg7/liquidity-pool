// SPDX-License-Identifier: MIT
// For testing in Arbitrum forked: forge test -vvvv --fork-url https://arb1.arbitrum.io/rpc --match-test

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/SwapApp.sol";
import "../src/interfaces/IFactory.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract SwappAppTest is Test {

    SwapApp app;
    address uniswapV2SwappRouterAddress = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address uniswapv2FactoryAddress = 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9;
    address user = 0xB45323118e29e3C33c4a906dD8ce9d9CF443D380; // Address with USDT in Arbitrum Mainnet
    address USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT address in Arbitrum Mainnet
    address DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI address in Arbitrum Mainnet

    function setUp() public {
        app = new SwapApp(uniswapV2SwappRouterAddress, uniswapv2FactoryAddress, USDT, DAI);
        deal(USDT, user, 100 * 1e6);
        deal(DAI, user, 100 * 1e18);
    }

    function testHasBeenDeployedCorrectly() public view {
        assert(app.V2Router02Address() == uniswapV2SwappRouterAddress);
    }

    function testSwapTokensCorrectly() public {
        vm.startPrank(user);
        uint256 amountIn = 5 * 1e6;
        uint256 amountOutMin = 4 * 1e18;
        IERC20(USDT).approve(address(app), amountIn);
        uint256 deadline = 1738499328 + 1000000000;
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;

        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(user);
        app.swapTokens(amountIn, amountOutMin, path, user, deadline);
        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceAfter = IERC20(DAI).balanceOf(user);

        assert(usdtBalanceAfter == usdtBalanceBefore - amountIn);
        assert(daiBalanceAfter > daiBalanceBefore);

        vm.stopPrank();
    }

    function testCanAddLiquidityCorrectly() public {
        vm.startPrank(user);
        uint256 amountIn_ = 6 * 1e6;
        uint256 amountOutMin_ = 2 * 1e18;
        address[] memory path_ = new address[](2);
        path_[0] = USDT;
        path_[1] = DAI;
        uint256 amountAMin_ = 0;
        uint256 amountBMin_ = 0;
        uint256 deadline_ = 1738499328 + 1000000000;

        IERC20(USDT).approve(address(app), amountIn_);
        app.addLiquidity(amountIn_, amountOutMin_, path_, amountAMin_, amountBMin_, deadline_);

        vm.stopPrank();
    }

    function testCanRemoveLiquidityCorrectly() public {
        vm.startPrank(user);
        uint256 amountIn_ = 6 * 1e6;
        uint256 amountOutMin_ = 2 * 1e18;
        address[] memory path_ = new address[](2);
        path_[0] = USDT;
        path_[1] = DAI;
        uint256 amountAMin_ = 0;
        uint256 amountBMin_ = 0;
        uint256 deadline_ = 1738499328 + 1000000000;

        IERC20(USDT).approve(address(app), amountIn_);
        app.addLiquidity(amountIn_, amountOutMin_, path_, amountAMin_, amountBMin_, deadline_);

        address lpTokenAddress = IFactory(app.UniswapFactoryAddress()).getPair(USDT, DAI);
        uint256 lpTokenBalance = IERC20(lpTokenAddress).balanceOf(user);
        assert(lpTokenBalance > 0);

        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(user);

        IERC20(lpTokenAddress).approve(address(app), lpTokenBalance);
        app.removeLiquidity(lpTokenBalance, amountAMin_, amountBMin_, user, deadline_);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceAfter = IERC20(DAI).balanceOf(user);

        assert(usdtBalanceAfter > usdtBalanceBefore);
        assert(daiBalanceAfter > daiBalanceBefore);
        assert(IERC20(lpTokenAddress).balanceOf(user) == 0);

        vm.stopPrank();
    }
}
