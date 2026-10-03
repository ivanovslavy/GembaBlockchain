# Plan — refresh the validator binary (October 2026)

**Status: PLANNED, not executed.** Nothing in this document has been applied to a live box.

## Why this is needed

On 2026-10-03, validator **.83** (`cosmosvaloper19527lffudd9cx00ptr5ghvxgyhqeqgv6sjd000`) was found
unable to add anything to its stake since **2026-09-21** — 13 days, ~650 GMB of lost compounding.
Every attempt, down to **1 agmb**, came back:

```
would add 1 to its stake today, exceeding the 50000000000000000000/day max bond
increase (governance-set, x/valgate §6); already added 50000000000000000000 today
```

The chain was never at fault. Three measurements separate the two:

1. The committed §6 counter for .83 (`abci_query /store/valgate/key`, key `0x02 ++ valoperBytes`)
   read **day 20716 (2026-09-20), 50 GMB** — honestly stale, and `keeper.dailyBondUsed` treats a
   stored day that is not the current day as zero. Nothing in consensus blocked a new bond.
2. The **same signed transaction** was accepted (`code=0`) by the archive node and rejected by
   .83's own node.
3. After .83's `gembad-val` restarted, its own node accepted the delegation too — and kept
   rejecting it before the restart **even once the committed counter had been refreshed to the
   current day**, which no reading of the committed store can explain.

So: **the node's CheckTx view of the §6 counter had gone stale and never rolled over.** Its last
successful bond (2026-09-20) left "50 GMB used, day 20716" in the node's own check state; because
that remembered day equals the day of the last success, the keeper's staleness guard could never
fire, and the counter only refreshes when a bond *succeeds*. A self-sustaining lockout, node-local,
invisible to every other node, and clearable only by restarting the process.

Two more facts from the same session:

- `gembad-val` on .83 **panicked** during the investigation:
  `panic: runtime error: invalid memory address or nil pointer dereference` in
  `github.com/cosmos/evm/mempool/internal/queue`, reached through an ordinary transaction check on
  the local CometBFT RPC. systemd restarted it in ~5 s; no jail, no missed-block penalty.
  **Exposure, stated precisely:** the node binds 26657/8545/8546/9090 to `127.0.0.1` only, `ufw`
  opens 22 and P2P 26656 to the world and 443 to the Cloudflare ranges only — so the CometBFT RPC
  path that produced the panic is not remotely reachable. The public EVM endpoints, however, are
  served through that 443 proxy into `127.0.0.1:8545`, and a submitted EVM transaction enters the
  **same mempool component**. Whether this specific nil-pointer is reachable that way is unproven
  and deliberately untested against live validators. Treat it as unbounded until the binary is
  refreshed: that is what moves this plan from hygiene to priority.
- `/check_tx` on this build is **not** read-only: cosmos/evm's mempool inserts the transaction, so
  a "probe" is a broadcast. Three probe transactions landed on chain during the investigation.

Both live in **cosmos/evm v0.7.0's** mempool, not in our modules — and both are the real reason to
refresh the binary rather than only patch the ops scripts.

## The defect, located in upstream code (2026-10-03)

The investigation above said the node's CheckTx view had gone stale. The code says exactly how.

`cosmos/evm`'s mempool **replaces the application's CheckTx**: `NewCheckTxHandler` takes
`_ sdk.RunTx` — it never calls it — and simply decodes the transaction and inserts it into the
custom mempool, returning the insert error as the CheckTx code. (This is also why `/check_tx` on
this build is not a read-only probe: it inserts, so it broadcasts.) The insert path is
`RecheckMempool.Insert` in `mempool/recheck_pool.go`:

1. it branches the rechecker's **long-lived cached context** (`TxRechecker.ctx`),
2. runs the **full ante handler** against that branch — including x/valgate's §6 decorator, which
   *writes* the per-validator daily-bond counter,
3. and on success calls `write()`, persisting those ante writes **back into the cached context**.

