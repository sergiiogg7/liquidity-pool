# Security

## Status

This repository has not been externally audited. Do not use it with real funds without an independent review.

## Assumptions

- The router and factory are the genuine Uniswap V2 contracts. They are set at deployment and cannot be changed.
- `addLiquidity` and `removeLiquidity` only operate on the USDT/DAI pair. `swapTokens` accepts any path, so callers choose the tokens they trust.
- Fee-on-transfer tokens are not supported by `swapTokens`.
- Tokens sent directly to the contract are not recoverable. The contract has no rescue function by design.

## Invariants

- The contract holds no USDT or DAI between calls.
- The contract leaves no allowance on the router after a call.

## Reporting a vulnerability

Open a private security advisory on the GitHub repository. Do not open a public issue.
