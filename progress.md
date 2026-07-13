# GembaBlockchain — progress log

> Running change log (rule 3/5). Newest first. Detailed history lives in git; this file
> captures notable milestones and decisions. Private repo only (gitignored from any public
> mirror). Docs in English (rule 1).

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
  contracts, paymaster, access NFT, on-ramp, ticketing, Blockscout explorer, monitoring.
- See `git log` and `CLAUDE.md` (§13 phased plan) for the authoritative record.
