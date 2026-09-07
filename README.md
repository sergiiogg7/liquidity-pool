# LiquidityPool

Uniswap V2 liquidity pool manager for ERC-20 tokens on Arbitrum. Single contract for swaps, adding liquidity, and removing liquidity.

## Overview

LiquidityPool abstracts Uniswap V2 complexity with three operations:

- **Swap tokens** — Direct token-to-token exchange
- **Add liquidity** — Deposit and receive LP tokens (internally 50/50 split via swap)
- **Remove liquidity** — Burn LP tokens, get underlying tokens back

```
User ──approve──▶ LiquidityPool ──▶ Uniswap V2 Router
                       │
                       ├─ swapTokens()
                       ├─ addLiquidity()
                       └─ removeLiquidity()
```

## Getting Started

```bash
git clone https://github.com/<your-username>/liquidity-pool.git
cd liquidity-pool
forge install
```

## Build

```bash
forge build
```

## Test

Tests run against an Arbitrum mainnet fork:

```bash
forge test --fork-url $ARBITRUM_RPC_URL -vvv
```

## Operations

### 1. Swap Tokens

Direct token-to-token trade.

```solidity
address[] memory path = new address[](2);
path[0] = USDT;
path[1] = DAI;

IERC20(USDT).approve(address(app), amountIn);

uint256 amountOut = app.swapTokens(
    amountIn,
    amountOutMin,
    path,
    msg.sender,
    deadline
);
```

### 2. Add Liquidity

Deposit tokens into the pool. Splits input 50/50: half swaps to the paired token, both added to pool.

```solidity
address[] memory path = new address[](2);
path[0] = USDT;
path[1] = DAI;

IERC20(USDT).approve(address(app), amountIn);

app.addLiquidity(
    amountIn,        // Total USDT (half → swap, half → pool)
    amountOutMin,    // Min DAI from swap
    path,
    amountAMin,      // Min USDT liquidity
    amountBMin,      // Min DAI liquidity
    deadline
);
// Returns LP tokens to msg.sender
```

### 3. Remove Liquidity

Burn LP tokens and receive underlying tokens.

```solidity
address lpTokenAddress = IFactory(app.UniswapFactoryAddress())
    .getPair(USDT, DAI);

IERC20(lpTokenAddress).approve(address(app), lpAmount);

app.removeLiquidity(
    lpAmount,
    amountAMin,      // Min USDT returned
    amountBMin,      // Min DAI returned
    msg.sender,
    deadline
);
```

## Contract Interface

```solidity
function swapTokens(
    uint256 amountIn_,
    uint256 amountOutMin_,
    address[] memory path_,
    address to_,
    uint256 deadline_
) external returns (uint256)

function addLiquidity(
    uint256 amountIn_,
    uint256 amountOutMin_,
    address[] memory path_,
    uint256 amountAMin_,
    uint256 amountBMin_,
    uint256 deadline_
) external

function removeLiquidity(
    uint256 liquidityAmount_,
    uint256 amountAMin_,
    uint256 amountBMin_,
    address to_,
    uint256 deadline_
) external
```

| Parameter       | Description                                    |
|-----------------|------------------------------------------------|
| `amountIn_`     | Input amount (whole for swap, split for add)   |
| `amountOutMin_` | Minimum output from swap (slippage guard)      |
| `path_`         | Token route, e.g. `[USDT, DAI]`                |
| `to_`           | Recipient address                              |
| `amountAMin_`   | Minimum first token (liquidity)                 |
| `amountBMin_`   | Minimum second token (liquidity)                |
| `deadline_`     | Transaction deadline (Unix timestamp)           |
| `liquidityAmount_` | LP tokens to burn                           |

## Tech Stack

- **Solidity** `^0.8.24`
- **Foundry** — Build, test, deploy toolkit
- **OpenZeppelin v5** — `SafeERC20`, `IERC20`
- **Uniswap V2** — DEX router for token swaps
- **Arbitrum** — Target deployment network

## Project Structure

```
liquidity-pool/
├── src/
│   ├── SwapApp.sol              # Liquidity pool manager
│   └── interfaces/
│       ├── IV2Router02.sol      # Uniswap V2 Router
│       └── IFactory.sol         # Uniswap V2 Factory
├── test/
│   └── SwapApp.t.sol            # Fork tests (Arbitrum)
├── lib/
│   ├── forge-std/               # Foundry testing
│   └── openzeppelin-contracts/  # ERC-20 utilities
└── foundry.toml                 # Config
```

## License

MIT
