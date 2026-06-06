# GembaSwap — developer DEX tooling (1:1 Uniswap V2, renamed)

> **Positioning (read first).** GembaBlockchain itself **does not operate a DEX** and
> **provides no liquidity for GMB** — it is built for use, not speculation/trading
> (`CLAUDE.md` §2, §8, §16). These contracts are **permissionless, optional
> infrastructure that ecosystem developers deploy for their OWN ERC-20 tokens** — to
> bootstrap and test their token's liquidity. They are **not** a project-operated
> canonical GMB market. On a permissionless chain anyone can deploy a DEX (§16.1).

## `gembaswap/` — the AMM is the official Uniswap V2, renamed 1:1

`src/dex/gembaswap/` is a **byte-for-byte port of Uniswap V2** (core 0.5.16 +
periphery 0.6.6) with **only** two changes: every identifier `UniswapV2` → `GembaSwap`
(contracts, libraries, interfaces, revert-string prefixes) and the pair init-code-hash
constant in `GembaSwapLibrary.pairFor` recomputed to match our compiled `GembaSwapPair`
(standard when deploying Uniswap V2 on a new chain). The logic, math, fees (0.30%),
and the **full Router02 ABI** are identical to mainnet Uniswap V2 — nothing abbreviated.

| Contract | = Uniswap V2 | Role |
|---|---|---|
| `gembaswap/core/GembaSwapFactory` | `UniswapV2Factory` | creates one pair per ERC-20 pair (CREATE2) |
| `gembaswap/core/GembaSwapPair` | `UniswapV2Pair` | the x·y=k pool; is the ERC-20 LP token |
| `gembaswap/core/GembaSwapERC20` | `UniswapV2ERC20` | LP token base (EIP-2612 permit) |
| `gembaswap/periphery/GembaSwapRouter02` | `UniswapV2Router02` | **full** periphery: add/remove liquidity (+ETH), all swap variants (exact-in/out, ETH, **fee-on-transfer supporting**), quote/getAmountsOut/In |
| `gembaswap/periphery/GembaSwapLibrary` | `UniswapV2Library` | pairFor/quote math (patched init hash) |

`Router02.WETH()` is our `WGMB` (wrapped native GMB). Fee-on-transfer tokens are
supported via the standard `...SupportingFeeOnTransferTokens` functions.

## Other contracts (Gemba-original)

| Contract | What it is |
|---|---|
| `WGMB` | Wrapped GMB (WETH9-style, 1:1) — the `WETH` for GembaSwapRouter02. |
| **`GembaNativePool`** (+ `GembaNativePoolFactory`) | A **pure-native** GMB↔token AMM that holds native GMB **directly (no WGMB)**, with its own add/remove/swap. The "no wrapper" option. |
| `LiquidityLocker` | Time-locks LP tokens (withdraw-after-unlock, extend-only; anti-rug). No admin. |

## Native GMB — two ways

1. **GembaSwapRouter02 + WGMB** (standard, Uniswap-SDK-compatible): the pool holds WGMB;
   the router's `addLiquidityETH`/`swapExactETHForTokens`/`swapExactTokensForETH` (and the
   fee-on-transfer variants) wrap/unwrap so users handle native GMB.
2. **`GembaNativePool`** (pure native): the pool holds native GMB directly — no WGMB.

Tests: `test/Dex.t.sol` (deploys GembaSwap via `vm.deployCode`, exercises ERC-20, native,
and fee-on-transfer swaps + the native pool + the locker). Not project-operated.
