# Validator auto-ops — auto-unjail + auto-compound

Two small, safe daemons every GembaBlockchain validator can run to stay healthy and to
**strengthen the bonded set over time**. Built for the founder's testnet validators (active
now) and part of the mainnet validator setup from genesis.

## Why (the network-survival reason)

GembaBlockchain is **free to use and GMB carries no financial price** (§2, §16). That is the
point — but it means casual validators (someone runs a node on a home PC, then powers it off
tomorrow) can let the **bonded ratio** collapse. The bonded ratio is *the* security KPI
(ADR-008: target ~66%, floor ~50%, red line ~33%); two well-known chains have died exactly
this way. So the founder's validators:

- **auto-unjail** — a downtime blip doesn't leave a validator sitting jailed until a human
  notices; it rejoins automatically once it has caught up.
- **auto-compound** — each day they re-stake **50% of the rewards they earned** into their own
  self-delegation, so they continuously grow and anchor ≥ ~66% bonded.

> **This does NOT re-centralise governance.** Staking more = more *consensus* power (which
> earns the security budget) — it grants **zero** treasury/governance weight: the Solidity
> Governor is 1-GMB-1-vote and **excludes the founder + reserves** (§5.7, §7). Two separate
> electorates, on purpose.

## What they do

| Daemon | Cadence | Action | Safety |
|---|---|---|---|
| `auto-unjail.sh` | every 5 min | if jailed **and** the node has caught up → `tx slashing unjail` | never unjails while still catching up (would just re-jail/re-slash); never touches a double-sign tombstone (permanent) |
| `auto-compound.sh` | daily | withdraw self-delegation rewards + commission, then `delegate` `REINVEST_PCT`% (default 50%) of what was received back to its own validator | skips dust runs; keeps the rest liquid for fees |

Both sign with the validator's **operator key** (the key that created the validator), read
from the local keyring. They are operator tools for **your own** validator — not a protocol
change and not imposed on anyone else.

## Install (on the validator box, as root)

```bash
sudo ./install-validator-auto.sh
# then edit /etc/gemba/validator-auto.env if your CHAIN_ID / home / key name differ
```

It installs `jq`+`bc`, copies the scripts to `/usr/local/bin`, the config to
`/etc/gemba/validator-auto.env`, the systemd units, and enables both timers. Logs:
`/var/log/gemba-validator-auto.log`.

## Config (`validator-auto.env`)

| Var | Default | Meaning |
|---|---|---|
| `VAL_KEY` | `valop` | operator key name in the keyring (must be the validator's operator key) |
| `CHAIN_ID` | `gemba-testnet-1` | mainnet: `gemba-1` |
| `REINVEST_PCT` | `50` | % of each run's rewards to re-stake |
| `MIN_REINVEST_AGMB` | `1e18` (1 GMB) | skip runs below this (don't waste a tx fee) |
| `GAS_PRICES` | `1000000000agmb` | 1 gwei fee floor |

> The operator key must be in the box's keyring under `VAL_KEY`. The first auto-compound
> run needs a little liquid GMB to pay the withdraw tx fee; after that it funds its own fees
> from the withdrawn rewards.
