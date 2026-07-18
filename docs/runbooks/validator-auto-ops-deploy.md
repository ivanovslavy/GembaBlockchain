# Runbook — activating validator auto-ops on the testnet validators

Activates `auto-unjail` + `auto-compound` (`gemba-validator/auto/`) on the live
`gemba-testnet-1` validators, using the **on-box operator-key model** (each validator
self-manages with its own operator key — the same shape mainnet uses). Tokens are valueless
test GMB; the boxes are SSH-key-only. This step is reversible (`gembad keys delete`, disable
the timers).

## Why this needs a deliberate step

The validators' **operator keys** (`node0..node3`, the keys that created the validators) are
kept **off** the public boxes — only locally in `wallet-backup/` (gitignored). The boxes hold
just the consensus key (`priv_validator_key.json`, signs blocks) plus an unrelated `valop`
key. The daemons sign with the **operator** key, so activation = place each validator's
operator key on its box. Operator keys are private — never commit/print them.

## Verified mapping (box → validator → operator), by consensus pubkey

| Box (SSH) | consensus pubkey | on-chain validator | operator address |
|---|---|---|---|
| `13.140.139.82` | `ykx8dLaSQvvs52Ik3Ab…` | **gemba-tn-val-0** | `cosmosvaloper1u6zhxsehl4xad59vlfmcuchv70pka76t7uzsye` |
| `13.140.139.83` | `6IL/blncaykWL4JI09kh…` | **gemba-tn-val-1** | `cosmosvaloper19527lffudd9cx00ptr5ghvxgyhqeqgv6sjd000` |
| `13.140.139.84` | `hhk3PonUtHTiOhu3NkPZ…` | **gemba-tn-val-2** | `cosmosvaloper1vayp2t4c9ysq8frgca2rhlach3wxyuvvya3xfd` |
| node2 (LAN/Docker) | `H83xdDuW8zNQSKcfrycu…` | **gemba-tn-val-3** | `cosmosvaloper10d6u5g6yatjaqvtuav9mdpuvcs65m0yy9qh3vh` |

> The `valop` key already on each box is **not** the operator (its address is not in the set
> above) — do not use it. Use the validator's real operator key from `wallet-backup/`.

## Steps (per Contabo box; node2 is Docker — see note)

For each box, with its matching operator key from `wallet-backup/` (`PRIVATE-KEYS.md` /
`keyring-raw/nodeX`):

1. **Import the operator key** into the box keyring (test backend). From the mnemonic:
   ```bash
   # on the box, as root — paste the validator's operator mnemonic when prompted
   gembad keys add valop-operator --recover --keyring-backend test --home /root/.gembad
   ```
   Confirm the derived address equals the operator address in the table (account form, i.e.
   the `cosmos1…` of the `cosmosvaloper1…`). If it does not match, STOP — wrong key.

2. **Bootstrap gas** (the operator account starts with 0 liquid; the first reward-withdraw
   needs a fee). Send a small amount from the founder, once:
   ```bash
   # ~5 GMB is plenty; it self-funds fees from rewards afterwards
   gembad tx bank send <founder> <operator-cosmos1-addr> 5000000000000000000agmb \
     --gas auto --gas-adjustment 1.4 --gas-prices 1000000000agmb -y \
     --chain-id gemba-testnet-1 --node tcp://localhost:26657
   ```

3. **Configure + install** the daemons:
   ```bash
   # set VAL_KEY=valop-operator in the env, then run the installer from gemba-validator/auto/
   sed -i 's/^VAL_KEY=.*/VAL_KEY=valop-operator/' /etc/gemba/validator-auto.env 2>/dev/null || true
   ./install-validator-auto.sh   # installs deps, scripts, /etc/gemba/validator-auto.env, timers
   ```

4. **Verify**:
   ```bash
   systemctl list-timers 'gemba-auto-*'
   /usr/local/bin/gemba-auto-unjail.sh   # not jailed -> exits 0, logs nothing to do
   /usr/local/bin/gemba-auto-compound.sh # withdraws rewards, re-stakes 50% (or "skip" if dust)
   tail /var/log/gemba-validator-auto.log
   ```
   Confirm on-chain the self-delegation grew:
   `gembad query staking delegation <operator-cosmos1> <valoper> --node tcp://localhost:26657`.

