# GmbCollector — drop-in for the GembaPay hardhat project

Minimal **native-GMB** payment collector for GembaPay. `pay(orderId)` forwards GMB to a changeable
`recipient` and emits a GembaPayEuro-shaped `PaymentProcessed` event. **One job: an orderId can be
paid only once (no double payment).** Native only — rejects direct GMB, ERC-20, ERC-721, ERC-1155.
1 GMB = €1 by design (no oracle).

> The GembaPay hardhat **deploy** project is not on the production server (.162) — only the SDK
> gitrepo + the dApp hardhat projects. So the live **testnet** deploy was done with the
> GembaBlockchain Foundry toolchain (same bytecode, verified). These files let you add the contract
> to your GembaPay hardhat project and (re)deploy — e.g. for mainnet — **without touching existing
> contracts or scripts** (drop `GmbCollector.sol` in `contracts/`, the script in `scripts/`).
>
> **Canonical source: `contracts/src/payments/GmbCollector.sol`** — edit THAT file, then copy it
> here. CI (`tests.yml`) fails if this drop-in copy ever diverges from the canonical source.

## Live testnet deployment (already done + verified)
- **GmbCollector:** `0x72F771d2CaC82Dd807435b03D3a216006413614c`  (✅ verified on testnet.gembascan.io)
- Network: `gemba-testnet-1`, EVM chainId **821207**
- owner: `0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC` (founder/ops) · recipient: `0x8eB8Bf106EbC9834a2586D04F73866C7436Ce298`
- Verified live: pay → recipient credited, **double-pay reverts (`OrderAlreadyPaid`)**, direct sends revert.

## 1. Add the Gemba networks to `hardhat.config.js` (additive)
```js
networks: {
  // … existing networks …
  gembaTestnet: { url: "https://rpc1.gembascan.io", chainId: 821207, accounts: [process.env.DEPLOYER_PK] },
  gembaMainnet: { url: "https://gmb1.gembascan.io", chainId: 821206, accounts: [process.env.DEPLOYER_PK] }, // mainnet RPC = gmb1/2/3.gembascan.io (2026-07-17)
},
etherscan: {                       // Blockscout verification for GembaScan
  apiKey: { gembaTestnet: "blockscout", gembaMainnet: "blockscout" },
  customChains: [
    { network: "gembaTestnet", chainId: 821207, urls: { apiURL: "https://testnet.gembascan.io/api", browserURL: "https://testnet.gembascan.io" } },
    { network: "gembaMainnet", chainId: 821206, urls: { apiURL: "https://gembascan.io/api", browserURL: "https://gembascan.io" } }, // TBD at mainnet
  ],
},
```

## 2. Deploy + verify
```bash
GMB_COLLECTOR_OWNER=0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC \
GMB_COLLECTOR_RECIPIENT=0x8eB8Bf106EbC9834a2586D04F73866C7436Ce298 \
DEPLOYER_PK=0x... \
npx hardhat run scripts/deploy-gmb-collector.js --network gembaTestnet   # then --network gembaMainnet
```

Solc 0.8.24, optimizer 200, evm `cancun` (matches the verified testnet build).
