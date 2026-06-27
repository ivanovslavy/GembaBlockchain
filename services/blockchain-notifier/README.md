# blockchain-notifier

Email-only alerting for GembaBlockchain. **One `NETWORK` switch (`testnet` | `mainnet`) drives
everything** — deploy the same code twice (one instance per network); every email is labelled
`[GembaChain · TESTNET · …]` / `[GembaChain · MAINNET · …]` in the subject and carries the
chain-id in the body, so the two streams can never be confused.

> Status: **built, not started.** It runs in DRY-RUN (logs, never sends) until SMTP is set. The
> gembachain.io mail domain + mailboxes (`testnet@`, `mainnet@`, `contacts@`) are being created.

## What it watches

| Source | What | How |
|---|---|---|
| **Validators** | new validator · jailed · unjailed | Cosmos REST (`/cosmos/staking` + `/cosmos/slashing`) |
| **GMB sales** | every GembaPay GMB sale | EVM `Dispensed(to,amount,ref)` event on the GembaPay dispenser (`0x0EB2…`) |
| **Uptime** | rpc1/2/3 + explorer down/recovered | HTTP/JSON-RPC probes |
| **Risk** | validator share ≥30%/≥33%, Nakamoto=1, active < 4, bonded-ratio <50%/<33%, large sale (>10%/>25% of bonded), fast rises | computed from the above |

Thresholds are mathematically grounded (BFT 1/3 & 2/3, the S>B/2 sale-danger derivation,
bonded-ratio ADR-008) and **relative** so they auto-scale as the network grows — see
`docs/notifications-implementation-plan.md`. All are env-tunable.

## Email design

- **From** `${NETWORK}@gembachain.io` (sender encodes the environment) · **To** `contacts@gembachain.io`.
- Same SMTP credentials as the gembachain.io contact form (only sender/recipient differ).
- No Telegram — email only, by design.

## Run

```bash
npm install
cp .env.example .env          # fill SMTP_* when the mailboxes exist; blank SMTP_HOST => DRY-RUN
npm run once                  # one-shot, prints what it WOULD send (great for a pre-SMTP smoke test)
npm start                     # daemon (use the systemd unit in production)
```

Without SMTP it logs every alert as `[DRY-RUN EMAIL]` — so the watchers are fully testable before
the mailboxes exist. The EVM (sales/uptime) watchers work from anywhere; the **validator watcher
needs Cosmos REST** which is firewalled.

## Deploy on .162 (when SMTP is ready) — the two prerequisites

1. **Cosmos REST access (Option A):** on the archive node **`.137`**, allow `1317` **from the
   notifier host only** (e.g. `ufw allow from <.162-ip> to any port 1317 proto tcp`). 1317 stays
   closed to the public.
2. **SMTP:** create `testnet@gembachain.io` / `contacts@gembachain.io` (+ SPF/DKIM/DMARC for
   gembachain.io) and fill `SMTP_*` in `.env`.

Then install `systemd/blockchain-notifier.service`, `systemctl enable --now blockchain-notifier`.
Pick the next free port only if you add an HTTP surface (currently none — it's a poller).

## Mainnet later

Copy the deploy with `NETWORK=mainnet`, the mainnet `GEMBA_CHAIN_ID` / `COSMOS_CHAIN_ID` /
endpoints, and `MAIL_FROM=mainnet@gembachain.io`. Nothing else changes.
