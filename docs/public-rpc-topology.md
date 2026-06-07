# Public RPC, archive & explorer topology — `gemba-testnet-1`

Set up 2026-06-08. Adds redundant public EVM JSON-RPC on two validator nodes (behind a
protected nginx proxy), alongside the existing archive/explorer endpoint.

## Public endpoints (EVM JSON-RPC, chainId **821207**)
| URL | Origin | Node type | Notes |
|---|---|---|---|
| `https://rpc1.gembascan.io` | .83 (gemba-tn-contabo-2) | **pruned** | nginx TLS + rate-limit, Cloudflare-only |
| `https://rpc2.gembascan.io` | .84 (gemba-tn-contabo-3) | **pruned** | same |
| `https://testnet.gembascan.io/rpc` | .82 `gembad-archive` | **archive** | behind Apache; also the explorer's source |

DNS: Cloudflare A records, **Proxied (orange)**, SSL **Full (strict)**. MetaMask works with
any of them (chainId 821207, symbol GMB). Redundant: if one endpoint dies, the others serve.

## Layered architecture (why this shape)
- **Consensus** = 4 validators over P2P (`:26656`), independent of RPC. **If every public RPC
  dies, the chain keeps producing blocks** — RPC is only the "front desk" (read/submit access),
  not the network's liveness. (Verified during stress testing: explorer/RPC overloaded, chain
  never halted.)
- **Live RPC** (dapps, MetaMask): `rpc1` + `rpc2` (pruned) + the `.82` archive. Pruned nodes
  serve latest/recent state cheaply — that covers the vast majority of dapp calls.
- **Historical / explorer**: the `.82` **archive node** (`pruning=nothing`) keeps ALL state from
  genesis (old balances/storage at any height, `debug_trace`/internal txs) → feeds Blockscout.
  One archive is functionally enough; pair it with several cheap pruned RPC nodes for live-traffic
  redundancy (this setup).

## Protection on the validator RPC nodes (.83 / .84)
A validator's #1 job is signing blocks reliably; exposing RPC adds attack surface, so it is
locked down:
- gembad `[json-rpc]` bound to **127.0.0.1:8545** (+ `enable-indexer=true` for receipts) — the
  raw port is never public.
- **nginx** on `:443` (reuses the `*.gembascan.io` Cloudflare origin cert) → `127.0.0.1:8545`;
  `limit_req` **25 r/s per IP** (burst 50); CORS for browser dapps; `real_ip` from Cloudflare.
- **ufw**: `443` allowed **only from Cloudflare IPv4 ranges** (origin can't be hit directly;
  all traffic goes through the CF edge, which adds DDoS/rate protection).
- Config files: `/etc/nginx/sites-available/rpc.conf`, `/etc/nginx/conf.d/{cf-realip,ratelimit}.conf`,
  cert at `/etc/ssl/cloudflare/gembascan-origin.{pem,key}`.
- Trade-off: even rate-limited, RPC on a validator is residual risk. For maximum safety use
  **dedicated non-validator RPC nodes**. Acceptable on testnet; reconsider for mainnet.

## node2 (.100 "jellyfin", LAN)
Runs gembad via **Docker** with `--json-rpc.enable=true --json-rpc.address 0.0.0.0:8545` baked
into its systemd `ExecStart` → RPC is **LAN-exposed** (pre-existing; app.toml is ignored for it).
Not part of the public set. Behind home NAT (not internet-reachable). Fine as a personal/LAN node.

## Archive on a home/residential box? — No
Technically a node catches up after **short** outages (block-sync from peers); but for an
**archive** a **long** outage is risky (peers prune `default`, so a stale gap may be unfillable
without a snapshot). More importantly, the **public explorer reads from the archive** — putting it
on a residential/intermittent box ties explorer availability to home internet/power, cripples the
heavy indexer over residential bandwidth, and piles load on a box that also runs a validator. Keep
the public archive in a datacenter. `jellyfin` is fine for a *personal pruned* node, not the public
archive.

## Mainnet
Mainnet (`gemba-1`, EVM chainId **821206**) is a **separate chain** → needs its **own** archive +
explorer + public RPC set (can't share testnet's). Notes:
- Validators distribute across independent operators (not all founder-run).
- The mainnet archive will be **heavier** (real traffic) → size disk/RAM bigger.
- Put explorer + archive on a **dedicated box, never on a validator** (the .82 lesson).
- One well-resourced box can co-host both mainnet and testnet explorer+archive (separate
  processes/ports/data-dirs); testnet can be downsized after mainnet launch. So it's a second
  *supporting* set, not a blind 2× of everything.
