# GembaBlockchain — notifications implementation (plan + built service)

Companion to `GembaBlockchain_Известявания_и_Аларми.md`. The service is **built** in
`services/blockchain-notifier/` and runs in DRY-RUN until SMTP is provided. Email-only (no
Telegram, by design). **One `NETWORK` switch serves testnet now and mainnet later.**

## Where it runs
gembachain.io is a **static** site on **.162 (46.225.1.162)** — no backend there. The notifier
is a **separate poller service on .162** (its email infra already exists on that box). It needs
**no public DNS** (outbound email + polling only) and currently **no port** (it's a poller, not
an HTTP server) — assign the next free port (e.g. 3115) only if an HTTP surface is added later.

## Email design (decided)
- **From `${NETWORK}@gembachain.io`** (sender encodes the environment) → **To `contacts@gembachain.io`**.
- Subject `[GembaChain · TESTNET · <severity>] <event>`; body first line `Network: … / EVM chainId …`.
- Same SMTP credentials as the gembachain.io contact form; only sender/recipient differ.
- Pending on your side: create the gembachain.io mail domain + `testnet@` / `mainnet@` / `contacts@`
  mailboxes (+ SPF/DKIM/DMARC for gembachain.io), then fill `SMTP_*` in the service `.env`.

## Sources (what is built)
- **A. Validators** (Cosmos REST): new validator · jailed · unjailed.
- **B. GMB sales** (EVM): the GembaPay dispenser's `Dispensed(to,amount,ref)` event = "GMB sold".
  The dispenser (`0x0EB2…`, `docs/gembapay-gmb-dispenser.md`) is the single on-chain source of
  truth — the notifier watches only that contract; **no coupling to GembaPay internals**.
- **C. Uptime** (HTTP): rpc1/2/3 + explorer down/recovered.
- **D. Risk alarms** (computed): see thresholds below.

## Alarm thresholds (mathematically grounded, all env-tunable, **relative** so they auto-scale)
Base: BFT halts at **>1/3**, forges at **≥2/3**. Genesis = 4 validators × 10k = 25% each.

| Metric | Threshold | Why |
|---|---|---|
| Single-validator share | warn **≥30%**, crit **≥33.3%** | ≥1/3 ⇒ one validator can halt the chain |
| Nakamoto coefficient | crit **=1** | one operator controls ≥1/3 |
| Active validators | crit **<4** | BFT N≥3f+1: below 4 can't tolerate one failure |
| Single GMB sale | warn **>10%** of bonded, crit **>25%** | a buyer adding S to bonded B passes 1/3 at **S>B/2** |
| Bonded ratio | warn **<50%**, crit **<33%** | ADR-008 security KPI (target 66%) |
| Rate of change | share **+5pp/7d**, bonded **−10pp/7d** | catches accumulation (delegations aren't capped) |

These tighten as the set grows (25%/validator is normal at genesis — ADR-010).

## Deploy prerequisites (when SMTP is ready)
1. **Option A — Cosmos REST whitelist:** on the archive node **.137 (13.140.148.137)** open
   `1317` **only to .162** (`ufw allow from <.162-ip> to any port 1317 proto tcp`). 1317 stays
   closed to the public; the validator/bonded watchers need it (the EVM sale/uptime watchers
   don't — they're already validated live).
2. **SMTP** mailboxes + creds → service `.env`.
3. Install `systemd/blockchain-notifier.service`, enable + start.

## Status — LIVE on .162 (2026-06-27)
Deployed + running (systemd, auto-restart), sending real email `testnet@gembachain.io →
contacts@gembachain.io`:
- **`blockchain-notifier.service`** — all four sources live: GMB sales (Dispensed event, verified
  live), uptime, validators (new/jailed/unjailed) and risk alarms (share/Nakamoto/count/large-sale).
- **`notifier-rest-tunnel.service`** — the chosen secure path: on the archive (.137) Cosmos REST
  is enabled on **localhost only**; a persistent restricted SSH tunnel forwards `127.0.0.1:1317`
  on .162 → .137 `localhost:1317`. **No public port, no firewall hole.** (The archive's REST was
  off; enabled in `/root/.gembad-archive/config/app.toml` `[api] enable=true`, localhost bind.)
- **Bonded-ratio alarm disabled on testnet** (`TH_BONDED_*=0`) — at bootstrap almost nothing is
  staked vs the 100M supply, so the ratio sits ~0.1% and the alarm is noise. Mainnet re-enables it.
- Contact form (`contact-form.service`) live behind `gembachain.io/api/contact`.

The pre-written defensive governance proposal (§4 of the companion doc) remains the only authoring
task — text + params + a ready `cast` script for incident response.
