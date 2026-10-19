# Mainnet launch hardening checklist

Operationalizes the audit-finding fixes that are NOT pure code (genesis config, infra, and the one
fix that needs devnet validation). Companion to `docs/audit-findings-2026-07-13.md` (the findings)
and the code fixes already merged. There is **no mainnet genesis yet** — build it against this list.

## A. Code fixes already merged (for reference)
- **H2** purchase-backend fails closed on empty webhook secret + re-validates amount/currency.
- **H1** valgate `InitGenesis` defaults omitted (nil) caps to `DefaultParams` (caps ship active even
  if genesis omits them). Belt-and-suspenders: still set them explicitly in genesis (§B).
- **M2** rewardstreamer `FormulaParams` carried in `GenesisState` (survives export/import).
- **M4** rewardstreamer aggregate daily reward budget (`MaxTotalPerDay`, default ≈2M GMB/yr).
- **M3** GembaGovernor: reserve `release` + UUPS `upgrade*` are Critical tier by selector.

## B. Mainnet GENESIS config — set explicitly, verify before launch (irreversible)

### DECIDED VALUES (2026-07-17, owner) — feed these into the mainnet genesis builder
The devnet builder (`init-gembad-multinode.sh`) already sets caps/supply/unbonding/feemarket
correctly; it uses DEVNET-loose gov + a devnet-amplified reward rate. For mainnet set:
- **feemarket.min_gas_price = `5000000000` agmb (5 gwei).** ✓ confirmed.
- **staking.unbonding_time = `1814400s` (21 days).** ✓ already correct.
- **rewardstreamer:** `annual_reward = 2,000,000 GMB`, `max_total_per_day = 5479 GMB` (the hard
  emission backstop = 2M/365, so a mis-set block count can't over-emit). Block-time MEASURED on the
  live testnet 2026-07-17 = **2.402s avg over 100k blocks** → set BOTH consistently:
  `params.blocks_per_year = 13,140,000` and `formula_params.blocks_per_day = 36,000` (~2.4s). The
  devnet's `blocks_per_year=2000` / `blocks_per_day=28800` are devnet-amplified — DO NOT ship them.
  Re-measure real mainnet block-time weeks 1-4 and reconcile.
- **gov:** `voting_period = 259200s` (3 days); `expedited_voting_period = 86400s` (1 day, < voting);
  `min_deposit = 10,000 GMB` (`10000000000000000000000 agmb` — devnet was 1e7 agmb ≈ 0, spam risk);
  `quorum = 0.334`, `threshold = 0.5`, `expedited_threshold = 0.667` (Critical ≥66% ✓); governance
  **Timelock min delay 24–48h**.
- **valgate:** `max_self_bond = 10,000 GMB`, `max_daily_bond_increase = 50 GMB`. ✓ already correct.
- **Supply:** mint disabled (inflation 0), total = exactly 100,000,000 GMB, 20M reward reserve in the
  rewardstreamer module account. ✓ already correct in the builder's "mainnet split".
- **GembaVotes exclusion set** — POPULATE at genesis (every reserve/faucet/foundation/DAO/onramp/
  contingency address); verify `getVotes()==0` for each. ⏳ owner to populate (highest-severity item).

> **BUILDER DONE 2026-07-17:** `chain/gembad/init-gembad-mainnet.sh` (build → gentx ceremony →
> collect → verify) implements every decided value below, handles NO private keys (addresses +
> gentx files only), and embeds a 33-assertion verify battery (exact bigint supply check included).
> Dry-run validated end-to-end the same day: throwaway 4-validator ceremony → `validate-genesis`
> OK → 4-node network BOOTS AND PRODUCES BLOCKS from the produced genesis (height 22, no panics;
> the L1 wiring assertion active). Items below marked [x] are implemented+dry-run-verified in the
> builder — STILL re-run `init-gembad-mainnet.sh verify` on the REAL genesis at ceremony day.
> Note: legacy `rewardstreamer.params.enabled=false` on purpose — the FORMULA is the reward model,
> so a gov `MsgUpdateFormulaParams` kill-switch is a FULL payout stop (no silent legacy fallback).
> Node start requires `--chain-id gemba-1 --evm.evm-chain-id 821206` (see the ceremony runbook).

- [x] **valgate.params** — `max_self_bond` (10,000 GMB), `max_daily_bond_increase` (50 GMB) and
      `min_self_bond` (1,000 GMB) set explicitly (H1); asserted by the verify battery.
- [x] **feemarket.min_gas_price > 0** (L2) — 5 gwei floor set + asserted (decided value; the old
      1-gwei example here was stale).
- [x] **rewardstreamer.formula_params** — explicit in genesis: enabled, rate 1%/day, floor 10,
      cap 100, blocks_per_day 36,000, max_total_per_day 5,479 (M4 budget); legacy stream disabled.
- [x] **gov params** — voting 3d, expedited 1d, min_deposit 10,000 GMB (expedited 50,000 = SDK 5×
      convention), quorum 0.334, threshold 0.5, expedited_threshold 0.667. The **Timelock min
      delay 24–48h** is an EVM-contract deploy parameter (`MIN_DELAY`), not genesis — set it at
      the governance deploy (ceremony runbook).
- [x] **staking.unbonding_time** — 1,814,400s (21d) explicit + asserted.
- [ ] **GembaVotes exclusion set POPULATED at genesis** — every reserve/faucet/foundation/DAO/
      contingency address excluded from voting (the single highest-severity launch item; testnet
      left it empty until a manual governance cycle). Verify `getVotes()==0` for each reserve.
- [x] **Supply reconciliation** — verify battery sums every bank balance with exact bigint math:
      total == 100,000,000 GMB, 20M in the rewardstreamer module account, 30M in the Public
      Reserve account; mint inflation asserted zero. NO onramp account (removed 2026-07-17).
- [x] **Begin-blocker order assertion (L1) — DONE 2026-07-17.** `chain/x/wiring` validates the
      RESOLVED `OrderBeginBlockers` (feesplit → rewardstreamer → tailreward → distribution;
      presence, uniqueness, relative order) and the patched app constructor panics on any
      violation (`gembad-wiring.patch`). Unit-tested (good order + 4 violation classes);
      full `build-gembad.sh` green; runtime smoke: node constructs the app cleanly.

## C. Phase 2 (devnet) — needs the full app build + a live test, do NOT rush in-tree
- [x] **M1 — §6 daily-bond cap bypass via the EVM staking precompile. DONE + DEVNET-VALIDATED
      (commit 677e5e2, fix; re-validated end-to-end 2026-07-17).** The cap was enforced only in the
      ante, which never saw the precompile's `delegate`/`redelegate` (they call the staking msg
      server directly during EVM execution, after the ante). **Fix (in-tree, in the genesis binary):**
      `chain/x/valgate/keeper/staking_msgserver.go` = `CapEnforcingStakingMsgServer`, a staking
      `MsgServer` decorator that calls `CheckAndRecordDailyBond(dstValoper, amount)` before
      `Delegate`/`BeginRedelegate` (all other methods pass through). `chain/gembad/gembad-wiring.patch`
      builds the staking precompile from the cap-enforcing server and `EVMKeeper.RegisterStaticPrecompile`
      overrides the default — so ONLY the precompile server is wrapped; the Cosmos path (ante) and the
      precompile path (wrapper) each check the SAME valgate counter exactly once (no double-count).
      **End-to-end validation 2026-07-17 (this box):**
      - Unit: `chain/x/valgate/staking_msgserver_test.go` → `go test ./x/valgate/...` PASS (over-cap
        precompile delegate/redelegate rejected before the inner server).
      - Build: clean `build-gembad.sh` from scratch — patch applies cleanly to pinned cosmos/evm
        v0.7.0, full binary built (version 677e5e2-dirty).
      - Live devnet (`gemba-1` / EVM 821206, 4 nodes, `--json-rpc.enable`, genesis cap 50 GMB/day):
        precompile `delegate` 40 GMB via EVM JSON-RPC → MINED status=1 (under cap); +20 GMB
        (60 > 50) → **REVERTED** — the bypass is closed. Cosmos-path parity: a subsequent Cosmos
        `MsgDelegate` +15 GMB was rejected with "already added 40000000000000000000 today" — proving
        BOTH paths share ONE daily counter (precompile 40 + cosmos 15 = 55 > 50 → rejected).
      Consensus code, already committed → ships in the mainnet genesis binary (built via
      `build-gembad.sh`), NOT a later governance upgrade. No `genesis.json` change needed for M1.

