# GembaBlockchain — token distribution (post-regenesis 2026-06-27)

Fixed supply **100,000,000 GMB** — verified on-chain (`gembad q bank total` = 100,000,000 GMB). No inflation.

## Where the 100M lives now
| Bucket | Holder | GMB | Kind |
|---|---|---|---|
| Public/Municipal Reserve (**faucet**) | Cosmos faucet module `cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d` | **30,000,100** (30M + 40% fee-split accrual) | Cosmos module acct |
| Validator reward reserve | Cosmos rewardstreamer module `cosmos1s32mhm7c0eest48njscsr5fnn2c42mr9w8cnqe` | **29,959,962** (streaming max(10,min(100,stake×1%))/val/day) | Cosmos module acct |
| FoundationTreasury | EVM `0x353CC67C2000fC9b142C0aa505a2e45DA693CDe0` | **15,000,000** | EVM contract, Timelock-owned |
| DAOReserve | EVM `0x68093A1C9682df9D1C59586b2Cfc04ed132e7eE5` | **10,000,000** | EVM contract, Timelock-owned |
| ContingencyReserve | EVM `0xCBbf84966335e0846cffB52d8624a9aeF58227b4` | **10,000,000** | EVM contract, Timelock-owned |
| Founder / ops | EOA `0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC` | **~4,769,000** (5M − dApp funding/gas below) | EOA, non-voting |
| GembaPay GMB dispenser | EVM `0x0EB298466F862E548d2416a75d3D108E503bD2Cf` | **100,000** | holds GMB for GembaPay sales; owner-only dispense (`docs/gembapay-gmb-dispenser.md`) |
| Validators (bonded stake) | val0–3 (4 × 10,000) | **40,000** | staked |
| GembaTicket relayer (gas) | `0x8eB8Bf106EbC9834a2586D04F73866C7436Ce298` | **100,000** | dApp gas wallet |
| **Main system faucet (`GembaFaucet`)** | EVM `0x0147581e2351dD182edD651DFEfD955CB353f8aA` | **10,000** | the single testnet faucet — dispenses GMB + mints stablecoins; used by landing/GembaWin/Escrow (`docs/faucet.md`) |
| DripFaucet (dormant) | EVM `0x0D16a7a490eB2f4766480424E28EE0187d5c74AB` | **10,000** | governance-owned (Timelock) GMB reserve; no dApp links it — can't be key-swept (§3.6), no voting base to drain it |
| GembaPass operator (gas) | `0xf886770683572DB6EFE69c76b0C865205C81C80e` | **10,000** | gas wallet for **GembaPass — a SEPARATE EXTERNAL system (gembapass.com)** with its own contracts/logic; testnet-only legacy row, **NOT a GembaBlockchain-genesis contract** — the mainnet genesis omits it |
| Faucet **contract** (EVM) | `0x9406B634Eae1856d13251245d7D472D9b6594F56` | **0** | the 30M sits in the Cosmos faucet module (Cosmos→EVM faucet seam pending) |
| OnRamp | `0xC35E5F9AD571499785060aa63e3Eb492DbB3Fd17` | **0** | no public sale (publicSaleEnabled=false) |
| **TOTAL** | | **100,000,000** | ✓ supply invariant holds |

## Protocol contract addresses (CA) — CREATE2, 2026-06-27
Full list incl. apps: `contracts/REGENESIS-ADDRESSES-2026-06-27.md`. Governance: Timelock `0xa75aC1AF…`, Votes `0x0056ab3c…`, Governor `0xCCd9f780…`, EmergencyPause `0x372462Fc…`. Reserves owned by the Timelock.

## dApp contract addresses (CA) — redeployed 2026-06-27
| dApp | Contracts |
|---|---|
| GembaWin | Factory `0xb77b4c87bc1B9237e5B743a5D33B107c502C5FDC`, Template `0x7b62446722bC69591fFCBAa963dbea7Ad5e8a3cc`, Faucet `0x0147581e2351dD182edD651DFEfD955CB353f8aA`, USDT `0xF61647866ad7be8137230Ad688092D2f3F4A1666`, USDC `0xc9af98AD8ae78086620821F9Ceb05842Dd7950CF`, EURC `0x7Ff43282d7939418a3f0A308E2d48Dd93536044e` |
| GembaTicket | PlatformRegistry `0x32977E6391e7C25BF0Ddc2a5f4c9A311e5bA1d02`, ERC721 V3 `0x95e75771B4e066A7edAD62d8d7CbDD50307c814e`, ERC1155 V3 `0x0b9749eE7DfCE7e1e825C8Fc7C363496ED7F75a0` (base 721 `0x8dD64483…`, base 1155 `0x03c0710C…`) |
| EduChain | Whitelist `0x48efcf1269d0CcBE0744c4Cf5CF6648AF8e16395`, GameToken `0x385335b67d8c6C3cb7114D4a907Ca6017391279B`, GameNFTPredefined `0x96FA050384c298c98A8AEc77c74F08df315684BA`, GameNFTCustom `0xb33456F2892A3563AAD6dA5388c954Eb3B5a5e13`, TokenMarketplace `0x9A3C2b9785d424348AEA49a94331c11DA8544259`, TrackingContract `0x68EF7dcbF9C1403D49c64b1d40F1A316be554385`, ETHFaucet `0x6056Cb44e9C6A429D45BBaC254FbD2D8CDa40D47` |
| Escrow | RealEstateFactory `0xf2dc67274CCd82bcFa3e446BcD55fB1889866e26`, RealEstateDeal template `0x1c99D2912D6b8F31b7F9c697C242f8882474524D` (whitelists GembaWin's USDT/USDC/EURC, uses faucet `0x0147…`) |
| GembaPass ⚠️ **EXTERNAL** | Separate system at **gembapass.com** — its own contracts + logic, **NOT part of GembaBlockchain genesis/deploy** (not built by any deploy script; won't be deployed on mainnet). Legacy testnet ref only: GembaAccessPass `0x1B72b95588B75925B59715d582504C9D42594899` (ERC-1155 soulbound, nonce-0 CREATE). |

**All dApp + protocol contracts are VERIFIED on https://testnet.gembascan.io** (source visible).

dApp test stablecoins (USDT/USDC/EURC) are separate mintable ERC-20s (not GMB) used by GembaWin + Escrow + the landing.
