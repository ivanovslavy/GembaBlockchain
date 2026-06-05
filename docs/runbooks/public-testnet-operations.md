# Runbook — public testnet operations (gemba-testnet-1)

> Operational record + how-to-correct guide for the **public** `gemba-testnet-1`
> deployment (EVM chainId 821207). Captures what was migrated, where things run,
> and the non-obvious gotchas hit along the way. Secrets, the operator's home IP,
> and exact keys are **not** here (gitignored `.env` / local secret store).
> Status snapshot: [`../testnet-status.md`](../testnet-status.md).

## 1. Current topology (4 validators)

| moniker | host | role |
|---|---|---|
| gemba-tn-contabo-1 | Contabo `13.140.139.82` (FR) | validator **+ archive node + GembaScan + RPC** |
| gemba-tn-contabo-2 | Contabo `13.140.139.83` (FR) | validator |
| gemba-tn-contabo-3 | Contabo `13.140.139.84` (FR) | validator |
| gemba-tn-val-node2  | operator LAN node, behind NAT | validator (dials out to the Contabo nodes) |

Each validator self-bonds 1,000,000 GMB. **Decommissioned** (was a 7-validator set):
the original laptop/LAN `node0`, `node1`, `node3` — removed by **unbonding their full
self-stake** (see §3), not by just stopping the process.

## 2. Access

- Contabo boxes: SSH **key-only** (password auth disabled). Automation key + an
  operator `slavy` user with NOPASSWD sudo. LAN nodes: operator user via SSH key.
- Per-box services are **systemd** units; the explorer stack is **docker compose**.
- Exact IPs/keys/node-ids are in the local agent memory + `.env`, not committed.

## 3. Validators — add / remove (THE important procedures)

**Binary:** `/usr/local/bin/gembad` (same checksum on every host). Distribute by
`scp` of the built binary (it only needs glibc) — no per-host build, no GitHub key.

**Add a validator** (permissionless dynamic join — full procedure in
[`testnet-deploy.md`](./testnet-deploy.md) §7):
1. `gembad init <moniker>` (fresh, **unique** consensus + node key — never reuse).
2. Copy the canonical `genesis.json` (sha must match), set `persistent_peers`,
   `addr_book_strict=false`, `mempool.type="app"`, `minimum-gas-prices`,
   `--evm.evm-chain-id 821207`.
3. systemd unit, `ufw allow 22` **then** `26656`, start, wait `catching_up=false`.
4. Fund the operator from the faucet, then `tx staking create-validator`.

**Remove a validator — terminate participation, don't just stop it:**
> Just stopping a bonded validator leaves it in the bonded set; if too many are
> offline-but-bonded the chain **halts** (needs >2/3 of the bonded set online).
1. `gembad tx staking unbond <valoper> <full-self-stake>agmb --from <operator>` →
   the validator drops out of the active set immediately (UNBONDING + jailed, 0
   voting power). Do this **one at a time**, verifying the chain still produces.
2. Only then `systemctl disable --now` the node process.

**BFT NAT gotcha:** if multiple validators sit behind one NAT (shared public IP),
the public peers reject the duplicates unless they have **`allow_duplicate_ip=true`**.
A NAT'd validator participates fine by **dialing out** to the public peers (no inbound
port-forward required; A1-style CGNAT often blocks inbound anyway).

## 4. Explorer + RPC (host `13.140.139.82`, `/root/gembascan`)

- A dedicated **archive node** (`gembad-archive.service`, home `/root/.gembad-archive`,
  `pruning=nothing`, JSON-RPC on `0.0.0.0:8545` but **ufw-restricted to docker
  subnets** `172.16.0.0/12`, not public) feeds Blockscout.
- Blockscout stack: `db`, `redis`, `sc-verifier`, **backend `blockscout:6.8.0`**,
  **frontend pinned `v1.36.3`**, published on `127.0.0.1:{4000,3000}` (localhost only).
- **Apache** terminates TLS with a **Cloudflare Origin cert** (`/etc/ssl/cloudflare/`),
  same-origin reverse proxy: `/`→frontend, `/api`+`/socket`→backend, **`/rpc`→archive
  :8545** (the public MetaMask RPC). Cloudflare proxy (orange) ON, SSL **Full(strict)**.
- Brand assets in `/var/www/gembascan-brand`, served by Apache at `/brand/`
  (excluded from the proxy with `ProxyPass /brand !`).

### Explorer gotchas (how to correct)
- **Frontend/backend version pairing.** Frontend tag MUST match the backend's API
  contract. Backend `6.8.0` → frontend `v1.36.3` (last on the `tx_types` field shape).
  A newer frontend (`v1.37.0`) expects `transaction_types` + sends an
  `updated-gas-oracle` header → homepage `undefined.sort()` → "500 Oops". Bump both
  together. See [`/explorer/README.md`](../../explorer/README.md).
- **Network logo/icon must be an absolute URL.** `NEXT_PUBLIC_NETWORK_LOGO/ICON` are
  URL-validated at startup — a **relative path crashes the frontend** (503 crash loop).
  But an absolute URL on a custom domain is rejected by `next/image`'s build-time
  domain allowlist (400 "url not allowed"), so the sidebar icon shows a blank box.
  The **favicon works** regardless (generated server-side from `FAVICON_MASTER_URL`),
  which is what shows the brand in the browser tab. Don't "fix" the sidebar icon with
  a relative path — it takes the whole frontend down.
- **CORS / same-origin.** Serving UI + API + RPC from one origin (Apache) avoids the
  cross-origin CORS + `wss` issues entirely.

## 5. MetaMask + chain registry

- MetaMask: RPC `https://testnet.gembascan.io/rpc`, explorer
  `https://testnet.gembascan.io`, chainId **821207**, symbol **GMB**.
- Network + native-coin **icon in MetaMask/chainlist** comes from
  `ethereum-lists/chains` (not our explorer). Submission payloads are in
  [`../chain-registry/`](../chain-registry/) (chain JSON prettier-formatted to pass
  their CI; icon pinned to IPFS). Fine-grained PATs can fork + push but **cannot open
  the PR to the upstream** (403) — that is a manual click. First PRs also wait on a
  maintainer to approve the CI workflows.

## 6. `gembascan.io` domains

`gembascan.io` is **reserved for the future mainnet explorer**. `testnet.gembascan.io`
is the current testnet explorer/RPC. When mainnet launches it gets its own
(mainnet-pointed) explorer + archive instance on `gembascan.io`.
