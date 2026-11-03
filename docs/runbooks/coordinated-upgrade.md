# Runbook — coordinated node-operator upgrade

Changing the chain's **binary / consensus rules** is a coordinated upgrade, not an
on-chain governance execution (CLAUDE.md §7: on-chain governance controls
contracts/treasuries/params; the binary is social coordination). Two paths:

## A. Governance-gated halt-and-upgrade (`x/upgrade`, recommended)

Deterministic: every validator upgrades at the **same height**, so there is no
fork.

1. **Proposal.** Submit a `software-upgrade` governance proposal naming the upgrade
   `name`, the target `height`, and the release `info` (binary URL + checksum):
   ```bash
   gembad tx gov submit-proposal software-upgrade <name> \
     --upgrade-height <H> --upgrade-info '<json: binaries + sha256>' ...
   ```
2. **Vote.** Bonded GMB votes via `x/gov` (chain-level governance, §7). The voting
   base is the consensus electorate (staked GMB), distinct from the treasury
   electorate (ADR-008b).
3. **Prepare.** Operators pre-stage the new binary. Recommended:
   [cosmovisor](https://docs.cosmos.network/main/tooling/cosmovisor) auto-swaps the
   binary at the upgrade height:
   ```
   cosmovisor/upgrades/<name>/bin/gembad   # staged ahead of time
   ```
4. **Halt & swap.** At height `H` the chain halts automatically; cosmovisor (or the
   operator manually) swaps to the new binary and restarts. Migrations registered
   for `<name>` run once. The chain resumes at `H+1` on the new rules.
5. **Verify.** All validators back online, same app hash, height advancing.

## B. Emergency coordinated restart (off-chain)

When the chain is already halted (see `halt-recovery.md`) and can't pass an on-chain
proposal:
1. Operators agree off-chain (the social layer) on the fix, the binary checksum, and
   the resume height.
2. Optionally `gembad export` → migrate → new `genesis.json` with `initial_height`.
3. Distribute binary + genesis via the agreed channel; verify checksums.
4. Everyone restarts **together** from the agreed height.

## C. Off-chain `halt-height` (what this four-validator testnet actually uses)

Path A without the voting period: every node gets `halt-height = H` in `app.toml`, the chain stops
at `H` by itself, every box swaps the binary, and the chain resumes once more than ⅔ of the voting
power is back. Rehearsed end to end on a devnet by `security/devnet/upgrade-rehearsal.sh`; facts it
measured that matter here: block `H` is **committed but not executed** by the old binary (the new
one executes it), a halted node **does not exit** (it idles with consensus stopped, so stop it
yourself), and nobody is jailed — a coordinated halt produces no missed blocks.

## The October–November 2026 binary refresh

Live testnet binary: **`39daa6e`** (cosmos/evm v0.7.3 + the mempool patch, sha256 `fd9deac7…b3e0`)
on all five boxes since 2026-10-03, rolled out canary-first because it was measured NOT
consensus-breaking. The next one — v0.7.4 + the valgate §6 fix + the BLOBBASEFEE fix — IS
state-machine-breaking and goes out by path C. The ready-to-run plan, with heights, order,
rollback and the expected sha256, is in
[`validator-binary-refresh-2026-10.md`](validator-binary-refresh-2026-10.md#the-live-upgrade--ready-to-run-plan).

## Rules

- **Same height, same binary, verified checksums** — a subset upgrading early/late,
  or running a different build, risks a fork or an AppHash halt.
- **Test first** (working rule §0.9): rehearse the upgrade on a devnet/testnet from
  exported mainnet-like state before the real one. Upstream cosmos/evm bumps
  (ADR-006) follow the same drill — pin, read release notes, isolate our modules.
- **Custom modules** (`x/rewardstreamer`, `x/feesplit`, `x/tailreward`) carry their
  own consensus version + migrations; bump the version when their state layout
  changes and register the migration under the upgrade `name`.
- Communicate the schedule to operators well ahead; keep a rollback plan (the prior
  binary) staged.
