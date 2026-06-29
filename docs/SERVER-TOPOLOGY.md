# GembaBlockchain — server & RPC topology (post-regenesis 2026-06-27)

Single reference so nobody has to re-discover where things live. Chain `gemba-testnet-1` / EVM `821207`.

## Validators (4) — `chain/gembad`, systemd, build `d8a454f`
| Role | Public IP | Host | Home | Service | Notes |
|---|---|---|---|---|---|
| val (rpc1) | 13.140.139.82 | Contabo-1 | /root/.gembad | gembad-val | **also serves RPC1** (EVM JSON-RPC :8545, app.toml json-rpc=true). Also runs a **Qortal** node (:12391) — DO NOT TOUCH. |
| val (rpc2) | 13.140.139.83 | Contabo-2 | /root/.gembad | gembad-val | **also serves RPC2** (:8545) |
| val (rpc3) | 13.140.139.84 | Contabo-3 | /root/.gembad | gembad-val | **also serves RPC3** (:8545) |
| val (val3) | 88.203.191.208 / LAN 192.168.100.100 | jellyfin | /home/slavy/.gembad-testnet-node2 | gembad.service (Docker `gembad-node2`, ubuntu:24.04, host glibc 2.35 can't run natively) | NAT, dials out. **No public RPC.** auto-unjail/compound timers here. |

**RPCs: one per Contabo validator. `rpc1=.82, rpc2=.83, rpc3=.84`** — each is the validator's own gembad-val
serving EVM JSON-RPC on `:8545`, behind **Cloudflare → `rpc1/2/3.gembascan.io`** (direct :8545 is firewalled).
jellyfin (.100) and the archive (.137) have **no** public RPC.

## Archive + explorer
| Role | IP | Home/Dir | Service | Notes |
|---|---|---|---|---|
| Archive (pruning=nothing) | 13.140.148.137 | /root/.gembad-archive | gembad-archive.service | EVM JSON-RPC :8545 (local). Feeds the explorer; **explorer moved OFF this box 2026-06-29 → now archive-only**. |
| Explorer (Blockscout "gembascan") | **213.136.85.32** (Cloud VPS 20 NVMe, Hub Europe) | /root/gembascan | docker compose | **Moved off .137 on 2026-06-29** to end CPU/RAM contention. Reaches the .137 archive `:8545/:8546` over a hardened **autossh tunnel** (`archive-rpc-tunnel.service`); Blockscout 9.0.2 / frontend v2.3.0. DNS cutover (`testnet.gembascan.io`/`gembascan.io` → this box) pending re-index; records are CF-proxied so the origin flip is instant (no TTL change). See `docs/public-rpc-topology.md`. |
| Dev archive | local dev box (192.168.100.x) | ~/.gembad-testnet-archive | gembad-archive.service | RPC :8565 — used for contract deploys (allow-unprotected-txs=true). |

## dApp production server
| IP | User | dApps (the only things to touch here) |
|---|---|---|
| 46.225.1.162 (Hetzner, host "gembapay") | slavy (sudo) | GembaTicket, GembaPass, Escrow, GembaWin, EduChain. **Do NOT touch other services** (GembaKitchen, gembait, gembaindustrial, gembapay). |

## Auth
- Validators (.82/.83/.84), archive (.137): `root` via SSH key `~/.ssh/gemba_claude`.
- Explorer (213.136.85.32): `slavy` (sudo NOPASSWD) via keys `~/.ssh/gemba_claude` + `~/.ssh/id_rsa`; **root login + password auth disabled (key-only)**. The tunnel to .137 uses a dedicated `~/.ssh/tunnel_to_137` key (restricted to port-forward :8545/:8546 only).
- jellyfin: `slavy` via key (LAN 192.168.100.100).
- dApp server .162: `slavy` / password (in wallet-backup, gitignored), sudo.
- Private keys: `wallet-backup/PRIVATE-KEYS.md` (gitignored) + `scratchpad/founder.pk`. Never committed.

## Contracts (CREATE2, 2026-06-27)
See `contracts/REGENESIS-ADDRESSES-2026-06-27.md`.

## Testnet → mainnet transition (DECIDED 2026-06-29)

The public testnet is **not** run in parallel with mainnet. When mainnet (`gemba-1`, EVM `821206`) is
prepared: `gemba-testnet-1` is **stopped** and its boxes (validators `.82/.83/.84`, archive `.137`,
explorer `213.136.85.32`) are **cleaned and reused for mainnet** — no new fleet is bought. Ongoing
upgrade testing thereafter runs **locally on jellyfin `.100`** as an **on-demand 4-validator testnet**,
spun up from the genesis generators only to rehearse a binary/consensus upgrade before it touches the
value-bearing mainnet, then torn down. (`.100` already runs testnet val3 today.) Full rationale:
`docs/public-rpc-topology.md` and `CLAUDE.md §13`.