That cache is only rolled over by `doRecheck`, which calls `rechecker.Update(latestCtx, newHead)`
on each new head — and which **logs and returns silently** when `GetLatestContext` fails
(`recheck_pool.go`: `"failed to get context for recheck"`). That the call can fail is not
hypothetical: .83's own journal carries `ERR failed to initialize rechecker context err="failed
to get latest context: …"` from the same path at startup.

So once the refresh stops, every later CheckTx is judged against the block time **and the
accumulated ante writes** of the moment it froze. For .83 that moment was its successful compound
on 2026-09-20: counter at 50 GMB, day stuck at 20716. Nothing could bond — and because the counter
only advances on a *successful* bond, nothing could ever roll it over either. Self-sustaining,
node-local, silent.

The panic has the same origin: `insert()` runs that ante inside the queue's **own goroutine**
(started by `queue.New`), where nothing recovers, so a nil `AuthInfo.Fee` reaching
`x/auth/ante.SetUpContextDecorator` killed the process.

### The fix, and how it is proven

`chain/gembad/gembad-mempool-fixes.patch` (tracked, applied by `build-gembad.sh` after the wiring
patch, on the pin bumped to **v0.7.3**):

| defect | fix | proof |
|---|---|---|
| panic in the queue worker kills the node | `recover()` in `insertTxs`, turning the panic into an error for the batch — what baseapp already does for the same ante synchronously | regression test added to upstream's own `queue_test.go`. **Against unpatched v0.7.3 it does not fail — it crashes the test binary**, with the same stack shape as the live crash (`created by …queue.New[...]`). Patched: PASS |
| new transactions judged against a frozen context | `Insert` compares the cached context's height with the chain head and refreshes instead of trusting it | the guard cannot fire on a healthy node (heights track); devnet Phase 1 test 1 asserts it stays quiet while transactions flow |

`go test ./mempool/...` on the patched tree: every package ok except
`TestNewEVMMempoolIterator_BothEmpty`, which **fails identically on a clean v0.7.3 clone** — a
pre-existing upstream failure, not ours. Don't chase it.

Built artefact (reproducible, from a clean tree): `version: 87c6577`, **no `-dirty`**, go1.25.9,
`sha256 8b94496c4b92d936cd816420018ab9e191039f47ada7f1fd22a4601e948a8d70`.

## What is running, and why it is not reproducible

```
gembad version --long  →  version: d8a454f-dirty   commit: d8a454f
/usr/local/bin/gembad  →  built 2026-06-26 22:46, md5 59fd14b9e705c59de82960edab80e4ad
```

`build-gembad.sh` stamps the version from `git describe --tags --always --dirty` of `chain/`, so
**`-dirty` means the tree carried uncommitted modifications when the binary was built.** The live
state machine therefore corresponds to *no commit in this repository*: it is `d8a454f` plus work
that was only committed later (or never). That is the deeper problem to remove — a chain whose
source of truth is unrecoverable cannot be audited, reproduced, or safely patched.

## This is a CONSENSUS-BREAKING upgrade — not a rolling one

`git diff --stat d8a454f..HEAD -- chain/` touches the state machine:

| change | commit | effect |
|---|---|---|
| valgate §6 cap on the EVM staking precompile | `677e5e2` (audit M1) | new rejection path during EVM execution |
| valgate genesis caps | `5f82ba4` (audit H1) | genesis validation |
| rewardstreamer formula + gov-gated `MsgUpdateFormulaParams` | `5f82ba4`, `0459bf2` (M2, M4) | **per-block minting changes** |
| begin-blocker order assertion | `f808ab1` (audit L1) | startup assertion |

Swapping one box at a time would diverge the app hash and fork that box off the chain. The swap
must happen at a single height for every validator: **`docs/runbooks/coordinated-upgrade.md` path A**
(`software-upgrade` proposal + staged binary), or path B (announced simultaneous halt and swap) on
a testnet where coordination is a single operator. Rolling is not an option.

## Phases

