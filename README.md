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
chain/       Cosmos EVM app (Go): genesis, node config, devnet scripts, custom modules
contracts/   Solidity (Foundry): governor, treasuries, NFTs, paymaster
services/    Node.js/Express backends (on-ramp, access-control API, indexers)
frontend/    React
explorer/    Blockscout docker setup ("GembaScan")
docs/        Detailed specs and runbooks (start with docs/risks.md)
```

## Build status

The project is built in phases (see `CLAUDE.md` §13).

- Phase 0, Scaffolding: complete. Monorepo structure, secret hygiene, risk register.
- Phase 1, Local devnet: complete. Single-node and 4-validator devnets built from
  the pinned upstream `cosmos/evm` `evmd` (v0.7.0), with GembaBlockchain's economics
  baked into genesis (zero inflation, a non-zero gas-price floor, EVM chainId
  821206, ~2s blocks, the fixed 100M GMB allocation). Verified end to end: MetaMask
  connection, a GMB transfer, a Solidity deploy, and 4-validator BFT liveness with
  one validator down. See [`chain/scripts`](./chain/scripts).
- Phase 2, Custom chain modules: next. The validator reward streamer, the 60/40 fee
  split, and the post-reserve tail reward, all zero-inflation (no minting).

**Live test network.** The GembaBlockchain **test network is up and working end to
end** — producing ~2 s blocks, serving EVM JSON-RPC, accepting MetaMask, and the
**first GMB transfer has been made and is indexed in GembaScan** (the self-hosted
Blockscout explorer). This is the valueless dress-rehearsal testnet (`gemba-testnet-1`,
EVM chainId `821207`), not mainnet — public launch is still gated by the blockers
below. Details and the first-transaction record: [`docs/testnet-status.md`](./docs/testnet-status.md).

## Quick start (local devnet)

Prerequisites: Go (the version pinned in the upstream `cosmos/evm` `go.mod`), a C
compiler (for CGO), `jq`, and [Foundry](https://book.getfoundry.sh) for the
transfer/deploy demos.

```bash
# 1. Build the pinned node binary once.
git clone --branch v0.7.0 https://github.com/cosmos/evm
cd evm && make install            # installs evmd to $(go env GOPATH)/bin
export PATH="$PATH:$(go env GOPATH)/bin"

# 2. Single-node devnet.
cd /path/to/GembaBlockchain
./chain/scripts/init-single-node.sh
./chain/scripts/start-single-node.sh

# 3. Or a 4-validator BFT devnet (tolerates one validator down).
./chain/scripts/init-multinode.sh
./chain/scripts/start-multinode.sh
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

## Conscious trade-offs and hard launch blockers

This is a real public chain with honestly recorded risks. See `CLAUDE.md` §16 and
the full Architecture Decision Records in [`docs/risks.md`](./docs/risks.md). Public
launch is blocked until all of the following clear:

1. MiCA classification confirmed in writing by a Bulgarian fintech lawyer (ADR-009).
2. The upstream Cosmos EVM audit lands, plus our own review (ADR-006).
3. The long-term security-budget tail reward is implemented and tested, and
   bonded-ratio monitoring is live (ADR-008).

Devnet, testnet, and closed formula-based institutional grants are not blocked by
these gates.

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
