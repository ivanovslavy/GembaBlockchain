# GembaSwap — developer DEX tooling (a modified Uniswap V2)

> **Positioning (read first).** GembaBlockchain itself **does not operate a DEX** and
> **provides no liquidity for GMB** — it is built for use, not speculation/trading
> (`CLAUDE.md` §2, §8, §16). These contracts are **permissionless, optional
> infrastructure that ecosystem developers deploy for their OWN ERC-20 tokens** — to
> bootstrap and test their token's liquidity. They are **not** a project-operated
> canonical GMB market. On a permissionless chain anyone can deploy a DEX (§16.1).

## Licence — this directory is GPL-3.0-or-later, the rest of the repo is Apache-2.0

`src/dex/gembaswap/` is a **modified copy of Uniswap V2** and is distributed under
**GPL-3.0-or-later**, the licence of the original (Uniswap V2 core, periphery and
solidity-lib, © 2020 Uniswap Labs and the Uniswap V2 authors). The full text is in
[`gembaswap/LICENSE`](gembaswap/LICENSE); the attribution and the complete list of changes
are in [`gembaswap/NOTICE`](gembaswap/NOTICE), and every file carries its own SPDX line and
header. Everything else in this repository — including the Gemba-original contracts in this
`dex/` folder (`WGMB`, `GembaNativePool*`, `LiquidityLocker`, `examples/`) — stays
**Apache-2.0**. GembaSwap is not affiliated with or endorsed by Uniswap Labs.

## `gembaswap/` — the AMM is Uniswap V2, renamed

`src/dex/gembaswap/` is **Uniswap V2** (core 0.5.16 + periphery 0.6.6) with **only** these
changes (full list in `gembaswap/NOTICE`): every identifier `UniswapV2` → `GembaSwap`
(contracts, libraries, interfaces, revert-string prefixes); the LP token is named
**`GembaSwap V2` / `GSWAP-V2`** instead of `Uniswap V2` / `UNI-V2`; npm imports became
relative imports; and the pair init-code-hash constant in `GembaSwapLibrary.pairFor` is
recomputed to match our compiled `GembaSwapPair` (standard when deploying Uniswap V2 on a new
chain) — today `0xb154cd520d99f29f2d52a8c4b7b5236bd8a368ae9030110bf24a28b28b19d83f`. The logic,
math, fees (0.30%), and the **full Router02 ABI** are identical to mainnet Uniswap V2 —
nothing abbreviated.

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
