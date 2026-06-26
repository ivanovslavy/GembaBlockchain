# Live-deployment security audit + reconciliation — 2026-06-26

End-to-end security verification of the **live testnet deployment** (`gemba-testnet-1`,
EVM 821207), focused on the question **"can the contracts that hold funds be drained/stolen?"**,
plus an on-chain-vs-docs reconciliation. Complements the static audits + the
`docs/security-pentest-2026-06-24.md` campaign. Run with funded wallets + Foundry forks
against the real deployed contracts.

> **Verdict: the fund-holding contracts cannot be drained by a non-privileged caller.**
> Every reserve is owned by the Timelock; the only path to move reserve funds is
> Governor → Timelock → execute (proven end-to-end, live). 5 direct drain/escalation
> attacks were attempted against the live contracts and **all reverted**.

## 1. Fund-holding contracts — security map

| Contract | Live address | Holds (GMB) | Authority to move funds | Drain protection | Verified by |
|---|---|---|---|---|---|
| **Faucet** (public/municipal) | `0x0C6b72…3a66` | **29,999,500** | `release`/params = Timelock (owner); `grant` = granter, capped | onlyOwner + per-grant cap + epoch cap + pausable | A1/A2 live (grant ok, over-cap reverts, non-granter reverts); `Faucet.t.sol`; `LiveGov` |
| **Reserve (15M)** | `0x06cb10…6f7f` | **15,000,000** | Timelock (owner) | `release` onlyOwner; UUPS `_authorizeUpgrade` onlyOwner | A1 live (release reverts for non-owner); `Reserve.t.sol`; `LiveGov` |
| **Reserve (10M)** | `0x7E00f3…Abb8` | **10,000,000** | Timelock (owner) | same | A1 live; `LiveGov` |
| **Foundation (10M)** | `0xb5dec9…4696` | **10,000,000** | Timelock (owner) | same | A1 live; `Reserve.t.sol` |
| **Validator reward reserve** | `x/rewardstreamer` module acct | **20,000,000** | Cosmos module logic (no EVM/operator key) | streams a fixed annual amount via `BeginBlocker`; **mint/burn-free** keeper interface | `rewardstreamer/keeper` tests; live supply-invariant |
| **DEX** (LiquidityLocker, pairs) | Router `0x53d78a…`, Locker `0x88cb73…` | LP-supplied (0 pairs today) | LP owners; Locker time-locks LP | Uniswap-V2 K-invariant; Locker can't early-withdraw | audited **1:1 Uniswap V2**; `Dex.t.sol`, `F2_NativePoolFoT`, `Phase8Reentrancy` |
| OnRamp | `0x49Da58…eFd5` | 0 (sale disabled) | **owner = Timelock** | `publicSaleEnabled=false` by design; `nonReentrant`+SafeERC20; owner is governance | deployed+verified 2026-06-26; `OnRamp.t.sol` |
| Tickets / Perks / Paymaster / AccessNFT | see §6 | — | issuer/admin (app-level) | caps, soulbound, EIP-2771 | deployed+verified 2026-06-26; `Ticketing.t.sol`, `Perks.t.sol`, `MetaTx.t.sol`, `AccessControlNFT.t.sol` |

**Total in the Solidity reserve contracts: 65,000,000 GMB** (30+15+10+10), + 20M in the
rewardstreamer module = the 85M of non-circulating reserves; the remaining 15M is
circulation (10M) + founder (5M).

## 2. Live attack results (A) — all defended

- **A1 — governance/treasury:** the full **propose → vote → queue (Timelock) → execute**
  cycle works end-to-end (a forked run moved `Faucet.perGrantCap` only through that path).
  Five live drain/escalation attacks from a funded, non-privileged wallet **all reverted**:
  `Faucet.grant` (not granter), `Reserve.release` (not owner), `Reserve.upgradeToAndCall`
  (not owner), `Timelock.schedule` (not PROPOSER), `Faucet.setGranter` (not owner). Timelock
  roles correct (Governor = PROPOSER; open EXECUTOR after delay).
- **A2 — Faucet:** a real grant (500 GMB) succeeded; an over-cap grant (2000 > 1000) reverted.
- **A3 — DEX:** WGMB wrap/unwrap 1:1 live; deep adversarial covered by the audited 1:1
  Uniswap-V2 fork + Foundry.
- **B6 — valgate (min-self-bond):** observed live (the chain rejected a `min_self_delegation=1`
  validator at genesis); enforced at **two layers** — ante decorator (unwraps authz `MsgExec`,
  bounded depth) + `AfterValidatorCreated` hook (covers the precompile path).
