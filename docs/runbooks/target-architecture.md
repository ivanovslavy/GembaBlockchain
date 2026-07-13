# Target architecture + testnet decommission plan

Decided 2026-07-13. This is the **final steady-state design**. It **supersedes** the
weak-hardware workarounds in `pruned-explorer-node-setup.md` and
`explorer-dedicated-node-and-indexing-tuning.md` — those were only needed because the archive
sat on a slow Contabo box. Moving the archive to real NVMe (Hetzner) removes the whole
pruned-node + RPC-router + tunnel edifice: a plain archive keeps up **and** serves the explorer
from one box.

## Why (the lesson that drove this)

The only thing that ever bottlenecked the explorer was **the archive on weak Contabo I/O**
(HDD-speed "NVMe" ≈ 250 MB/s). Under load it couldn't both sync fat blocks and serve
Blockscout, fell behind, got flooded, stalled. Fix = put the archive on a box with real NVMe
and strong cores. Everything else (validators, mgnuniverse) is fine on Contabo — only the
archive/explorer is I/O-bound. Contabo stays for the cheap roles; **only the archive goes
Hetzner**. Cost: Martin contributes toward a Contabo box, so the Hetzner cax31 nets out cheaper.

## Steady-state topology

```
Hetzner cax31 (ARM, NVMe, 8c/16GB/160GB, ~3.5x a Contabo 6-core, €21/mo)
  ├─ gembad ARCHIVE (pruning=nothing) — json-rpc bound to 127.0.0.1 only
  └─ Blockscout / GembaScan stack — reads the archive over localhost / Docker network
     → NO external RPC, NO autossh tunnel, NO pruned node, NO router. Internal port only.
     → public: only p2p 26656 (+ the site via Cloudflare). 8545/8546 firewalled to localhost.
  (replaces TWO Contabo boxes: the old .137 archive + the 213.136.85.32 explorer box)

Contabo boxes (reinstalled clean OS, cheap roles):
  ├─ mainnet validator nodes, one per box (validators don't serve the explorer → Contabo is fine)
  └─ 13.140.148.137 (the old archive box — big SSD) → mgnuniverse.com (moved off the Pi)
     Nice reuse: .137's SSD was a liability for an ARCHIVE (random-I/O-bound) but is ideal for
     mgn's 4K video — media serving is space + sequential throughput, not the random I/O that
     hurt the chain. Big + SSD = exactly right for Martin's clips.

Disk: cax31 holds two growing datasets (archive chain DB + Blockscout Postgres). 160GB is fine
for testnet (re-genesis'd) and a good while on mainnet; **mount an extra volume when it fills**.
```

### Why co-locating archive + explorer is correct here (it was hardware, not co-location)
The old vicious cycle — *weak archive falls behind → Blockscout floods it with eth_call →
archive stalls* — only happened because the archive was slow. On a strong box the archive never
falls behind → Blockscout stays caught up → no flood → stable. Co-location then becomes a **win**:
Blockscout reads over **localhost** (faster than any cross-box tunnel) and the RPC never leaves
the box (smaller attack surface).

### ARM prerequisite (one-time)
cax31 is ARM64. gembad's app-hash is **architecture-independent** (deterministic Go state
machine), so an ARM64 build from the exact deployed source produces the same app-hash. Before
trusting the cax31 archive: build gembad for arm64 from commit `d8a454f` (full `git clone` first
— it isn't in every local checkout), start it, and **verify it syncs without an app-hash panic**.
Also confirm the Blockscout backend has an arm64 image (Postgres/Redis/frontend already do;
Ampere users run Blockscout, so it's likely fine — verify).

## Testnet lifecycle — decommission to on-demand

After the current big tests finish, the testnet is **no longer kept always-on** (not worth
maintaining a full validator set for it):

1. **Properly unbond** the Contabo testnet validators so their voting power → 0, leaving
   **`.100` (val-3, home) as the sole validator (100% power)**. (Mind the unbonding period; for
   a chain we fully control this is just an operational step.)
2. **Reinstall the freed Contabo boxes with clean OS** and repurpose them (mainnet validators /
   mgnuniverse per the topology above).
3. `.100` keeps the testnet node but **stopped by default**. A single validator with 100% power
   can produce blocks alone, so:
   - **Need to test before a big update?** Start `gembad-node2` on `.100` → the testnet goes
     live (solo validator) → run the tests → **stop it again**.
   - `.100` is therefore an **on-demand testnet**, not a standing cost. It only runs during a
     test window, so it doesn't permanently load `.100` (which also runs Qortal/Jellyfin/etc.).

> This is why we did NOT stand up a permanent extra node on `.100` for the pruned-node
> experiment — `.100` is already busy; an always-on node would risk its services. On-demand
> start/stop is the right pattern there.

## Purchase / rollout order

1. Wait for **cax31 availability**, buy it.
2. One-time: verify the **arm64 gembad build** (app-hash) + Blockscout arm64 image.
3. Bring up **archive + Blockscout on cax31**, internal RPC, sync it.
4. **DNS cutover** `testnet.gembascan.io` / `gembascan.io` → cax31 (Cloudflare-proxied → instant
   origin flip). Retire the old `.137` archive + `213.136.85.32` explorer Contabo boxes.
5. After the big tests: **decommission the testnet to the on-demand `.100` model**; wipe +
   repurpose the Contabo boxes as mainnet validators; repurpose **`.137` (big SSD) → mgnuniverse.com**.
6. **Mainnet** uses the same shape: archive+explorer on Hetzner (bigger box / extra disk as it
   grows), validators on Contabo.
