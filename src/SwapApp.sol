// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./interfaces/IV2Router02.sol";
import "./interfaces/IFactory.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

// ─── Errors ───────────────────────────────────────────────────────────────────

/// @notice Thrown when a constructor address argument is the zero address.
error ZeroAddress();

/// @notice Thrown when amountIn_ is zero.
error ZeroAmount();

/// @notice Thrown when the swap path has fewer than two tokens.
error InvalidPath();

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

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted on a successful token swap.
    /// @param tokenIn  Address of the token sent by the user.
    /// @param tokenOut Address of the token received by the user.
    /// @param amountIn Exact input amount.
    /// @param amountOut Actual output amount received.
    event SwapTokens(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @notice Emitted when liquidity is successfully added to the USDT/DAI pool.
    /// @param token0       First token of the pair (USDT).
    /// @param token1       Second token of the pair (DAI).
    /// @param lpTokenAmount LP tokens minted and sent to the caller.
    event AddLiquidity(address indexed token0, address indexed token1, uint256 lpTokenAmount);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Deploys SwapApp and sets immutable addresses.
    /// @param v2Router_ Address of the Uniswap V2 Router.
    /// @param usdt_     Address of the USDT token.
    /// @param dai_      Address of the DAI token.
    constructor(address v2Router_, address usdt_, address dai_) Ownable(msg.sender) {
        if (v2Router_ == address(0)) revert ZeroAddress();
        if (usdt_ == address(0)) revert ZeroAddress();
        if (dai_ == address(0)) revert ZeroAddress();
        V2Router02Address = v2Router_;
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
    function swapTokens(
        uint256 amountIn_,
        uint256 amountOutMin_,
        address[] memory path_,
        uint256 deadline_
    ) public nonReentrant whenNotPaused returns (uint256 amountOut) {
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
        uint256 remaining = amountUSDT_ - half; // handles odd amounts

        // Pull all USDT from caller
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amountUSDT_);

        // Swap half USDT → DAI; output stays in this contract
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
        uint256 daiReceived = _swap(half, amountOutMin_, path, address(this), deadline_);

        // Approve router to spend remaining USDT and received DAI
        IERC20(USDT).approve(V2Router02Address, remaining);
        IERC20(DAI).approve(V2Router02Address, daiReceived);

        (uint256 usedUSDT, uint256 usedDAI, uint256 lpAmount) = IV2Router02(V2Router02Address)
            .addLiquidity(
                USDT,
                DAI,
                remaining,
                daiReceived,
                amountAMin_,
                amountBMin_,
                msg.sender,
                deadline_
            );

        // Return leftover tokens to caller
        uint256 leftoverUSDT = remaining - usedUSDT;
        uint256 leftoverDAI = daiReceived - usedDAI;
        if (leftoverUSDT > 0) IERC20(USDT).safeTransfer(msg.sender, leftoverUSDT);
        if (leftoverDAI > 0) IERC20(DAI).safeTransfer(msg.sender, leftoverDAI);

        emit AddLiquidity(USDT, DAI, lpAmount);
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
    function _swap(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal returns (uint256) {
        IERC20(path[0]).approve(V2Router02Address, amountIn);
        uint256[] memory amounts = IV2Router02(V2Router02Address).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        return amounts[amounts.length - 1];
    }
}
