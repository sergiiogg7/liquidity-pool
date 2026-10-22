// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/SwapApp.sol";
import "../src/interfaces/IV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ─── Mocks ────────────────────────────────────────────────────────────────────

contract LiqMockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to_, uint256 amount_) external {
        _mint(to_, amount_);
    }
}

/// @dev Mimics mainnet USDT: no return values and approve must go through zero first.
contract LiqNoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to_, uint256 amount_) external {
        balanceOf[to_] += amount_;
    }

    function approve(address spender_, uint256 amount_) external {
        require(amount_ == 0 || allowance[msg.sender][spender_] == 0, "approve from non-zero");
        allowance[msg.sender][spender_] = amount_;
    }

    function transfer(address to_, uint256 amount_) external {
        balanceOf[msg.sender] -= amount_;
        balanceOf[to_] += amount_;
    }

    function transferFrom(address from_, address to_, uint256 amount_) external {
        allowance[from_][msg.sender] -= amount_;
        balanceOf[from_] -= amount_;
        balanceOf[to_] += amount_;
    }
}

contract LiqMockFactory {
    address public pair;

    function setPair(address pair_) external {
        pair = pair_;
    }

    function getPair(address, address) external view returns (address) {
        return pair;
    }
}

/// @dev Router that consumes only half of the offered liquidity and honours min-amount checks.
contract LiqMockRouter is IV2Router02 {
    using SafeERC20 for IERC20;

    address public lpToken;

    function setLpToken(address lpToken_) external {
        lpToken = lpToken_;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external override returns (uint256[] memory amounts) {
        require(amountIn >= amountOutMin, "insufficient output");
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        LiqMintable(path[path.length - 1]).mint(to, amountIn);
        amounts = new uint256[](path.length);
        amounts[path.length - 1] = amountIn;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address,
        uint256
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        amountA = amountADesired / 2;
        amountB = amountBDesired / 2;
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);
        liquidity = amountA + amountB;
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256
    ) external override returns (uint256 amountA, uint256 amountB) {
        amountA = liquidity;
        amountB = liquidity;
        require(amountA >= amountAMin, "A insufficient");
        require(amountB >= amountBMin, "B insufficient");
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), liquidity);
        LiqMintable(tokenA).mint(to, amountA);
        LiqMintable(tokenB).mint(to, amountB);
    }
}

interface LiqMintable {
    function mint(address to_, uint256 amount_) external;
}

