// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SwapApp.sol";
import "../src/interfaces/IV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ─── Mocks ────────────────────────────────────────────────────────────────────

contract InvMockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract InvMockV2Router is IV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "expired");
        require(amountIn >= amountOutMin, "insufficient output");
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        InvMockERC20(path[path.length - 1]).mint(to, amountIn);
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(block.timestamp <= deadline, "expired");
        require(amountADesired >= amountAMin, "A insufficient");
        require(amountBDesired >= amountBMin, "B insufficient");
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);
        return (amountADesired, amountBDesired, amountADesired + amountBDesired);
    }

    function removeLiquidity(address, address, uint256, uint256, uint256, address, uint256)
        external
        pure
        override
        returns (uint256, uint256)
    {
        return (0, 0);
    }
}

// ─── Handler ──────────────────────────────────────────────────────────────────

contract Handler is Test {
    SwapApp public app;
    InvMockERC20 public usdt;
    InvMockERC20 public dai;

    address[] public actors;

    uint256 public ghost_usdtSpentTotal;

    uint256 constant DEADLINE = type(uint256).max;

    constructor(SwapApp _app, InvMockERC20 _usdt, InvMockERC20 _dai, address[] memory _actors) {
        app = _app;
        usdt = _usdt;
        dai = _dai;
        actors = _actors;
    }

    function doSwap(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1, 1_000 ether);

        usdt.mint(actor, amount);
        vm.prank(actor);
        usdt.approve(address(app), amount);

        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(dai);

        vm.prank(actor);
        app.swapTokens(amount, 0, path, DEADLINE);

        ghost_usdtSpentTotal += amount;
    }

    function doAddLiquidity(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 2, 1_000 ether);

        usdt.mint(actor, amount);
        vm.prank(actor);
        usdt.approve(address(app), amount);

        vm.prank(actor);
        app.addLiquidity(amount, 0, 0, 0, DEADLINE);

        ghost_usdtSpentTotal += amount;
    }
}

// ─── Invariant Test ───────────────────────────────────────────────────────────

contract SwapAppInvariantTest is Test {
    SwapApp public app;
    InvMockV2Router public router;
    InvMockERC20 public usdt;
    InvMockERC20 public dai;
    Handler public handler;

    address[] internal actors;

    function setUp() public {
        router = new InvMockV2Router();
        usdt = new InvMockERC20("USDT", "USDT");
        dai = new InvMockERC20("DAI", "DAI");
        app = new SwapApp(address(router), address(0xFAC7), address(usdt), address(dai));

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));

        handler = new Handler(app, usdt, dai, actors);

        targetContract(address(handler));
    }

    /// @dev The contract must never hold USDT between calls.
    function invariant_contractHoldsNoUSDT() public view {
        assertEq(usdt.balanceOf(address(app)), 0);
    }

    /// @dev The contract must never hold DAI between calls.
    function invariant_contractHoldsNoDAI() public view {
        assertEq(dai.balanceOf(address(app)), 0);
    }

    /// @dev The app never leaves a residual allowance on the router.
    function invariant_noResidualAllowanceToRouter() public view {
        assertEq(usdt.allowance(address(app), address(router)), 0);
        assertEq(dai.allowance(address(app), address(router)), 0);
    }
}
