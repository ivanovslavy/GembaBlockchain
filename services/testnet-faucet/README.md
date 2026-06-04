# testnet-faucet — gemba-testnet-1 drip faucet

Hands out **valueless test GMB** so developers can use the public testnet. Sends a
fixed amount from the testnet drip account, **rate-limited per recipient address and
per client IP** so no one can drain it.

- On `gemba-testnet-1`, the drip account is `tnfaucet` (see `chain/testnet`), funded
  with 20,000,000 test GMB at genesis. The faucet service holds its **testnet-only**
  key — never a mainnet key (CLAUDE.md §3).
- Tokens here have **no value** (it's a testnet).

## API

| Method | Path | Body | Result |
|---|---|---|---|
| GET | `/health` | — | `{faucet, balance, dripGmb}` |
| POST | `/drip` | `{"address":"0x..."}` | `{ok, to, amountGmb, txHash}` or `429` (cooldown) / `400` (bad address) |

## Run

```bash
npm install
npm test                      # rate-limit + validation unit tests (no chain needed)

FAUCET_KEY=0x<testnet-drip-key> \
TESTNET_EVM_RPC=http://<testnet-rpc>:8545 \
DRIP_AMOUNT_GMB=100 DRIP_COOLDOWN_MS=86400000 FAUCET_PORT=3002 \
  npm start
```

Put `FAUCET_KEY` (and any real config) in `.env` / a secret store — never commit it.
Front the service with the Apache reverse proxy + Let's Encrypt (HTTPS) and the
existing rate-limiting, as for the other public endpoints (CLAUDE.md §11).

## Verified

Against a local gembad node: a fresh address (0 GMB) received exactly 100 GMB
(`txHash` returned); a second request for the same address returned `429` with a
~24h `retryAfterMs`; an invalid address returned `400`.
