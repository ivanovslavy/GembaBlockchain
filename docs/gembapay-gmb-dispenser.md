# GembaPay GMB Dispenser

> Secure on-chain GMB vault that GembaPay uses to deliver GMB to buyers after a payment is
> settled off-chain (fiat **or** crypto — GembaPay decides). Deployed + verified 2026-06-27.

## Address & key

| | |
|---|---|
| **Contract (`GembaPayDispenser`)** | **`0x0EB298466F862E548d2416a75d3D108E503bD2Cf`** ✅ verified on gembascan |
| Network | `gemba-testnet-1` (EVM chainId 821207) |
| Owner / GembaPay signer | `0xAB9503dBC3FE22C16Ff94B9C76D7f57A6020E96a` (Ownable2Step) |
| GMB held | **100,000 GMB** (funded from the founder via the owner wallet) |
| Source | `contracts/src/onramp/GembaPayDispenser.sol` · tests `contracts/test/onramp/GembaPayDispenser.t.sol` |
| Owner private key | **NOT in git** (repo is public, CLAUDE.md §0.3). Stored in `wallet-backup/gembapay-dispenser-owner.md` (gitignored) and in the GembaPay backend `.env` on .162 (`/gembapay.com/backend/.env`, gitignored). |

> Superseded: an earlier deploy at `0x8FF0207e5652C2399C8271526AaDa88F3fB2505C` (solc 0.8.27)
> was drained to 0 and abandoned because forge's svm solc-0.8.27 build wouldn't verify on the
> Blockscout instance. Re-deployed with **solc 0.8.24 / evm cancun** (the toolchain that
> verified all other contracts) → verified. Do not use the 0x8FF0 address.

## What it does (exactly)

A payment-agnostic, owner-controlled GMB vault. GembaPay receives a payment (fiat or crypto,
settled in GembaPay's own backend); the backend then signs a tx with the owner key and the
contract sends GMB from its reserve to the buyer's wallet. The contract itself knows nothing
about payments — it is just a secure GMB safe only the owner can move funds out of.

| Function | Who | Effect |
|---|---|---|
| `fund()` payable | owner | top up the GMB reserve (the **only** way GMB enters; bare sends revert) |
| `dispense(to, amount, ref)` | owner | send `amount` GMB to a buyer; `ref` = opaque off-chain payment id (on-chain audit). Emits `Dispensed`. |
| `withdraw(to, amount)` | owner | recover GMB (refill/rotate/wind-down). Emits `Withdrawn`. |
| `pause()` / `unpause()` | owner | freeze/unfreeze dispensing (withdraw still works while paused) |
| `balance()` / `dispensable()` | anyone | read reserve (dispensable = 0 while paused) |

**How GembaPay should integrate (no contract change needed):** on a confirmed GMB order, call
`dispense(buyerWallet, gmbAmount, orderRef)` from the owner key (in `/gembapay.com/backend/.env`
as `GEMBA_DISPENSER_OWNER_PK`, with `GEMBA_DISPENSER_ADDRESS` + `GEMBA_RPC_URL` + `GEMBA_CHAIN_ID`).
The `Dispensed(to, amount, ref)` event is also what the blockchain notifier watches for
"GMB sold" alerts (see `docs/notifications-implementation-plan.md`).

## Security

Secure by default, fail loud (CLAUDE.md §11):
- **Owner is the only mover of funds** (`dispense` + `withdraw` are `onlyOwner`); Ownable2Step.
- **ReentrancyGuard** on every value path; **Pausable**; native sends via OZ `Address.sendValue`.
- **Rejects everything it should not hold:** anonymous native deposits revert (`receive`/`fallback`),
  ERC-721/1155 safe transfers revert (receiver hooks revert). Funding only via owner-only `fund()`.
- Custom errors + zero-addr/zero-amount/insufficient-balance checks; an event on every state change.

**Audit:** 19 adversarial Foundry tests pass — incl. a malicious reentrant buyer that cannot
double-spend, direct-deposit rejection, ERC-721/1155 rejection, full access-control matrix,
pause, Ownable2Step, and a fuzz invariant (a dispense never exceeds the reserve). Slither clean.
**Live E2E verified** on `gemba-testnet-1`: dispense pays the buyer, direct sends revert, the
reserve is conserved.

Re-run tests: `cd contracts && forge test --match-path 'test/onramp/GembaPayDispenser.t.sol' -vv`
