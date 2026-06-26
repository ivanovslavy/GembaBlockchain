# /monitoring — GembaBlockchain node monitoring (Phase 9)

Prometheus + alerting for node operators, with the **bonded ratio as a first-class
security metric** (ADR-008).

## Files

| File | Purpose |
|---|---|
| `prometheus.yml` | scrape config: CometBFT (`:26660`), app telemetry, node_exporter; forwards alerts to Alertmanager |
| `alerts.yml` | alert rules: bonded-ratio (66/50/33, ADR-008), chain halt, low peers, disk, **economic-module-stalled** |
| `alertmanager.yml` | routes firing alerts to the operator **by email** (gembascan.io SMTP) |
| `bonded-ratio-exporter.sh` | computes `gemba_bonded_ratio` (bonded / circulating) and writes a node_exporter textfile metric |

## How you (the operator) receive alerts — EMAIL

The chain is **fail-soft**: it keeps producing blocks even if the fee-split or reward
stream silently breaks (AU-1), and a halt/low-peers/disk problem won't email anyone by
itself. Alertmanager closes that gap — **every firing alert is emailed to you**.

**Delivery path:** node metrics → Prometheus (`alerts.yml` evaluates them) →
**Alertmanager** (`alertmanager.yml`) → **email to `ivanovslavy@gmail.com`**.

**Setup (once, on the monitoring box):**
1. Run Alertmanager next to Prometheus (`:9093`), pointed at `alertmanager.yml`.
2. Fill the 3 SMTP fields in `alertmanager.yml` with the **gembascan.io contact-form
   mailbox** (`smtp_smarthost`, `smtp_from`, `smtp_auth_username`).
3. Put that mailbox's **password** in `/etc/alertmanager/smtp_password` (root-owned,
   `chmod 600`). It is read at runtime via `smtp_auth_password_file` and is **never**
   committed — this repo is public, so no secret goes in git.

**What gets emailed:** chain halt + bonded-ratio red line (critical, re-notified every
30 min); fee-split / reward-streamer / tail-reward stalls, low peers, disk pressure,
bonded-ratio below target/floor (warning, re-notified every 3 h). Subject line:
`[GembaChain <severity>] <AlertName>`. You also get a "resolved" email when it clears.

> The three economic-module alerts (`FeeSplitStalled`, `RewardStreamerStalled`,
> `TailRewardStalled`) need the counters from the modules' BeginBlockers — enable
> `[telemetry] enabled = true` + `prometheus-retention-time > 0` in `app.toml`, and roll
> out the binary that has the `telemetry.IncrCounter` calls. Confirm the exact metric
> names at the node's `/metrics` (`gemba_feesplit_skipped_blocks`, etc.).

## Enable the metric sources on the node

- **CometBFT** (`config.toml`): `[instrumentation] prometheus = true` → `:26660`.
- **App telemetry** (`app.toml`): `[telemetry] enabled = true`.
- **node_exporter** with the textfile collector, pointed at the dir the exporter writes.

## Bonded ratio (the security KPI — ADR-008)

With zero inflation there is no dynamic-inflation lever, so the bonded ratio is the
metric governance defends, using the two levers in ADR-008 (tail-reward rate + gas
floor). The exporter computes **bonded / circulating** (circulating = total supply
minus the non-voting reserves, §3.4) — the security-relevant denominator, since
reserves are never staked. Thresholds:

| Level | Ratio | Alert |
|---|---|---|
| target | ≥ 66% | — |
| floor | < 50% | warning |
| red line | < 33% | critical (below 1/3, halting is cheap) |

Run the exporter on a 1-minute timer:
```bash
REST_URL=http://localhost:1317 OUT=/var/lib/node_exporter/textfile/gemba.prom \
  ./bonded-ratio-exporter.sh
```
Add the real reserve addresses to the `RESERVES` list for the target network.

Grafana: chart `gemba_bonded_ratio`, `cometbft_consensus_height`,
`cometbft_p2p_peers`, and disk usage; the bonded-ratio panel is the headline
security health indicator.
