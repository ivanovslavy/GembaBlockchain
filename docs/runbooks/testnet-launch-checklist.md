# Testnet launch checklist — first weeks of gemba-testnet-1

What to watch in the first weeks, treating it as the mainnet dress rehearsal. Wire
up `/monitoring` (Prometheus + Grafana + the bonded-ratio metric) on day 0.

## Day 0 — bring-up

- [ ] All 5 validators online; `validator set = 5`; height advancing ~2s on every node.
- [ ] Each node has **4 peers**, stable (no peer flapping in logs).
- [ ] `sha256` of `genesis.json` matches on all 5 nodes.
- [ ] Prometheus scraping all nodes; Grafana dashboard up; alerts firing test OK.
- [ ] Drip faucet `/health` returns the 20M balance; a test drip lands; cooldown works.
- [ ] One archive node (`pruning = nothing`) synced; GembaScan (Blockscout) indexing it.
- [ ] RPC/REST/JSON-RPC reachable only via HTTPS reverse proxy (not raw ports).

## Block production & liveness (continuous)

- [ ] `cometbft_consensus_height` increasing steadily; **no halts** (ChainHalted alert quiet).
- [ ] No validator missing precommits repeatedly (`/dump_consensus_state`); none jailed.
- [ ] Block time stays ~2s under idle and under load.
- [ ] Kill 1 validator on purpose: the chain **keeps producing** (BFT, 5 tolerate 1) —
      then bring it back and confirm it catches up. Repeat for each region.

## Bonded ratio — the security KPI (ADR-008)

- [ ] `gemba_bonded_ratio` exported and charted as the headline panel.
- [ ] Sits near the **66% target**; alerts configured at floor **50%** and red line **33%**.
- [ ] Rehearse the levers: enable/size the **tail reward** (`x/tailreward`) by
      governance and confirm the bonded ratio / validator rewards respond — and that
      **total supply stays constant** (see "zero inflation" below).

## Under real traffic (run a load test)

- [ ] Push sustained tx load (transfers + contract calls). Confirm **EIP-1559 base
      fee rises** with block fullness and **decays** when idle (the `demo-feemarket`
      behaviour) — never below the 1 gwei floor.
- [ ] Mempool stays healthy; no runaway pending; gas estimation works for apps.
- [ ] Deploy the Phase 3–8 contracts (governance, faucet, NFTs, on-ramp with its
      `publicSaleEnabled=false` default, tickets) and exercise the real flows end-to-end.

## Zero inflation (the marquee invariant)

- [ ] `gembad q bank total` / `eth` total supply **stays exactly the genesis amount**
      across weeks, even while the reward streamer and (if enabled) the tail reward
      pay validators — proves recirculation, never minting (§3.1). This is the same
      invariant the unit/integration tests assert; verify it holds on the live network.
- [ ] Faucet (40% fee inflow) and rewardstreamer (reserve draining) balances move as
      designed; no unexpected mints in any module.

## Resources & ops

- [ ] Validators **pruning** correctly — disk bounded, `NodeDiskFillingUp` quiet;
      archive node disk growing as expected (provisioned).
- [ ] CPU/mem/IO headroom under load; no OOM/restarts.
- [ ] Backups tested (restore a node from snapshot/state-sync) — `backups.md`.
- [ ] Validator keys on tmkms; failover drill done without a double-sign — `validator-keys.md`.

## Drills (do them on testnet, not first on mainnet)

- [ ] **Coordinated upgrade**: ship a no-op or small upgrade via `x/upgrade` +
      cosmovisor; all 5 swap at the same height, no fork (`coordinated-upgrade.md`).
- [ ] **Halt recovery**: induce a halt (e.g. take >1/3 offline), then recover per
      `halt-recovery.md`; time it.
- [ ] **Governance**: pass a parameter-change proposal end-to-end (propose → vote →
      execute) so the on-chain governance path is exercised before mainnet.

## Exit criteria (ready to plan mainnet)

Weeks of stable block production across regions, the bonded ratio held near target,
zero-inflation confirmed live, the upgrade + halt-recovery drills rehearsed, and the
remaining **non-code** hard blocker progressing on its own track: the **security audit
(ADR-006)** — required before any public mainnet launch. (The MiCA / public-sale gate
ADR-009 was withdrawn — no liquidity, no exchange, no public sale by design.)
