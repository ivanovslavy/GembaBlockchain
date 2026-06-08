# Runbook — node setup: peers & pruning

How operators connect a node and choose pruning. Two node profiles:

| Profile | Who | Pruning | Disk |
|---|---|---|---|
| **Validator / full node** | validators, RPC providers | **pruned** | bounded |
| **Archive node** | the explorer (GembaScan), data/indexing | **nothing** (full history) | grows forever |

## Peers: seeds & persistent_peers (CLAUDE.md §11)

Peer discovery is via **seeds** (give you an address book, then you disconnect) and
**persistent_peers** (you stay connected). In `config.toml [p2p]`:

```toml
# seeds: a few well-known seed nodes (id@host:26656), comma-separated
seed_nodes = ""                # legacy key; use `seeds` below if present
seeds = "<seed_id>@seed1.gemba.example:26656,<seed_id2>@seed2.gemba.example:26656"
# persistent_peers: stable peers you always dial (sentries, known validators)
persistent_peers = "<peer_id>@peer1:26656,<peer_id2>@peer2:26656"
# get a node's id:  gembad comet show-node-id
```

- **Genesis validators** (the founder's 5 servers, §5.3) seed each other via
  `persistent_peers`. New operators add a couple of public **seeds**.
- **Sentry architecture (recommended for validators):** the validator's P2P is
  private; it only `persistent_peers` to its own sentry nodes, which face the
  public network. The validator's address is not gossiped (DDoS protection):
  `pex = false` on the validator, sentries set `private_peer_ids` to the validator.
- Localhost multi-node dev: set `addr_book_strict = false` and
  `allow_duplicate_ip = true` (see `chain/scripts/init-multinode.sh`).

## Pruning (CLAUDE.md §11)

State growth is continuous (~5s blocks), so **validators prune**. In `app.toml`:

```toml
# --- validator / full node: prune, keep a recent window ---
pruning = "custom"
pruning-keep-recent = "100000"   # ~ a few days of state at 5s blocks
pruning-interval = "10"
# (or pruning = "default" for the SDK's sensible default)
```

```toml
# --- ARCHIVE node (explorer backend): keep EVERYTHING ---
pruning = "nothing"
```

> The explorer (Blockscout/GembaScan) needs historical state and per-block traces,
> so it MUST point at an **archive** node — never a pruned validator (a pruned node
> errors on historical-state queries). See `explorer/README.md`.

Also relevant:
- `min-retain-blocks` (app.toml) — block (not state) retention; `0` = keep all.
- Snapshots (`[state-sync.snapshot-*]`) — let new nodes state-sync fast instead of
  replaying from genesis.

## Disk guidance

- **Pruned validator:** plan tens of GB; monitor with the `NodeDiskFillingUp`
  alert (`monitoring/alerts.yml`).
- **Archive node:** plan for unbounded growth; provision generously and budget for
  ongoing expansion.
