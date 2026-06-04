# contracts — Security notes & Slither triage

Static analysis: `slither . --filter-paths "lib/|test/" --exclude-dependencies`
(Slither 0.11.3). Every finding is triaged below. Per
`docs/phase3-treasury-principles.md`: **tests first, funding last** — no contract
holds tokens until tests + (for reserves) an audit are done. These contracts are
**unfunded** and **not deployed to mainnet**.

## Retroactive security pass (docs/security-standards.md)

All Phase 3 & 4 contracts were reviewed against the standards. Changes:

- **`GembaVotes`** — added `ZeroAmount` custom error; `depositFor` now validates
  `to != 0` and `msg.value != 0`; `withdrawTo` now validates `amount != 0`. CEI
  (burn before send) + `nonReentrant` documented.
- **`BaseReserve`** (and `Faucet`/`FoundationTreasury`/`DAOReserve`/`LiquidityReserve`)
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
