# contracts — Security notes & Slither triage

Static analysis: `slither . --filter-paths "lib/|test/" --exclude-dependencies`
(Slither 0.11.3). Every finding is triaged below. Per
`docs/phase3-treasury-principles.md`: **tests first, funding last** — no contract
holds tokens until tests + (for reserves) an audit are done. These contracts are
**unfunded** and **not deployed to mainnet**.

## Remix AI review hardening (2026-06-06)

Minor findings from a Remix AI pass over each contract, triaged & addressed:

- **`EmergencyPause`** — *front-running on guardian add/remove (no fund loss).* Real
  cause: a removed guardian's stale confirmation kept counting toward a threshold (and
  a guardian could pre-confirm just before removal). Fix: added `configEpoch`, mixed
  into the confirmation id and bumped on every `setGuardian`/`setThreshold`, so any
  config change invalidates pending confirmations. No fund path either way (pause-only).
- **`GembaTicketing`** — *consider rejecting stray native value.* Added explicit
  reverting `receive()`/`fallback()` (`DirectPaymentNotAllowed`) so inbound GMB can only
  arrive via `buy()` (which tracks `proceeds`); fail loud instead of silent default revert.
- **`GembaPerks`** — *suggested address(0) checks for `ticketing.issue`.* Already present
  (`grantPerk` validates `employee != 0`; constructor validates `ticketing`/`admin`). No
  change needed.
- **`HelloGemba`** (Phase-1 smoke test) — `setGreeting` was open; restricted to `deployer`.
- **`SeamProbe`** (Phase-3 devnet probe) — `forward()` (the spend path) was open; restricted
  to `owner` (deployer). `receive()` is intentionally left open and documented — the probe
  must accept bank-layer deposits from any sender; only `owner` can move funds out.
- **`LiquidityReserve` → `ContingencyReserve`** — renamed (no liquidity by design, §8).

All 83 Foundry tests pass after these changes.

## Retroactive security pass (docs/security-standards.md)

All Phase 3 & 4 contracts were reviewed against the standards. Changes:

- **`GembaVotes`** — added `ZeroAmount` custom error; `depositFor` now validates
  `to != 0` and `msg.value != 0`; `withdrawTo` now validates `amount != 0`. CEI
  (burn before send) + `nonReentrant` documented.
- **`BaseReserve`** (and `Faucet`/`FoundationTreasury`/`DAOReserve`/`ContingencyReserve`)
  — added `ZeroAmount`; `_release` now validates `amount != 0` (single validated
  exit, reached by `release` and `Faucet.grant`).
- **`EmergencyPause`** — now `is ReentrancyGuard`; `confirm()` is `nonReentrant`
  (it makes an external `pause()/unpause()` call) and validates `target != 0`. CEI
  already advanced the round before the external call.
- **Reentrancy-attack tests added** (`test/Reentrancy.t.sol`): a re-entrant caller
  is repelled on `GembaVotes.withdrawTo`, `Faucet.grant`, and
  `EmergencyPause.confirm`.
- `GembaGovernor` / `GembaTimelock` / `GembaForwarder` / `WorkplaceCheckIn` — no
  changes needed: thin subclasses of audited OZ (or no external call / no value),
  with our added code already validated.

Result: **44 Foundry tests pass**; Slither **13 results, all triaged** (no new
findings from the pass).

## Resolved

- **Missing zero-check, `GembaVotes` constructor `_governance`** → added
  `ZeroAddress` revert.
- **Missing zero-check, `GembaVotes.withdrawTo` `to`** → added `ZeroAddress`
  revert (prevents burning vGMB and losing the native GMB to `address(0)`).

## Accepted (intentional / not exploitable)

- **"Sends ETH to arbitrary destination" — `BaseReserve._release`.** The
  destination is chosen by an **access-controlled** caller: `release()` is
  `onlyOwner` (the Timelock), and `Faucet.grant()` is granter/owner-only and
  capped. Moving GMB to a chosen recipient is the contract's whole purpose; the
  control is *who* may call, enforced and tested. `_release` runs under
  `nonReentrant` and checks the call's success.
- **"Low-level call" — `_release`, `GembaVotes.withdrawTo`.** Native GMB transfers
  must use `call{value:}` (the only safe way to send native value post-EIP-1884).
  All are guarded by `nonReentrant` and revert on failure.
- **Missing zero-check — `Faucet` `granter`.** A zero granter is **valid and
  intentional**: it disables the formula/automation path, leaving only governance
  `release()`. Not a bug.
- **"Costly operations in a loop" — `EmergencyPause` constructor.** Runs once at
  deployment over a small, fixed guardian list. Acceptable.
