# Runbooks — node operations (Phase 9 hardening)

Operational runbooks for running and maintaining GembaBlockchain nodes. Pair with
[`/monitoring`](../../monitoring) (Prometheus + the bonded-ratio security metric).

| Runbook | Covers |
|---|---|
| [`node-setup.md`](./node-setup.md) | seeds & persistent_peers (sentry topology), pruning — validator (pruned) vs archive (nothing) |
| [`validator-keys.md`](./validator-keys.md) | consensus/node/operator keys, **tmkms** remote signer, the double-sign trap |
| [`backups.md`](./backups.md) | what to back up, snapshots, the `priv_validator_state.json` trap |
| [`halt-recovery.md`](./halt-recovery.md) | recovering a halted BFT chain (liveness vs AppHash) |
| [`coordinated-upgrade.md`](./coordinated-upgrade.md) | binary/consensus upgrades via `x/upgrade` + cosmovisor, or emergency restart |

These are **social/operational** procedures: there is no admin key that force-runs
the chain (§6). Test every procedure on a devnet/testnet before mainnet (§0.9).
