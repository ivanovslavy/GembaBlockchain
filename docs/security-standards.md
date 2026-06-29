# GembaBlockchain — Solidity Security Coding Standards

> **Mandatory for every Solidity contract in this repository, from now on.**
> New contracts must comply before merge; existing contracts are held to the same
> bar (see the retroactive pass below). Referenced by `CLAUDE.md` §0. The guiding
> principle is **secure by default, not by exception** and **fail loud, never
> silent**.

## 1. Reentrancy

- Apply the **checks-effects-interactions (CEI)** pattern everywhere: validate
  inputs, then mutate state, then make external calls / send value — in that order.
- Put a **`nonReentrant` guard** on every function that makes an external call,
  sends value, or can receive incoming calls/value where re-entry is conceivable.
- Where CEI alone is sufficient and a guard is omitted, **document why** in a
  comment. Where there is the slightest doubt, **add the guard.** Default protected.
- External calls go last; never trust the callee. Prefer pull-over-push where it
  meaningfully reduces surface.

## 2. Events

- **Emit an event for every function that changes state or moves value.** No state
  change without a corresponding event — for transparency (audit/explorer) and
  off-chain indexing.
- **Index** the fields that matter for filtering: addresses, token IDs, and other
  identifiers (`indexed`).

## 3. Error handling & input validation

- Use **custom errors**, not `require` with strings (cheaper, clearer).
- **Explicitly `revert` on every invalid input.** Validate **all external inputs at
  the start of the function**: zero-address checks, zero-amount checks where
  applicable, range/bounds checks.
- No silent no-ops on meaningless input — **fail loud.**

## 4. Highest-security practices

- **Explicit access control** on every sensitive (state-/value-changing,
  privileged) function — `onlyOwner`/role checks/custom guards, never implicit.
- **Safe external calls:** check return values, revert on failure, and bound gas /
  effects of the callee. Sending native value uses `call{value:}` with a checked
  success and a `nonReentrant` guard.
- **No silent failures:** every failure path reverts with a custom error. Never
  swallow a failed call or return a misleading success.

## 5. Inherited-library exception

Contracts that are thin subclasses of **audited OpenZeppelin** code (e.g.
`TimelockController`, `Governor`, `ERC2771Forwarder`, `ERC20Votes`) inherit OZ's
reentrancy/event/error handling. Our subclasses must still apply these standards to
**any code we add** (overrides, new functions), and the reliance on OZ must be
**explicit in a comment**.

---

## Retroactive pass — Phase 3 & 4 (status)

Every contract was reviewed against §1–§4. Changes are recorded in
`contracts/SECURITY.md` and covered by tests (including reentrancy-attack tests for
every function that makes an external value call). Summary:

| Contract | Reentrancy | Events | Custom errors + validation | Notes |
|---|---|---|---|---|
| `GembaVotes` | CEI + `nonReentrant` on `withdrawTo` | ✓ | + zero-amount checks | native wrap/unwrap |
| `BaseReserve`/reserves | CEI + `nonReentrant` on `release`/`grant` | ✓ | + zero-amount checks | UUPS, native holds |
| `PublicReserve` | inherits BaseReserve guards | ✓ | + zero-amount on grant | capped grants |
| `EmergencyPause` | + `nonReentrant` on `confirm`; CEI (round advanced pre-call) | ✓ | + target zero-check | external `pause()` call |
| `GembaGovernor` | OZ + view-only override | OZ | constructor range check | OZ Governor |
| `GembaTimelock` | OZ (`TimelockController`) | OZ | OZ | no custom code |
| `GembaForwarder` | OZ (`ERC2771Forwarder`) | OZ | OZ | no custom code |
| `WorkplaceCheckIn` | no external call / no value | ✓ (indexed) | no external input | OZ `ERC2771Context` |
