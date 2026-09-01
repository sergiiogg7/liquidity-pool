# SwapApp

A minimal Uniswap V2 swap wrapper for ERC-20 token swaps on Arbitrum.

## Overview

SwapApp is a thin smart contract that abstracts the complexity of interacting with Uniswap V2. Users approve tokens to the contract, call `swapTokens()`, and receive output tokens directly in their wallet — no tokens are held by the contract between swaps.

```
User ──approve──▶ SwapApp ──swapExactTokensForTokens──▶ Uniswap V2 Router
                  ▲                                              │
                  └──────────── Output Tokens ◀──────────────────┘
```

## Getting Started

```bash
# Clone and install dependencies
git clone https://github.com/<your-username>/swap-app.git
cd swap-app
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

## Usage

1. **Approve** the SwapApp contract to spend your input tokens.
2. **Call** `swapTokens()` with the desired amount, minimum output, token path, and deadline.

```solidity
address[] memory path = new address[](2);
path[0] = USDT;  // token in
path[1] = DAI;   // token out

IERC20(USDT).approve(address(swapApp), amountIn);

swapApp.swapTokens(
    amountIn,
    amountOutMin,
    path,
    block.timestamp
);
```

## Contract Interface

```solidity
function swapTokens(
    uint256 amountIn_,
    uint256 amountOutMin_,
    address[] memory path_,
    uint256 deadline_
) external
```

| Parameter      | Description                                         |
|----------------|-----------------------------------------------------|
| `amountIn_`    | Amount of input tokens to swap                      |
| `amountOutMin_`| Minimum amount of output tokens (slippage保护)      |
| `path_`        | Token route, e.g. `[USDT, DAI]`                     |
| `deadline_`    | Transaction deadline (Unix timestamp)               |

## Tech Stack

- **Solidity** `^0.8.24`
- **Foundry** — Build, test, deploy toolkit
- **OpenZeppelin v5** — `SafeERC20`, `IERC20`
- **Uniswap V2** — DEX router for token swaps
- **Arbitrum** — Target deployment network

## Project Structure

```
swap-app/
├── src/
│   ├── SwapApp.sol              # Main swap wrapper contract
│   └── interfaces/
│       └── IV2Router02.sol      # Uniswap V2 Router interface
├── test/
│   └── SwapApp.t.sol            # Fork tests on Arbitrum
├── lib/
│   ├── forge-std/               # Foundry testing library
│   └── openzeppelin-contracts/  # ERC-20 utilities
└── foundry.toml                 # Foundry configuration
```

## License

MIT