/// @dev Token that re-enters SwapApp.swapTokens from inside transferFrom.
contract LiqReentrantToken is ERC20 {
    SwapApp public app;

    constructor() ERC20("Evil", "EVIL") {}

    function setApp(SwapApp app_) external {
        app = app_;
    }

    function mint(address to_, uint256 amount_) external {
        _mint(to_, amount_);
    }

    function transferFrom(address from_, address to_, uint256 amount_) public override returns (bool) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(this);
        app.swapTokens(1, 0, path, type(uint256).max);
        return super.transferFrom(from_, to_, amount_);
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

contract SwapAppLiquidityTest is Test {
    SwapApp app;
    LiqMockRouter router;
    LiqMockFactory factory;
    LiqMockERC20 usdt;
    LiqMockERC20 dai;
    LiqMockERC20 lp;

    address user = makeAddr("user");
    address recipient = makeAddr("recipient");
    uint256 constant DEADLINE = type(uint256).max;

    function setUp() external {
        router = new LiqMockRouter();
        factory = new LiqMockFactory();
        usdt = new LiqMockERC20("USDT", "USDT");
        dai = new LiqMockERC20("DAI", "DAI");
        lp = new LiqMockERC20("LP", "LP");
        factory.setPair(address(lp));
        router.setLpToken(address(lp));

        app = new SwapApp(address(router), address(factory), address(usdt), address(dai));

        lp.mint(user, 1_000 ether);
        usdt.mint(user, 1_000 ether);
        vm.startPrank(user);
        lp.approve(address(app), type(uint256).max);
        usdt.approve(address(app), type(uint256).max);
        vm.stopPrank();
    }

    // ─── constructor ──────────────────────────────────────────────────────────

    function test_constructor_withZeroFactory_revertsWithZeroAddress() external {
        // Arrange / Act / Assert
        vm.expectRevert(ZeroAddress.selector);
        new SwapApp(address(router), address(0), address(usdt), address(dai));
    }

    function test_constructor_withIdenticalTokens_revertsWithIdenticalTokens() external {
        // Arrange / Act / Assert
        vm.expectRevert(IdenticalTokens.selector);
        new SwapApp(address(router), address(factory), address(usdt), address(usdt));
    }

    function test_constructor_setsFactoryAndOwner() external view {
        // Assert
        assertEq(app.UniswapFactoryAddress(), address(factory));
        assertEq(app.owner(), address(this));
    }

    // ─── removeLiquidity ──────────────────────────────────────────────────────

    function test_removeLiquidity_withValidAmount_sendsTokensToRecipient() external {
        // Arrange
        uint256 amount = 100 ether;

        // Act
        vm.prank(user);
        app.removeLiquidity(amount, 0, 0, recipient, DEADLINE);

        // Assert
        assertEq(usdt.balanceOf(recipient), amount);
        assertEq(dai.balanceOf(recipient), amount);
        assertEq(lp.balanceOf(user), 900 ether);
        assertEq(lp.balanceOf(address(app)), 0);
    }

    function test_removeLiquidity_emitsEvent() external {
        // Arrange
        vm.expectEmit(false, true, false, true);
        emit SwapApp.RemoveLiquidity(100 ether, recipient);

        // Act
        vm.prank(user);
        app.removeLiquidity(100 ether, 0, 0, recipient, DEADLINE);
    }

    function test_removeLiquidity_withZeroLiquidity_revertsWithZeroLiquidity() external {
        // Arrange / Act / Assert
        vm.prank(user);
        vm.expectRevert(ZeroLiquidity.selector);
        app.removeLiquidity(0, 0, 0, recipient, DEADLINE);
    }

    function test_removeLiquidity_withZeroRecipient_revertsWithZeroAddress() external {
        // Arrange / Act / Assert
        vm.prank(user);
        vm.expectRevert(ZeroAddress.selector);
        app.removeLiquidity(1 ether, 0, 0, address(0), DEADLINE);
    }

    function test_removeLiquidity_whenPairMissing_revertsWithPairNotFound() external {
        // Arrange
        factory.setPair(address(0));

        // Act / Assert
        vm.prank(user);
        vm.expectRevert(PairNotFound.selector);
        app.removeLiquidity(1 ether, 0, 0, recipient, DEADLINE);
    }

    function test_removeLiquidity_whenPaused_reverts() external {
        // Arrange
        app.pause();

        // Act / Assert
        vm.prank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        app.removeLiquidity(1 ether, 0, 0, recipient, DEADLINE);
    }

    function test_removeLiquidity_withoutAllowance_reverts() external {
        // Arrange
        address stranger = makeAddr("stranger");
        lp.mint(stranger, 1 ether);

        // Act / Assert
        vm.prank(stranger);
        vm.expectRevert();
        app.removeLiquidity(1 ether, 0, 0, recipient, DEADLINE);
    }

    function test_removeLiquidity_whenMinAmountTooHigh_reverts() external {
        // Arrange / Act / Assert
        vm.prank(user);
        vm.expectRevert("A insufficient");
        app.removeLiquidity(1 ether, 2 ether, 0, recipient, DEADLINE);
    }

    function testFuzz_removeLiquidity_neverLeavesLpInContract(uint256 amount_) external {
        // Arrange
        amount_ = bound(amount_, 1, lp.balanceOf(user));

        // Act
        vm.prank(user);
        app.removeLiquidity(amount_, 0, 0, recipient, DEADLINE);

        // Assert
        assertEq(lp.balanceOf(address(app)), 0);
        assertEq(IERC20(address(lp)).allowance(address(app), address(router)), 0);
    }

    // ─── addLiquidity ─────────────────────────────────────────────────────────

    function test_addLiquidity_withOddAmount_refundsLeftoversAndClearsAllowances() external {
        // Arrange
        uint256 amount = 1_001;

        // Act
        vm.prank(user);
        app.addLiquidity(amount, 0, 0, 0, DEADLINE);

        // Assert
        assertEq(usdt.balanceOf(address(app)), 0);
        assertEq(dai.balanceOf(address(app)), 0);
        assertEq(usdt.allowance(address(app), address(router)), 0);
        assertEq(dai.allowance(address(app), address(router)), 0);
    }

    // ─── USDT-like token (no return value, approve via zero) ──────────────────

    function test_addLiquidity_withNoReturnToken_succeeds() external {
        // Arrange
        LiqNoReturnToken usdtLike = new LiqNoReturnToken();
        SwapApp usdtApp = new SwapApp(address(router), address(factory), address(usdtLike), address(dai));
        usdtLike.mint(user, 1_000 ether);
        vm.prank(user);
        // Raw call: the token returns no data, so the typed IERC20 interface cannot be used here.
        (bool ok,) = address(usdtLike).call(abi.encodeCall(LiqNoReturnToken.approve, (address(usdtApp), 1_000 ether)));
        assertTrue(ok);

        // Act
        vm.prank(user);
        usdtApp.addLiquidity(1_000 ether, 0, 0, 0, DEADLINE);

        // Assert
        assertEq(usdtLike.balanceOf(address(usdtApp)), 0);
        assertEq(usdtLike.allowance(address(usdtApp), address(router)), 0);
    }

    // ─── reentrancy ───────────────────────────────────────────────────────────

    function test_swapTokens_reentrantToken_revertsWithReentrancyGuard() external {
        // Arrange
        LiqReentrantToken evil = new LiqReentrantToken();
        evil.setApp(app);
        evil.mint(user, 10 ether);
        vm.prank(user);
        evil.approve(address(app), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(evil);
        path[1] = address(dai);

        // Act / Assert
        vm.prank(user);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        app.swapTokens(1 ether, 0, path, DEADLINE);
    }
}
