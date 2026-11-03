# Plan — refresh the validator binary (October 2026)

**Status:** the 39daa6e refresh was EXECUTED on 2026-10-03 (Phase 2 below). The follow-up halt-height
upgrade (valgate §6 + BLOBBASEFEE + cosmos/evm v0.7.4) is rehearsed and READY, NOT executed —
[jump to the plan](#the-live-upgrade--ready-to-run-plan).

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

Two further upstream questions were closed while picking the pin. The statedb locked-balance fix
(#1187, backported as #1189) is in **both** v0.7.0 and v0.7.3. But **#1254** — "harden statedb
balance and event amount handling", the backport of #1176, merged to `release/v0.7.x` on
2026-08-19 — is **not** in v0.7.0 and **is** in v0.7.3, so the pin bump brought it along. That
closes the ADR-006 residual action in the genesis ceremony in full.

`go test ./mempool/...` on the patched tree: every package ok except
`TestNewEVMMempoolIterator_BothEmpty`. **Corrected 2026-11-03:** that was not an upstream failure —
the cosmos/evm tests need `-tags=test` (`EVMConfigurator.ResetTestConfig` panics without it). With
`go test -tags=test ./mempool/... ./ante/evm/... ./x/vm/keeper/... ./x/vm/statedb/...` every
package passes, on the patched v0.7.3 and on the patched v0.7.4 tree.

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

## Is it consensus-breaking? Measured, not assumed — and the answer is no

The first draft of this plan said a rolling upgrade was impossible because `d8a454f..HEAD` touches
the state machine. That is true of the *code*; what matters is whether it changes **execution against
the state this chain actually holds**. Each change, checked:

| change | commit | effect on the live chain |
|---|---|---|
| rewardstreamer aggregate daily budget `MaxTotalPerDay` | `5f82ba4`, M4 | **inert.** The streamer binds it only `if budget.IsPositive()`, the live params predate the field so it unmarshals nil → `MaxTotalPerBlock()` returns zero, and nothing backfills a default on read. Even if it were set, four validators accrue ≈512 GMB/day against a 5,479 GMB/day budget |
| gov-gated `MsgUpdateFormulaParams` | `0459bf2`, M2 | a new message type — inert until one is submitted |
| valgate genesis caps | `5f82ba4`, H1 | `InitGenesis` only; never runs on a live chain |
| valgate §6 cap on the EVM staking precompile | `677e5e2`, M1 | the one real runtime change: a delegation **through the precompile** above the cap now fails. Nothing else moves |
| begin-blocker order assertion | `f808ab1`, L1 | startup assertion only — and the devnet boots with this exact wiring, so it passes |
| new/changed events | several | events and logs are excluded from `LastResultsHash`; they cannot diverge an app hash |

So the expected divergence surface is a single path (the staking precompile) that the founder
validators do not use. **That makes a canary possible, and a canary is strictly safer than halting
the chain.**

### Rollout shape: canary first, then one validator at a time

The **archive node** (`13.140.148.137`) is the ideal canary: it validates every block against the
live chain's app hash yet carries **no voting power**, so if the new binary computes anything
differently it halts *itself* with an app-hash mismatch and the chain does not notice. Swap it,
watch it follow the chain, and only then move voting power.

If the archive **does** diverge, the rolling path is off and the coordinated halt is mandatory:
set `halt-height H` on every node, let them all stop at the same height, swap, restart. Path A of
[`coordinated-upgrade.md`](coordinated-upgrade.md) with governance is the formal version; on a
four-validator testnet with a single operator, `halt-height` is the same thing without the voting
period.

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

### Phase 1 — RESULT (run 2026-10-03, 4-node devnet on the new binary)

| check | result |
|---|---|
| four validators produce and sign blocks | ✅ all four signing, chain `gemba-1` past height 140 |
| panics / app-hash mismatches in any node log | ✅ none (the only `appHash=` line is the height-0 handshake) |
| the stale-rechecker guard stays quiet on healthy nodes | ✅ zero occurrences across all four logs while transactions flowed |
| §6 cap enforced per validator, with the correct day | ✅ val0 at 50/50 refused a further 1 GMB with the proper message; val1, counter empty, accepted 1 GMB and recorded `day 20729 · 1 GMB` |
| the queue panic cannot kill a node | ✅ regression test passes patched; **crashes the test binary unpatched** |
| day rollover with a full counter | not run — it needs a UTC midnight. The rollover is demonstrated continuously on the live chain, where the three healthy validators' records advance 20717 → 20718 → 20719 daily; what failed on .83 was the frozen cache, which is what the guard addresses |

Two notes for whoever runs this next. `query valgate params` prints **only** `min_self_bond`
even though the store holds all three values (verified by reading key `0x01` directly on the
devnet: 1000 / 10000 / 50 GMB) — a display defect in the query response, not a state problem, and
**not** evidence about which valgate version a chain runs; an earlier draft of this document drew
exactly that wrong conclusion from the live chain. And `go test ./mempool/...` "fails" `TestNewEVMMempoolIterator_BothEmpty` only because it was
run without `-tags=test` (corrected 2026-11-03 — with the tag it passes).

### Phase 2 — live rollout (canary, then one validator at a time)
1. **Backup first:** per box, `cp /usr/local/bin/gembad /usr/local/bin/gembad.PROVEN-d8a454f-dirty`
   (md5 `59fd14b9e705c59de82960edab80e4ad`) and snapshot `priv_validator_key.json` +
   `priv_validator_state.json`. Rollback is then one `cp` and a restart.
2. Stage the new binary on all six boxes (4 validators, archive `.137`, explorer node) **without**
   swapping.
3. **Canary:** swap the archive `.137` only, restart it, and watch it follow the chain for at
   least 100 blocks — no app-hash mismatch, height advancing, peers > 0. This is the measurement
   that turns the analysis above into a fact. If it diverges, stop and switch to `halt-height`.
4. Then the validators, **one at a time**, in the order **.82 → .84 → node2 → .83**, each time
   waiting for ≥30 minutes of clean signing before touching the next. .83 last, since it is the
   box whose behaviour we understand least.
5. **Never two validators down at once** — the bonded set would drop below the 2/3 quorum and the
   chain would halt. This is the same rule as the 2026-07-31 jail drill.

### Phase 2 — RESULT (executed 2026-10-03 evening)

Artefact: `version 39daa6e`, no `-dirty`, go1.25.9,
`sha256 fd9deac77b0cd97a17d7cea41d7a7f7cf677f5a3e7c0fbbeb2c99a43fbd3b4e0` — built once and
**shipped** to every box; each box's hash compared before the swap, never rebuilt per box.

| box | before → after | result |
|---|---|---|
| archive `.137` (canary) | `d8a454f-dirty` → `39daa6e` | 64 blocks in 150 s, 3 peers, `catching_up=false`, **0** app-hash mismatches, 0 panics |
| `.82` | `d8a454f-dirty` → `39daa6e` | signing in the first block after the restart; **130/130** blocks signed over the following audit, weight unchanged, not jailed |
| `.84` | `d8a454f-dirty` → `39daa6e` | signing in the first block after the restart; **60/60** blocks over the window after it; weight unchanged |
| node2 `.208` | `d8a454f-dirty` → `39daa6e` | signing in the first block; 38/40 over its restart window; 3 peers, weight unchanged |
| `.83` | `d8a454f-dirty` → `39daa6e` | signing in the first block; 47/50 (the three being its own restart); weight unchanged |

Each box missed only the blocks of its own ~35 s restart — far from the jail threshold (more than
50 of 100). The chain never lost a block: with one validator restarting, three of four kept
signing, which is why **only ever one at a time**.

### Phase 3 — RESULT (verification per box)

```
.82     ✅ 39daa6e · sha fd9deac77b0c…      node2  ✅ 39daa6e · sha fd9deac77b0c…
.83     ✅ 39daa6e · sha fd9deac77b0c…      archive ✅ 39daa6e · sha fd9deac77b0c…
.84     ✅ 39daa6e · sha fd9deac77b0c…
```

No `-dirty` anywhere, one identical artefact on all five boxes. Signing over the 50 blocks after
the last swap: node2 50/50, .84 50/50, .82 50/50, .83 47/50 (its own restart). All four BONDED,
none jailed.

End-to-end on `.83`, the box the incident started on:

```
committed §6 counter : day 20729 · 49.0 GMB used
delegation           : …653248 → …653249   (+1 agmb, code=0, through ITS OWN node)
auto-compound        : "capped to the 999999999999999996 agmb still free under today's §6 cap"
stale-context guard  : 0 messages — silent on a healthy node
```

The counter it reads now agrees with the chain, it bonds through its own node, and the compound
sizes itself to the real remainder instead of asking for the full cap. The last end-to-end proof
is the 03:2x compound run after the next UTC midnight, when `.83`'s allowance resets to the full
50 GMB for the first time since 2026-09-20.


**Consensus compatibility: measured.** At the same height the canary on the new binary and two
validators on the old one returned the *identical* block hash and app hash — and then, with a real
transaction (a 1 agmb delegation, which exercises the ante, the §6 counter write, staking and
distribution), block `H`'s hash and block `H+1`'s app hash — the state *after* executing it — were
identical across new and old:

```
3671426  app=1CB016BC…A9F12D  txs=1     the block carrying the transaction
3671427  app=600D139B…8733A6            the state after it — same on new and on both old binaries
```

That is what justifies the rolling swap over halting the chain. Empty blocks alone would not have
proven it; insist on a transaction.

#### Two traps worth knowing before you repeat this

- **`grep -ci panic` over a node journal gives false positives.** `gembad`'s own `--help` lists
  `panic` as a log level, and the old process prints its usage on shutdown, so a clean swap reported
  "panics: 2" on `.84`. Match `^panic:|runtime error|SIGSEGV` instead, and confirm against
  `systemctl show -p NRestarts` — a real panic restarts the unit.
- **node2 (`.208`) needs no special binary handling.** Its container is plain `ubuntu:24.04` with
  the HOST's `/usr/local/bin/gembad` bind-mounted read-only, so swapping the host file and
  restarting `gembad.service` (not `gembad-val`, and with `sudo`) is the whole procedure.

Pause the box's `gemba-auto-unjail.timer` for the duration of each swap so the watchdog does not
race the restart, and start it again afterwards.

### Phase 3 — verification per box
- `gembad version --long` → the expected commit, **no `-dirty`**.
- synced (`catching_up=false`), peers > 0, signing (appears in `/commit`), not jailed.
- `gemba-auto-compound.sh --dry-run` → exit 0 and a sane `today's §6 allowance:` line.
- The §6 invariant from Phase 1 test 1, run against the live box.

## Found by the devnet acceptance run — a separate defect, deliberately NOT bundled

Delegating on the devnet with the new binary surfaced a defect of **our own module**, unrelated to
the mempool: a delegation that passes the ante and then **fails during message execution** still
burns the day's §6 allowance. Evidence, from the run:

```
tx:      code=5  failed to delegate; 1433817519999990000agmb is smaller than
                 50000000000000000000agmb: insufficient funds
stake:   unchanged
§6 record: day 20729 · used 50.0 GMB      <-- charged in full for a delegation that never happened
```

The cause is structural: `CheckAndRecordDailyBond` both checks *and writes* from the ante, and ante
state writes are intentionally kept when the message itself fails (that is how gas and sequence
survive a failed tx). So any delegation that reverts — out of gas, insufficient funds, a staking
error — costs the validator a day of compounding.

### What the fix looks like (designed, not yet implemented)

1. **Split the keeper call.** `CheckAndRecordDailyBond` becomes two: `CheckDailyBond` (read-only —
   reads the counter, compares, returns an error) and `RecordDailyBond` (the write). Nothing else
   about the §6 arithmetic changes.
2. **The ante only CHECKS.** `x/valgate/ante.go` calls the read-only variant. The cheap
   mempool-level rejection of an over-cap delegation is preserved, and — a second benefit worth as
   much as the first — **the ante stops writing state during CheckTx at all**, so the mempool's
   cached recheck context can never again carry a phantom "50 GMB already added". That is the same
   failure this upgrade patched in upstream; removing the write removes our half of it.
3. **Record where it reverts with the message.** Wire `CapEnforcingStakingMsgServer` (which already
   exists and is proven for the EVM precompile) into the staking message route itself, so the
   check+record runs inside the message's own cache: a delegation that fails afterwards rolls the
   counter back with it. It also picks up authz-wrapped delegations for free, since authz routes
   the inner message through the same router — today the ante has to unwrap `MsgExec` by hand.
   The staking hooks are NOT an option: `AfterDelegationModified` does not carry the amount.
4. **Tests:** the devnet scenario that exposed this (a delegation that passes the ante and fails on
   insufficient funds must leave the counter untouched), plus the existing cap tests, plus one for
   a two-delegation transaction where the second exceeds the cap.

**Why it needs its own upgrade.** The change alters *when* the counter is written. For a
**successful** delegation the end state is byte-identical, so the app hash matches the current
binary; the two diverge only on a delegation that **fails after the ante** — exactly the case being
fixed. A canary rollout would therefore look clean right up until someone's delegation fails
mid-window, which is precisely the wrong way to learn. So: `halt-height` on every node, swap, restart
— path B of [`coordinated-upgrade.md`](coordinated-upgrade.md). Bundle the regenerated
`params.pb.go` descriptor fix into the same swap, since it is inert and already in the tree.

### IMPLEMENTED 2026-10-04 (commits `26a12ab`, `87f161a`) — proven, awaiting the halt-height window

Artefact: `version 87f161a`, no `-dirty`,
`sha256 7df02eda9f61be2db9cbabcf6442f507bf7b970a1436ec30645037adf8c5aaa9`.

Devnet acceptance, reproducing exactly the scenario that exposed the defect:

```
50 GMB delegation with 1.4 GMB liquid → submit code=0, in the block code=5 insufficient funds
§6 counter afterwards: NO RECORD — nothing burned        (it used to charge the full 50)
1 GMB delegation → succeeds, counter reads day 20729 · 1.0 GMB
```

Plus unit tests for success=false charging nothing, success=true charging once, intra-transaction
summing, and a nil `next`. **The devnet earned its keep twice:** the first wiring panicked
InitChain on the genesis gentx, because `posthandler.NewPostHandler(HandlerOptions{})` builds an
empty decorator chain and `sdk.ChainPostDecorators` returns **nil** for that — which baseapp reads
as "no post-handler" but which our decorator dereferenced as its `next`. The unit tests could not
have caught it; they passed a non-nil next.

### Rolling it out: halt-height, not a canary

A canary cannot validate this one — new and old agree on every successful delegation and differ
only on a failing one, so the canary would look clean until someone's delegation failed. Use the
coordinated halt instead:

1. **Pick a height** ~200 blocks out (≈8 minutes at 2.3 s) and note it as `H`.
2. **One box at a time** (never two validators down at once), still on the OLD binary: set
   `halt-height = H` in `~/.gembad*/config/app.toml` and restart the node. Pause each box's
   `gemba-auto-unjail.timer` for the window so the watchdog does not fight the deliberate stop.
3. **At `H` every node stops by itself.** The chain stops here — that is the point. (Measured on
   the devnet 2026-11-03: the process does NOT exit — it logs `halt per configuration height H`
   and idles; stop the unit yourself before swapping.)
4. **Per box:** swap the binary to `87f161a`, remove `halt-height` (set it back to `0`), start the
   node. Do the archive first (it proves the binary boots and replays without consensus weight),
   then the validators.
5. **Resume:** the chain produces again once more than ⅔ of voting power is back. Re-arm the
   timers. Verify per box as in Phase 3, then submit one deliberately failing delegation on the
   live chain and confirm the §6 counter does not move — the same check the devnet ran.

Rollback at any point: `cp /usr/local/bin/gembad.PROVEN-d8a454f-dirty` is the pre-refresh binary,
and the previous good one is `39daa6e` (`sha256 fd9deac7…`), which every box ran from 2026-10-03.

**Sequencing note.** Do this AFTER the 03:19–03:35 compound run, not before: that run is the last
end-to-end proof of the mempool fix (`.83` bonding a full 50 GMB for the first time since
2026-09-20), and swapping binaries first would mix two independent changes in one observation.

Until the swap, the practical exposure of the §6 defect stays small: `auto-compound.sh` sizes the
delegation to the real remaining allowance and verifies the stake actually grew, so a burnt
allowance surfaces as a loud failure the next day rather than as silence.

### Superseded 2026-11-03: the rollout is folded into one upgrade (below)

The 2026-10-04 plan above ("halt-height, not a canary", artefact `87f161a`) was never executed —
Slavy's decision was to carry the §6 fix on the next restart that happens anyway. Since then two
more reasons for a coordinated upgrade appeared, so all three ship in ONE halt:

| change | why | consensus |
|---|---|---|
| valgate §6: check in the ante, charge in a post-handler (`26a12ab`, `87f161a`) | a delegation that fails after the ante burned the day's allowance | breaking, but only on a *failing* delegation |
| BLOBBASEFEE: `BlockContext.BlobBaseFee = 0` (`gembad-blobbasefee.patch`) | the opcode dereferenced nil — `eth_call` error, tx included as `code 111222` with no receipt | **breaking** — proven: an old node fed one BLOBBASEFEE tx left consensus (`wrong Block.Header.AppHash`) |
| cosmos/evm **v0.7.3 → v0.7.4** | six security advisories (GHSA-p8x8-4gg6-prcc, -c6xv-pppp-rjw6, -2m6r-q6x4-4w5g, -wm4f-qpxp-rch4, -7xxp-gq2c-x47x, -9xwc-4fgh-f64f) — gas charging, self-destruct with staking positions, precompile call counter, EIP-712 fields, two mempool panics | breaking (gas and execution changes) |

`v0.7.4` makes our queue `recover()` redundant (GHSA-9xwc is the same fix), so the patch set on
v0.7.4 is: wiring + `gembad-mempool-recheck-guard.patch` + `gembad-blobbasefee.patch`.

### Rehearsal — RESULT (2026-11-03, 4-node devnet, `security/devnet/upgrade-rehearsal.sh`)

OLD = the live testnet's exact binary (`39daa6e`, sha256 `fd9deac7…b3e0`, copied from node2),
NEW = `85a9adc` (below). 10/10 rehearsal checks and 13/13 prague-suite checks PASS:

```
baseline OLD : failing 50 GMB delegation → code 5, §6 counter "day 20760 · 50 GMB"   (the defect)
             : BLOBBASEFEE eth_call → nil pointer dereference                       (the defect)
halt         : halt-height armed node by node (one restart at a time, chain never stopped)
             : all four stop at H=47 by themselves; block 47 committed, NOT executed;
               the processes keep running ("halt per configuration height 47"), nobody exits
swap         : cp NEW over the binary, halt-height = 0, start → block 48, 49 …
             : stall from the halt to the second new block 19.3 s, of which 15 s was the
               harness deliberately waiting to be sure the chain had stopped; restart → +2 blocks 4.1 s
verify NEW   : same app hash on all four · nobody jailed · no panic/consensus failure
             : failing 50 GMB delegation → code 5, §6 counter untouched (NO RECORD)
             : successful 0.5 GMB delegation charged exactly once
             : BLOBBASEFEE → 0 in eth_call and status 1 in a tx; EIP-7702 works (docs/evm-compatibility.md)
divergence   : one node put back on OLD + one BLOBBASEFEE tx → that node CONSENSUS FAILURE, the
               other three carry on — the change cannot be rolled out one box at a time
```

The same rehearsal also passed with a v0.7.3-based candidate (valgate + BLOBBASEFEE only), so if
v0.7.4 must be held back, `EVM_VERSION=v0.7.3 ./build-gembad.sh` is the fallback build.

## The live upgrade — ready-to-run plan

**NOT EXECUTED. Waits for Slavy to pick the time.** Nothing below has touched a live box.

**Artefact.** `gembad` `85a9adc` (cosmos/evm v0.7.4 + wiring + recheck guard + BLOBBASEFEE,
`chain/` = valgate fix), go1.25.9, no `-dirty`, built once on the laptop:

```
~/gemba-releases/gembad-85a9adc
sha256 9b2f7c2dbc50c5d5953b6ce8711eabf65d0e3981b60c912157978c3759be5781
```

The build is **not** bit-for-bit reproducible yet (see `build-gembad.sh`): ship THIS file, do not
rebuild per box; if it is lost, rebuild from `85a9adc`, re-run the rehearsal against the new file
and record its sha256 here instead.

**Quorum arithmetic (2026-11-03):** voting power 16218 / 16063 / 14887 / 13026 = 60194; the chain
needs > 40129. Any three validators (≥ 43976) restart it; any two cannot. Because the halt is
coordinated, there are no missed blocks and no jail — but the chain is DOWN from `H` until the
third validator is back on the new binary.

**Estimated live halt: 3–5 minutes** (devnet mechanics: ~5 s; the rest is the operator — five
SSH sessions, a `cp`, a `sed`, a start, with the hash check). Prepare the five shells beforehand;
do the swaps in parallel, not box by box.

#### T−1 day
1. Copy `gembad-85a9adc` to every gembad box (validators .82, .83, .84, node2 .208, archive .137)
   as `/usr/local/bin/gembad.NEW-85a9adc` and check `sha256sum` = `9b2f7c2d…5781` on each.
   **Do not swap yet.** On node2 the container bind-mounts the host's `/usr/local/bin/gembad`.
2. On each box keep the rollback: `cp /usr/local/bin/gembad /usr/local/bin/gembad.PROVEN-39daa6e`
   (sha256 `fd9deac7…b3e0`); snapshot `priv_validator_state.json`.
3. Announce the window (dApps and wallets see no new blocks for a few minutes).

#### T−30 min — arm the halt (chain keeps running)
4. Read the height from any RPC and set `H = height + 800` (≈ 30 min at 2.29 s/block — enough to
   arm five boxes one at a time). Write `H` down.
5. Pause `gemba-auto-unjail.timer` on the four validators (and the node watchdog on the archive)
   so no watchdog "repairs" the deliberate stop.
6. **One box at a time**, starting with the archive, then .82 → .84 → node2 → .83: set
   `halt-height = H` in that node's `config/app.toml` (its `--home`, see `systemctl cat <unit>`),
   restart the unit (`gembad-val` on Contabo, `gembad` with `sudo` on node2, the archive's unit on
   .137), and wait until it signs again before the next. Never two validators restarting at once.
   If `H − height` drops below ~150 before all are armed, clear `halt-height` everywhere and start over.

#### At H — the chain stops by itself
7. Every node logs `halt per configuration height H` and **stays running**. Confirm all report the
   same height `H` (block `H` is stored but not yet executed — the new binary executes it).
8. On every box, in parallel:
   ```
   systemctl stop <unit>
   cp /usr/local/bin/gembad.NEW-85a9adc /usr/local/bin/gembad && sha256sum /usr/local/bin/gembad   # 9b2f7c2d…5781
   sed -i 's/^halt-height = .*/halt-height = 0/' <home>/config/app.toml
   systemctl start <unit>
   ```
   Start the archive first if you can (it executes block H without consensus weight); the chain
   moves again as soon as the third validator is up.

#### After — verify (30 min)
9. Height advancing on rpc1/2/3; every box `gembad version` = `85a9adc` (node2: check by sha256,
   its host glibc cannot run the binary outside the container); same app hash on all at one height;
   4/4 signing; nobody jailed; no `^panic:|SIGSEGV|CONSENSUS FAILURE` in the journals since the swap.
10. Re-enable the paused timers, and re-export the validator bundle from `85a9adc`
    (`gemba-validator/src/README.md`) so new validators build the new rules.
11. Functional proof on the live chain — the same two the devnet ran:
    - one deliberately failing delegation (amount > liquid balance) from one validator → `code 5`,
      and its §6 record (`abci_query /store/valgate/key`, key `0x02 ++ valoper`) does **not** move;
    - `eth_call` with data `0x4a5f5260205ff3` → `0x00…00` instead of the nil-pointer error.
      (This is the call that must NOT be sent to a live node BEFORE the upgrade.)

#### Rollback
- **Before H:** set `halt-height = 0` and restart each box as in step 6 — nothing else changed.
- **After the swap, if the chain does not resume or app hashes differ:** stop every node, `cp
  /usr/local/bin/gembad.PROVEN-39daa6e /usr/local/bin/gembad`, keep `halt-height = 0`, start —
  ALL boxes, never a mix. If the new binary never committed a block, the old one simply executes
  `H` itself and continues. If it did commit blocks, the old binary continues from that state on
  the old rules, which is consistent only if none of those blocks held a transaction whose outcome
  differs (a failing delegation, a BLOBBASEFEE call, one of the v0.7.4 advisory paths) — check them
  first; otherwise it is path B of `coordinated-upgrade.md`. Decide within the first minutes.

Sequencing: not during the 03:19–03:35 CEST compound runs, and not while Contabo is mid-maintenance
(two validators down = no quorum for the restart either).

## Mitigation already in place (does not need the upgrade)

`auto-compound.sh` now reads the **real** remaining allowance from the chain instead of clamping to
the 50 GMB limit, and when the local node refuses a delegation that the committed state allows it
says so explicitly, submits through `FALLBACK_NODE` if one is configured, and **e-mails** after two
consecutive failed days. The 13-day silence was the second failure in this incident: the compound
had no alerting at all, while jails and disks have had it since 2026-07-18.

See also: `docs/runbooks/coordinated-upgrade.md`, `docs/runbooks/validator-auto-ops-deploy.md`,
`docs/runbooks/halt-recovery.md`.
