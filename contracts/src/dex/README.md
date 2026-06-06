# GembaSwap — optional developer DEX tooling

> **Positioning (read first).** GembaBlockchain itself **does not operate a DEX** and
> **provides no liquidity for GMB** — it is built for use, not speculation/trading
> (`CLAUDE.md` §2, §8, §16). These contracts are **permissionless, optional
> infrastructure that ecosystem developers can deploy for their OWN ERC-20 tokens** —
> to bootstrap and test their token's liquidity. They are **not** a project-operated
> canonical GMB market. On a permissionless chain anyone can deploy a DEX (§16.1); this
> is just a clean, audited-style reference so developers don't have to write their own.

A Uniswap-V2-style constant-product (x·y=k) AMM ported to Solidity 0.8.x with the
project's security standards, plus a "pure native GMB" pool variant and a liquidity
locker. 0.30% swap fee to LPs. 90 Foundry tests pass (`test/Dex.t.sol`).

## Contracts

| Contract | What it is |
|---|---|
| `WGMB` | Wrapped GMB (WETH9-style). Native GMB isn't an ERC-20; wrap 1:1 so AMMs/ERC-20 tooling can hold the GMB side. |
| `GembaSwapFactory` | Deploys one `GembaSwapPair` per ERC-20 pair (permissionless). |
| `GembaSwapPair` | The ERC-20↔ERC-20 constant-product pool; is itself the ERC-20 LP token. |
| `GembaSwapRouter` | Periphery: `addLiquidity`/`removeLiquidity`, multi-hop swaps, **plus native-GMB convenience** (`addLiquidityGMB`, `swapExactGMBForTokens`, `swapExactTokensForGMB`) that wrap/unwrap WGMB at the edges so users handle pure native GMB. |
| **`GembaNativePool`** | **The "pure native GMB" variant** — a self-contained GMB↔token pool that **holds native GMB directly (no WGMB)**, with its own `addLiquidity`/`removeLiquidity`/`swapExactNativeForTokens`/`swapExactTokensForNative`. No router needed. |
| `GembaNativePoolFactory` | One native pool per token (discoverability). |
| `LiquidityLocker` | Time-locks ERC-20 (typically LP) tokens until a timestamp; owner can only withdraw after unlock and only **extend** (anti-rug). No admin, no path to move locked tokens. |

## Native GMB — two ways

Native GMB is not an ERC-20 (no `balanceOf`/`transfer`), so an AMM pool needs an
ERC-20 handle for the GMB side. Two options:

1. **WGMB + router** (standard, Uniswap-SDK-compatible). The **pool** holds WGMB; the
   **router** wraps/unwraps so the **user** deals in pure native GMB. Use this for
   ERC-20↔ERC-20 pairs and standard tooling.
2. **`GembaNativePool`** (pure native). The pool holds native GMB directly — no WGMB
   contract involved at all. Simplest for a single GMB↔token pool; not Uniswap-SDK
   shaped.

## Notes / omissions (kept minimal on purpose)

- No TWAP price oracle and no protocol fee (the `feeTo` Uniswap mechanism) — not needed
  for dev tooling; LPs get the full 0.30%.
- Pair address discovery is via `factory.getPair` (a call), not CREATE2 init-code-hash.
- Not deployed or operated by the project. A developer deploys what they need.