## D. Infra / key & secret hygiene
- [x] **I2 — auto-ops `test` keyring backend. RESOLVED / risk-accepted 2026-07-17 (owner).** The
      validator hosts are reachable ONLY via SSH key auth — no outsider gets a shell, so no path to
      read the keyring at rest. Left as-is by decision; no change.
- [x] **I3 — SMTP credential in `services/blockchain-notifier/.env`. RESOLVED / risk-accepted
      2026-07-17 (owner).** Mail host is SSH-key-only; the `.env` is gitignored and unreadable
      without a shell. Left as-is by decision; no change.
- [x] **Round-4 GitHub PAT / secret-scan. RESOLVED / risk-accepted 2026-07-17 (owner).** Infra is
      SSH-key-only; owner accepts the current secret posture across all three key/password items
      above. No rotation performed by decision.
- [ ] Confirm production owners of `GembaPayDispenser`/`GmbCollector`/`GembaFaucet`/
      `GembaSwapFactory.feeToSetter` are governance/Timelock (or documented operational EOAs with a
      rotation plan) — the audit refuted these as SPOFs only under the "documented operational key"
      reading; verify the deploy actually sets the intended owner. (`GembaOnRamp` dropped from this
      list — contract removed from the codebase 2026-07-17, nothing to own.)
