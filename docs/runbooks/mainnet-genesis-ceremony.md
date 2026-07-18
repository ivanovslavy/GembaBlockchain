# Mainnet genesis ceremony & launch runbook — gemba-1 (EVM 821206)

> The step-by-step procedure for launching GembaBlockchain mainnet, written 2026-07-17.
> Companion checklists: `docs/mainnet-launch-hardening.md` (§B genesis values — the builder
> asserts them), `docs/mainnet-exclusion-list.md` (voting exclusions), the infra plan in
> memory/`docs/SERVER-TOPOLOGY.md` (testnet→mainnet transition), and the existing ops
> runbooks (`node-setup.md`, `validator-keys.md`, `backups.md`, `halt-recovery.md`,
> `coordinated-upgrade.md`). **Every ✋ step needs the owner; every ✅ step has a scripted
> check — record its output in the launch log.**

Topology (P1, €0-reuse): 4 validators = Contabo **.82/.83/.84** + the 4th box; archive =
**.137** (pruning "nothing"); explorer = **213.136.85.32** (gembascan.io). Mainnet RPC =
**gmb1→.82, gmb2→.83, gmb3→.84** (fresh subdomains; testnet's rpc1/2/3 die with the testnet).

---

## Phase 0 — Gates (before anything irreversible)

- ✅ **ADR-006 — CLEARED (owner 2026-07-18, `docs/risks.md`).** The upstream-audit gate
  is accepted (Sherlock-audited codebase + v0.7.0 pins every published advisory fix +
  our own multi-phase audit); NOT waiting for a formal v1 audit. **One residual action
  at genesis day:** check github.com/cosmos/evm for a `v0.7.1` tag (two security-adjacent
  backports were pending on `release/v0.7.x` on 2026-07-17: statedb locked-balance #1187,
  mempool base-fee #1223) — if tagged, bump `EVM_VERSION` in `build-gembad.sh` +
  rebuild/retest; otherwise launch on v0.7.0.
- ✅ Full test evidence recorded: `forge test` (contracts), `go test ./...` (chain),
  security e2e re-run — see hardening §B/§C and `security/results/`.
- ✋ Testnet farewell: announce the stop date, then execute Phase 0.5 below.

## Phase 0.5 — TESTNET DECOMMISSION + fresh boxes (THE NEXT STEP — owner plan 2026-07-18)

**STEP 0 — RPC CONTINUITY FIRST (owner 2026-07-18): move `rpc1/2/3` onto `.208` BEFORE
touching any validator.** Live dApps (educhain, escrow, win, gembaticket, gembapass) call
these hostnames; today `rpc1`→.83, `rpc2`→.84, `rpc3`→.82 — i.e. all three die the moment
the Contabo reinstalls start. `.208` is the box that stays up longest by design, so parking
all three names there keeps the dApps alive through the whole decommission with **zero
downtime and no dApp code changes** (the move is at DNS level).

- **Mechanism — Cloudflare Tunnel, NOT a DNS repoint.** `.208` is A1/**NAT, dials out, "No
  public RPC"** (`SERVER-TOPOLOGY.md:11`): it has no inbound reachability and A1 is likely
  CGNAT, so port-forwarding is not an option. Install `cloudflared` on the jellyfin host,
  create one tunnel, and route **all three hostnames** (`rpc1`, `rpc2`, `rpc3.gembascan.io`)
  through it to the container's local JSON-RPC. Cloudflare already fronts `*.gembascan.io`,
  so this is a DNS/tunnel change only.
- **Keep the hardened posture** (the security e2e asserts it): expose **only**
  `eth,net,web3` — never `debug`/`personal`/`admin`/`txpool` — plus the single-CORS +
  rate-limit rules on the Cloudflare side. Enabling JSON-RPC on `.208` must not regress
  pentest P-1/P-2/P-3. Verify `eth_chainId` answers on every hostname **before** step 1
  (and mind gotcha 0b below: the v0.7.0 JSON-RPC startup race — restart until 8545 answers).
- **Accepted for the wind-down:** all three names now resolve to ONE box (the fallback list
  is cosmetic) and `.208` has a downtime/jail history + residential bandwidth. Testnet load
  is ~0, so this is fine for a decommission window.
- **Also dies with the explorer (step 4):** `https://testnet.gembascan.io/rpc` (the swap
  frontend's FIRST entry, proxied by the explorer's Apache → rpc1). Either repoint that
  proxy at the tunnel too, or accept that swap falls back to `rpc1` — decide before step 4.
- **End of life:** when `.208` stops (step 6) the testnet RPC is gone for good and every
  testnet dApp goes dark. ✋ Owner decision needed before that: migrate each dApp to mainnet
  or let it retire with the testnet.

**Phased shutdown — validators unbond ONE BY ONE, `.208` is last and is ONLY stopped:**

1. Unbond `.82` (announce → `gembad tx staking unbond` full self-bond → confirm the chain
   keeps producing on the remaining set). Back up its testnet state per `backups.md`.
2. Unbond `.83` the same way.
3. Unbond `.84` the same way — at this point **`.208` (A1/NAT, docker validator) is the
   SOLE validator (100%)** and the testnet keeps producing on it alone.
4. Stop the explorer box `213.136.85.32` (docker compose down; final DB backup if wanted).
5. Stop the archive `.137` (final state backup — this is the full testnet history).
6. Only when everything else is down: **stop `.208`** (`docker stop` — it is the ONLY box
   that does NOT get reinstalled; the validator there is docker and is just stopped).
   The testnet ends here.

**Reinstall the 5 Contabo boxes with a CLEAN OS** (`.82`, `.83`, `.84`, explorer
`213.136.85.32`, archive `.137`) **and prepare them from zero for mainnet:**

- SSH: key-only auth (fresh authorized_keys), fail2ban/ufw baseline, updates.
- Validators — the 4 genesis boxes are **`.82`, `.83`, `.84` + `.208`** (owner decision
  2026-07-18). `.82/.83/.84`: deps + Go + `gembad` built from source, systemd service
  (installer does all of it: `GEMBA_NETWORK=mainnet` + `network.mainnet.env`), I4
  pruning from block 0, firewall (26656 open; RPC vhosts CF-only), Apache + Cloudflare
  Origin certs for `gmb1/gmb2/gmb3.gembascan.io` (gmb1→.82, gmb2→.83, gmb3→.84).
  **`.208` (A1/NAT, docker — no OS reinstall):** after its testnet container is stopped,
  stand up a FRESH mainnet docker container (mainnet gembad build + the
  `network.mainnet.env` params, new keys per the ceremony — nothing testnet is reused);
  NAT box = outbound peers only, no public RPC there (same as testnet).
- Archive `.137`: gembad archive profile (`pruning="nothing"`, `evm-timeout 60s`),
  systemd, NO public RPC (hard rule).
- Explorer `213.136.85.32`: docker + `explorer/docker-compose.mainnet.yml` + fresh
  `envs/backend.env` secrets, Apache/TLS for `gembascan.io`.
- **autossh tunnel archive → explorer** (same pattern as testnet: the explorer reads the
  archive's EVM RPC privately; only the explorer box can reach it).
- Monitoring per box (prometheus/alertmanager + bonded-ratio exporter host),
  auto-unjail/auto-compound units on the validators, backups per `backups.md`.
- Then proceed to Phase 1 (DNS finalization) and the ceremony — **mainnet begins**.

## Phase 1 — DNS + boxes (days before genesis day)

1. Cloudflare DNS: `gmb1.gembascan.io`→.82, `gmb2`→.83, `gmb3`→.84 (proxied), plus
   `gembascan.io`→213.136.85.32. Apache vhosts + Cloudflare Origin certs on each box
   (same pattern as the testnet rpc vhosts).
2. Explorer box: place `explorer/docker-compose.mainnet.yml` + a fresh
   `envs/backend.env` built from `envs/backend.mainnet.env.example` — **generate fresh
   SECRET_KEY_BASE / CLOAK / API keys, never reuse testnet secrets**.
3. Archive box .137: node home wiped, `pruning="nothing"`, `evm-timeout 60s` (the
   explorer-tuning lesson), autossh tunnel to the explorer box re-pointed.
4. Validator boxes: wiped per the transition plan; I4 disk hardening comes via the
   installer (`network.mainnet.env` pruning block).

## Phase 2 — Key ceremony ✋ (see also `validator-keys.md`)

**Rule: a validator operator key is BORN on its box and never leaves it. No key material
in the repo tree, ever. Every key gets an encrypted backup + a TESTED restore (the owner's
condition: "всички ключове ги имаме и е сигурно, че можем да ги ползваме при нужда").**

1. On each validator box: `gembad keys add validator --keyring-backend file` (NOT `test`).
   Record the ADDRESS only. (`priv_validator_key.json` + `node_key.json` are generated by
   init; they are box-local consensus/p2p keys — back them up encrypted, they ARE the
   validator identity.)
2. On the owner's secure machine (offline preferred): generate `founder`, `foundation`,
   `dao`, `contingency`, `publicfaucet` + the 3 EmergencyPause guardians + the
   GembaPayDispenser owner (fresh — do NOT reuse the testnet dispenser key) +
   `COLLECTOR_RECIPIENT`. Record addresses.
3. Backups: `age`-encrypt (or GPG) every mnemonic/keystore → TWO offline copies
   (USB + second location). **Restore test is mandatory**: decrypt each backup on a clean
   machine, re-derive, compare addresses. Log the test.
4. Fill the address tables: `docs/mainnet-exclusion-list.md` rows 1–9 + the env sheet for
   Phase 3/5 (VAL_ADDRS, FOUNDER_ADDR, …). Dispenser/collector/drip-faucet addresses
   (rows 10–12) are CREATE2 — precompute them (`forge script` simulation prints them) so
   they can go straight into `EXCLUDE_EXTRA`.

## Phase 3 — Genesis build ✅ (`chain/gembad/init-gembad-mainnet.sh`)

1. Build the binary: `./build-gembad.sh` (EVM_VERSION per the Phase-0 decision). Same
   binary version on ALL boxes.
2. `FOUNDER_ADDR=… FOUNDATION_ADDR=… DAO_ADDR=… CONTINGENCY_ADDR=… PUBLICFAUCET_ADDR=…
   VAL_ADDRS="v0 v1 v2 v3" ./init-gembad-mainnet.sh build`
   → the 33-assert battery must print **VERIFY OK** (supply exact 100M, gov 3d/0.334,
   unbonding 21d, valgate 1k/10k/50, feemarket 5 gwei, formula 1%/10/100/36000/5479,
   legacy stream OFF, zero inflation).
3. Distribute the PRE-GENTX genesis to each validator box; each runs the printed gentx
   command (self-bond 10,000 GMB, `--min-self-delegation 1000000000000000000000` — the
   valgate floor) and returns ONLY the gentx json.
4. `GENTX_DIR=… ./init-gembad-mainnet.sh collect` → validate + VERIFY OK + **sha256**.
5. Publish: genesis to `https://gembascan.io/brand/genesis.json`; fill `GENESIS_SHA256`
   + `SEEDS` (from `gembad comet show-node-id` per box) into
   `gemba-validator/network.mainnet.env`; commit; announce the hash.

## Phase 4 — Network start ✅

1. Each validator box: `GEMBA_NETWORK=mainnet ./scripts/install-validator.sh` (it now
   refuses blanks; systemd ExecStart already carries `--chain-id gemba-1
   --evm.evm-chain-id 821206` — a bare `gembad start` without them FAILS, this is known).
2. All 4 up → blocks flow. Checks: height rises on all 4; `curl gmb1…/​` eth_chainId =
   `0xc87d6`; no `wiring: begin-blocker` panic in journals (the L1 assertion booted);
   `init-gembad-mainnet.sh verify` against the LIVE genesis file.
3. Archive .137 syncs (pruning nothing); explorer compose up; Blockscout indexes from
   block 1 (tiny chain — minutes).

## Phase 5 — Contract deploys (ORDER MATTERS) ✅

From the owner machine, against `https://gmb1.gembascan.io`:

> **⚠️ TWO GOTCHAS CAUGHT BY THE 2026-07-18 STAGING REHEARSAL (do these first):**
>
> **(0a) The canonical CREATE2 factory does NOT exist on a fresh chain** — every deploy
> script fails with "missing CREATE2 deployer 0x4e59b44847…". Deploy it FIRST
> (Arachnid deterministic-deployment-proxy, same address on every chain):
> ```
> # temporarily start the serving node with --json-rpc.allow-unprotected-txs=true
> # (the presigned tx is legacy/non-EIP155); remove the flag afterwards
> cast send 0x3fab184622dc19b6109349b94811493bf2a45362 --value 100000000000000000 \
>   --private-key $FOUNDER_PK --rpc-url $RPC          # fund the one-time deployer
> cast publish 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222 \
>   --rpc-url $RPC
> cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url $RPC   # must be non-empty
> ```
>
> **(0b) cosmos/evm v0.7.0 JSON-RPC startup race** — if the HTTP JSON-RPC server starts
> before the first applied block, it dies permanently (ctx-cancel in server/json_rpc.go;
> WS may stay up but hangs). On live chains a restart usually wins the race; at GENESIS
> day it is a coin flip. After starting any RPC-serving node ALWAYS verify
> `eth_chainId` answers on 8545; if dead, restart the node until it does. Enabling
> JSON-RPC on several nodes gives several lottery tickets. (Watch upstream for a fix
> in v0.7.1+.)

1. **DeployGovernance** — env: `FOUNDER_PK`, `FOUNDATION_PK`, `DAO_PK`, `CONTINGENCY_PK`,
   `GUARDIAN1..3`, `MIN_DELAY=86400` (24h), `VOTING_PERIOD=108000` (blocks ≈ 3d @2.4s),
   QUORUM_PCT **unset** (= standard 40; Critical is fixed 51/66),
   `EXCLUDE_EXTRA=<rows 1–12 of the exclusion list, comma-joined>` (strict parsing — a
   typo reverts the deploy, by design). Funds Foundation 15M / DAO 10M / Contingency 20M.
2. **`contracts/script/verify-exclusions.sh`** — MANDATORY GATE: every list entry
   `excluded=true` + `getVotes==0`, negative control open. **Do not announce before OK.**
3. **DeployDripFaucet** → fund 100,000 GMB from `publicfaucet` EOA.
4. **DeployDispenser** — `DISPENSER_OWNER=<GembaPay signer>`, `COLLECTOR_RECIPIENT=…`;
   then `fund()` the dispenser from the founder stock (operational amount, e.g. 100k).
5. **DeployApps** (Ticketing, Perks, Forwarder, CheckIn, AccessNFT). *(No OnRamp — the
   contract no longer exists.)*
6. **DeployDex** (optional reference tooling — project operates none of it).
7. **`GEMBA_NETWORK=mainnet contracts/script/verify-all.sh`** — every contract verified
   on gembascan.io.
8. The 30M Public Reserve stays in the Cosmos feesplit module account; the EVM
   PublicReserve contract is deployed but seeded later via the documented Cosmos↔EVM
   seam (`tokenomics-pending.md` "Genesis mechanics" #2) — NOT a launch step.

## Phase 6 — Critical infrastructure (т.18 — ALL of it, before announcing)

| System | Action | Check |
|---|---|---|
| Email известявания | `services/blockchain-notifier` with `NETWORK=mainnet` env (chainId 821206 default, explicit `COSMOS_REST`, mainnet dispenser address, SMTP creds) | send a test alert; `Dispensed` watcher sees a test dispense |
| Аларми | `monitoring/` per box: prometheus + alertmanager + `alerts.yml`; SMTP password via file | fire a test alert route |
| Bonded-ratio (ADR-008 gate) | `monitoring/bonded-ratio-exporter.sh` against a mainnet REST endpoint + the 66/50/33 alerts | metric visible in Prometheus; **this closes the ADR-008 launch blocker** |
| Watchdog (auto-restart→sync→unjail) + auto-compound | `gemba-validator/auto/install-validator-auto.sh` on all 4 boxes; `validator-auto.env` with `CHAIN_ID=gemba-1` + **per-box `RESTART_CMD`** (Contabo `systemctl restart gembad-val`, .208 `systemctl restart gembad`) + `TIP_EVM_RPCS="https://gmb1.gembascan.io https://gmb2.gembascan.io https://gmb3.gembascan.io"` + `NOTIFY_CMD=/usr/local/bin/gemba-alert-email.sh` (email on jail/recovery/give-up). The watchdog rewrite (2026-07-18) fixes the old unjail-only script that could NOT recover a frozen/de-peered node — see `validator-auto-ops-deploy.md` | timers active; force-a-stuck drill: stop peers → see it restart → unjail; jail one → email arrives |
| Disk-guard + node-watchdog + alert email (**every box, from genesis**) | `install-validator-auto.sh` now also installs **gemba-disk-guard** (emails before a full disk crash-loops the node) + **gemba-alert-email** (SMTP sink). On NON-validator boxes (archive/explorer) run `install-node-ops.sh [--with-watchdog]` — the archive gets **gemba-node-watchdog** (detect-stuck→restart, NO unjail; set `RPC_HTTP` to the node's REAL rpc port — the testnet archive uses **26667**, not 26657). Provision the SMTP secret: `printf %s '<pw>' > /etc/gemba/smtp_password; chmod 600`; set `SMTP_HOST` in `/etc/gemba/notify.env` | `gemba-disk-guard.timer` active on all boxes; test: force a mount to CRIT → email; archive: stop it → node-watchdog restarts it |
| Backups | `backups.md` applied to the mainnet homes (keyring + priv_validator_key + node_key, encrypted, off-box) | restore test logged |
| Public faucet service | `services/testnet-faucet` in CONTRACT mode (`FAUCET_CONTRACT=<drip faucet addr>`); raw mode self-refuses on 821206 | `/drip` works; 0.1 GMB/day per §4.1 |
| GembaPay backend | `.162` `/gembapay.com/backend/.env`: mainnet `GEMBA_DISPENSER_ADDRESS`, `GEMBA_RPC_URL=https://gmb1.gembascan.io`, `GEMBA_CHAIN_ID=821206`, NEW owner key | E2E Buy-GMB test purchase |
| purchase-backend | same env family (chainId 821206, gmb1 RPC, mainnet dispenser) — defaults are still testnet, override ALL | webhook fail-closed test (H2) |
| Swap frontend | fill `DEX[821206]` addresses (if Phase-5 #6 ran), add `gembaMainnet` to `SUPPORTED_CHAINS` | connect + read path |
| Chain registry | submit `docs/chain-registry/eip155-821206.json` (RPC must answer first) | chainlist shows "Gemba" |
| Chainscout | add `gemba-821206.json` once the mainnet explorer is live | — |
| Websites/SEO | gembachain.io & co: mainnet RPC/addresses pages + `llms.txt`/`ai.txt`/sitemap per CLAUDE.md §0.12 | — |

## Phase 7 — Post-launch (weeks 1–4)

- Re-measure real block time; if it drifts from 2.4s, reconcile `blocks_per_year` /
  `formula_params.blocks_per_day` via governance (`MsgUpdateParams` /
  `MsgUpdateFormulaParams` — both gov-gated, no upgrade needed).
- Publish the decentralization KPIs (ADR-010): operators, Nakamoto coefficient, bonded
  ratio, founder share of circulating GMB.
- Run `security/e2e/live-invariants.sh` with a mainnet `config.sh` (leave `C_ONRAMP`
  unset — the check then asserts "no public sale by construction").
- Keep the on-demand `.100` testnet recipe for upgrade rehearsals
  (`coordinated-upgrade.md`).