- **B5/B7:** slash→faucet (zero-burn) is unit-tested for both pools (incl. not-bonded =
  double-sign) and **proven live** (downtime slash; supply unchanged); tailreward unit+live.

## 3. On-chain ⇄ docs reconciliation (findings)

| # | Finding | Severity | Status / fix |
|---|---|---|---|
| **R-1** | **Reserves ARE funded into the Solidity contracts** (65M live), contradicting CLAUDE.md §4.1 / `tokenomics-pending.md` which say they are "still held by genesis EOAs/module accounts, NOT yet by the Solidity reserve contracts". | doc-stale | **Update the docs** (done here + CLAUDE.md note). |
| **R-2** | Reserves were NOT excluded from `GembaVotes` on the live deploy (the deploy script intends to, but the live `excluded[]` set was empty). | ~~Low (live)~~ **FIXED 2026-06-26** | **Fixed via a real live governance cycle** (propose→vote→queue→Timelock→execute): all 4 reserves (Faucet/Foundation/DAO/Contingency) now `excluded[]=true` with `getVotes()=0`, and the same proposal raised the **quorum 50→66%**. Mainnet genesis also excludes the FINAL addresses (DeployGovernance, `excludedReserves`). Proof: proposal `GEMBA-HARDEN-1`. |
| **R-3** | OnRamp / Ticketing / Perks / Paymaster / AccessNFT were **not deployed on the live testnet** (only DEX + governance/treasury were). | info | **DONE 2026-06-26:** all 5 deployed + Blockscout-verified on the testnet (OnRamp owner=Timelock, sale disabled). Purpose + which are actually needed: **§6**. |
| **R-4** | **Genesis-generation bug:** `init-gembad-multinode.sh` didn't pass `--min-self-delegation`, so `gentx` defaulted to 1 wei and **x/valgate rejected every genesis validator** (chain wouldn't start). | build bug | **Fixed** (passes `--min-self-delegation ≥ MIN_SELF_BOND_GMB`). Mainnet genesis must do the same. |
| **R-5** | Governance params on the live testnet are **loose** (votingPeriod 600 blocks, quorum 50%, Timelock minDelay 300s) — testnet-only. | info | **Tighten for mainnet:** supermajority (66–75%) + higher quorum + longer timelock (CLAUDE.md §7). |

## 4. Self-audit (C) — static + multi-agent

- **`go vet`** (chain modules): **clean.** **`forge build`**: compiles (benign `block.timestamp`
  warnings on vesting/timelock comparisons).
- **Foundry suite: 107 passed / 0 failed** (3 `LiveGov` fork tests skip on an unforked run).
  Covers the fund-security path: reentrancy (`Reentrancy.t.sol`, `Phase8Reentrancy.t.sol`) +
  invariants (`FaucetInvariant`, `PerksInvariant`, `TicketingInvariant`, `VotesInvariant`).
- **slither** (`src/`, 128 contracts, 100 detectors): 273 results — overwhelmingly OZ-library
  style notes (naming) + the **GembaSwap (1:1 Uniswap-V2 fork)** known patterns (`unchecked-transfer`,
  `block.timestamp`, `weak-PRNG` in the init-hash). **No new `reentrancy-eth` / `arbitrary-send` /
  `suicidal` / `controlled-delegatecall` in our own contracts** — consistent with the triaged
  baseline in `contracts/SECURITY.md`.
- **npm audit:** `access-control` clean; **`testnet-faucet` had 2 (1 high = `ws` DoS, 1 moderate)
  → FIXED** via `npm audit fix` (ws 8.17.1→8.21.0, ethers 6.16→6.17); 0 vulnerabilities, tests still 5/5.
- **multi-agent `gemba-security-audit`** (auditor-per-component → adversarial verify → synthesis):
  _results appended below when the run completes._

**Multi-agent `gemba-security-audit` result (38 agents, adversarial verification):**
**No Critical / High / Medium findings.** 29 raw candidates → **4 confirmed** after adversarial
verification: **1 info + 3 low**, all observability/operational hardening, none exploitable.
Verdict: *"no buyer/user funds at risk anywhere; no supply or consensus risk; no repo secret leak."*

| # | Sev | Component | Finding | Action |
|---|---|---|---|---|
| AU-1 | Low | chain Go modules | fail-soft `recover()` in the BeginBlockers (feesplit/rewardstreamer/tailreward) has **no metric/alert** → a recurring panic would silently stall the economic logic while the node looks healthy | add per-module skip counters + a `/monitoring` alert (pre-mainnet) |
| AU-2 | Low | testnet-faucet | rate-limit + daily budget are **in-process only** (reset on restart, not shared across instances); min-balance floor is the durable hard stop | back with Redis or document single-instance |
| AU-3 | Low (op) | secret hygiene | local `.env`/the known GitHub PAT flagged for rotation (NOT committed) | rotate (operator note; PAT kept by decision until 2026-12-31) |
| AU-4 | Info | GembaOnRamp | on-ramp owner can drain its **own pre-funded sale stock** (operator-trust, by design, documented §16) | transfer ownership to Governor+Timelock for any public deploy |