- [ ] **I4 — validator node storage config FROM GENESIS (root cause: testnet disk-fill 2026-07-15).**
      On 2026-07-15 validator `.82` filled its 72G disk under load and crash-looped (jailed + rpc3
      down); the culprit was chain DATA: `application.db` 36G (`pruning="default"` keeps 362,880
      versions) + `tx_index.db` 13G, with journald uncapped. **Mainnet validators must launch as
      lean pruned nodes, configured at provisioning (NOT retroactively — applying `keep-recent=100`
      to an already-fat node grinds the 362k-version backlog and makes catch-up fall behind the
      chain; the clean fix is state-sync bootstrap or correct-from-genesis config):**
  - `app.toml`: `pruning="custom"`, `pruning-keep-recent="100"`, `pruning-interval="10"` from first
    start (a node pruned from genesis never accumulates the backlog, so it stays small AND syncs fine).
  - `config.toml`: `[tx_index] indexer="null"` on validators (EVM receipts use the app-side indexer;
    CometBFT tx-search lives on the archive/explorer only).
  - journald drop-in cap `SystemMaxUse=500M` (uncapped default = 10% of disk).
  - Keep the dedicated **archive** node (`pruning="nothing"`) as the sole history/explorer source, so
    pruned validators lose nothing globally.
  - The offline `gembad prune` subcommand is BROKEN in the current `evmd` build (`leveldb: closed`,
    reclaims nothing) — do not depend on it. Add a disk-usage watchdog/alert. NB: the validator
    watchdog (`gemba-validator/auto/auto-unjail.sh`, rewritten 2026-07-18) auto-restarts a
    frozen/de-peered node and re-unjails after sync, but it will NOT paper over a full disk — after
    `MAX_CONSECUTIVE_RESTARTS` with no recovery it stops and alerts (a restart can't reclaim disk).
    The `%used` alert is now shipped: **gemba-disk-guard** (`gemba-validator/auto/disk-guard.sh`,
    a timer on EVERY box from genesis) emails WARN@85% / CRIT@95% via **gemba-alert-email** before the
    disk fills — closing the "silent write-crash-loop" gap. Disk sizing remains the primary defence;
    see `runbooks/validator-auto-ops-deploy.md`.

## E. Operational lessons from the testnet, Aug–Oct 2026 — build these in from genesis

Everything below was learned by running the testnet, after this checklist was first written. None of
it is theoretical; each line cost either money or an outage.

### E1 — 🔴 FOUR VALIDATORS TOLERATE EXACTLY ONE OUTAGE. Mainnet needs seven.

Measured on the testnet set, 2026-10-19:

```
total voting power   57 978        quorum (>2/3)   38 653
one validator down   42 510–44 918   ✅ consensus holds, whichever one it is
two validators down  27 197–30 781   🔴 CONSENSUS STOPS — every one of the six pairs
```

With four near-equal validators the set survives one failure and no more; that is the arithmetic of
⅔, not a defect of any provider. **Mainnet must launch with ≥7 validators** (⌊(7−1)/3⌋ = 2 tolerated)
and must not place a majority of voting power behind one provider, one region, or one network path.

🔴 **On the testnet three of the four sat at the same provider (Contabo, one IP range).** On
2026-10-18/19 that provider rebooted all three for host maintenance inside twenty hours. Only the
fact that it staggered them — 15:23, 19:58, then 11:19 the next day — kept the chain alive. That was
their schedule protecting us, not our design.

### E2 — Provider maintenance reboots are routine. Plan for them, do not be surprised.

Signature seen twice (2026-10-16 and 2026-10-18/19): a clean `systemd-poweroff`, 15–25 minutes down,
the VM returns on a newer kernel. `Unattended-Upgrade::Automatic-Reboot` is **off** on every box, so
these are not ours. Each one jails that validator until the watchdog unjails it (~5–9 minutes
observed).

How to read it from the outside, so this is diagnosed in minutes rather than hours:
- **Cloudflare 521** = the origin refused the connection → the process is dead, the machine is up.
- **Cloudflare 522** = the origin was not reachable at all → the machine is down.
- nginx `connect() failed (111: Connection refused) while connecting to upstream` pins it to the
  backend process; a gap of missing minutes in the nginx **access** log pins it to the machine.
- 🔑 `journalctl --list-boots` showing a single row is the start of the retained journal, **not** a
  reboot. Always confirm with `uptime -s`.

### E3 — Nothing was watching the CHAIN. Ship `gemba-chain-watch.sh` from genesis.

Every watchdog we had was per-box: each one checks its own node and is blind to consensus. A halted
chain was therefore **silent** — the wallet listeners simply read no new blocks, and silence raises
no alarm. Added 2026-10-19, running from the existing 5-minute `gemba-auto-unjail.timer` on **every**
validator (so two boxes can be down and the third still reports):

- the height is the **max** of the local node and the public RPCs, so a locally stuck node raises no
  chain alarm — that is the other watchdog's job;
- **no answer is not a halt** — if every source fails to reply, that box is isolated; it logs and
  stays quiet rather than crying wolf;
- one mail per episode via a marker file, plus one on recovery, exactly like the jail watchdog;
- the alert carries the stuck height and the signature count, so the mail already says *why*.

### E4 — P2P death clock: `tcp_retries2`. Already fixed; mainnet must not inherit the default.

Carried in `runbooks/mainnet-genesis-ceremony.md` and `99-gemba-p2p.conf`; repeated here because it
is a genesis-time setting. Default `tcp_retries2 = 15` ≈ 924 s means a validator whose path breaks
for two minutes is **jailed for twenty**, because the remote validators hold the black-holed socket
for 15.4 minutes and refuse every reconnect as a duplicate node ID, while the chain jails after ~50
missed blocks ≈ 1.9 minutes. On the testnet this cost node2 **sixteen jails in a hundred days and
about 15% of its stake**. The recorded cause was wrong for months — it was blamed on the home line,
while Qortal on the same box, same line, same NAT logged nothing at all during the incident.

Provision every validator with `net.ipv4.tcp_retries2 = 6`, `tcp_keepalive_time = 300`,
`tcp_keepalive_intvl = 30`, `tcp_keepalive_probes = 5`. **Result on the testnet: the home validator
has gone from jailing twice in four days to eight days without a single jail.**

### E5 — Alerting discipline: an alarm that cries wolf is worse than no alarm.

Two separate incidents taught the same lesson, so it is a rule now, not an anecdote:

- A listener mailed **48 messages in one day** reading "0 RPC failure(s), 40 switch(es)" — every one
  saying nothing was wrong. The cause was accounting, not the network: one global "current endpoint"
  overwritten by two classes of call, each overwrite reported as a switch.
- A weekly check demanded "the release that fixes **SN-2026-011** within 7 days" while the installed
  release was already the one that fixed it — because the advisory id was **hardcoded** into the
  message, so every future release would look like an emergency forever.

**Rules for anything that mails on this chain:** count what it sends per day when nothing is wrong,
and if the answer is not "one" or "zero" it is noise; never hardcode an advisory id or a deadline
into a generic message — derive it from the data; a real failure gets a mail, a self-healed blip gets
a counter and a daily line.
