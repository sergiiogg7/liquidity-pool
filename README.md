# LiquidityPool

Thin Uniswap V2 wrapper for ERC-20 tokens on Arbitrum. One contract, `SwapApp`, for swaps, adding liquidity and removing liquidity on a USDT/DAI pair.

## Overview

- **Swap tokens**: exact-input swap over any path. Output goes to the caller.
- **Add liquidity**: the caller provides only USDT. The contract swaps half to DAI, adds both as liquidity (LP tokens minted to the caller) and refunds anything unused.
- **Remove liquidity**: the caller approves LP tokens, the contract burns them through the router and sends USDT and DAI to a chosen recipient.

```
User --approve--> SwapApp --> Uniswap V2 Router
                    |
                    +-- swapTokens()
                    +-- addLiquidity()
                    +-- removeLiquidity()
```

The contract is designed to hold no tokens between calls: tokens are pulled in, approved to the router and forwarded to the caller in the same transaction.

## Contract Reference

```solidity
function swapTokens(uint256 amountIn_, uint256 amountOutMin_, address[] memory path_, uint256 deadline_)
    public returns (uint256 amountOut);

function addLiquidity(
    uint256 amountUSDT_,
    uint256 amountOutMin_,
    uint256 amountAMin_,
    uint256 amountBMin_,
    uint256 deadline_
) external;

function removeLiquidity(
    uint256 liquidityAmount_,
    uint256 amountAMin_,
    uint256 amountBMin_,
    address to_,
    uint256 deadline_
) external;

function pause() external;   // owner only
function unpause() external; // owner only
```

| Parameter | Description |
|---|---|
| `amountIn_` / `amountUSDT_` | Input amount. For `addLiquidity`, half is swapped to DAI |
| `amountOutMin_` | Minimum output of the swap leg (slippage guard) |
| `path_` | Token route, for example `[USDT, DAI]` |
| `amountAMin_` / `amountBMin_` | Minimum USDT / DAI accepted by the router |
| `liquidityAmount_` | LP tokens to burn |
| `to_` | Recipient of the underlying tokens (cannot be zero) |
| `deadline_` | Unix timestamp after which the call reverts |

Custom errors: `ZeroAddress`, `IdenticalTokens`, `PairNotFound`, `ZeroAmount`, `InvalidPath`, `ZeroLiquidity`.

## Security

| Measure | Location |
|---|---|
| Reentrancy guard on every user function | `SwapApp` (`nonReentrant`) |
| Pausable, owner can halt all user functions | `SwapApp.pause`, `SwapApp.unpause` |
| Two-step ownership transfer | `Ownable2Step` |
| `SafeERC20` transfers and `forceApprove` (works with USDT-style tokens) | `SwapApp` |
| Allowances to the router reset to zero after `addLiquidity` | `SwapApp._provideLiquidity` |
| Constructor validation: zero addresses, identical tokens | `SwapApp` constructor |
| LP pair existence and recipient checked before burning | `SwapApp.removeLiquidity` |
| Custom errors only, no `require` strings | `SwapApp.sol` |
| Slither in CI | `slither.config.json` |

See [SECURITY.md](SECURITY.md) for assumptions and limits.

## Testing

Tests use mock routers, factories and tokens, so no fork is required.

| Suite | Type |
|---|---|
| `SwapApp.t.sol` | Unit: constructor, pause, ownership, swap, add liquidity |
| `SwapAppLiquidity.t.sol` | Unit and fuzz: remove liquidity, constructor checks, USDT-style token, reentrancy attacker |
| `SwapAppFuzz.t.sol` | Fuzz: amounts and fund retention |
| `SwapAppInvariant.t.sol` | Invariant: contract never holds USDT or DAI, never leaves an allowance on the router |

```bash
forge test                                              # all tests
forge coverage --no-match-coverage "script|test"        # coverage of src/
forge snapshot --check                                  # gas regression check
```

CI runs `forge fmt --check`, `forge build --sizes`, `forge test` (profile `ci`, higher fuzz runs), a 95% line-coverage gate on `src/`, `forge snapshot --check` and Slither.

## Getting Started

```bash
git clone --recursive https://github.com/sergiiogg7/liquidity-pool.git
cd liquidity-pool
forge build
forge test
```

Deploy (Arbitrum addresses are read from the environment, see `.env.example`):

```bash
cp .env.example .env   # fill in values
source .env
forge script script/Deploy.s.sol --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Tech Stack

- Solidity 0.8.24, Foundry (`via_ir`, optimizer)
- OpenZeppelin v5: `SafeERC20`, `ReentrancyGuard`, `Ownable2Step`, `Pausable`
- Uniswap V2 router and factory on Arbitrum

## Project Structure

```
liquidity-pool/
├── src/
│   ├── SwapApp.sol
│   └── interfaces/          # IV2Router02, IFactory
├── test/                    # unit, fuzz and invariant suites with mocks
├── script/Deploy.s.sol
├── slither.config.json
├── SECURITY.md
└── foundry.toml
```

## License

MIT