This corroborates the live testing: the security work is **hardening backlog, not vulnerability
remediation**. AU-2 also overlaps the faucet (its npm deps were fixed here).

## 5. Mainnet hardening checklist (carry-over)

- [x] **Exclude the reserve contracts in `GembaVotes`** — done live on testnet via governance (2026-06-26); mainnet genesis excludes the FINAL addresses. — R-2
- [x] **Tighten governance params** — testnet quorum raised to 66% via governance; mainnet deploy sets `MIN_DELAY=86400` (24h) + `QUORUM_PCT=66` via env (DeployGovernance). — R-5
- [ ] **Genesis sets `--min-self-delegation ≥ valgate floor`** for all genesis validators. — R-4 (script fixed)
- [x] Deploy OnRamp/Ticketing/Perks/Paymaster/AccessNFT on testnet + verify (done 2026-06-26, §6). — R-3
- [ ] Update CLAUDE.md / `tokenomics-pending.md` (reserves ARE funded). — R-1 (done)
- [x] One validator = one box; RPC never on archive/explorer (`public-rpc-topology.md`).
- [ ] Validator key mgmt (tmkms/Vault); bonded-ratio monitoring live.
- [ ] **Upstream Cosmos EVM audit (ADR-006)** — hard launch blocker. Timeline: cosmos/evm v1 (post-audit) targeted **~end of Q2 2026**; track the cosmos/evm releases + the Sherlock report.

## 6. App / reference contracts — deployed on testnet 2026-06-26 (what they are, what you need)

All five were deployed to `gemba-testnet-1` and **Blockscout-verified** (gembascan.io). They are
**reference implementations**; the chain does not depend on any of them. Several overlap dApps that
already run on the testnet with their own contracts (**GembaPass** = access/subscription, **GembaTicket**
= ticketing), so "deployed" ≠ "you must use it".

| Contract | Address | What it does | Do you need it? |
|---|---|---|---|
| **GembaOnRamp** | `0x49Da581bf5C09aE24312574D4835d416EE5eEfd5` | Sells GMB for a stablecoin at a fixed rate (closed, **not** a public market). `publicSaleEnabled=false`, **owner=Timelock**. | **Yes, for mainnet** — this is the §6 institutional on-ramp (institutions pay stablecoin → get GMB). Governance-controlled. Keep it; enable via governance when an institution buys in. |
| **GembaTicketing** | `0xDA9dFb87f77ED2176C00339da0cEae2Ac6E5e722` | ERC-1155 events: create event, sell/issue tickets (GMB), redeem; supply caps. | **Probably not** — your **GembaTicket** dApp already does ticketing with its own contracts. This is a generic template/alternative. |
| **GembaPerks** | `0x3C9Fbaf4eCCD485698d1d99A2bA704ceb1bE266E` | Institution pays GMB employee bonuses + grants perk tickets (uses Ticketing). | **Optional** — only if you want on-chain employee bonus/perk flows. |
| **GembaForwarder** + **WorkplaceCheckIn** | `0xC2a4AA8B1E2cEB9Db8e565dEB52411F734bcB560` / `0xC4e2fb18AA7CD8E569f1A8E91A4d2dfDb1E95839` | Sponsored gas (EIP-2771 meta-tx): an institution's relayer pays gas so an employee needs **0 GMB**. CheckIn is an example sponsored target. | **Optional but valuable for adoption** — gasless UX for employees. Per-institution operational, **not** a chain dependency (ADR-011). |
| **AccessControlNFT** | `0xDd49015Ff5842cA7dc44681149194848ea68D4Ae` | Soulbound ERC-1155 capability NFT ("may enter zone X"), **no PII on-chain** (§10). | **Probably not** — your **GembaPass** dApp already covers access. This is the generic §10 reference. |

**Bottom line:** for mainnet the one with a real protocol role is **OnRamp** (governance-owned GMB
sale to institutions). The rest overlap GembaPass/GembaTicket — keep them as audited **references/templates**
and deploy per product only where a new institution needs that exact primitive. None are required for the
chain itself to run. On mainnet, deploy with the FINAL addresses and (for OnRamp) `owner=Timelock` from the
start — already the testnet posture here.
