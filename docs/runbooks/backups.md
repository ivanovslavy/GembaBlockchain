# Runbook — backups

What to back up, and how to recover, for a GembaBlockchain node (Phase 9).

## What to back up

| Item | Path (`--home`, default `~/.gembad`) | Frequency | Notes |
|---|---|---|---|
| **Consensus key** | `config/priv_validator_key.json` | once, on creation | **encrypted, offline.** Losing it ≠ disaster (you can rotate by re-bonding a new validator); leaking it = slash risk. |
| **Validator double-sign state** | `data/priv_validator_state.json` | continuous | restoring an OLD copy can cause a double-sign — see below |
| **Node key** | `config/node_key.json` | once | identity only |
| **Operator mnemonic** | (your secret store) | once, on creation | hardware wallet / offline |
| **Genesis** | `config/genesis.json` | once | public; also in the repo / a known mirror |
| **Config** | `config/config.toml`, `app.toml` | on change | reproducible from the runbooks |
| **Chain data** | `data/` | snapshot-based | optional; can be re-synced |

## Chain data: snapshots, not naive copies

Don't `cp` `data/` while the node is running (you'll get a corrupt copy). Options:
- **Re-sync** from genesis or via **state-sync** (fastest for a fresh node) — the
  chain data is reproducible, so backups are a convenience, not a necessity.
- **Periodic snapshots:** stop the node (or use the SDK snapshot feature), archive
  `data/`, restart. For validators, minimize downtime (the double-sign window does
  not apply to being *offline*, only to *signing twice*).

## The `priv_validator_state.json` trap

This file tracks the last height/round/step the validator signed. **Never restore
an old `priv_validator_state.json`** onto a running validator and then sign again at
a height it already signed — that is a double-sign (slash + tombstone, §5.6). On
recovery, prefer letting the node start fresh with the current state, or use tmkms
(which keeps the authoritative high-water mark — see `validator-keys.md`).

## Off-host & encryption

- Store the consensus-key backup **encrypted** (e.g. age/gpg) and **off the
  validator host** (offline media / a separate vault).
- Test restores periodically: a backup you have never restored is a hope, not a
  backup.
