# gemba-testnet-1 — live contract deployments (DEX)

> Live on **gemba-testnet-1** (EVM chainId **821207**), deployed 2026-06-06 by the
> `founder` test account. Explorer: **https://testnet.gembascan.io** (append `/address/<CA>`).
> These are **developer DEX tooling** (GembaSwap = Uniswap V2 renamed 1:1) — NOT
> project-operated, NOT for GMB; see `contracts/src/dex/README.md` and `CLAUDE.md` §9.

## Contract addresses (CA)

| Contract | Address |
|---|---|
| `WGMB` (wrapped native GMB) | `0xc20BF44AB4AfC63816564e5bfe78Fa5332D98B50` |
| `GembaSwapFactory` (Uniswap V2 factory) | `0x2f08C50dE1B63b888Ff9327b500B49318e686cA7` |
| `GembaSwapRouter02` (Uniswap V2 router, full ABI) | `0xea5a93fDb123ae8016E9D79d028D1c9232A7cD2F` |
| `GembaNativePoolFactory` | `0x4FDbd5fbDc7661FC547389F6b389cc07Fc5207A5` |
| `LiquidityLocker` | `0x18926d6f0BBCC9c4CD067cD7fACec77C460dD9A8` |
| `DemoToken` (DEMO, example dev token) | `0xd14Da7b04DA77ed925C68CB67b8bAE025f754D58` |
| `DemoFeeToken` (FEEDEMO, 5% fee-on-transfer) | `0x9A8eB2f34f342BBa4292F4b1E5110DC61c914888` |
| DEMO/WGMB **pair** (GembaSwap) | `0x32dd08eABa1f89A36d732896F4b89e3d3Fd4A3Fa` |
| DEMO **native pool** (pure GMB) | `0x2208B35385D36Eec9B5D1dd3888c18fC9A3D88f2` |

## What was exercised live (all confirmed on-chain)

- **GembaSwap (WGMB path):** add 3 GMB + 1000 DEMO liquidity → buy DEMO with native GMB →
  sell DEMO for native GMB → **lock half the LP** in `LiquidityLocker` (~4 min) → remove
  (withdraw) the other half. ("со WGMB")
- **GembaNativePool (pure native, no WGMB):** create pool → add 3 GMB + 1000 DEMO → buy
  with pure GMB → sell for pure GMB. ("со GMB")
- **Fee-on-transfer token:** add `FEEDEMO`/GMB liquidity → buy + sell via the router's
  `...SupportingFeeOnTransferTokens` functions.

(The full suite is also covered by 92 Foundry tests — `contracts/test/Dex.t.sol`.)

## ⚠️ Chain finding hit during this deploy — block gas limit (FIXED in code)

The live exercise could not run as a single `forge script` batch because of the **10,000,000
block gas limit** (CometBFT `consensus_params.block.max_gas`). A single GembaSwap router
deploy is ~4–5M and a CREATE2 pair deploy ~2.5M, so forge's per-tx gas (estimate × multiplier)
either under-ran swaps (OOG) or, when raised, exceeded the 10M block cap. **Root cause + fix:**
`docs/risks.md` ADR-012 and the genesis generator (`chain/scripts/lib.sh`, now **100M**).
Workaround used here: `cast send --gas-limit 8000000` per op (explicit, under the live 10M cap).
**The live testnet still has 10M** until raised by governance — see
`docs/runbooks/raise-block-gas-limit.md`.

## Verification — TODO

Blockscout contract verification needs **no API key** (open). Pending per contract via
`forge verify-contract <CA> <Contract> --verifier blockscout --verifier-url
https://testnet.gembascan.io/api/` (GembaSwap core/periphery compile at 0.5.16/0.6.6).