- **Naming — `__BaseReserve_init`, `__gap`.** OpenZeppelin upgradeable conventions
  (initializer prefix, storage gap). Intentional.

## Phase 4 (meta-tx sponsored gas)

- **`GembaForwarder`** is a thin subclass of OpenZeppelin's audited
  `ERC2771Forwarder` (EIP-2771); **`WorkplaceCheckIn`** uses OZ `ERC2771Context`.
  Slither reports no reentrancy / arbitrary-send / unchecked findings on either —
  only a benign **"different pragma directives"** note (our contracts pin
  `^0.8.24`; the OZ files allow `^0.8.20`; they compile and run together fine).
- The forwarder relays only **signature-verified** requests and cannot move funds
  beyond the call the employee signed (ADR-011 "Paymaster constraints"); replay,
  bad-signature and expired-deadline paths are tested in `MetaTx.t.sol`.

## Phase 6 (GembaPay on-ramp)

- **`GembaOnRamp.buy` / `withdrawGmb`** — "sends ETH to arbitrary destination" /
  "low-level call": **intentional and access-/guard-protected**. `buy` sends GMB to
  the **paying buyer** (`msg.sender`) who just transferred stablecoin in; CEI (pull
  payment, then deliver) + `nonReentrant` (tested in `OnRamp.t.sol`
  `test_BuyReentrancyBlocked`). `withdrawGmb` is `onlyOwner` + `nonReentrant`.
  Native GMB transfers must use `call{value:}` with a checked success — done.
- The **MiCA gate** (`publicSaleEnabled`, default `false`) is enforced and tested
  (`test_PublicSaleDisabledByDefault`); enabling is `onlyOwner`.

## Phase 8 (Ticketing + perks)

- **`GembaTicketing.buy` / `GembaPerks.payBonus`** — re-entrancy is repelled
  (`nonReentrant` + CEI): `buy` mints (ERC-1155 acceptance callback is the external
  call) after bumping supply/proceeds; `payBonus` is role-gated. Both have
  reentrancy-attack tests (`Phase8Reentrancy.t.sol`).
- **"sends ETH to arbitrary user" / "low-level call"** on `withdrawProceeds`,
  `GembaPerks._payBonus` / `withdraw` — intentional, access-controlled
  (`onlyRole`), `nonReentrant`, capped (`maxBonus`); native sends require
  `call{value:}` with checked success.
- **"external call in a loop"** — `payBonusBatch` pays each employee in a loop.
  Intentional batch payout: atomic (one failing recipient reverts the whole batch —
  fail loud), `nonReentrant`, distributor-gated. Accepted; callers keep batches a
  reasonable size.
- Supply cap and pool-drain protection are fuzzed: `TicketingInvariant`
  (minted ≤ maxSupply) and `PerksInvariant` (only authorized bonuses leave the
  pool), 128k calls each.

## Out of scope

- **`SeamProbe.sol`** — a **devnet-only** probe used to prove the Cosmos↔EVM seam
  (`docs/phase3-treasury-principles.md`). It is never deployed to production; its
  Slither findings (arbitrary send, low-level call, event-after-call) are
  irrelevant to the treasury system.
- **`HelloGemba.sol`** — a Phase 1 deploy smoke-test, not part of Phase 3.

## Design properties enforced by tests

- Reserve funds leave **only** via the owner (Timelock): `release()` is `onlyOwner`
  (`Reserve.t.sol`, `GovernanceIntegration.t.sol`), and the fuzz invariant
  `FaucetInvariant` (128k calls) shows no unauthorized/over-cap call can drain it.
- **Upgrade authority is the Timelock only**, never an EOA
  (`test_UpgradeOnlyByOwnerTimelock`).
- **EmergencyPause can only pause/unpause**, never move funds
  (`test_PauseCannotMoveFunds`).
- **1-GMB-1-vote with reserves excluded**; every vGMB backed 1:1 by native GMB
  (`VotesInvariant`).
- A proposal needs **high quorum AND supermajority** and a **timelock delay**
  before any reserve pays out (`GovernanceIntegration.t.sol`).

---

## Audit remediation + tooling re-run (2026-06-08)

Following the multi-agent audit (`docs/security-audit-2026-06-08.md`), the Solidity findings
were fixed (96/96 Foundry tests pass):

- **#3 Faucet** — added a rolling-window aggregate cap (`epochCap`/`epochLength`,
  gov-tunable) so a compromised `granter` key cannot drain the reserve via many sub-cap
  calls; deploy wires 100k GMB/day. (`test_EpochCapStopsDrainAcrossManyCalls`.)
