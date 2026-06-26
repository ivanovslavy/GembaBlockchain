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

## Mainnet (from genesis)

On mainnet each operator runs `install-validator-auto.sh` on their own box with their own
operator key — decentralised by construction. The founder validators ship with it enabled.
`REINVEST_PCT=50` and the cooldown/timer cadence are the defaults; tune per operator.

## Rollback

`systemctl disable --now gemba-auto-unjail.timer gemba-auto-compound.timer` and, if desired,
`gembad keys delete valop-operator --keyring-backend test` to remove the operator key from the box.
