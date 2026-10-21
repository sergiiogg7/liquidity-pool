// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SwapApp.sol";
import "../src/interfaces/IV2Router02.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// ─── Mocks (duplicated to keep files self-contained) ─────────────────────────

contract FuzzMockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract FuzzMockV2Router is IV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override returns (uint[] memory amounts) {
        require(block.timestamp <= deadline, "expired");
        require(amountIn >= amountOutMin, "insufficient output");
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        FuzzMockERC20(path[path.length - 1]).mint(to, amountIn);
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external override returns (uint amountA, uint amountB, uint liquidity) {
        require(block.timestamp <= deadline, "expired");
        require(amountADesired >= amountAMin, "A insufficient");
        require(amountBDesired >= amountBMin, "B insufficient");
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);
        return (amountADesired, amountBDesired, amountADesired + amountBDesired);
    }
}

// ─── Fuzz Tests ───────────────────────────────────────────────────────────────

contract SwapAppFuzzTest is Test {
    SwapApp public app;
    FuzzMockV2Router public router;
    FuzzMockERC20 public usdt;
    FuzzMockERC20 public dai;

    address public user;
    uint256 public constant DEADLINE = type(uint256).max;

    function setUp() public {
        user = makeAddr("user");
        router = new FuzzMockV2Router();
        usdt = new FuzzMockERC20("USDT", "USDT");
        dai = new FuzzMockERC20("DAI", "DAI");
        app = new SwapApp(address(router), address(usdt), address(dai));

        vm.prank(user);
        usdt.approve(address(app), type(uint256).max);
        vm.prank(user);
        dai.approve(address(app), type(uint256).max);
    }

    /// @dev Any valid amount swaps 1:1 and leaves the contract with zero balance.
    function testFuzz_SwapAnyAmount(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, 100_000 ether);

        usdt.mint(user, amountIn);
        uint256 usdtBefore = usdt.balanceOf(user);
        uint256 daiBefore = dai.balanceOf(user);

        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(dai);

        vm.prank(user);
        uint256 amountOut = app.swapTokens(amountIn, 0, path, DEADLINE);

        assertEq(amountOut, amountIn);
        assertEq(usdt.balanceOf(user), usdtBefore - amountIn);
        assertEq(dai.balanceOf(user), daiBefore + amountIn);
        assertEq(usdt.balanceOf(address(app)), 0);
        assertEq(dai.balanceOf(address(app)), 0);
    }

    /// @dev Any valid USDT amount leaves the contract with zero USDT and DAI.
    function testFuzz_AddLiquidityAnyAmount(uint256 amountUSDT) public {
        amountUSDT = bound(amountUSDT, 2, 100_000 ether);

        usdt.mint(user, amountUSDT);

        vm.prank(user);
        app.addLiquidity(amountUSDT, 0, 0, 0, DEADLINE);

        assertEq(usdt.balanceOf(address(app)), 0);
        assertEq(dai.balanceOf(address(app)), 0);
    }

    /// @dev Contract never retains funds regardless of operation type.
    function testFuzz_ContractNeverRetainsFunds(uint256 amount, bool doSwap) public {
        amount = bound(amount, 2, 100_000 ether);
        usdt.mint(user, amount);

        if (doSwap) {
            address[] memory path = new address[](2);
            path[0] = address(usdt);
            path[1] = address(dai);
            vm.prank(user);
            app.swapTokens(amount, 0, path, DEADLINE);
        } else {
            vm.prank(user);
            app.addLiquidity(amount, 0, 0, 0, DEADLINE);
        }

        assertEq(usdt.balanceOf(address(app)), 0);
        assertEq(dai.balanceOf(address(app)), 0);
    }
}
