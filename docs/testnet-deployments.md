# gemba-testnet-1 — live contract deployments

> Live on **gemba-testnet-1** (EVM chainId **821207**), redeployed **2026-06-27** after the
> regenesis (deterministic CREATE2 → new addresses). Explorer: **https://testnet.gembascan.io**
> (append `/address/<CA>`). Public copy: **https://addresses.gembachain.io**.
>
> **⚠️ All pre-2026-06-27 addresses are INVALID** (no code on the current chain). The authoritative
> machine-readable list is **[`contracts/REGENESIS-ADDRESSES-2026-06-27.md`](../contracts/REGENESIS-ADDRESSES-2026-06-27.md)**;
> this doc mirrors it for humans.

---

## Governance & Reserves (§7, §4.1)

| Contract | Address | §4.1 balance |
|---|---|---|
| `GembaTimelock` (execution delay, testnet) | `0xa75aC1AF72D54e34c5646534F985Be7a172C37C1` | reserve custody |
| `GembaVotes` (1 GMB = 1 vGMB, excludes reserves) | `0x0056ab3c91FF5ba8eCdBA8c7C453fd9F424F7F39` | — |
| `GembaGovernor` (supermajority 66%, quorum 50%) | `0xCCd9f78047E1BB8Bec419490E80409bfBf3B7b72` | — |
| `EmergencyPause` (guardian, pause-only) | `0x372462Fc8e28c558E2A1bcE6b9CF56a47c71DeA0` | — |
| `PublicReserve` — Public/Municipal Reserve | `0x9406B634Eae1856d13251245d7D472D9b6594F56` | 30,000,000 GMB* |
| `FoundationTreasury` | `0x353CC67C2000fC9b142C0aa505a2e45DA693CDe0` | 15,000,000 GMB |
| `DAOReserve` | `0x68093A1C9682df9D1C59586b2Cfc04ed132e7eE5` | 10,000,000 GMB |
| `ContingencyReserve` | `0xCBbf84966335e0846cffB52d8624a9aeF58227b4` | 10,000,000 GMB |

> *The Faucet reserve's 30M is held in the **Cosmos faucet module account** (feesplit/slash accrual);
> this contract is the EVM seam (Cosmos→EVM faucet sweep is the documented follow-up).
>
> **Ownership:** all reserve contracts owned by `GembaTimelock`. Upgrades require
> `GembaGovernor` proposal → vote → timelock queue → execute. **Guardians (EmergencyPause, 2-of-3):**
> founder / foundation / dao.

---

## Application contracts (§9)

| Contract | Address |
|---|---|
| `GembaOnRamp` (stablecoin → GMB; public sale OFF by design) | `0xC35E5F9AD571499785060aa63e3Eb492DbB3Fd17` |
| `GembaTicketing` (ERC-1155 event tickets) | `0xDe541f5E11af36cAE643D04F2e49fA54Cf14B6ce` |
| `GembaPerks` (employee perks & bonuses) | `0x0c4ab65FC5A295995A0ef50714aA4e2f33b6ada6` |
| `AccessControlNFT` (soulbound workplace access, no PII) | `0xE2DCB80ee598Dd0eb0dda8179A51c02b7C266a98` |
| `GembaForwarder` (EIP-2771 sponsored gas) | `0x5c7A951ed32c3ce77f4b6e6585018eB5b32C426E` |
| `WorkplaceCheckIn` (meta-tx demo) | `0xbD57C7CD844ad0aC23a4e1D6B9F016E3FE89bE19` |
| `GembaDripFaucet` (legacy drip, being retired) | `0x0D16a7a490eB2f4766480424E28EE0187d5c74AB` |

---

## DEX tooling (developer reference, NOT project-operated, §9)

| Contract | Address |
|---|---|
| `GembaSwapRouter02` (Uniswap V2 router, full ABI) | `0x49Da581bf5C09aE24312574D4835d416EE5eEfd5` |
| `GembaSwapFactory` (Uniswap V2 factory) | `0x15752A99d2e06d001F5d228AA158EbD687276DB4` |
| `WGMB` (wrapped native GMB) | `0x4A74DB9c9cE285960d01B53a626945DDd100e8d8` |
| `GembaNativePoolFactory` | `0x92F048fDF7fB98F800C4cF3c78F779681A208a99` |
| `LiquidityLocker` | `0xa2bf89D6FDAA3d72310DD82A9da40032abd398c6` |
| `DemoToken` (DEMO, example dev token) | `0xDA9dFb87f77ED2176C00339da0cEae2Ac6E5e722` |

> GembaSwap = Uniswap V2 renamed 1:1. NOT for GMB liquidity; see `contracts/src/dex/README.md` and
> `CLAUDE.md` §9. Verified + full swap/liquidity/lock E2E proven 2026-06-27.

---

## System faucet & test stablecoins

| Contract | Address |
|---|---|
| `GembaFaucet` (0.1 GMB + 10,000 of each stablecoin / 24h per wallet) | `0x0147581e2351dD182edD651DFEfD955CB353f8aA` |
| `USDT` — Tether USD (Test, 6 dec) | `0xF61647866ad7be8137230Ad688092D2f3F4A1666` |
| `USDC` — USD Coin (Test, 6 dec) | `0xc9af98AD8ae78086620821F9Ceb05842Dd7950CF` |
| `EURC` — Euro Coin (Test, 6 dec) | `0x7Ff43282d7939418a3f0A308E2d48Dd93536044e` |
| `GmbCollector` (GembaPay native-GMB payments) | `0x72F771d2CaC82Dd807435b03D3a216006413614c` |

> The old standalone drip faucet `0x2baE94C0…` and the compromised tnfaucet key
> `0x40a0cb1C…` (pentest P-1) are **dead/retired — do not use** (`docs/KEY-INVENTORY.md`).

---

## Validators (4 × moniker "regen", 10,000 GMB self-bond)

| Operator (EVM) | Cosmos valoper |
|---|---|
| `0xE685734337FD4Dd6d0AcFA778e62EcF3C36efb4b` | `cosmosvaloper1u6zhxsehl4xad59vlfmcuchv70pka76t7uzsye` |
| `0x2D15EfA53C6B4B833DE158E88bb0c825C190219A` | `cosmosvaloper19527lffudd9cx00ptr5ghvxgyhqeqgv6sjd000` |
| `0x6748152eB8292003A468C7543bFFB8bC5c62718C` | `cosmosvaloper1vayp2t4c9ysq8frgca2rhlach3wxyuvvya3xfd` |
| `0x7b75ca2344eae5D0317CEB0bB6878Cc4354dBc84` | `cosmosvaloper10d6u5g6yatjaqvtuav9mdpuvcs65m0yy9qh3vh` |

---

## Deployer

| Account | EVM address | Allocation |
|---|---|---|
| `founder` (deployer, non-voting) | `0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC` | 5,000,000 GMB |

---

## Notes

- Gas limit **100,000,000**; `x/feesplit` 60/40 (60% validators, 40% faucet module acct).
- Mainnet (gemba-1 / EVM 821206) is **not deployed yet** — at genesis ALL of the above (especially
  the DEX) must be redeployed & verified. See the mainnet tab on addresses.gembachain.io.
