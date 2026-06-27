# GmbCollector — Self-Audit

**Contract:** `GmbCollector.sol` · **Author:** GEMBA IT · **Audit date:** 2026-06-27 · **Status:** no exploitable findings.

This is an internal (self) security review of the minimal native-GMB payment collector used by
GembaPay on GembaBlockchain. It is not a substitute for an independent third-party audit before
high-value mainnet use, but it documents the design, the full threat model, and the testing that
backs the "no exploitable findings" conclusion.

## 1. Scope

| | |
|---|---|
| File | `contracts/GmbCollector.sol` (Solidity 0.8.24, OpenZeppelin v5) |
| Testnet deployment | `0x72F771d2CaC82Dd807435b03D3a216006413614c` — `gemba-testnet-1`, EVM chainId 821207 (verified) |
| Compiler / settings | solc 0.8.24, optimizer 200 runs, evm `cancun`, bytecodeHash ipfs |
| Inherits | `Ownable2Step`, `Pausable`, `ReentrancyGuard`, uses `Address.sendValue` |

## 2. What it does (and deliberately does NOT do)

A customer settles a GembaPay order by calling `pay(orderId)` and sending native **GMB**. The
contract forwards the GMB to `recipient` and emits `PaymentProcessed(... eurCents, orderId ...)`
(the same event shape as `GembaPayEuro`, so the existing GembaPay event-listener consumes it by
only adding the GembaBlockchain network).

**Single responsibility: an `orderId` can be paid only once.** That is the only reason to use a
contract instead of a plain wallet transfer — it binds a payment to an order in an on-chain event,
and guarantees no duplicate settlement.

Deliberately minimal — it does **not**: hold custody (forwards every wei), handle ERC-20/721/1155,
use a price oracle (1 GMB = €1 by design), charge a fee, or accept anonymous deposits.

## 3. Public interface

| Function | Access | Notes |
|---|---|---|
| `pay(string orderId) payable` | anyone | the payment entry point; `whenNotPaused` + `nonReentrant` |
| `isOrderPaid(string) view` | anyone | order already settled? |
| `recipient() / paymentCount() / paidOrders(bytes32) / VERSION()` | anyone | views |
| `setRecipient(address)` | **owner** | change payout address (Ownable2Step) |
| `pause() / unpause()` | **owner** | freeze/resume payments |
| `receive() / fallback()` | — | **revert** (`DirectPaymentNotAllowed`) |
| `onERC721Received / onERC1155Received / onERC1155BatchReceived` | — | **revert** (`TokensNotAccepted`) |

## 4. Threat model & mitigations

| # | Threat | Mitigation | Verified |
|---|---|---|---|
| T1 | **Double payment** (the core risk) — same order settled twice | `paidOrders[keccak(orderId)]` set **before** the forward (CEI); the EVM serialises txs, so a concurrent race resolves to exactly one success | Foundry `test_DoublePay_reverts`; **live race attack (1/2 mined)** |
| T2 | **Reentrancy** via the native forward | `nonReentrant` + CEI (order marked paid before `sendValue`); a reentrant call with the same order hits `OrderAlreadyPaid`, a different one hits the guard | Foundry `test_Reentrancy_cannotDouble`; Slither |
| T3 | **Payout hijack** — attacker redirects funds | `setRecipient` is `onlyOwner`; `Ownable2Step` prevents accidental ownership loss | Foundry + **live non-owner attack rejected** |
| T4 | **Stuck funds / accidental deposits** | `receive`/`fallback` revert; the contract custodies nothing (forwards in the same tx) | Foundry `test_DirectSend_reverts`; live; integrity check `balance == 0` |
| T5 | **Token traps** (NFTs/ERC-20) | ERC-721/1155 receiver hooks revert; no ERC-20 logic (a raw ERC-20 push is inert — no contract can block a push, but nothing here can act on it) | Foundry `test_Rejects_NFTs` |
| T6 | **Price manipulation / oracle attack** | none — price is fixed 1 GMB = €1 in code, no oracle, no external price dependency | by design |
| T7 | **Arithmetic over/underflow** | Solidity 0.8.x checked arithmetic (reverts); only `amount/1e16` and `++paymentCount` — neither is exploitable | solc 0.8.24; Mythril SWC-101 triaged as false positive |
| T8 | **Malformed input** (0 value, empty orderId) | explicit `ZeroAmount` / `EmptyOrderId` reverts | Foundry + live |
| T9 | **DoS** | `pay` is O(1); the forward target is an owner-set address; a hostile recipient can only break its own payments (it is trusted/owner-set), never double-spend or drain | Foundry reentrancy test |

## 5. Testing

- **Slither** — clean (only an informational OZ pragma-range note).
- **Foundry adversarial suite** (`test/onramp/GmbCollector.t.sol`) — **12/12 pass**: double-pay revert, reentrancy-can't-double (malicious recipient), reject direct/NFTs, access control, pause, Ownable2Step, fuzz.
- **Mythril** (bytecode mode — the sandbox blocks solc download) — only standard 0.8.x bytecode false positives (SWC-101 checked-arithmetic "underflow"; SWC-110 our intended `revert()`s read as assertions). No real issue.
- **Live brutal attack harness** (`security/collector-attack.mjs`) vs the deployed contract — **7/7 DEFENDED**: sequential **and concurrent-race** double-pay, direct send, non-owner `setRecipient` hijack, malformed inputs, and a custody-integrity check (contract holds 0).

## 6. Accepted limitations (by design)

- **Trusted owner.** The owner can `pause` and change `recipient`. Funds are never custodied, so the owner cannot steal in-flight payments, but on mainnet the owner key should be a hardware-key / multisig.
- **ERC-20 push.** No contract can prevent a raw `ERC20.transfer` to an address; such tokens would be inert/stuck. There is intentionally no token-handling surface (and no recovery function, to keep the attack surface minimal).
- **`recipient` must accept native GMB.** An EOA (the default `0x8eB8Bf…`) always does; if ever set to a contract, it must accept value.

## 7. Conclusion

`GmbCollector` is a deliberately minimal, single-purpose contract. Across Slither, a 12-test
adversarial Foundry suite, Mythril, and a live concurrent-attack harness, **no exploitable finding
was identified**. Its one guarantee — no duplicate payment — holds under sequential and race
conditions on-chain. For high-value mainnet use, an independent audit + a multisig owner are
recommended.
