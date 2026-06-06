# gemba-testnet-1 — live contract deployments

> Live on **gemba-testnet-1** (EVM chainId **821207**), re-deployed 2026-06-06 after
> re-genesis. Explorer: **https://testnet.gembascan.io** (append `/address/<CA>`).
>
> **⚠️ Old addresses (pre-re-genesis) are INVALID — new chain, new addresses below.**

---

## Governance & Reserves (§7, §4.1)

| Contract | Address | §4.1 balance |
|---|---|---|
| `GembaTimelock` (5-min delay, testnet) | `0x4117ae45e76A77D1d54af57642aefD02A184cf90` | — |
| `GembaVotes` (1 GMB = 1 vGMB, excludes reserves) | `0xbD40Df2b3aEFFAc672A8B34B2615f4639c1C4b49` | — |
| `GembaGovernor` (supermajority 66%, quorum 50%) | `0x3DF48Ce0331b3322970deF66a6a116927059B4e7` | — |
| `EmergencyPause` (2-of-3 guardian, pause-only) | `0x2429828C0538328e87a96418E5C1cF68057d7dBD` | — |
| `Faucet` (UUPS proxy) — Public/Municipal Reserve | `0x0C6b72AC9ee4CBd132DF181468F7d905C6FD3a66` | 30,000,000 GMB |
| `FoundationTreasury` (UUPS proxy) | `0x06Cb10aCe5BdB3B6dF301d3B4af4c78A42896f7F` | 15,000,000 GMB |
| `DAOReserve` (UUPS proxy) | `0x7E00f38DB8F01d442447b0C90Eea315329B0Abb8` | 10,000,000 GMB |
| `ContingencyReserve` (UUPS proxy) | `0xb5dEc9867a89c041345B56cE1a339415B5BE4696` | 10,000,000 GMB |

> **Ownership:** all reserve contracts owned by `GembaTimelock`. Upgrades require
> `GembaGovernor` proposal → vote → timelock queue → execute.
>
> **Guardians (EmergencyPause, 2-of-3):** testnet founders/validators — see `contracts/.env`.

---

## DEX tooling (developer reference, NOT project-operated, §9)

| Contract | Address |
|---|---|
| `WGMB` (wrapped native GMB) | `0x68b735671C0b6ab1a6B8Fe4eaBd532B8736E68b4` |
| `GembaSwapFactory` (Uniswap V2 factory) | `0x61224Ee338C3c62e1050838AB75c76A7cd6f95ed` |
| `GembaSwapRouter02` (Uniswap V2 router, full ABI) | `0x53D78A64D01fC38A7Cc3436b6ec81DB203836D65` |
| `GembaNativePoolFactory` | `0x432c733005Fb389b32B7813260c33c27745aDA2b` |
| `LiquidityLocker` | `0x88CB73797FFA34d6D469e855ea19A7bB28Ba1020` |
| `DemoToken` (DEMO, example dev token) | `0xD172E25ac8fAC629a171aF8dcf50FEb49e369592` |
| `DemoFeeToken` (FEEDEMO, 5% fee-on-transfer) | `0x91CE1f91A845801db29568337A48075CDA6191F9` |

> GembaSwap = Uniswap V2 renamed 1:1. NOT for GMB; see `contracts/src/dex/README.md` and
> `CLAUDE.md` §9.

---

## Deployer & EOAs (post-re-genesis)

| Account | EVM address | Initial allocation |
|---|---|---|
| `founder` (deployer, non-voting) | `0x5578c75f22de0bf1caa4bdd46ba28406c696a5dc` | 5,000,000 GMB |
| `faucetreserve` (→ Faucet) | `0x81a82830e7123e33538d41efdf8c4baceeb8253a` | 30,000,000 GMB (now in Faucet) |
| `foundation` (→ FoundationTreasury) | `0xb22e0cbe56b6651cd55d354afe73e2dc818b5041` | 15,000,000 GMB (now in FoundationTreasury) |
| `dao` (→ DAOReserve) | `0x8453c623091ed59d5abcda21c19bddf0eedb6665` | 10,000,000 GMB (now in DAOReserve) |
| `contingency` (→ ContingencyReserve) | `0xdf183ec4674b228cafea536ad93ee66de7569f47` | 10,000,000 GMB (now in ContingencyReserve) |
| `tnfaucet` (drip faucet service key) | `0x40a0cb1c63e026a81b55ee1308586e21eec1efa9` | 2,000,000 GMB |

---

## Verification status

| Contract | Verified on GembaScan |
|---|---|
| GembaSwapFactory | ✅ |
| GembaSwapRouter02 | ✅ |
| All governance + reserve contracts | ⏳ bytecode-mismatch — retry with explicit constructor args |

Run `contracts/script/verify-all.sh` to re-attempt (no API key needed).

---

## Notes

- Gas limit: **100,000,000** (0x5f5e100) from re-genesis genesis — the old 10M is gone.
- `x/feesplit` 60/40 split: 60% → validators, 40% → faucet module acct. The on-chain
  `Faucet` contract receives these via a separate sweep/hook — integration pending (step 5c).
- Keys in `/tmp/gemba-regenesis/node0/keyring-test/` (on local machine) — copy to secure
  backup; `/tmp` is ephemeral.
