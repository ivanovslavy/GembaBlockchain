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

## 7. Gas pricing — ~1 gwei (low but non-zero), NOT free

> **EXECUTED (2026-06-09):** the 1 gwei floor is now live as a **consensus `x/feemarket`
> param**, applied by an actual on-chain governance round (proposal **#2**, PASSED). A real
> transfer pays ~0.000021 GMB (21,000 gas × 1 gwei) — fractions of a cent, but **not zero**.
> Block time is **~5 s** (not 2 s). All public copy must say "near-zero / ~1 gwei", never
> "free", and "~5 s blocks", never "2 s".
>
> **Correction to the earlier (2026-06-08) note:** that note claimed the floor was already
> live, but only the **node-level** `--minimum-gas-prices 1000000000agmb` start flag had been
> set — a *local mempool filter on each validator*, **not** the chain's consensus param. The
> `x/feemarket` `min_gas_price` was still **`0`** (and `base_fee` had decayed to ~`7e-18`),
> so `eth_gasPrice` could still read ~0 from any node not enforcing the flag. The governance
> change below is what actually moved the **consensus** param to 1 gwei.

Earlier (2026-06-06) the testnet ran `x/feemarket` with `min_gas_price = 0`, so the EIP-1559
base fee decayed to ~0 and `eth_gasPrice` read 0 (txs paid ~1 wei). The toggle instructions
below remain valid if a zero-gas testnet is ever wanted again (submit the same proposal with
`base_fee`/`min_gas_price` set back to `"0.000000000000000000"`).

**To restore the 1 gwei floor** (done on testnet 2026-06-09; same recipe for mainnet),
it is a governance change to `x/feemarket` (authority = the gov module account),
**not** an explorer setting. Voting period on testnet is ~30 s. Recipe:

```jsonc
// feemarket-prop.json  — gembad tx gov submit-proposal feemarket-prop.json
{
  "messages": [{
    "@type": "/cosmos.evm.feemarket.v1.MsgUpdateParams",
    "authority": "cosmos10d07y265gmmuvt4z0w9aw880jnsr700j6zn9kn",
    "params": {
      "no_base_fee": false, "base_fee_change_denominator": 8,
      "elasticity_multiplier": 2, "enable_height": "0",
      "base_fee": "1000000000.000000000000000000",       // 1 gwei = 1e9 agmb/gas
      "min_gas_price": "1000000000.000000000000000000",  // the floor
      "min_gas_multiplier": "0.500000000000000000"
    }
  }],
  "deposit": "20000000agmb",
  "title": "Restore 1 gwei gas floor",
  "summary": "Set x/feemarket min_gas_price + base_fee to 1 gwei per Phase 4 / §16.8"
}
```

Submit + deposit, then vote with bonded validators (quorum 33.4%, threshold 50%);
the validator operator keys (`val0..val3`) live in the re-genesis keyring backup.
Type URL `/cosmos.evm.feemarket.v1.MsgUpdateParams` verified against the live binary.

### Executed run — 2026-06-09 (gov-flow rehearsal, proposal #2)

Ran the full flow end-to-end to (a) rehearse the governance path on testnet and (b) make the
live consensus param match the "~1 gwei" policy. Verified result:

- **Before:** `min_gas_price = 0`, `base_fee = 0.000000000000000007` (decayed to ~0).
- **After (PASSED):** `min_gas_price = base_fee = 1000000000.000000000000000000` (1 gwei).
  Public RPC confirms: block `baseFeePerGas = 0x3b9aca00` (1.0 gwei), `eth_gasPrice` ≈ 1.125 gwei.
- Tally: 3 validators voted YES = 3000 GMB of 3990 bonded → **75 % turnout** (> 33.4 % quorum),
  100 % yes (> 50 % threshold). One ~30 s voting round; whole flow ≈ 1.5 min.

**Mechanics used (keys stay on the laptop — never copied to a server):**

- Operator/voting keys = `wallet-backup/tmp-regenesis/node{0,1,2,3}/keyring-test` → `val0..val3`
  (`~/.gemba-testnet` is the *stale pre-regenesis* keyring — do NOT use it). Each operator
  account carries a large liquid balance, so it self-funds gas + the 20000000agmb deposit.
- `.82` CometBFT RPC is bound to `127.0.0.1:26657` (not public), so broadcast from the laptop
  through an SSH local-forward: `ssh -i ~/.ssh/gemba_claude -N -L 26657:127.0.0.1:26657 root@13.140.139.82`.
- Common tx flags: `--chain-id gemba-testnet-1 --node tcp://127.0.0.1:26657 --keyring-backend
  test --gas auto --gas-adjustment 1.4 --gas-prices 1000000000agmb -y`.
- **Timing gotcha:** the testnet voting period is only **30 s**. Submit, then `sleep ~9` (one
  block, so the proposal is created and the proposer's sequence increments), then cast all
  votes back-to-back **in one uninterrupted script** — interactive round-trips between submit
  and vote will blow past the 30 s window (the proposal then fails quorum and you re-submit).

> **MAINNET "dead time" caveat.** The 30 s `voting_period` is a **testnet-only convenience** for
> fast iteration. **On `gemba-1` (mainnet) the real designed delay applies** — the full
> governance voting period **plus** the Timelock execution delay (the deliberate "dead time" so
> the community can see and block a change before it executes, per CLAUDE.md §7). Do **not**
> ship mainnet with a shortened voting period; a feemarket change there takes days, by design,
> not ~1.5 min.

## 8. RESOLVED — browser HTTP 500 on search / Tokens (was a version mismatch)

> **FIXED 2026-06-07:** root cause was a **backend↔frontend version mismatch** — frontend
> `v2.3.5` requires backend **v9.1.x** but the backend was **v7.0.2**, so pages crashed
> client-side (the frontend referenced API fields the old backend doesn't return) while every
> API call returned 200. Fix = align versions to a published, compatible pair:
> **backend `ghcr.io/blockscout/blockscout:9.0.2` + frontend `ghcr.io/blockscout/frontend:v2.3.0`**
> (per the compatibility matrix; 9.1.x had no published docker image). Migrations 7→9 ran
> cleanly on a 23 MB DB (backed up first via pg_dump). Tokens/search/login all work and the UI
> is faster. **Lesson: bump backend and frontend together to a matrix-compatible pair.**
> Original investigation kept below.

**Symptom (2026-06-06):** in the browser, typing a contract address in the search box,
and opening the **Tokens** page, show an **HTTP 500**.

**What we verified — it is NOT reproducible server-side.** Every relevant endpoint returns
**200** when hit directly (curl, incl. with cookies + cache-busting; Cloudflare reports
`cf-cache-status: DYNAMIC`, i.e. uncached):
- `/api/v2/search?q=…` → 200, `/api/v2/tokens` → 200
- frontend SSR `/search-results`, `/tokens` → 200, and their `/_next/data/<buildId>/*.json` → 200
- `/node-api/csrf` → 200 (after the Apache `get_csrf` stub, §explorer-account-login runbook)

**Leading hypotheses (to confirm):**
1. **Stale client** — the browser is running a cached app bundle / service worker from before
   the fixes. Test in a **fresh incognito window** or after **clearing site data**; if it's
   gone there, it's client cache.
2. **Frontend/backend version skew** — the explorer runs `frontend:latest` (v2.3.5) against
   `backend:7.0.2`. Blockscout warns these must be bumped together (see the pinned
   `explorer/docker-compose.yml` comments). A client-side handler in v2.3.5 may throw on a
   backend 7.0.2 response shape. **Fix path:** pin the frontend to the version Blockscout
   ships for backend 7.0.2 and re-test.

**To action this:** open DevTools → Network, reproduce, and capture the exact failing
request (URL + status + response body). That pinpoints whether it's a specific API call,
a `/node-api/*` route, or a client render error. Until then this is logged, not fixed.
