# /explorer — GembaScan (Blockscout) + optional ping.pub

Self-hosted block explorers for GembaBlockchain (Phase 7).

- **GembaScan = Blockscout** (Docker) for the **EVM side**: blocks, transactions,
  balances, token/contract pages, **Solidity contract verification**, an
  **Etherscan-compatible API** (+ REST v2 + GraphQL), and **self-issued API keys**.
- **ping.pub** (optional) for the **Cosmos side**: staking / governance / validator
  views (those live in Cosmos modules, not the EVM).

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
docker compose up -d            # UI on http://localhost, API on :4000/api
```

Images are pinned in `docker-compose.yml`. The backend reads internal txs via
`debug_traceBlockByNumber` (callTracer) from the archive node.

> Note: the live Blockscout UI/API needs Docker. In the dev environment used to
> build this, Docker was unavailable, so we verified the layer Blockscout consumes
> — see "Verified against the archive node" below — and provide the full,
> reproducible setup here (one `docker compose up` away).

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
curl "http://localhost:4000/api?module=account&action=balance&address=0x963E...&apikey=YOUR_KEY"
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
