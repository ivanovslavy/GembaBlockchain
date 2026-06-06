# Phase 3 — Treasury & Governance Contract Principles

> Binding principles for the Phase 3 Solidity contracts (Governor, Timelock,
> Faucet, FoundationTreasury, DAOReserve, ContingencyReserve [renamed from
> LiquidityReserve — no liquidity by design, `CLAUDE.md` §8], EmergencyPause). Read
> together with `CLAUDE.md` §7, §9 and `docs/risks.md`. Recorded **before** writing
> the contracts on purpose — these are design decisions, not afterthoughts.

## 1. Tests first, funding last (HARD RULE)

No contract receives tokens before it is tested. In order:

1. **Unit tests** (Foundry) for every state-changing path and access-control check.
2. **Invariant / fuzz tests** (Foundry `invariant_`/`testFuzz_`) for the money
   properties: e.g. reserves only leave via Governor+Timelock; the faucet never
   pays above its per-grant cap without governance; sum of balances is conserved;
   no path lets an EOA move reserve funds.
3. **Static analysis** (Slither) clean, with every finding triaged in the PR.
4. **Local devnet**, then **public testnet** exercise of the real flows.
5. **Only then** funding — and even then, in stages.

**Genesis-funded reserve contracts** (Faucet, Foundation, DAO, Contingency) hold real
supply from block 0, so they additionally **require an external security audit
before mainnet genesis** (consistent with `docs/risks.md` ADR-006: no public
launch before audit). A bug in a pre-funded reserve is not patchable by "deploy a
fix" — the funds are already there. Tests + audit are the only gate.

> One-line invariant to keep in view: **tokens never precede tests.** If a contract
> is about to hold value, its tests (and, for reserves, its audit) must already be
> green.

## 2. Upgradeability & control (no EOA ever holds power)

- All treasury/reserve contracts are **upgradeable via a proxy** (e.g.
  transparent/UUPS), because governance must be able to evolve them.
- **Upgrade authority is the Governor + Timelock — and nothing else.** No EOA, no
  multisig, no deployer key may upgrade or migrate a treasury contract. The
  deployer must renounce/transfer admin to the Timelock as part of deployment, and
  a test must assert the proxy admin/owner is the Timelock (not an EOA).
- **Pausing** is the only fast path: the `EmergencyPause` multisig may **pause** a
  contract during an incident, **never** move or drain funds, and its signers are
  elected and replaceable by governance (`CLAUDE.md` §7, `docs/risks.md` ADR-004).
- This preserves the §3.6 invariant: **no unilateral control of reserves.** Funds
  leave only via propose → vote → Timelock delay → anyone executes.

## 3. The Cosmos ↔ EVM seam (think before writing the Faucet)

Phase 2's `x/feesplit` is a **Cosmos Go module** that sends 40% of fees to a
module account named `faucet`. In Phase 3 the faucet becomes a **Solidity
contract** on the EVM. These live in two different layers, and the hand-off needs a
deliberate design — decide it before coding the Faucet, not after:

- **The deposit direction (Go → EVM contract).** A Go module deposits via the bank
  keeper to an **address**; an EVM contract is just an account at an address. In
  cosmos/evm the native coin has an ERC-20 representation, and the EVM and bank
  balances of an address are reconciled. So `feesplit` can keep sending GMB to the
  faucet **address** (bank-level), and the Faucet contract reads its own balance
  (native GMB / the native-precompile ERC-20) when it disburses. Options to weigh:
  1. **feesplit targets the contract's address directly** (simplest): the Go module
     sends to the EVM contract's account; the contract sees the balance via the
     native token. Verify the bank↔EVM balance reconciliation holds for a contract
     account (not just an EOA), and that sending to a contract address does not
     require the contract to implement a receive hook at the bank layer.
  2. **feesplit keeps sending to a module account; a periodic/contract-triggered
     sweep moves it into the Faucet contract.** More moving parts, but keeps the
     Go side oblivious to EVM addresses.
- **Whichever we pick, the split ratio and the faucet target stay governance
  params** (already true in `x/feesplit`), so the seam can be re-pointed without a
  chain upgrade.
- **Open questions to resolve in the Phase 3 design doc before implementation:**
  does a contract account correctly receive bank-level sends in cosmos/evm v0.7.0?
  Is the native-coin ERC-20 balance of a contract equal to its bank balance? Do we
  want the faucet's *accounting* (grants, vesting, caps) on the EVM side while the
  *inflow* is bank-level? Prototype this hand-off on devnet first.

This is the one place where the two layers of GembaBlockchain meet; getting the
interface right up front avoids a painful retrofit.

### RESOLVED (devnet prototype, `contracts/src/SeamProbe.sol`)

Prototyped on the gembad devnet before writing the real Faucet. Result:
**Variant 1 works — `feesplit` deposits directly into the Faucet contract's
address.** A bank-layer send (`gembad tx bank send`, i.e. exactly what feesplit's
`SendCoins` does) of 12,345 GMB to a deployed contract's address showed up
immediately as the contract's **native EVM balance** (`address(this).balance`),
and the contract **spent it** via a normal EVM call (`forward()` moved 5,000 GMB
out, balance 12,345 → 7,345). So in cosmos/evm v0.7.0 the native-coin bank balance
and the EVM balance of a *contract* account are the same ledger, and the contract
has full control of funds that arrived at the bank layer.

**Design decision for the Faucet:** the Faucet contract simply holds **native
GMB** at its (proxy) address; no wrapper, no sweep. `x/feesplit`'s `faucet_account`
param is pointed at the **Faucet proxy address**, and feesplit sends to that
address (a one-line change from `SendCoinsFromModuleToModule` to
`SendCoinsFromModuleToAccount` — done as part of wiring, the contract design does
not depend on it). The proxy address is stable across upgrades, so re-pointing is
never needed after launch.
