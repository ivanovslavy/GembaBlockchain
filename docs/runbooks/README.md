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
| [`explorer-account-login.md`](./explorer-account-login.md) | GembaScan **per-user login + API keys** (currently DISABLED): the Auth0/cloak/reCAPTCHA/SendGrid dependency chain, exactly where it fails (email verification → 403), and how to finish later. The Etherscan-compatible API works without it. |
| [`raise-block-gas-limit.md`](./raise-block-gas-limit.md) | **block gas limit** finding (`block.max_gas` was 10M — too low for EVM deploys/DeFi): fixed to 100M in the genesis generator; the `x/consensus` gov-proposal procedure to raise it on the running testnet. (ADR-012) |
| [`testnet-re-genesis.md`](./testnet-re-genesis.md) | **corrected re-genesis** of gemba-testnet-1 to the exact §4.1 allocation (each reserve held by its contract at its %); the destructive reset + redeploy + fund + verify procedure. (path A) |
| [`explorer-migration.md`](./explorer-migration.md) | **split Blockscout off the archive** (`.137`) onto a dedicated NVMe box: parallel run, secure archive RPC tunnel (only the new server reads), re-index, Cloudflare DNS cutover, instant rollback — frees the archive from CPU/RAM contention |

These are **social/operational** procedures: there is no admin key that force-runs
the chain (§6). Test every procedure on a devnet/testnet before mainnet (§0.9).
