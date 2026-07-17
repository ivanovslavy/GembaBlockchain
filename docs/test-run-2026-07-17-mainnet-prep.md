# Test evidence — mainnet-prep changes, 2026-07-17 (curated record)

> The committed record the earlier audit found missing: raw runner output of the full
> suites AFTER the mainnet-prep change set (OnRamp removal, MsgUpdateFormulaParams,
> L1 wiring assertion, mainnet genesis builder, strict EXCLUDE_EXTRA, faucet mainnet
> guard, notifier/explorer/validator mainnet configs). Local toolchain: forge 1.7.1,
> go1.22.2 (module toolchain per `chain/go.mod`). Commits `bf10c97`..`0b61e3d`.

## Contracts — `forge test` (full suite)

```
Ran 26 test suites in 17.24s (83.80s CPU time): 170 tests passed, 0 failed, 3 skipped (173 total tests)
```

- 173 total = the previous 181 − 9 deleted OnRamp tests + 1 new exclusion-parsing test
  (which itself packs the empty/mainnet/malformed EXCLUDE_EXTRA paths).
- 3 skipped = the live-testnet fork tests (`LiveGov.t.sol`), skipped offline as designed.
- The stale `cache/test-failures` rerun-cache entry (`test_reserveProposal_isStandard`,
  a mid-fix leftover from 2026-07-13 that predated the M3 rename) was deleted — it was
  never a live failure.

## Chain — `go test -count=1 ./...` (fresh, uncached)

```
ok  github.com/ivanovslavy/GembaBlockchain/chain/tests                    0.045s
ok  github.com/ivanovslavy/GembaBlockchain/chain/x/feesplit/keeper        0.047s
ok  github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/keeper  0.053s
ok  github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types   0.042s
ok  github.com/ivanovslavy/GembaBlockchain/chain/x/slashfunds             0.053s
ok  github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/keeper      0.044s
ok  github.com/ivanovslavy/GembaBlockchain/chain/x/valgate                0.035s
ok  github.com/ivanovslavy/GembaBlockchain/chain/x/wiring                 0.028s
```

## Dynamic validation (same day)

- **Full `build-gembad.sh`** (cosmos/evm v0.7.0 + extended wiring patch) — clean build;
  patch verified with `git apply --recount --check` against pristine upstream files.
- **Mainnet genesis builder dry-run** (`init-gembad-mainnet.sh`): build → 33/33 verify
  assertions OK → throwaway 4-validator gentx ceremony → `collect` (validate-genesis OK,
  sha256 emitted) → **4-node network booted from the produced genesis and produced
  blocks (height 22 in ~30 s, no panics; the L1 wiring assertion active in the binary)**.
- **Faucet service** `npm test`: 16/16 (incl. the 3 new mainnet-guard cases against a
  local JSON-RPC stub).
- **Notifier config**: mainnet env resolves 821206 + gmb1; missing `COSMOS_REST` on
  mainnet fails loud; testnet path unchanged.

## Standing references (unchanged by this change set)

- `docs/audit-phase2-results-2026-07-13.md` — post-audit-fix devnet dynamic validation
  (downtime-slash→faucet 4/4, double-sign→tombstone 5/5, RPC hardening) + the original
  181/0 contracts run.
- `docs/mainnet-launch-hardening.md` §C — M1 devnet validation end-to-end (2026-07-17).
- A fresh `security/e2e/live-invariants.sh` run against MAINNET is a launch-day step
  (ceremony runbook Phase 7), not reproducible before the network exists.

## CI

A ready-to-enable GitHub Actions workflow is prepared at
`.github/workflows/tests.yml.proposed` (forge + go suites on every push). Rename to
`tests.yml` to activate — owner's call (kept inactive on request, 2026-07-17).