### node2 (val-3, Docker on the LAN box)

node2 runs gembad **in a Docker container** (glibc). Run the daemons inside the container (or
exec `gembad` via `docker exec`), pointing `GEMBAD_HOME` at the container's home, and import
val-3's operator key into the container keyring. Otherwise identical.

## Status (2026-06-26) — what is LIVE vs pending

**LIVE on the 3 Contabo validators (val-0/1/2):** operator keys imported, gas bootstrapped,
daemons installed, both systemd timers active (auto-unjail /5min, auto-compound daily). First
auto-compound proven: each grew its self-stake **1000 → ~6,774 / 6,902 / 6,888 GMB** (claimed the
~11.8k GMB reward backlog, re-staked 50%).

**Per-validator compound numbers (today):** ~11.8k GMB rewards accrued over ~20 days since
re-genesis ≈ **~590 GMB/day rewards → ~295 GMB/day re-staked (50%)** per validator at current
load; the one-time backlog re-stake was ~5.9k GMB each. (Use these to size the per-day add cap —
the planned next task.)

**ALL 4 now balanced to ~25% each** (so losing any one leaves ~75% online, above the 2/3 BFT
threshold → the chain survives a single-validator outage):
`val-0 6,774 · val-1 6,902 · val-2 6,888 · val-3 6,851 GMB`.

- **node2 / val-3 (jellyfin, Docker): ACTIVATED.** The host `gembad` can't run (no glibc 2.38), so
  the node runs in the `gembad-node2` container and the daemons call gembad via `docker exec`
  (`GEMBAD="docker exec gembad-node2 gembad"`, home `/home/slavy/.gembad-testnet-node2` mounted in).
  val-3's operator key (`val3op`) imported into the container keyring; compounded 980 → 3,702 (its
  reward backlog was smaller, ~5.4k), then topped up +3,150 from its operator liquid to ~6,851 to
  match the others (25% balance). Timers active.

**Pending:**
- **valgate max-self-bond cap (10000) live on testnet:** the cap is coded, unit-tested (9 tests)
  and **active on mainnet from genesis** (DefaultParams). Enforcing it on the *running* testnet
  needs a binary upgrade, but the validators run `b7f96c2-dirty` (an unreproducible build) and
  `main` has since diverged — a blind swap risks an AppHash fork unrelated to the cap. So testnet
  activation is deferred to a **planned coordinated upgrade** (reconcile the running version, build
  a matching binary, canary one validator while the other 3 keep the chain live, then roll). Low
  urgency: the cap only affects creating a >10k-GMB validator, which is not happening on the testnet.

> **Observation to review:** the val-0/1/2 operator accounts each hold **~2,000,000 GMB liquid**
> (~6M total) — separate from their self-bond. Not touched by auto-compound (it re-stakes only the
> *delta* of withdrawn rewards). Worth confirming this liquid allocation is intended.

## Watchdog: detect-stuck → restart → sync → unjail (auto-unjail.sh)

`auto-unjail.sh` is a **three-layer watchdog**, not a bare unjail. Rewritten 2026-07-18 after a
live incident: val-3 (.208) lost its home-line peers, **froze**, and got jailed — but the old
unjail-only script never acted, because it asked the *frozen local node* "am I jailed?" and the
node, stuck in the past at its pre-jail height, honestly answered "no". Root cause (lost
connectivity) was never touched, so a human had to restart it by hand.

The watchdog fixes that with a pipeline that runs each timer tick:

