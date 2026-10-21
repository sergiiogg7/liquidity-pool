// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SwapApp.sol";
import "../src/interfaces/IV2Router02.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// OZ error selectors — defined inside contracts so must be accessed via bytes4
bytes4 constant OWNABLE_UNAUTHORIZED = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
bytes4 constant ENFORCED_PAUSE = bytes4(keccak256("EnforcedPause()"));

// ─── Mocks ────────────────────────────────────────────────────────────────────

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev 1:1 swap mock. Pulls path[0] from caller, mints path[last] to `to`.
contract MockV2Router is IV2Router02 {
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
        MockERC20(path[path.length - 1]).mint(to, amountIn);

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

/// @dev addLiquidity only consumes half of each token, leaving leftover for the contract to return.
contract PartialMockV2Router is IV2Router02 {
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
        MockERC20(path[path.length - 1]).mint(to, amountIn);

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

        uint usedA = amountADesired / 2;
        uint usedB = amountBDesired / 2;

        IERC20(tokenA).transferFrom(msg.sender, address(this), usedA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), usedB);

        return (usedA, usedB, usedA + usedB);
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

contract SwapAppTest is Test {
    SwapApp public app;
    MockV2Router public router;
    MockERC20 public usdt;
    MockERC20 public dai;

    address public owner;
    address public user;

    uint256 public constant DEADLINE = type(uint256).max;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        router = new MockV2Router();
        usdt = new MockERC20("USDT", "USDT");
        dai = new MockERC20("DAI", "DAI");

        app = new SwapApp(address(router), address(usdt), address(dai));

        usdt.mint(user, 1_000_000 ether);
        dai.mint(user, 1_000_000 ether);

        vm.prank(user);
        usdt.approve(address(app), type(uint256).max);
        vm.prank(user);
        dai.approve(address(app), type(uint256).max);
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    function testConstructorSetsAddresses() public view {
        assertEq(app.V2Router02Address(), address(router));
        assertEq(app.USDT(), address(usdt));
        assertEq(app.DAI(), address(dai));
        assertEq(app.owner(), owner);
    }

    function test_RevertWhen_ConstructorZeroRouter() public {
        vm.expectRevert(ZeroAddress.selector);
        new SwapApp(address(0), address(usdt), address(dai));
    }

    function test_RevertWhen_ConstructorZeroUSDT() public {
        vm.expectRevert(ZeroAddress.selector);
        new SwapApp(address(router), address(0), address(dai));
    }

    function test_RevertWhen_ConstructorZeroDAI() public {
        vm.expectRevert(ZeroAddress.selector);
        new SwapApp(address(router), address(usdt), address(0));
    }

    // ─── Pause / Unpause ─────────────────────────────────────────────────────

    function testPauseUnpause() public {
        app.pause();
        assertTrue(app.paused());

        app.unpause();
        assertFalse(app.paused());
    }

    function test_RevertWhen_PauseNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OWNABLE_UNAUTHORIZED, user));
        app.pause();
    }

    function test_RevertWhen_UnpauseNotOwner() public {
        app.pause();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OWNABLE_UNAUTHORIZED, user));
        app.unpause();
    }

    // ─── Ownable2Step ─────────────────────────────────────────────────────────

    function testOwnershipTransfer2Step() public {
        app.transferOwnership(user);
        assertEq(app.pendingOwner(), user);
        assertEq(app.owner(), owner);

        vm.prank(user);
        app.acceptOwnership();
        assertEq(app.owner(), user);
    }

    // ─── swapTokens ───────────────────────────────────────────────────────────

    function testSwapTokens() public {
        uint256 amountIn = 1_000 ether;
        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(dai);

        uint256 usdtBefore = usdt.balanceOf(user);
        uint256 daiBefore = dai.balanceOf(user);

        vm.prank(user);
        uint256 amountOut = app.swapTokens(amountIn, 0, path, DEADLINE);

        // 1:1 mock swap
        assertEq(amountOut, amountIn);
        assertEq(usdt.balanceOf(user), usdtBefore - amountIn);
        assertEq(dai.balanceOf(user), daiBefore + amountIn);

        // Contract holds nothing after swap
        assertEq(usdt.balanceOf(address(app)), 0);
        assertEq(dai.balanceOf(address(app)), 0);
    }

    function test_RevertWhen_SwapZeroAmount() public {
        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(dai);

        vm.prank(user);
        vm.expectRevert(ZeroAmount.selector);
        app.swapTokens(0, 0, path, DEADLINE);
    }

    function test_RevertWhen_SwapInvalidPath() public {
        address[] memory path = new address[](1);
        path[0] = address(usdt);

        vm.prank(user);
        vm.expectRevert(InvalidPath.selector);
        app.swapTokens(1 ether, 0, path, DEADLINE);
    }

    function test_RevertWhen_SwapWhenPaused() public {
        app.pause();
        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(dai);

        vm.prank(user);
        vm.expectRevert(ENFORCED_PAUSE);
        app.swapTokens(1 ether, 0, path, DEADLINE);
    }

    function testSwapEmitsEvent() public {
        uint256 amountIn = 500 ether;
        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(dai);

        vm.expectEmit(true, true, false, true);
        emit SwapApp.SwapTokens(address(usdt), address(dai), amountIn, amountIn);

        vm.prank(user);
        app.swapTokens(amountIn, 0, path, DEADLINE);
    }

    // ─── addLiquidity ─────────────────────────────────────────────────────────

    function testAddLiquidity() public {
        uint256 amountUSDT = 1_000 ether;
        uint256 usdtBefore = usdt.balanceOf(user);

        vm.prank(user);
        app.addLiquidity(amountUSDT, 0, 0, 0, DEADLINE);

        // User spent amountUSDT
        assertEq(usdt.balanceOf(user), usdtBefore - amountUSDT);

        // Contract holds no tokens after the call
        assertEq(usdt.balanceOf(address(app)), 0);
        assertEq(dai.balanceOf(address(app)), 0);
    }

    function test_RevertWhen_AddLiquidityZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(ZeroAmount.selector);
        app.addLiquidity(0, 0, 0, 0, DEADLINE);
    }

    function test_RevertWhen_AddLiquidityWhenPaused() public {
        app.pause();
        vm.prank(user);
        vm.expectRevert(ENFORCED_PAUSE);
        app.addLiquidity(1_000 ether, 0, 0, 0, DEADLINE);
    }

    function testAddLiquidityEmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit SwapApp.AddLiquidity(address(usdt), address(dai), 0);

        vm.prank(user);
        app.addLiquidity(1_000 ether, 0, 0, 0, DEADLINE);
    }

    function testAddLiquidityReturnsLeftovers() public {
        // Deploy a new SwapApp backed by PartialMockV2Router
        PartialMockV2Router partialRouter = new PartialMockV2Router();
        SwapApp partialApp = new SwapApp(address(partialRouter), address(usdt), address(dai));

        vm.prank(user);
        usdt.approve(address(partialApp), type(uint256).max);
        vm.prank(user);
        dai.approve(address(partialApp), type(uint256).max);

        uint256 amountUSDT = 1_000 ether;
        uint256 usdtBefore = usdt.balanceOf(user);

        vm.prank(user);
        partialApp.addLiquidity(amountUSDT, 0, 0, 0, DEADLINE);

        // Contract holds nothing
        assertEq(usdt.balanceOf(address(partialApp)), 0);
        assertEq(dai.balanceOf(address(partialApp)), 0);

        // User got leftover back so spent less than full amountUSDT
        assertGt(usdt.balanceOf(user), usdtBefore - amountUSDT);
    }
}
