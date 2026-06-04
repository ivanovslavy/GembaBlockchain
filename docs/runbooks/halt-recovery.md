# Runbook — chain halt recovery

A CometBFT BFT chain **halts** (stops producing blocks) when it cannot reach +2/3
voting power on the next block. This is a **coordinated, social** recovery — there
is no admin key that can force-produce blocks (by design, §6). Triggered by the
`ChainHalted` alert (`monitoring/alerts.yml`).

## 1. Confirm and diagnose

- Confirm height is stuck across **multiple independent** nodes (not just yours):
  `gembad status | jq .sync_info.latest_block_height` on several validators.
- Check consensus state: `gembad query consensus state` / the CometBFT
  `:26657/dump_consensus_state` — which validators are missing precommits?
- Classify the cause:
  - **Liveness (≥1/3 offline):** enough validators down/unreachable that the set
    can't reach +2/3. Most common. Fix = get validators back online.
  - **App-level non-determinism / consensus failure:** nodes disagree on the app
    hash (`AppHash` mismatch) or a module panicked in a block. Needs a fix +
    coordinated restart, often a state-export/migrate.
  - **Network partition:** validators are up but can't see each other → peers/seeds.

## 2. Liveness halt (the usual case)

1. Page the down validators' operators; bring their nodes back up.
2. Verify peer connectivity (`gembad net-info`); fix `persistent_peers`/`seeds`
   (see `node-setup.md`) and firewalls.
3. Once > 2/3 voting power is online and connected, the chain resumes on its own —
   no manual block production.
4. BFT tolerates `f` of `3f+1` down; the genesis set is ≥4 so 1 down is fine (§5.3).
   If the active set itself dropped below the BFT minimum, governance/operators must
   bond enough validators back (§5.5 liveness guard).

## 3. App-level halt (AppHash mismatch / module panic)

1. **Stop all validators** at the same (last good) height. Do NOT let a subset keep
   trying — you want a clean coordinated restart.
2. Identify the bug (logs show the panicking module / the height where app hashes
   diverged). If a custom module is implicated (`x/rewardstreamer`, `x/feesplit`,
   `x/tailreward`), reproduce on a devnet from the exported state.
3. Build a fixed binary. If the fix is state-breaking, export state
   (`gembad export --height <h>`), migrate, and produce a new genesis with
   `initial_height` set; otherwise just patch the binary.
4. Distribute the fixed binary + (if any) the patched genesis to **all** operators
   via the same channel used for upgrades (see `coordinated-upgrade.md`).
5. Operators replace the binary/genesis and restart **together**; the chain resumes
   from the agreed height.

## 4. After recovery

- Post-mortem: root cause, timeline, and a regression test (for a module bug, a
  failing test that the fix makes pass — this repo's modules already carry
  supply-invariant and reentrancy tests; add one for the new fault).
- If the halt was caused by a custom module, the fix ships via the normal
  coordinated upgrade, not a hotfix to a single node.
