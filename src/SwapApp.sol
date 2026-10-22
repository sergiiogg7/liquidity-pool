// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./interfaces/IV2Router02.sol";
import "./interfaces/IFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// ─── Errors ───────────────────────────────────────────────────────────────────

/// @notice Thrown when a required address argument is the zero address.
error ZeroAddress();

/// @notice Thrown when the constructor receives the same address for USDT and DAI.
error IdenticalTokens();

/// @notice Thrown when the factory has no USDT/DAI pair deployed.
error PairNotFound();

/// @notice Thrown when an input amount is zero.
error ZeroAmount();

/// @notice Thrown when the swap path has fewer than two tokens.
error InvalidPath();

/// @notice Thrown when liquidity amount to remove is zero.
error ZeroLiquidity();

// ─── Contract ─────────────────────────────────────────────────────────────────

/// @title SwapApp
/// @notice Thin Uniswap V2 wrapper that lets users swap ERC-20 tokens and
///         add USDT/DAI liquidity in a single transaction.
/// @dev Tokens are never held between calls — every function transfers in,
///      interacts with the router, and transfers any leftovers back in the
///      same transaction.
contract SwapApp is ReentrancyGuard, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Address of the Uniswap V2 Router.
    address public immutable V2Router02Address;

    /// @notice USDT token address used in addLiquidity.
    address public immutable USDT;

    /// @notice DAI token address used in addLiquidity.
    address public immutable DAI;

    /// @notice Uniswap V2 Factory address used to resolve LP token addresses.
    address public immutable UniswapFactoryAddress;

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted on a successful token swap.
    /// @param tokenIn  Address of the token sent by the user.
    /// @param tokenOut Address of the token received by the user.
    /// @param amountIn Exact input amount.
    /// @param amountOut Actual output amount received.
    event SwapTokens(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /// @notice Emitted when liquidity is successfully added to the USDT/DAI pool.
    /// @param user          Account that provided liquidity and received the LP tokens.
    /// @param token0        First token of the pair (USDT).
    /// @param token1        Second token of the pair (DAI).
    /// @param lpTokenAmount LP tokens minted and sent to the caller.
    event AddLiquidity(address indexed user, address indexed token0, address indexed token1, uint256 lpTokenAmount);

    /// @notice Emitted when liquidity is removed from the USDT/DAI pool.
    /// @param lpAmount Amount of LP tokens burned.
    /// @param to       Recipient of the returned USDT and DAI.
    event RemoveLiquidity(uint256 lpAmount, address indexed to);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Deploys SwapApp and sets immutable addresses.
    /// @param v2Router_ Address of the Uniswap V2 Router.
    /// @param factory_  Address of the Uniswap V2 Factory.
    /// @param usdt_     Address of the USDT token.
    /// @param dai_      Address of the DAI token.
    constructor(address v2Router_, address factory_, address usdt_, address dai_) Ownable(msg.sender) {
        if (v2Router_ == address(0)) revert ZeroAddress();
        if (factory_ == address(0)) revert ZeroAddress();
        if (usdt_ == address(0)) revert ZeroAddress();
        if (dai_ == address(0)) revert ZeroAddress();
        if (usdt_ == dai_) revert IdenticalTokens();
        V2Router02Address = v2Router_;
        UniswapFactoryAddress = factory_;
        USDT = usdt_;
        DAI = dai_;
    }

    // ─── Owner functions ──────────────────────────────────────────────────────

    /// @notice Pauses swaps and liquidity additions.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── External functions ───────────────────────────────────────────────────

    /// @notice Swaps an exact amount of `path_[0]` for as many `path_[last]` tokens
    ///         as possible, sending the output directly to the caller.
    /// @dev Pulls `amountIn_` from the caller, approves the router, then calls
    ///      `swapExactTokensForTokens`. No tokens remain in the contract after the call.
    /// @param amountIn_    Exact amount of input tokens to send.
    /// @param amountOutMin_ Minimum acceptable output amount (slippage guard).
    /// @param path_        Ordered token route, e.g. [USDT, DAI].
    /// @param deadline_    Unix timestamp after which the transaction reverts.
    /// @return amountOut   Actual amount of output tokens received by the caller.
    function swapTokens(uint256 amountIn_, uint256 amountOutMin_, address[] memory path_, uint256 deadline_)
        public
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        if (amountIn_ == 0) revert ZeroAmount();
        if (path_.length < 2) revert InvalidPath();

        IERC20(path_[0]).safeTransferFrom(msg.sender, address(this), amountIn_);

        amountOut = _swap(amountIn_, amountOutMin_, path_, msg.sender, deadline_);

        emit SwapTokens(path_[0], path_[path_.length - 1], amountIn_, amountOut);
    }

    /// @notice Converts `amountUSDT_` USDT into a USDT/DAI liquidity position.
    /// @dev Flow:
    ///      1. Pulls `amountUSDT_` USDT from the caller.
    ///      2. Swaps half into DAI (kept inside this contract).
    ///      3. Adds both halves as liquidity; LP tokens go to the caller.
    ///      4. Returns any unused USDT or DAI to the caller.
    /// @param amountUSDT_   Total USDT to deposit (half is swapped, half stays as USDT).
    /// @param amountOutMin_ Minimum DAI to receive from the internal swap.
    /// @param amountAMin_   Minimum USDT accepted by the router when adding liquidity.
    /// @param amountBMin_   Minimum DAI accepted by the router when adding liquidity.
    /// @param deadline_     Unix timestamp after which the transaction reverts.
    function addLiquidity(
        uint256 amountUSDT_,
        uint256 amountOutMin_,
        uint256 amountAMin_,
        uint256 amountBMin_,
        uint256 deadline_
    ) external nonReentrant whenNotPaused {
        if (amountUSDT_ == 0) revert ZeroAmount();

        uint256 half = amountUSDT_ / 2;
        uint256 usdtForPool = amountUSDT_ - half;

        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amountUSDT_);

        uint256 daiReceived = _swap(half, amountOutMin_, _usdtDaiPath(), address(this), deadline_);
        uint256 lpAmount = _provideLiquidity(usdtForPool, daiReceived, amountAMin_, amountBMin_, deadline_);

        emit AddLiquidity(msg.sender, USDT, DAI, lpAmount);
    }

    /// @notice Burns LP tokens and returns the underlying USDT and DAI to `to_`.
    /// @dev Pulls LP tokens from the caller, approves the router, then calls
    ///      `removeLiquidity`. The LP token address is resolved via the factory's
    ///      `getPair` so no extra storage is needed.
    /// @param liquidityAmount_ Amount of LP tokens to burn.
    /// @param amountAMin_      Minimum USDT to receive (slippage guard).
    /// @param amountBMin_      Minimum DAI to receive (slippage guard).
    /// @param to_              Recipient of the returned tokens.
    /// @param deadline_        Unix timestamp after which the transaction reverts.
    function removeLiquidity(
        uint256 liquidityAmount_,
        uint256 amountAMin_,
        uint256 amountBMin_,
        address to_,
        uint256 deadline_
    ) external nonReentrant whenNotPaused {
        if (liquidityAmount_ == 0) revert ZeroLiquidity();
        if (to_ == address(0)) revert ZeroAddress();

        address lpToken = IFactory(UniswapFactoryAddress).getPair(USDT, DAI);
        if (lpToken == address(0)) revert PairNotFound();

        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), liquidityAmount_);
        IERC20(lpToken).forceApprove(V2Router02Address, liquidityAmount_);

        IV2Router02(V2Router02Address)
            .removeLiquidity(USDT, DAI, liquidityAmount_, amountAMin_, amountBMin_, to_, deadline_);

        emit RemoveLiquidity(liquidityAmount_, to_);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// @notice Approves the router and executes a token swap.
    /// @dev Assumes `amountIn` of `path[0]` is already held by this contract.
    /// @param amountIn    Amount of input token to swap.
    /// @param amountOutMin Minimum acceptable output (slippage guard).
    /// @param path        Ordered token route.
    /// @param to          Recipient of the output tokens.
    /// @param deadline    Unix timestamp deadline.
    /// @return Output amount received.
    function _swap(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline)
        internal
        returns (uint256)
    {
        IERC20(path[0]).forceApprove(V2Router02Address, amountIn);
        uint256[] memory amounts =
            IV2Router02(V2Router02Address).swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
        return amounts[amounts.length - 1];
    }

    /// @notice Adds `usdtAmount` and `daiAmount` as liquidity and refunds unused tokens to the caller.
    /// @dev Allowances are reset to zero afterwards so no residual approval remains on the router.
    /// @param usdtAmount   USDT offered to the pool.
    /// @param daiAmount    DAI offered to the pool.
    /// @param amountAMin   Minimum USDT accepted by the router.
    /// @param amountBMin   Minimum DAI accepted by the router.
    /// @param deadline     Unix timestamp deadline.
    /// @return lpAmount    LP tokens minted to the caller.
    function _provideLiquidity(
        uint256 usdtAmount,
        uint256 daiAmount,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) internal returns (uint256 lpAmount) {
        IERC20(USDT).forceApprove(V2Router02Address, usdtAmount);
        IERC20(DAI).forceApprove(V2Router02Address, daiAmount);

        uint256 usedUSDT;
        uint256 usedDAI;
        (usedUSDT, usedDAI, lpAmount) = IV2Router02(V2Router02Address)
            .addLiquidity(USDT, DAI, usdtAmount, daiAmount, amountAMin, amountBMin, msg.sender, deadline);

        IERC20(USDT).forceApprove(V2Router02Address, 0);
        IERC20(DAI).forceApprove(V2Router02Address, 0);

        _refund(USDT, usdtAmount - usedUSDT);
        _refund(DAI, daiAmount - usedDAI);
    }

    /// @notice Sends `amount` of `token` to the caller when it is non-zero.
    /// @param token  Token to refund.
    /// @param amount Amount to refund.
    function _refund(address token, uint256 amount) internal {
        if (amount > 0) IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @notice Builds the [USDT, DAI] swap path.
    /// @return path Two-element route from USDT to DAI.
    function _usdtDaiPath() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
    }
}
