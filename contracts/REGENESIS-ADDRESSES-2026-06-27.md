# GembaBlockchain regenesis contract addresses (2026-06-27, chain gemba-testnet-1 / EVM 821207)

Deployed via CREATE2 (Arachnid factory 0x4e59…, founder deployer) — deterministic across future regeneses.
**These REPLACE the pre-regenesis CREATE addresses — update all dApp configs.**

| Contract | Address |
|---|---|
| GembaTimelock | 0xa75aC1AF72D54e34c5646534F985Be7a172C37C1 |
| GembaVotes | 0x0056ab3c91FF5ba8eCdBA8c7C453fd9F424F7F39 |
| GembaGovernor | 0xCCd9f78047E1BB8Bec419490E80409bfBf3B7b72 |
| EmergencyPause | 0x372462Fc8e28c558E2A1bcE6b9CF56a47c71DeA0 |
| Faucet (reserve) | 0x9406B634Eae1856d13251245d7D472D9b6594F56 |
| FoundationTreasury | 0x353CC67C2000fC9b142C0aa505a2e45DA693CDe0 |
| DAOReserve | 0x68093A1C9682df9D1C59586b2Cfc04ed132e7eE5 |
| ContingencyReserve | 0xCBbf84966335e0846cffB52d8624a9aeF58227b4 |
| GembaDripFaucet | 0x0D16a7a490eB2f4766480424E28EE0187d5c74AB |
| GembaOnRamp | 0xC35E5F9AD571499785060aa63e3Eb492DbB3Fd17 |
| GembaTicketing | 0xDe541f5E11af36cAE643D04F2e49fA54Cf14B6ce |
| GembaPerks | 0x0c4ab65FC5A295995A0ef50714aA4e2f33b6ada6 |
| GembaForwarder | 0x5c7A951ed32c3ce77f4b6e6585018eB5b32C426E |
| WorkplaceCheckIn | 0xbD57C7CD844ad0aC23a4e1D6B9F016E3FE89bE19 |
| AccessControlNFT | 0xE2DCB80ee598Dd0eb0dda8179A51c02b7C266a98 |

Funding: Foundation 15M, DAO 10M, Contingency 10M (all owned by Timelock). Faucet reserve's 30M
stays in the Cosmos faucet module account (feesplit/slash accrual); Cosmos→EVM faucet seam is the
documented follow-up. DripFaucet seeded 10,000 GMB. Guardians: founder/foundation/dao (2-of-3).

## DEX & ecosystem (developer reference, §9 — redeployed 2026-06-27, verified, swap-E2E-proven)

| Contract | Address |
|---|---|
| GembaSwapRouter02 | 0x49Da581bf5C09aE24312574D4835d416EE5eEfd5 |
| GembaSwapFactory | 0x15752A99d2e06d001F5d228AA158EbD687276DB4 |
| WGMB (wrapped native GMB) | 0x4A74DB9c9cE285960d01B53a626945DDd100e8d8 |
| GembaNativePoolFactory | 0x92F048fDF7fB98F800C4cF3c78F779681A208a99 |
| LiquidityLocker | 0xa2bf89D6FDAA3d72310DD82A9da40032abd398c6 |
| DemoToken (DEMO, example) | 0xDA9dFb87f77ED2176C00339da0cEae2Ac6E5e722 |

GembaSwap = Uniswap V2 renamed 1:1 (core 0.5.16 / periphery 0.6.6); init-code-hash recomputed.
NOT project-operated, NOT for GMB liquidity (§2/§8/§16.1) — reference contracts for ecosystem devs.

## Faucet & test stablecoins (system faucet, founder-owned)

| Contract | Address |
|---|---|
| GembaFaucet (combo: 0.1 GMB + 10,000 of each stablecoin / 24h per wallet) | 0x0147581e2351dD182edD651DFEfD955CB353f8aA |
| USDT — Tether USD (Test, 6 dec) | 0xF61647866ad7be8137230Ad688092D2f3F4A1666 |
| USDC — USD Coin (Test, 6 dec) | 0xc9af98AD8ae78086620821F9Ceb05842Dd7950CF |
| EURC — Euro Coin (Test, 6 dec) | 0x7Ff43282d7939418a3f0A308E2d48Dd93536044e |
| GmbCollector (GembaPay native-GMB payments) | 0x72F771d2CaC82Dd807435b03D3a216006413614c |

## Validators (4 × moniker "regen", 10,000 GMB self-bond each)

| Operator (EVM) | Cosmos valoper |
|---|---|
| 0xE685734337FD4Dd6d0AcFA778e62EcF3C36efb4b | cosmosvaloper1u6zhxsehl4xad59vlfmcuchv70pka76t7uzsye |
| 0x2D15EfA53C6B4B833DE158E88bb0c825C190219A | cosmosvaloper19527lffudd9cx00ptr5ghvxgyhqeqgv6sjd000 |
| 0x6748152eB8292003A468C7543bFFB8bC5c62718C | cosmosvaloper1vayp2t4c9ysq8frgca2rhlach3wxyuvvya3xfd |
| 0x7b75ca2344eae5D0317CEB0bB6878Cc4354dBc84 | cosmosvaloper10d6u5g6yatjaqvtuav9mdpuvcs65m0yy9qh3vh |

## ⏭ Mainnet (gemba-1 / EVM 821206) — NOT deployed yet

At mainnet genesis ALL of the above must be (re)deployed & verified, in particular the DEX
(Router02 / WGMB / Factory / NativePoolFactory / LiquidityLocker) — do not forget these. The public
addresses page (addresses.gembachain.io) mainnet tab carries the same reminder.
