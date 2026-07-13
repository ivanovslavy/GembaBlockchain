# Runbook — dedicated PRUNED node for the explorer

> **SUPERSEDED (2026-07-13) — see `target-architecture.md`.** The final decision is a plain
> archive + Blockscout **co-located on a Hetzner cax31** (real NVMe), which removes the need for
> a pruned node, RPC router, or tunnel entirely. Kept for reference / as a fallback pattern.

Goal: give GembaScan/Blockscout its **own** RPC node so its read load stops fighting the
validators / the `.137` archive. Origin: 2026-07-13 — under the 5× endurance run the single
Contabo archive `.137` (HDD-speed disk) couldn't both sync fat blocks and serve the explorer,
so it fell behind (~+6 min lag/hour). A pruned node keeps a **small state DB that lives in
RAM**, so Contabo's slow disk is barely touched → it keeps up while serving. See
`explorer-dedicated-node-and-indexing-tuning.md` for the incident.

## The pruned-vs-archive tradeoff (read first — honest)

`node-setup.md` warns the explorer "MUST point at an archive — never pruned." That is true
for **deep-historical** queries: a pruned node errors on historical-state calls (e.g. balance
at an old block) and can't re-serve traces for blocks older than its keep-recent window.

Why it's fine here anyway, on **testnet**:
- Blockscout traces blocks **as they arrive** (recent) — a pruned node has that state, so
  real-time indexing + `call_tracer` internal txs work.
- We keep a **generous keep-recent window** (~2.7 days) — Blockscout stays minutes behind on
  a node that keeps up, so it never approaches the window edge.
- The testnet is periodically **re-genesis'd**, so deep history isn't precious.
- Keep the **`.137` archive alive as a fallback** for the rare deep-historical lookup.

**Mainnet:** deep history matters — there, run a proper **archive on strong hardware**
(Hetzner NVMe), or pruned-primary + archive-secondary. Do NOT ship mainnet on a lone pruned
node without an archive somewhere.

## What you actually keep vs lose with pruning (FAQ — read this before panicking)

Common confusion: "pruned = I lose my history / old txs will error." **No.** The key is the
distinction between **Blockscout's own stored data** and **the node's live state**:

- When Blockscout **indexes** a block (as it arrives), it writes the transactions, receipts,
  logs, created contracts, and internal-tx traces into its **own PostgreSQL DB**. From then on
  that data is **permanent and independent of the node's pruning**.
- Pruning on the node only drops **old world-state** (the account/storage tree at old heights).
  It affects only queries that must **re-execute against ancient state**.

| You look at… | Served from | Works on pruned? |
|---|---|---|
| An old tx — incl. a **contract deploy** (input bytecode, constructor args, created address, logs) | Blockscout Postgres | ✅ yes |
| Who deployed a contract, when, its verified source, internal traces of that tx | Blockscout Postgres | ✅ yes |
| "Read Contract" tab (current values) | `eth_call` at **current** block | ✅ yes |
| "Balance/state of address **as of an old block**" | live re-exec vs old state | ⚠️ needs archive |
| Full Blockscout **re-index from scratch** (DB wiped) → re-trace blocks older than keep-recent | node historical state | ⚠️ needs archive |

Concrete: opening a 10-day-old deploy tx to see how a contract was deployed → **works fine**,
it's a DB read, not a node-state query. You only feel the limit for the two ⚠️ rows above
(rare), which is exactly what the `.137` archive fallback covers. This is why pruned-primary +
archive-fallback is safe on testnet.

## Box

