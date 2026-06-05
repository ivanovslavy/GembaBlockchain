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
| [`testnet-deploy.md`](./testnet-deploy.md) | deploy `gemba-testnet-1` on 5 geo-separated validators (genesis assembly, seeds, firewall, systemd) |
| [`testnet-launch-checklist.md`](./testnet-launch-checklist.md) | first-weeks checklist: block production, peers, bonded ratio, zero-inflation under load, drills |
| [`public-testnet-operations.md`](./public-testnet-operations.md) | **live public deployment**: 4-validator topology, add/remove (unbond, NAT) procedures, explorer+RPC architecture, MetaMask + chain-registry, and the version-pairing / next-image / CORS gotchas |

These are **social/operational** procedures: there is no admin key that force-runs
the chain (§6). Test every procedure on a devnet/testnet before mainnet (§0.9).