- **#6 GembaTicketing.buy()** — reverts `NotForSale` when `price == 0` (price-0 events are
  organizer-issue-only; blocks public free-mint front-running). (`test_BuyPriceZeroNotForSale`.)
- **#7 GembaNativePool** — fee-on-transfer / rebasing safe: credits only the `balanceOf`
  delta actually received on token-in paths (like the V2 pair).
- **#8 GembaNativePool** — zero-address `to` checks on all entrypoints (no silent native burn).
- **#10 GembaVotes** — constructor excludes the four reserve contracts from voting at genesis
  (was structural-only); `DeployGovernance` reorders deploy + wires it.

### Slither (2026-06-08): every High/Medium is in the bundled Uniswap V2 fork or WETH/probe

`slither .` (128 contracts, 100 detectors). **No real exploitable issue in project-authored
contracts.** Triage:

| Detector | Where | Verdict |
|---|---|---|
| reentrancy-eth/no-eth | `GembaSwapPair.swap/burn`, `Factory.createPair` | Guarded by the V2 `lock` mutex (verified present + applied) — benign |
| unchecked-transfer / unused-return | `GembaSwapRouter02`, `GembaSwapLibrary` | Canonical V2 (pair `transferFrom` reverts on failure; tuple-unused fields) — benign |
| weak-PRNG | `GembaSwapPair._update` (`block.timestamp % 2**32`) | TWAP timestamp, not randomness — benign (classic V2 false positive) |
| assembly-usage | V2 ERC20 chainid, Factory CREATE2 | Required by V2 — benign |
| reentrancy (WGMB.withdraw) | `WGMB` | Standard WETH9 (balance decremented before call, CEI) — benign |
| reentrancy (SeamProbe) | `SeamProbe` | Devnet probe, never on mainnet |
| sends-eth-to-arbitrary | `GembaOnRamp.buy`, `BaseReserve._release`, `GembaPerks.*`, `GembaTicketing.withdrawProceeds` | All access-controlled (`onlyOwner`/`onlyRole`/granter) or `to == msg.sender`; CEI + `nonReentrant` — by design |
| strict-equality / block-timestamp / missing-zero-addr / costly-loop / naming / too-many-digits | NativePool, LiquidityLocker, Faucet epoch, EmergencyPause ctor, V2 fork | Correct guards / by design / style — benign |

No suppression filter is configured **on purpose** — findings stay visible; this table is the triage.

### Why the "benign because it's Uniswap V2" verdict is *verified*, not assumed

A small divergence in a forked AMM can be catastrophic, so the canonical-V2 claim was checked
directly rather than trusted:

1. **`GembaSwapPair.sol` read line-by-line** vs canonical `UniswapV2Pair`: the `lock` reentrancy
   mutex is present and applied to `mint/burn/swap/skim/sync`; the **K-invariant**
   `balance0Adjusted·balance1Adjusted ≥ reserve0·reserve1·1000²` with the 0.30% fee
   (`·1000 − amountIn·3`) is intact; `MINIMUM_LIQUIDITY=1000` locked on first mint;
   `INVALID_TO`, `_safeTransfer` (return-checked), `_mintFee` (1/6 growth) all canonical.
2. **Init-code hash verified** — the single most dangerous fork divergence (CREATE2 `pairFor`
   address derivation). `keccak256(type(GembaSwapPair).creationCode)` ==
   `0x3f0934d46a91c709987fdcb90849be623789276da3993bdf747548e051eaa689`, the hash hardcoded in
   `GembaSwapLibrary.pairFor`. They MATCH → the router computes the real pair address; no
   fund-misrouting. (Re-verify with `cast keccak $(jq -r .bytecode.object out/GembaSwapPair.sol/GembaSwapPair.json)`.)
3. **End-to-end** — `Dex.t.sol` drives the full router path (add/remove liquidity, every swap
   variant incl. fee-on-transfer), all `pairFor`-dependent, and passes — integration proof the
   renamed core+periphery interoperate correctly.

> **Honest limitation:** a byte-for-byte diff against the official Uniswap V2 GitHub source needs
> network access to fetch the reference (unavailable in this offline run). The checks above verify
> the security-critical *invariants and the init hash directly*, which is the property that matters
> for funds; a full upstream textual diff is a recommended additional pre-mainnet step.

### Mythril (symbolic execution, 2026-06-08)

`myth analyze` on the flattened fund-handling / DEX contracts (local solc 0.8.30,
per-contract execution timeout): **`GembaOnRamp` → "No issues were detected."**
`GembaNativePool` and `GembaTicketing` runs follow.
