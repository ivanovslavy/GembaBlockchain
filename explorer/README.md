# /explorer — GembaScan (Blockscout) + optional ping.pub

Self-hosted block explorers for GembaBlockchain (Phase 7).

- **GembaScan = Blockscout** (Docker) for the **EVM side**: blocks, transactions,
  balances, token/contract pages, **Solidity contract verification**, an
  **Etherscan-compatible API** (+ REST v2 + GraphQL), and **self-issued API keys**.
- **ping.pub** (optional) for the **Cosmos side**: staking / governance / validator
  views (those live in Cosmos modules, not the EVM).

> **Production note (2026-06-29):** on the live testnet the Blockscout stack runs on a **dedicated box**
> (`213.136.85.32`, Contabo VPS 20 NVMe) **separate from the archive node** (`.137`), reaching the
> archive's RPC over a private **autossh tunnel** (`host.docker.internal:8545/8546`) — never co-located,
> never a public RPC. Inventory: `docs/SERVER-TOPOLOGY.md`; procedure: `docs/runbooks/explorer-migration.md`.

## CRITICAL: the explorer points at an ARCHIVE node, not a validator

Blockscout indexes **all** history — every block, every historical account state,
and per-block internal-transaction traces. That requires an **archive node**
(`pruning = "nothing"`, full history). But GembaBlockchain **validators run pruned
nodes** for disk economy (CLAUDE.md §11). So:

```
  validators (pruned)  ──p2p──►  dedicated ARCHIVE full node (pruning = nothing)  ◄── Blockscout
```

Run a dedicated, non-validator **archive full node** and point Blockscout's
`ETHEREUM_JSONRPC_*` URLs (`envs/backend.env`) at *its* EVM JSON-RPC — never at a
pruned validator (historical-state and trace queries would fail there).

Start an archive node (devnet example):
```bash
gembad start --home ~/.gembad-devnet --chain-id gemba-1 --evm.evm-chain-id 821206 \
  --pruning nothing \
  --json-rpc.enable --json-rpc.api eth,txpool,net,debug,web3
```

## Run GembaScan

```bash
# 1. create the real env from the committed template and set a real
#    SECRET_KEY_BASE (openssl rand -hex 32) + the archive node URLs:
cp envs/backend.env.example envs/backend.env   # backend.env is git-ignored (secrets)
# 2. bring up the stack (Docker required):
docker compose up -d            # UI + API on http://localhost  (single origin, see below)
```

Images are pinned in `docker-compose.yml`. The backend reads internal txs via
`debug_traceBlockByNumber` (callTracer) from the archive node.

> **Live.** GembaScan is running against the GembaBlockchain test network and is
> displaying real chain data, including the **first GMB transfer** (block 965). See
> [`docs/testnet-status.md`](../docs/testnet-status.md). Open `http://localhost/`
> on the host or `http://192.168.100.10/` from the LAN.

## Architecture: single-origin reverse proxy + version pairing

Two things must line up or the **UI shows a "500 — Oops! Something went wrong"
page even though the API answers fine from `curl`** (the failures are browser-only:
CORS preflight and JS field-shape errors, which `curl` never triggers):

1. **Single origin.** An nginx reverse proxy ([`proxy/gembascan.conf`](./proxy/gembascan.conf))
   is the only public entrypoint, on port **80**. It serves the frontend at `/`,
   proxies the backend API at `/api`, and proxies the live-update websocket at
   `/socket` as plain `ws`. Same-origin access (via the configured host) needs no
   CORS at all; for cross-origin callers (e.g. opening `http://localhost` while the
   app host is the LAN IP) the proxy adds a permissive CORS shim that **echoes the
   requested headers** — so any custom header the frontend sends is allowed,
   immune to frontend/backend skew. The frontend is configured with
   `NEXT_PUBLIC_API_PORT=80` and `NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL=ws` (the node
   is not TLS, so `wss://` would fail with `ERR_SSL_PROTOCOL_ERROR`).

