# GembaBlockchain — public network topology (post-regenesis 2026-06-27)

Chain `gemba-testnet-1` / EVM `821207`. This is the **public-safe** topology: what a
peer, dApp, or explorer user needs. Operational access details (SSH users/keys, auth
methods, box internals) live in the **gitignored** `docs/SERVER-TOPOLOGY.local.md` —
they do not belong in a public repo (moved out 2026-07-19).

## Public endpoints

| Role | Endpoint | Notes |
|---|---|---|
| EVM JSON-RPC | `rpc1.gembascan.io` / `rpc2.gembascan.io` / `rpc3.gembascan.io` | Cloudflare-proxied; each backed by one of the three RPC-serving validators (direct `:8545` is firewalled) |
| Explorer | `testnet.gembascan.io` | Blockscout ("GembaScan"), dedicated box, fed by the archive node |
| Seeds / persistent peers | `13.140.139.82`, `13.140.139.83`, `13.140.139.84` (P2P `:26656`) | published for node operators (see `gemba-validator/network.env`) |

## Node roles (4 validators + archive + explorer)

- **3 Contabo validators** double as the public RPC servers (rpc1/2/3 above).
- **1 NAT'd validator** (dials out; no public RPC, no gossiped address).
- **Archive node** (`pruning = nothing`) feeds the explorer; not publicly exposed.
- **Explorer box** runs Blockscout via docker compose and reads the archive over a
  hardened private tunnel.
- The dApp production server is separate from all chain infrastructure.

## Contracts (CREATE2, 2026-06-27)
See `contracts/REGENESIS-ADDRESSES-2026-06-27.md`.

## Testnet → mainnet transition (DECIDED 2026-06-29)

The public testnet is **not** run in parallel with mainnet. When mainnet (`gemba-1`,
EVM `821206`) is prepared: `gemba-testnet-1` is **stopped** and its boxes (validators,
archive, explorer) are **cleaned and reused for mainnet** — no new fleet is bought.
Ongoing upgrade testing thereafter runs locally as an **on-demand 4-validator
testnet**, spun up from the genesis generators only to rehearse a binary/consensus
upgrade before it touches the value-bearing mainnet, then torn down. Full rationale:
`docs/public-rpc-topology.md` and `CLAUDE.md §13`.
