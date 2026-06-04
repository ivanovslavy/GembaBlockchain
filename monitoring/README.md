# /monitoring — GembaBlockchain node monitoring (Phase 9)

Prometheus + alerting for node operators, with the **bonded ratio as a first-class
security metric** (ADR-008).

## Files

| File | Purpose |
|---|---|
| `prometheus.yml` | scrape config: CometBFT (`:26660`), app telemetry, node_exporter |
| `alerts.yml` | alert rules: bonded-ratio thresholds (66/50/33, ADR-008), chain halt, low peers, disk |
| `bonded-ratio-exporter.sh` | computes `gemba_bonded_ratio` (bonded / circulating) and writes a node_exporter textfile metric |

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