2. **Frontend/backend version pairing.** The Blockscout **frontend tag must match
   the backend's API contract.** Backend `6.8.0` returns the `tx_types` field shape;
   the matching frontend is **`v1.36.3`** (the last on that contract). A newer
   frontend (`v1.37.0`) expects the renamed `transaction_types` field and sends a
   custom `updated-gas-oracle` request header — against backend `6.8.0` the homepage
   did `undefined.sort()` and fell into the 500 error boundary. **Bump the frontend
   and backend together**, and re-check the `tx_types` ↔ `transaction_types` cutover
   if you change either tag.

The `sc-verifier` image's compiled-in default points the Solidity compiler list at
the now-defunct `solc-bin.ethereum.org`; `docker-compose.yml` repoints it at the
live `binaries.soliditylang.org` and disables the zkSync-Era fetcher (we are not a
zkSync chain), so the verifier starts cleanly instead of crash-looping.

## Contract verification

Verify a deployed contract (e.g. `HelloGemba`) with the Foundry standard-JSON-input
in [`verify/HelloGemba.standard.json`](./verify/HelloGemba.standard.json):

- **UI:** contract page → Verify & Publish → "Standard JSON Input" → upload the
  file; compiler `v0.8.24`, optimizer on / 200 runs; constructor args (ABI-encoded)
  e.g. `0x...0e47656d62615363616e2064656d6f...` (`cast abi-encode 'constructor(string)' 'GembaScan demo'`).
- **Etherscan-compatible API:** `POST /api?module=contract&action=verifysourcecode`
  with `codeformat=solidity-standard-json-input`, `sourceCode=@HelloGemba.standard.json`,
  `contractaddress`, `constructorArguements`, and `apikey`.

Regenerate the artifact for any contract:
```bash
cd contracts && forge verify-contract <addr> src/HelloGemba.sol:HelloGemba \
  --show-standard-json-input > ../explorer/verify/HelloGemba.standard.json
```

## API keys + Etherscan-compatible API

GembaScan issues **per-instance API keys** from the Account UI (`ACCOUNT_ENABLED`),
which you pass as `?apikey=` to the Etherscan-compatible endpoint at `/api` (you
control the rate limits, self-hosted). Example call:

```bash
# via the single-origin proxy (port 80); the backend's :4000 is also published for
# direct/local API use.
curl "http://localhost/api?module=account&action=balance&address=0x963E...&apikey=YOUR_KEY"
# -> {"status":"1","message":"OK","result":"2001234000000000000000000"}
```

The same `/api` supports `module=account|contract|transaction|block|logs|stats|token`
— the Etherscan/Polygonscan-compatible surface, so existing tooling works unchanged.

## Verified against the archive node (what Blockscout will index)

On the gembad archive devnet we confirmed the exact data/endpoints Blockscout
consumes are served:

- **blocks & receipts:** a GMB transfer (block 6, status `0x1`) and a `HelloGemba`
  deploy were indexed-ready via `eth_getBlockByNumber` / `eth_getTransactionReceipt`.
- **historical account state (the archive property):** `eth_getBalance(dev1, 0x1)`
  = 2,000,000 GMB vs `latest` = 2,001,234 GMB — state at old heights is served (a
  pruned node would error "state not available").
- **internal-tx traces:** `debug_traceTransaction` (callTracer) → `CREATE` for the
  deploy; `debug_traceBlockByNumber` traced block 6 — the call Blockscout uses to
  index internal transactions.

## Cosmos side (ping.pub, optional)

See [`ping-pub/gemba.json`](./ping-pub/gemba.json) — a chain config for the ping.pub
explorer (staking/governance/validator views over the Cosmos REST 1317 / RPC 26657).
ping.pub is a static front-end; self-host by cloning it and dropping this config in
its chains directory. Lightweight — no archive node needed (it reads current Cosmos
state). Optional for Phase 7; can be deferred to Phase 9.