### Phase 0 — recover a buildable source of truth
1. `git -C chain status --porcelain` must be empty; build from a tagged commit and confirm the
   version string has **no `-dirty`**.
2. Decide the upstream pin: `EVM_VERSION` is `v0.7.0`. Check the cosmos/evm releases after v0.7.0
   for the mempool nil-pointer fix; bump to the first tag that carries it, re-apply
   `gembad-wiring.patch` (`git apply --recount`), refresh the patch if upstream moved `app.go`.
   If no upstream fix exists, carry the one-line guard as a tracked patch beside the wiring patch —
   never as an uncommitted edit.
3. Record in the release notes: upstream tag, chain commit, `sha256` of the binary.

### Phase 1 — devnet acceptance (throwaway 4-node chain)
Run `chain/scripts/` multinode start, honouring the two known traps: the gentx must pass
`--min-self-delegation $(gmb $MIN_SELF_BOND_GMB)` (valgate rejects the default of 1 at genesis) and
transactions need `--gas-prices >= 5000000000agmb` (the 5 gwei floor).

Acceptance tests, all of which must pass before any live box is touched:
1. **The §6 invariant that broke:** bond up to the cap, then assert for every node that the
   verdict its own CheckTx gives (`/check_tx` of a 1 agmb delegate) agrees with the committed
   counter read from `/store/valgate/key`. Disagreement = the bug is still present.
2. **Day rollover:** with the counter at the cap, cross UTC midnight (or run the devnet with a
   genesis time placed just before it) and confirm the next bond succeeds **without a restart**.
3. **Panic replay:** on the devnet, replay the transaction shape recorded in the incident notes
   against both the CometBFT and the EVM submit paths, and confirm every node stays up. This is the
   test that decides whether the public endpoints were ever exposed — run it on the devnet, never
   against a validator carrying voting power.
4. **Compounding at the cap:** `auto-compound.sh` logs `today's §6 allowance:` with the real
   remainder and tops up only the difference.
5. Chain-level: 4/4 signing, no app-hash mismatch in any journal, a deliberate jail still recovers
   through the watchdog.

### Phase 2 — live rollout (one height, all boxes)
1. **Backup first:** per box, `cp /usr/local/bin/gembad /usr/local/bin/gembad.PROVEN-d8a454f-dirty`
   (md5 `59fd14b9e705c59de82960edab80e4ad`) and snapshot `priv_validator_key.json` +
   `priv_validator_state.json`. Rollback is then one `cp` and a restart.
2. Stage the new binary on all six boxes (4 validators, archive `.137`, explorer node) **without**
   swapping.
3. Announce/submit the upgrade height. At the height: halt, swap, restart, in the order
   **archive → .82 → .84 → node2 → .83** (archive first: it carries no consensus weight, so it
   proves the binary starts and replays before any voting power moves).
4. **Never two validators down at once** — the bonded set would drop below the 2/3 quorum and the
   chain would halt. This is the same rule as the 2026-07-31 jail drill.

### Phase 3 — verification per box
- `gembad version --long` → the expected commit, **no `-dirty`**.
- synced (`catching_up=false`), peers > 0, signing (appears in `/commit`), not jailed.
- `gemba-auto-compound.sh --dry-run` → exit 0 and a sane `today's §6 allowance:` line.
- The §6 invariant from Phase 1 test 1, run against the live box.

## Mitigation already in place (does not need the upgrade)

`auto-compound.sh` now reads the **real** remaining allowance from the chain instead of clamping to
the 50 GMB limit, and when the local node refuses a delegation that the committed state allows it
says so explicitly, submits through `FALLBACK_NODE` if one is configured, and **e-mails** after two
consecutive failed days. The 13-day silence was the second failure in this incident: the compound
had no alerting at all, while jails and disks have had it since 2026-07-18.

See also: `docs/runbooks/coordinated-upgrade.md`, `docs/runbooks/validator-auto-ops-deploy.md`,
`docs/runbooks/halt-recovery.md`.
