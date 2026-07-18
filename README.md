# GembaBlockchain

A decentralized, permissionless, public Proof-of-Stake L1 with full EVM
compatibility. Anyone with enough stake can validate; anyone can hold and send the
native coin Gemba (GMB). No central operator decides who participates.

GMB is a utility coin: value comes from use (cheaper service access, workplace
access control, event tickets, employee perks), not speculation. The long-term
goal is infrastructure owned and run by the institutions and community that use it,
where every participant follows the same on-chain rules and no one, including the
founder or a municipality, holds special power.

The single source of truth for the design is [`CLAUDE.md`](./CLAUDE.md). If a
design decision changes, update `CLAUDE.md` first, then the docs, then the code.

## Listed in public registries

**GembaBlockchain testnet** (EVM chainId **821207**) is listed in two official,
community-run open-source chain registries — both pull requests **merged**:

- **[ethereum-lists/chains #8413](https://github.com/ethereum-lists/chains/pull/8413)** —
  the canonical registry of EVM networks that powers **[chainlist.org](https://chainlist.org)**.
  Listing means wallets and developer tooling that read this registry recognise the network,
  and anyone can **add it to MetaMask in one click** from chainlist.org.
- **[blockscout/chainscout #241](https://github.com/blockscout/chainscout/pull/241)** —
  Blockscout's public directory of chains, listing the **GembaScan** testnet explorer
  ([testnet.gembascan.io](https://testnet.gembascan.io)).

> These are **testnet** listings (chainId **821207**). **Mainnet (chainId 821206) is not yet
> launched** — it gets its own registry entries once the mainnet RPC/explorer are live.

## Core facts

| Field | Value |
|---|---|
| Network | GembaBlockchain |
| Native coin | Gemba (GMB), the staking and gas coin |
| Framework | Cosmos SDK + Cosmos EVM (`cosmos/evm`, `evmd`) on CometBFT |
| Consensus | CometBFT BFT PoS, instant finality (~2s), no reorgs |
| Cosmos chain-id | `gemba-1` |
| EVM chainId | `821206` (EIP-155; separate from the Cosmos chain-id) |
| Accounts | `eth_secp256k1`, SLIP-0044 coin type 60, standard `0x` addresses (MetaMask works) |
| Total supply | Fixed, minted once at genesis, never again (0% inflation) |
| Fees | Real GMB fees (EIP-1559); low but non-zero, scaling with usage |
| License | Code: Apache-2.0; docs: CC BY-SA 4.0 |

## Repository layout

```
chain/            Cosmos EVM app (Go): custom modules (rewardstreamer, feesplit,
                  tailreward, valgate, slashfunds), gembad build + genesis builders
contracts/        Solidity (Foundry): governance, reserves, payments, tickets,
                  access NFT, paymaster, DEX infra (gembaswap)
services/         Node.js/Express backends: access-control, purchase-backend,
                  testnet-faucet, contact-form, blockchain-notifier
gemba-validator/  Self-contained validator install package + auto-ops daemons
                  (3-layer watchdog, auto-compound, disk-guard, alert email)
frontend/         React (landing, swap dApp) + static gmb/addresses pages
explorer/         Blockscout docker setup ("GembaScan") + Apache proxy confs
monitoring/       Prometheus/Alertmanager + bonded-ratio exporter (ADR-008)
security/         Adversarial pentest harness + mainnet prevalidation battery
stress/ endurance/ EVM load-test harnesses (burst + 24h soak)
scripts/          Mainnet ops: validator installer, key ceremony
docs/             Detailed specs and runbooks (start with docs/risks.md)
```

## Build status

The project is built in phases (see `CLAUDE.md` §13, which carries the full
per-phase record). **All nine technical phases are COMPLETE** (status 2026-07-19):

- **Phase 0-1** — scaffolding + local devnets (single-node and 4-validator BFT)
  from the pinned upstream `cosmos/evm` (v0.7.0).
- **Phase 2** — custom zero-inflation Go modules: `rewardstreamer` (reserve-funded
  validator rewards, incl. the mainnet formula model + gov kill-switch),
  `feesplit` (60/40), wired into the **`gembad`** binary (`chain/gembad`).
- **Phase 3-4** — governance + treasury contracts (two-tier Governor, Timelock,
  UUPS reserves, EmergencyPause; reserves excluded from voting) and EIP-1559
  tuning + EIP-2771 sponsored gas.
- **Phase 5-6** — soulbound access NFT + GDPR-split backend; **Buy-GMB** via
  `GembaPayDispenser` (the ONLY sale channel — the on-chain `GembaOnRamp` was
  removed entirely, owner decision 2026-07-17).
- **Phase 7-8** — GembaScan (Blockscout on a dedicated archive node) + ticketing/
  perks contracts.
- **Phase 9** — hardening: `tailreward` module (ADR-008b), monitoring with the
  bonded-ratio security metric, runbooks (halt recovery, upgrades, tmkms),
  multi-round security audits + pentest, validator auto-ops.

**Live public testnet.** `gemba-testnet-1` (EVM chainId `821207`, valueless) has
been live for weeks: ~2 s blocks, EVM JSON-RPC, MetaMask, GembaScan indexing,
drip faucet, swap dApp. Details: [`docs/testnet-status.md`](./docs/testnet-status.md).

**Mainnet (`gemba-1`, chainId 821206) is in final launch preparation** — genesis
builder with a 33-check verification battery (`chain/gembad/init-gembad-mainnet.sh`),
key-ceremony kit (`scripts/key-ceremony.sh`), prevalidation battery (`security/`),
and the launch runbooks under `docs/runbooks/`. Per the 2026-06-29 decision the
testnet fleet is reused for mainnet (testnet stops at cutover).

## Quick start (local devnet)

Prerequisites: Go (the version pinned in the upstream `cosmos/evm` `go.mod`), a C
compiler (for CGO), `jq`, and [Foundry](https://book.getfoundry.sh) for the
transfer/deploy demos.

```bash
# 1. Build the wired gembad binary once (fetches pinned cosmos/evm v0.7.0
#    and applies the Gemba wiring patch — custom modules included).
cd /path/to/GembaBlockchain/chain/gembad
./build-gembad.sh

# 2. Single-node devnet.
./init-gembad.sh

# 3. Or a 4-validator BFT devnet (tolerates one validator down).
./init-gembad-multinode.sh
EVMD=/tmp/gembad BASE=~/.gembad-multinode ../scripts/start-multinode.sh
```

Endpoints: CometBFT RPC `26657`, gRPC `9090`, REST `1317`, EVM JSON-RPC `8545`
(HTTP) / `8546` (WS). See [`chain/scripts/README.md`](./chain/scripts/README.md)
for how each genesis parameter maps to its specification section.

### MetaMask network parameters

| Field | Value |
|---|---|
| Network name | GembaBlockchain (local devnet) |
| RPC URL | `http://localhost:8545` |
| Chain ID | `821206` |
| Currency symbol | GMB |

## Conscious trade-offs and launch gates

This is a real public chain with honestly recorded risks. See `CLAUDE.md` §16 and
the full Architecture Decision Records in [`docs/risks.md`](./docs/risks.md).
The three original hard launch blockers have all been resolved:

1. **ADR-009 (MiCA)** — *withdrawn 2026-06-06*: no liquidity, no exchange, no
   public sale by design (ADR-003), so the public-sale MiCA trigger does not
   arise. Revisit only if a fiat-adjacent on-ramp is ever introduced.
2. **ADR-006 (upstream audit)** — *cleared 2026-07-18*: the pinned v0.7.0 carries
   every published advisory fix (incl. ASA-2026-002), the codebase was
   Sherlock-audited upstream, and our own multi-phase audit covered the
   integration + custom modules.
3. **ADR-008 (security budget)** — *done*: the recirculation-funded tail reward
   (`chain/x/tailreward`) is implemented, supply-invariant-tested and live on
   testnet; bonded-ratio monitoring ships in `monitoring/`.

What remains before the `gemba-1` genesis is operational, not architectural: the
key ceremony, final prevalidation battery, and launch-day runbook execution
(`docs/runbooks/`).

## Secret hygiene

This repository is public. Never commit `.env`, private keys, mnemonics, node keys,
keyrings, or database passwords. Copy [`.env.example`](./.env.example) to `.env` and
fill it in locally; `.gitignore` already excludes secrets and node data. The devnet
scripts use the well-known public `cosmos/evm` test mnemonics for reproducibility
only; these are published test vectors, not secrets, and must never be used on a
public network (see [`chain/scripts/README.md`](./chain/scripts/README.md)).

## License

Source code is licensed under the Apache License 2.0; see [`LICENSE`](./LICENSE).
This matches the upstream `cosmos/evm` license. Documentation is licensed under
CC BY-SA 4.0.
