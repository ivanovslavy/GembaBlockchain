# Public RPC, archive & explorer topology — `gemba-testnet-1`

Set up 2026-06-08. Redundant public EVM JSON-RPC + a **dedicated explorer/archive box** so no
validator carries the heavy serving load.

## Update 2026-06-08 — explorer + archive moved off the validators
The archive node + Blockscout explorer used to be co-hosted on the `.82` validator, which
overloaded it (the stress-test lesson). They were **migrated to a dedicated Contabo box
`13.140.148.137`** (6 vCPU / 12 GB / 200 GB, 12 GB swap). `.82` is now a **lean validator only**
(RAM dropped ~7 GB → ~1.8 GB). The landing `gembachain.io` + the DEX `swap.gembachain.io` moved
to `46.225.1.162` (gembait box). Explorer reads **locally** from its co-located archive
(`host.docker.internal:8545`), no external API calls.

## Public endpoints (EVM JSON-RPC, chainId **821207**)
**Primary = `rpc1`; fallbacks `rpc2`, `rpc3`.** As of **2026-06-25** the archive node is **no longer
a public wallet RPC** — it serves the explorer only. The old `testnet.gembascan.io/rpc` was overloaded
(it shares the box with Blockscout indexing) and hung on batched JSON-RPC, which broke MetaMask balance
reads + tx building (pentest P-2/P-5). It was de-advertised everywhere and its `/rpc` repointed to `rpc1`
so already-configured clients keep working.
| URL | Origin | Node type | Notes |
|---|---|---|---|
| `https://rpc1.gembascan.io` (**primary**) | .83 (gemba-tn-contabo-2) | pruned validator | nginx TLS + **single CORS** + rate-limit, Cloudflare-only |
| `https://rpc2.gembascan.io` | .84 (gemba-tn-contabo-3) | pruned validator | same |
| `https://rpc3.gembascan.io` (**added 2026-06-25**) | .82 (gemba-tn-contabo-1) | pruned validator | same — added to move wallet/dapp RPC off the archive |
| ~~`testnet.gembascan.io/rpc`~~ | .137 archive | archive | **REMOVED 2026-06-26** — public `/rpc` returns **`410 Gone`** (pentest P-2); the archive serves the explorer only and reads the node internally on `127.0.0.1:8545` |

Web / explorer hosts:
| Host | Box | Serves |
|---|---|---|
| `testnet.gembascan.io`, `gembascan.io`, `www` | **13.140.148.137** | GembaScan (Blockscout) only — public `/rpc` removed (`410`, P-2); reads the node internally on `127.0.0.1:8545` |
| `gembachain.io`, `www` | **46.225.1.162** | landing site (Apache static, `/gembachain.io/dist`) |
| `swap.gembachain.io` | **46.225.1.162** | GembaSwap DEX UI (`/swap.gembachain.io/dist`) — our own swap app, **no platform fees**; GMB↔WGMB wrap/unwrap is free (1:1); ERC-20 swaps via GembaSwap V2. Linked prominently from gembachain.io (nav + hero + footer). |
| `addresses.gembachain.io` | **46.225.1.162** | official address directory (`/addresses.gembachain.io`, static) — testnet/mainnet tabs; genesis reserves, governance, DEX (Router V2/WGMB/Factory), validators; copy + GembaScan links. Linked from gembachain.io (nav + footer). |

All Cloudflare A records, **Proxied (orange)**, SSL **Full (strict)** (`.137` uses the
`*.gembascan.io` origin cert; `.162` uses the `*.gembachain.io` origin cert). MetaMask works with
any RPC (chainId 821207, symbol GMB). Redundant: if one endpoint dies, the others serve.

## SEO / AI discoverability (gembachain.io)
The landing carries full SEO + AI metadata: canonical + OG/Twitter (absolute images) + robots
directives; **JSON-LD** (Organization `GEMBA EOOD` + WebSite); `robots.txt` (allows all + explicit
AI bots: GPTBot, ClaudeBot, PerplexityBot, Google-Extended, CCBot, Applebot-Extended…) + `sitemap.xml`;
and `llms.txt` / `llms-full.txt` / `ai.txt` for AI systems (in `frontend/landing/public/`).

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

## Mainnet — RPC policy (DECIDED 2026-06-25)
Mainnet (`gemba-1`, EVM chainId **821206**) is a **separate chain** → its own archive + explorer +
public RPC set (can't share testnet's).

**Operator decision:** mainnet uses the **same model as testnet — the validators serve the public RPC**,
just on **more powerful servers**. We will **NOT** stand up separate dedicated RPC-only servers (cost;
and the network is not under real load). The residual "RPC-on-a-validator" risk is **accepted**, mitigated
by beefier hardware + Cloudflare rate-limiting + ufw (CF-only) + single-CORS nginx.

**HARD RULE — RPC must NEVER live on the archive node or the explorer host.** That was the exact root of
the testnet incident (pentest P-2/P-5): the archive box also runs Blockscout indexing → it overloads and
**hangs on batched JSON-RPC**, so wallets read **0 balance / "Fund your wallet"** and can't build txs.
Keep them strictly separated:
- **Public RPC** → validator nodes only (beefier boxes), behind single-CORS nginx + rate-limit + CF-only ufw.
- **Archive node** → explorer/indexing ONLY; never advertised or used as a wallet RPC.

Other notes:
- Validators distribute across independent operators over time (not all founder-run).
- The mainnet archive will be **heavier** (real traffic) → size disk/RAM bigger.
- One well-resourced box can co-host mainnet + testnet explorer+archive (separate processes/ports/
  data-dirs); testnet can be downsized after mainnet launch.
