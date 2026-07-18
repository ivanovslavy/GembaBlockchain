# GembaBlockchain — progress log

> Running change log (rule 3/5). Newest first. Detailed history lives in git; this file
> captures notable milestones and decisions. NOTE: this repo is PUBLIC (CLAUDE.md §0.3)
> and this file is tracked — keep operational secrets out (they live in gitignored
> local files / the secret store). Docs in English (rule 1).

## 2026-07-19 — full-repo code review → mainnet-readiness cleanup
Read-only review (3 passes: contracts, chain/infra, hygiene) then a same-day fix sweep:
- **Launch blocker fixed:** `gemba-validator/src/chain` was a 40-day-stale snapshot missing
  the mainnet formula reward model + gov kill-switch + P-3 ldflags — a validator built from
  the package would have earned NO rewards on mainnet. Refreshed via the documented
  `git archive` procedure, verified byte-identical, and re-synced after later chain edits.
- **CI activated:** `tests.yml` (forge + go, was `.proposed`) — and it immediately caught a
  real reproducibility bug: fresh `forge install` pulls OZ with nested libs, auto-inferred
  remappings enter solc metadata → DIFFERENT bytecode → the gembaswap pair init-code hash
  and CREATE2 §41 address determinism break on any fresh checkout. Fixed by pinning all 5
  remappings + `auto_detect_remappings=false`. CI green (170/0 forge; go all ok).
- **Ceremony traps removed:** stale `QUORUM_PCT=66` instruction in DeployGovernance.s.sol
  (would revert the mainnet deploy) + block-time comment drift corrected.
- **Dead code removed:** HelloGemba.sol, SeamProbe.sol, the Phase-1 vanilla-evmd init
  scripts (init-single-node/init-multinode/start-single-node); GembaFaucet marked
  TESTNET-ONLY (live at 0x0147...f8aA, deliberately not in mainnet deploys);
  src/onramp → src/payments rename (OnRamp is gone); stray MIT/^0.8.20 headers normalized.
- **Docs de-drifted:** README (build status was ~7 phases behind; launch gates all resolved:
  ADR-009 withdrawn, ADR-006 cleared, ADR-008 done), .env.example reconciled with the real
  key set, this file's stale "private repo" claim fixed (repo is public by design).
- **Guards added:** CI cmp-check keeps the gembapay hardhat drop-in byte-identical to
  src/payments/GmbCollector.sol; gitleaks allowlist got the KEYALGO false-positive pinned
  by exact string (not path).

## 2026-07-17/18 — mainnet prep milestones (recorded from git)
- **Genesis + product decisions locked** (owner): GMB pure utility coin — no liquidity, Buy-GMB
  via dispenser only; `GembaOnRamp` removed entirely; "only validators vote at launch" via the
  vGMB wrapper + EXCLUDE_EXTRA; contract set final.
- **Readiness-audit remediation:** mainnet genesis builder with a 33-check verification
  battery (`init-gembad-mainnet.sh`), exclusion pipeline, gmb1/2/3 RPC map, key-ceremony kit
  (`scripts/key-ceremony.sh` + runbook), 4th genesis validator = `.208`.
- **ADR-006 CLEARED** (owner accepts the upstream-audit gate; pinned v0.7.0 carries all
  advisory fixes incl. ASA-2026-002).
- **Validator auto-ops:** auto-unjail rewritten as a 3-layer watchdog (detect-stuck →
  restart → sync-gate → unjail) + node-watchdog + disk-guard + alert email; in repo +
  runbook, pending activation on the boxes.

## 2026-07-13 (later) — final architecture decided
- **Target architecture locked in** (`docs/runbooks/target-architecture.md`, supersedes the
  pruned-node/router workarounds): archive + Blockscout **co-located on a Hetzner cax31** (real
  NVMe, ARM) reading over internal localhost RPC — no tunnel/router/pruned-node. Replaces the
  `.137` archive + `213.136.85.32` explorer Contabo boxes. Only the I/O-bound archive goes
  Hetzner; validators + mgnuniverse stay Contabo.
- **Testnet → on-demand:** after the big tests, unbond the Contabo testnet validators (leaving
  `.100` as sole 100% validator, **stopped by default**, started only to test before big
  updates), wipe + repurpose the Contabo boxes as mainnet validators, and repurpose **`.137`
  (big SSD) → mgnuniverse.com** (SSD/space ideal for 4K video; random-I/O weakness irrelevant
  for media serving). ARM prerequisite: one-time verify an arm64 gembad build syncs (app-hash
  is arch-independent) + Blockscout arm64 image.

## 2026-07-13
- **72h endurance run PASSED** (1.037M tx, 99.996% mined, 0 failedSubmit; no day1→day3
  drift). Added best-effort **revert-reason logging** to `endurance/lib/receiptCollector.js`
  and a **5× load** variant `endurance/run-72h-5x.sh` (20 TPS, `FUND_PER_WALLET=100` per the
  gas math). See `docs/endurance-test-2026-07-10-72h.md`. 5× 72h run launched (~ends 07-16).
- **Explorer under load:** the single archive `.137` can't both sync fat 5× blocks and serve
  Blockscout's read load (Contabo "NVMe" ≈ HDD ~250 MB/s; ~0.5 blk/s apply vs chain 0.43).
  Applied stopgap tuning (archive `evm-timeout 5s→60s`; Blockscout fetcher throttles) so it
  lags ~17 min gracefully instead of freezing; also fixed a 53 GB docker-log balloon on the
  explorer box (log rotation). Full detail + **candidate mainnet settings**:
  `docs/runbooks/explorer-dedicated-node-and-indexing-tuning.md`.
- **TODO (testnet now + mainnet on launch):** stand up a **dedicated pruned node** on real
  NVMe (Hetzner) as the explorer's RPC source instead of the archive. Contabo is 5-6× weaker
  than Hetzner for disk I/O — mainnet needs Hetzner for the I/O-bound roles (archive/explorer).

## 2026-06-10
- Ecosystem-wide infrastructure audit + documentation pass (see `~/Documents/Claude`):
  servers, apps, repos, email and the rule-7 source/public split are now documented.
- `progress.md` added to satisfy the per-project rule (CLAUDE.md was already present).
- Full local backup of all 22 GitHub repos taken to `~/repos-backup/` before any edits.
- Secret scan of the repo: clean (no keys/mnemonics/tokens tracked or in history).

## Earlier (from git history — highlights)
- Phases 0–9 + public testnet built: Cosmos-EVM `gembad`, custom modules
  (`rewardstreamer`, `feesplit`, `slashfunds`, `tailreward`), OZ-v5 treasury/governance
  contracts, paymaster, access NFT, on-ramp (later removed 2026-07-17), ticketing,
  Blockscout explorer, monitoring.
- See `git log` and `CLAUDE.md` (§13 phased plan) for the authoritative record.