Contabo **VPS 20 (6 vCPU / 12 GB RAM / SSD)** recommended. Why: pruned is disk-light, so RAM
(to keep the small state cached, dodging Contabo's slow disk) matters more than cores; 6 cores
give apply+serve headroom under 5×. VPS 10 (4c/8GB) likely works for low traffic but tighter.
Disk size is a non-issue (pruned stays tens of GB). NOT a validator; NOT co-located with one.

## Exact fixed values (from the live network — do not change)

| | |
|---|---|
| chain-id | `gemba-testnet-1` |
| evm-chain-id | `821207` |
| minimum-gas-prices | `1000000000agmb` |
| genesis.json | sha256 starts `d7cdc2c1...`, 22985 bytes — **copy the exact file** |
| gembad binary | `d8a454f-dirty` (custom build) — **copy the exact binary**, do NOT rebuild |
| persistent_peers | `44935754a7ea7e5ced5528eb39b5b4f6de73d3bb@13.140.139.82:26656,5473057935d09332c6051e7e83902ae226e060d2@13.140.139.83:26656,b7588b7dcd3e90bc0306dce68f7c95c5306d74a6@13.140.139.84:26656` |

> **App-hash safety:** the binary is a `-dirty` local build. A *different* binary caused an
> app-hash divergence during the 2026-06-06 regenesis. Copy `/usr/local/bin/gembad` and
> `genesis.json` **byte-for-byte** from an existing node — never `go install` a fresh build.

## Steps

### 1. Copy binary + genesis from an existing node
```bash
# on the NEW box (as root):
scp root@13.140.148.137:/usr/local/bin/gembad /usr/local/bin/gembad
chmod +x /usr/local/bin/gembad
gembad version                                   # must print d8a454f-dirty
export HOME_DIR=/root/.gembad-explorer
gembad init gemba-tn-explorer --chain-id gemba-testnet-1 --home $HOME_DIR
scp root@13.140.148.137:/root/.gembad-archive/config/genesis.json $HOME_DIR/config/genesis.json
sha256sum $HOME_DIR/config/genesis.json          # must start d7cdc2c1
```

### 2. config.toml (`$HOME_DIR/config/config.toml`)
```toml
moniker = "gemba-tn-explorer"
[p2p]
persistent_peers = "44935754a7ea7e5ced5528eb39b5b4f6de73d3bb@13.140.139.82:26656,5473057935d09332c6051e7e83902ae226e060d2@13.140.139.83:26656,b7588b7dcd3e90bc0306dce68f7c95c5306d74a6@13.140.139.84:26656"
pex = true
addr_book_strict = false        # peers are behind NAT/cloud; be lenient
```

### 3. app.toml (`$HOME_DIR/config/app.toml`)
```toml
minimum-gas-prices = "1000000000agmb"

# PRUNED — small state DB, lives in RAM, keeps ~2.7 days of state history.
pruning = "custom"
pruning-keep-recent = "100000"   # ~2.7 days @ 2.3s; raise to 200000 for more recent depth (bigger DB)
pruning-interval = "10"
min-retain-blocks = 0            # keep block bodies (Blockscout reads blocks); state is what's pruned

[json-rpc]
enable = true
address = "0.0.0.0:8545"
ws-address = "0.0.0.0:8546"
api = "eth,net,web3,debug,txpool"   # 'debug' is REQUIRED for call_tracer internal txs
evm-timeout = "60s"                 # same lesson as .137 — 5s cuts off fat-block traces
http-timeout = "120s"
gas-cap = 25000000
```

### 4. Bootstrap the state (state-sync is NOT available yet — pick one)
`snapshot-interval = 0` on all current nodes and their `:26657` is localhost-only, so
state-sync can't run out of the box. Options:

- **A. Genesis replay (foolproof, slow):** just start the node; it replays from block 0.
  On Contabo expect several hours to a day for ~620k+ blocks. Fine to leave running.
- **B. State-sync (fast, needs prep):** on `.137` set `snapshot-interval = 1000`,
  `snapshot-keep-recent = 3`, restart it, wait for one snapshot; expose its `:26657` to the
  new node (SSH tunnel); then on the new node set `[statesync] enable = true`,
  `rpc_servers = "<two .137 :26657 endpoints>"`, `trust_height`/`trust_hash` from
  `curl .137:26657/block`. Faster but more moving parts.

Recommend **A** for a one-off; **B** if you'll rebuild nodes often.

### 5. systemd unit `/etc/systemd/system/gembad-explorer.service`
```ini
[Unit]
Description=Gemba testnet PRUNED node (explorer source)
After=network-online.target
[Service]
User=root
ExecStart=/usr/local/bin/gembad start --home /root/.gembad-explorer --chain-id gemba-testnet-1 --evm.evm-chain-id 821207 --minimum-gas-prices 1000000000agmb --pruning custom --pruning-keep-recent 100000 --pruning-interval 10 --json-rpc.enable=true --json-rpc.address 0.0.0.0:8545 --json-rpc.ws-address 0.0.0.0:8546 --json-rpc.api eth,net,web3,debug,txpool
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
```
```bash
systemctl daemon-reload && systemctl enable --now gembad-explorer
```

### 6. Firewall
- Open **26656/tcp** (p2p) to the internet.
- Do NOT expose **8545/8546** publicly — the explorer reaches them over an SSH tunnel only
  (same pattern as `archive-rpc-tunnel.service`). Bind-firewall 8545 to the tunnel.

### 7. Verify it's synced
```bash
gembad status --home /root/.gembad-explorer 2>&1 | grep -o '"catching_up":[a-z]*'   # want false
# EVM height should track the live tip:
curl -s -X POST -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545
```

### 8. Repoint Blockscout at the new node
On `213.136.85.32`: point the autossh RPC tunnel at the new node instead of `.137` (or add a
second tunnel), then in `/root/gembascan/envs/backend.env` set `ETHEREUM_JSONRPC_HTTP_URL`
and `ETHEREUM_JSONRPC_TRACE_URL` to the new node's tunneled `:8545`, and
`docker compose -p gembascan up -d --force-recreate --no-deps backend`. Keep the `.137`
archive running as a deep-history fallback. Once stable, the Blockscout throttles added
2026-07-13 (`INDEXER_*_CONCURRENCY/BATCH_SIZE`) can be relaxed toward defaults.

### 9. Prove it under load
The real test: repoint while the 5× (or any high-load) run is live and watch the gap. If the
pruned node holds near the tip (explorer lag stays ~minutes, not growing), it's validated —
worst case handled.

## Option B — transparent archive fallback (optional)

Gives you **pruned speed + archive completeness**, transparently: Blockscout points at a tiny
RPC router; the router sends everything to the **pruned** node and only retries on the **`.137`
archive** when the pruned node reports it doesn't have that historical state. The rare deep
queries hit the archive; everything else stays on the pruned node. The archive's tip-lag is
irrelevant here (deep queries are for OLD blocks the archive already has).

Blockscout won't do this alone — you run a ~50-line failover proxy in front of both upstreams
(on the explorer box; both nodes reached over the existing SSH-tunnel pattern).

`gemba-rpc-fallback.js` (no deps beyond node's http):
```js
// Primary = pruned (real-time). Fallback = .137 archive, used ONLY on state-miss errors.
const http = require('http');
const PRUNED  = process.env.PRUNED_RPC  || 'http://127.0.0.1:8545'; // pruned node (tunnel)
const ARCHIVE = process.env.ARCHIVE_RPC || 'http://127.0.0.1:8547'; // .137 archive (tunnel)
const PORT    = Number(process.env.PORT || 8600);
// substrings meaning "pruned node lacks that historical state" — VERIFY against gembad's
// actual error text and adjust:
const STATE_MISS = ['missing trie node','required historical state','state not available',
                    'header not found','not available on pruned'];
const forward = (url, body) => new Promise((res, rej) => {
  const u = new URL(url);
  const r = http.request({hostname:u.hostname, port:u.port, path:u.pathname||'/', method:'POST',
    headers:{'content-type':'application/json','content-length':Buffer.byteLength(body)}},
    x => { let d=''; x.on('data',c=>d+=c); x.on('end',()=>res(d)); });
  r.on('error', rej); r.write(body); r.end();
});
const needsArchive = t => { const s=t.toLowerCase(); return STATE_MISS.some(m=>s.includes(m)); };
http.createServer((creq, cres) => {
  let body=''; creq.on('data',c=>body+=c);
  creq.on('end', async () => {
    try {
      let out = await forward(PRUNED, body);
      if (needsArchive(out)) out = await forward(ARCHIVE, body); // fallback only on state-miss
      cres.writeHead(200,{'content-type':'application/json'}); cres.end(out);
    } catch (e) { cres.writeHead(502); cres.end(JSON.stringify({error:String(e)})); }
  });
}).listen(PORT, '127.0.0.1', () => console.log(`rpc-fallback :${PORT} pruned=${PRUNED} archive=${ARCHIVE}`));
```

Wire-up:
- Tunnel the pruned node to `127.0.0.1:8545` and the `.137` archive to `127.0.0.1:8547` on the
  explorer box.
- Run the proxy under systemd (`node gemba-rpc-fallback.js`), listening on `127.0.0.1:8600`.
- Point Blockscout `ETHEREUM_JSONRPC_HTTP_URL` + `ETHEREUM_JSONRPC_TRACE_URL` at
  `http://host.docker.internal:8600`; recreate backend.

Caveats:
- **Verify `STATE_MISS`** against gembad's real error strings (`curl` an `eth_call` at a very
  old block against the pruned node and copy the error text) — the fallback only fires on a match.
- **Batch requests** (JSON-RPC array): this skeleton resends the *whole* batch to the archive if
  any part misses — fine at low volume; split per-item if it ever matters.
- **WebSocket** (`:8546`) isn't proxied here — point WS straight at the pruned node.
- Adds one small component to maintain. On testnet, plain pruned + manual `.137` for the rare
  deep lookup is also fine; Option B shines on **mainnet**, where deep-history must be seamless.

## Rollback
Repoint the tunnel + `ETHEREUM_JSONRPC_HTTP_URL` back to `.137`, recreate backend. The archive
was never stopped, so this is instant.
