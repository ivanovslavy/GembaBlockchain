# GembaBlockchain — live testnet status

> Milestone record. The GembaBlockchain test network is **live and working
> end to end**, and the **first GMB transaction** has been made and is visible in
> the self-hosted block explorer (GembaScan / Blockscout).
>
> This is the **valueless test network** — a mainnet dress rehearsal, not the
> public mainnet. Public launch remains gated by the hard blockers in `CLAUDE.md`
> §16 (upstream audit, security-budget tail). See also
> [`runbooks/testnet-deploy.md`](./runbooks/testnet-deploy.md).

## Network identity

| Field | Value |
|---|---|
| Network | GembaBlockchain test network (`gemba-testnet`) |
| Cosmos chain-id | `gemba-testnet-1` |
| EVM chainId | `821207` (EIP-155; distinct from mainnet's `821206`) |
| Native coin | Gemba (GMB) — **test GMB, no value** |
| Consensus | CometBFT BFT PoS, ~5 s blocks, instant finality |
| Explorer (public) | **https://testnet.gembascan.io** (GembaScan / Blockscout) |
| EVM JSON-RPC (public) | **https://rpc1.gembascan.io** |
| Active validators | 4 (3 on public cloud hosts + 1 operator node), each 1,000,000 GMB |

## Listed in public registries

The GembaBlockchain **testnet** (EVM chainId **821207**) is now listed in two official,
community-run open-source registries — both PRs **merged**:

| Registry | PR | What it is | Why it matters |
|---|---|---|---|
| **ethereum-lists/chains** | [#8413](https://github.com/ethereum-lists/chains/pull/8413) | the canonical registry of EVM networks (chainId → metadata + icon) | it powers **[chainlist.org](https://chainlist.org)** and is read by wallets/tooling, so the network is **recognised** and users can **add it to MetaMask in one click** (no manual RPC entry) |
| **blockscout/chainscout** | [#241](https://github.com/blockscout/chainscout/pull/241) | Blockscout's public directory of chains with an explorer | **GembaScan** ([testnet.gembascan.io](https://testnet.gembascan.io)) appears in Blockscout's chain directory — independent discoverability |

What being in `ethereum-lists/chains` concretely buys us: MetaMask and chainlist.org pull
network metadata **and the native GMB icon** from that repo (not from our own explorer), so a
listed chain shows up with its logo and an "Add to MetaMask" / "Connect Wallet" button on
chainlist.org. The ready-to-submit payloads live in [`chain-registry/`](./chain-registry/)
(MetaMask/chainlist) and [`chainscout/`](./chainscout/) (Blockscout directory).

> **Accuracy:** these are **testnet** listings (chainId **821207**). **Mainnet (chainId
> 821206) is not yet launched** and gets its own entries (with `isTestnet: false`) once the
> mainnet RPC + explorer are live. Do not describe GembaBlockchain as a "recognised network"
> in a way that implies mainnet — the recognition is of the testnet.

## What is verified working

The test chain is producing blocks and the full EVM surface is live:

- **Block production** — continuous ~5 s blocks (instant finality, no reorgs).
- **EVM JSON-RPC** — the geth-compatible endpoint serves blocks, receipts,
  historical account state, and `debug_trace*` (the data the explorer indexes).
- **MetaMask** — connects out of the box (chainId `821207`, `0x` addresses,
  coin type 60) and signs/sends a native GMB transfer.
- **First GMB transfer** — made from MetaMask, confirmed on-chain, balances
  updated correctly (see below).
- **GembaScan (Blockscout) explorer** — live, indexing the chain, and rendering
  the transfer on the home page, the transactions list, and the transaction
  detail page.

## First transaction

The first native GMB transfer on the GembaBlockchain test network, as indexed and
displayed by GembaScan:

| Field | Value |
|---|---|
| Transaction hash | `0x3467cbaaca69443ee2e7576c2e20122d11edae48d95cb22386e7f764310d7465` |
| Status | Success |
| Block | 965 |
| Timestamp | Jun 05 2026, 11:05:31 (+03:00) — confirmed within ≤ 5.192 s |
| From | `0xaf56bc7716288011ae12233ec6052Db39cda5833` |
| To | `0x51EB73719D8D1F11d0e6ED566a560830984C82f9` |
| Value | **1,000 GMB** |
| Transaction fee | 0 GMB (gas price 0 — idle base fee on the test chain) |
| Gas used / limit | 21,000 / 21,000 (100%) — a standard native transfer |
| Type | `coin_transfer` |

> Addresses are public on a public chain and safe to record here. The private
> keys / mnemonics behind them are not in the repository (secret hygiene,
> `CLAUDE.md` §14).

## Public deployment

The network moved from a single-laptop setup to a **public backbone**:

- **Validators (4):** three run on public cloud hosts (geo: EU) and one is an
  operator-run node, each bonded 1,000,000 GMB, all signing every block. Entry was
  the permissionless dynamic join of [`runbooks/testnet-deploy.md`](./runbooks/testnet-deploy.md) §7
  (sync as a full node → `MsgCreateValidator`); decommissioned validators were
  removed cleanly by **unbonding their full self-stake** (participation ends at once,
  one at a time, never dropping below the BFT minimum), not just stopped.
- **Explorer + RPC host:** a dedicated **archive node** (`pruning=nothing`) feeds a
  Blockscout (GembaScan) stack; **Apache** terminates TLS (behind Cloudflare) and
  same-origin reverse-proxies the UI (`/`), the Blockscout API (`/api`, `/socket`),
  and the **EVM JSON-RPC** (`/rpc`). The Blockscout **frontend is pinned to the tag
  matching the backend's API contract** — see [`/explorer/README.md`](../explorer/README.md).

## MetaMask network settings

After the migration, add/point MetaMask at:

| Field | Value |
|---|---|
| Network name | GembaBlockchain testnet |
| New RPC URL | **https://rpc1.gembascan.io** |
| Chain ID | **821207** |
| Currency symbol | **GMB** |
| Block explorer URL | **https://testnet.gembascan.io** |

Only the **RPC URL** and **explorer URL** changed in the migration; the network
name, currency symbol, and chain ID are unchanged. Addresses remain standard `0x…`
(eth_secp256k1, coin type 60).

The first GMB transfer (above) is viewable at
`https://testnet.gembascan.io/tx/0x3467cbaaca69443ee2e7576c2e20122d11edae48d95cb22386e7f764310d7465`.
