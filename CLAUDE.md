# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Foundry project (solc 0.8.24, `via_ir` + optimizer enabled). Dependencies (`forge-std`, `openzeppelin-contracts`) are git submodules in `lib/` — run `forge install` / clone with `--recursive`.

```bash
forge build
forge test -vvv                                   # what CI runs (mock-based, no fork needed)
forge test --match-test <name> -vvvv              # single test
forge test --match-path test/SwapAppFuzz.t.sol    # single file
forge test --fork-url $ARBITRUM_RPC_URL -vvv      # optionally against an Arbitrum mainnet fork
forge fmt --check                                 # CI enforces formatting
```

CI (`.github/workflows/test.yml`) runs `forge fmt --check`, `forge build --sizes`, `forge test -vvv`.

## Architecture

Everything lives in one contract, `src/SwapApp.sol` (`SwapApp`): a thin Uniswap V2 wrapper (Arbitrum) with `swapTokens`, `addLiquidity`, `removeLiquidity`. It inherits OpenZeppelin `ReentrancyGuard`, `Ownable2Step`, `Pausable`; all three user functions are `nonReentrant whenNotPaused`, and the owner can `pause`/`unpause`.

- Router, factory, USDT and DAI addresses are constructor-set immutables. `addLiquidity` and `removeLiquidity` are hard-wired to the **USDT/DAI pair**; only `swapTokens` accepts an arbitrary path.
- The contract is designed to hold no tokens between calls: it pulls tokens in, approves the router, and forwards outputs/leftovers to the caller in the same tx.
- `addLiquidity` takes only USDT: it swaps half to DAI (held in the contract), adds both as liquidity (LP tokens minted directly to `msg.sender`), then refunds unused USDT/DAI.
- `removeLiquidity` resolves the LP token via `IFactory.getPair(USDT, DAI)` rather than storing it, pulls LP tokens from the caller, and has the router send the underlying tokens to `to_`.
- Custom errors (`ZeroAddress`, `ZeroAmount`, `InvalidPath`, `ZeroLiquidity`) are file-level declarations in `SwapApp.sol`, not inside the contract.
- `src/interfaces/` holds minimal local `IV2Router02` and `IFactory`. OpenZeppelin is imported by relative path (`../lib/openzeppelin-contracts/...`), not via remappings.

## Tests

`test/SwapApp.t.sol`, `SwapAppFuzz.t.sol`, `SwapAppInvariant.t.sol` each define their own mock ERC20 / router (names prefixed per file, e.g. `InvMockERC20`) to avoid collisions — keep that when adding mocks. The mock routers enforce `deadline` and min-amount checks so slippage/expiry paths can be tested without a fork.

## README drift

`README.md` is out of date versus the code: it shows `swapTokens` with a `to_` argument, `addLiquidity` with a `path_` argument, and the router/factory as public getters under different names. Trust `src/SwapApp.sol` for the real signatures (`swapTokens(amountIn, amountOutMin, path, deadline)` sends output to `msg.sender`; `addLiquidity(amountUSDT, amountOutMin, amountAMin, amountBMin, deadline)`).