1. **DETECT + RESTART** — decides "stuck" from signals a frozen node cannot fake: `n_peers == 0`,
   height **not advancing between runs**, or (if `TIP_EVM_RPCS` set) far behind the network tip.
   If stuck, it runs `RESTART_CMD` so the node re-dials peers and catches up. Guarded by
   `RESTART_COOLDOWN_SEC` (backoff) and `MAX_CONSECUTIVE_RESTARTS` (after N with no recovery it
   STOPS and alerts — a restart won't fix a full disk or DB corruption; that needs a human).
2. **SYNC GATE** — proceeds only once the node is genuinely caught up (peers > 0, `catching_up=false`,
   within `SYNC_MARGIN_BLOCKS` of the tip). Never unjail a node that can't sign — it re-jails/slashes.
3. **UNJAIL** — now that the node is synced, its local jail status is authoritative (the old bug is
   impossible here: we read it *only after* confirming sync). If jailed, submit MsgUnjail; it reverts
   harmlessly inside the jail window or if tombstoned (double-sign) and the timer just retries.

**External truth for the network tip** uses the **public EVM RPC** (`eth_blockNumber`), because the
raw CometBFT RPC (26657) is intentionally not public (hardening). Leaving `TIP_EVM_RPCS` empty is
fine — layers 1/2 still work off the two purely-local signals (`peers==0` / height-not-advancing),
which is exactly what the .208 incident needed.

**Per-box `RESTART_CMD` (the one knob you must set right):**

| Box | node runs as | `RESTART_CMD` |
|---|---|---|
| Contabo val-0/1/2 (.82/.83/.84) | systemd `gembad-val.service` | `systemctl restart gembad-val` |
| Home val-3 (.208, Docker-under-systemd) | systemd `gembad.service` (wraps the container) | `systemctl restart gembad` |

The auto-unjail systemd unit runs as **root**, so it can restart the node service directly (no sudo).
Set `ENABLE_AUTO_RESTART=false` for detect-only (logs a STUCK line, never restarts) while validating.

## Disk-guard + node-watchdog + alert email (added 2026-07-18)

Three more box-ops pieces, meant for **every** box from genesis:

- **gemba-disk-guard** (`disk-guard.sh`, timer /10min, EVERY box incl. archive/explorer) — a full disk
  is the one failure `Restart=always` makes WORSE (write-crash → restart → crash = silent loop, the
  .82 2026-07-15 incident). The guard emails **WARN at 85% / CRIT at 95%** (throttled, with an
  all-clear on recovery) BEFORE that happens. Never destructive by default; optional journald vacuum
  first-aid on CRIT (`DISK_GUARD_VACUUM_JOURNAL=true`). Config: `/etc/gemba/disk-guard.env` (`DISK_MOUNTS`).
- **gemba-node-watchdog** (`node-watchdog.sh`, opt-in) — the validator watchdog's layers 1-2
  (detect-stuck → restart), **no unjail**, for NON-validator gembad nodes (archive / RPC source) that
  never jail but can freeze. ⚠️ `RPC_HTTP` MUST be the node's REAL CometBFT rpc port — the **testnet
  archive runs on 26667** (offset ports), NOT 26657; a wrong port reads every tick as "RPC unreachable"
  and needlessly restarts a healthy node (learned the hard way 2026-07-18). Do NOT put it on the
  explorer's Blockscout (not a gembad node).
- **gemba-alert-email** (`gemba-alert-email.sh`) — the shared SMTP sink used by disk-guard, node-watchdog
  (give-up), and the validator watchdog (**jail / recovery / give-up**). Reuses the gembachain.io mail
  account (`mail.gembamail.com`, same as the notifier). Wired as `NOTIFY_CMD` in each env. **Inert until
  the secret is provisioned** (silent no-op, never fails a caller): 
  `printf %s '<smtp-password>' > /etc/gemba/smtp_password && chmod 600 /etc/gemba/smtp_password` +
  set `SMTP_HOST` in `/etc/gemba/notify.env`.

Install: validators get all of this from `install-validator-auto.sh`; archive/explorer use
`install-node-ops.sh [--with-watchdog]` (watchdog only for gembad nodes, i.e. the archive).

## Mainnet (from genesis)

On mainnet each operator runs `install-validator-auto.sh` on their own box with their own
operator key — decentralised by construction. The founder validators ship with it enabled,
**including the watchdog + disk-guard + alert email** — set each box's `RESTART_CMD` (table above),
point `TIP_EVM_RPCS` at `https://gmb1.gembascan.io https://gmb2.gembascan.io https://gmb3.gembascan.io`,
and provision the SMTP secret so jail/disk emails actually send. `REINVEST_PCT=50` and the
cooldown/timer cadence are the defaults; tune per operator.

## Rollback

`systemctl disable --now gemba-auto-unjail.timer gemba-auto-compound.timer` and, if desired,
`gembad keys delete valop-operator --keyring-backend test` to remove the operator key from the box.
