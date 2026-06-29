# Explorer migration — split Blockscout off the archive onto its own box

Move **GembaScan (Blockscout)** off the co-located archive box (`13.140.148.137`) onto a
**dedicated NVMe box**, so the archive node stops fighting the Elixir indexer + Postgres for
CPU/RAM. This is the testnet rehearsal of the mainnet split (see
[`public-rpc-topology.md`](../public-rpc-topology.md) → "Mainnet hardware plan"): one box runs
the **archive node only**, the other runs **Blockscout only**.

> **Why this is needed.** On `.137` (6c/12GB) the stack measured **9.6GB/12GB RAM used (only
> 2.1GB free)** and load ~4.5 — `gembad` (5.4GB) and Blockscout (beam.smp + Postgres + verifier
> + frontend + redis ≈ 4GB) starve each other. The archive's disk was only 12–33% busy, so the
> bottleneck is **CPU+RAM contention, not disk**. Splitting frees the archive; putting Postgres
> on NVMe also fixes the random-IO latency that makes the explorer lag.

## Golden rule — parallel run, DNS is the only switch

**Do not touch `.137` until the new box is proven.** Both run in parallel; the Cloudflare DNS
record is the single cutover point; rollback = flip DNS back. Zero planned downtime.

## Prerequisites

- New box: **Contabo VPS 20, the NVMe option** (not the 200GB SSD — see why in
  [`gemba archive disk note`](../public-rpc-topology.md)), **Ubuntu 24.04 LTS** (match the fleet;
  Blockscout is Dockerized so host OS is near-irrelevant — consistency wins over Debian here).
- SSH access for `slavy` (key auth).
- The archive node stays on `.137` (`pruning=nothing`, `debug_trace*` enabled, RPC on
  `127.0.0.1:8545`).
- Secrets (DB password, any keys) live in `.env` on the box, **never committed** (CLAUDE.md §0.3).

---

## Phase 0 — Prep (before touching anything)

1. Provision the box, hand over `slavy` SSH.
2. **Lower the Cloudflare TTL** for the explorer hostnames (`testnet.gembascan.io`,
   `gembascan.io`, `www`) to **60s**, a day ahead, so cutover is fast and reversible.
3. Snapshot the current `.137` setup to copy over: `explorer/` docker-compose + `envs/*.env`
   (with the **pinned** Blockscout image tags), the `*.gembascan.io` Cloudflare **origin cert**,
   the archive RPC details.

## Phase 1 — Base install on the new box

```bash
# Ubuntu base + Docker + compose + firewall
sudo apt update && sudo apt -y upgrade
# Docker per docs; then:
sudo apt -y install autossh fail2ban
# ufw: deny inbound except SSH + 443 from Cloudflare only
sudo ufw default deny incoming && sudo ufw allow OpenSSH
# 443 only from Cloudflare ranges (script the CF IPv4/IPv6 list, as on .83/.84)
sudo ufw enable
```

- Copy the pinned Blockscout `explorer/` compose + `envs/backend.env` from the repo.
- nginx on `:443` using the copied `*.gembascan.io` origin cert → Blockscout frontend; reuse the
  `cf-realip` + `ratelimit` confs from the validator RPC nodes.

## Phase 2 — Secure link to the archive (`.137`) — "only the new server reads"

The archive RPC must stay **private, never public** (hard rule, `public-rpc-topology.md`). Bind
the tunnel to the new box's `127.0.0.1:8545` so Blockscout's existing `host.docker.internal:8545`
config works unchanged.

**Preferred — robust autossh tunnel** (`/etc/systemd/system/archive-rpc-tunnel.service`):

```ini
[Unit]
Description=autossh tunnel to archive RPC (.137)
After=network-online.target
Wants=network-online.target

[Service]
User=slavy
Environment=AUTOSSH_GATETIME=0
ExecStart=/usr/bin/autossh -M 0 -N \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:8545:127.0.0.1:8545 slavy@13.140.148.137
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now archive-rpc-tunnel
```

- **Alternative** if Contabo Private Networking (VLAN) is available between the boxes: use the
  private IP and `ufw allow from <EXPLORER_PRIV_IP> to any port 8545` on `.137`. Simpler/sturdier
  than a tunnel. Either way the archive RPC is **never on the public internet**.
- **Verify before continuing** (trace is mandatory — Blockscout needs `debug_trace*` for internal
  txs; the public validator RPC has `debug` disabled and **cannot** be the trace source):

```bash
curl -s -X POST localhost:8545 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
curl -s -X POST localhost:8545 -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"debug_traceBlockByNumber","params":["0x1",{}]}'
```

## Phase 3 — Bring up Blockscout (parallel, NO DNS yet)

- Point `ETHEREUM_JSONRPC_HTTP_URL` and `ETHEREUM_JSONRPC_TRACE_URL` at the archive (via the
  tunnel / private IP).
- Start the stack. For testnet (small DB) **re-index from genesis** — cleanest, no `pg_dump`
  version-mismatch risk. (For a large mainnet DB later, prefer `pg_dump`/physical copy to skip the
  long re-index.) Watch indexer lag → 0.
- Test **by the box IP / Host header**, NOT via the public hostname yet: recent + historical
  blocks, `eth_getBalance` at an old height, internal-tx traces, contract verification, the
  Etherscan-compatible API.

> 🚦 **GATE:** do not proceed until the new box is fully indexed and verified, while `.137` keeps
> serving live traffic.

## Phase 4 — DNS cutover (the single switch)

- In Cloudflare, change the A record(s) for the explorer hostname(s) from `.137` → the new box IP.
  Keep **Proxied (orange)**, SSL **Full (strict)**, origin cert `*.gembascan.io`. TTL is already 60s.
- Watch traffic shift; confirm the public hostname is served by the new box (access logs + a real
  MetaMask/explorer check).
- **Keep `.137`'s Blockscout running** — rollback is instant: flip the A record back to `.137`.

## Phase 5 — Decommission the old explorer on `.137` (after a safe window)

- After **24–48h** stable on the new box: `docker compose down` the Blockscout stack on `.137`.
- `.137` is now **archive-only → breathes** (RAM/CPU freed; the relief this whole migration is for).
- Keep the archive→explorer RPC link (tunnel/firewall). Confirm `.137`'s public `/rpc` stays
  `410 Gone` (no regression, pentest P-2).

---

## Rollback (any phase)

The new box is built entirely in parallel; nothing on `.137` changes until Phase 5. If the new
box misbehaves at any point:
- **Before DNS cutover:** just stop the new box's stack — no public impact.
- **After cutover:** flip the Cloudflare A record back to `.137` (60s TTL) — instant revert.
- `.137`'s archive node is never touched, so chain/explorer data is never at risk.

## Notes carried from `public-rpc-topology.md`

- **RPC must never live on the archive/explorer host** (the pentest P-2/P-5 root cause). The
  archive RPC reached here is an **internal indexer feed**, firewalled to the explorer box only —
  not a public wallet RPC.
- One box = one role. The archive box runs `gembad` only after this split; the explorer box runs
  Blockscout only.
- Mainnet uses the same procedure with its own separate chain/keys/genesis (`gemba-1`, EVM
  chainId 821206) — never reuse testnet keys/state.
