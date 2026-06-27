# GembaBlockchain — the public testnet faucet (`GembaFaucet`)

> **Single source of truth for the public testnet faucet.** Updated 2026-06-27 after the
> faucet consolidation. If the faucet address or behaviour changes, **update this file in
> the same change**.

## TL;DR

| | |
|---|---|
| **Main system faucet** | **`GembaFaucet` @ `0x0147581e2351dD182edD651DFEfD955CB353f8aA`** |
| Network | `gemba-testnet-1` (EVM chainId **821207**) |
| Verified source | https://testnet.gembascan.io/address/0x0147581e2351dD182edD651DFEfD955CB353f8aA (✅ verified) |
| Dispenses | **0.1 GMB** + **10,000 of each** test stablecoin (USDT/USDC/EURC), per wallet, **24h cooldown per asset** |
| Owner | founder/ops EOA `0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC` (Ownable2Step) |
| Source in repo | `contracts/src/faucet/GembaFaucet.sol` · tests `contracts/test/faucet/GembaFaucet.t.sol` |

**One faucet holds everything.** Before 2026-06-27 the faucet was scattered across several
contracts (a Cosmos-module reserve, a governance drip faucet, a dead pre-regenesis address,
plus per-dApp copies). It is now **one contract** that dispenses both native GMB and the test
stablecoins, and **every dApp + the gembachain.io faucet page points to it**. The only
exception is **EduChain**, which keeps its own separate GMB-only faucet (whitelist-gated —
only whitelisted users may draw there).

## What the faucet does

`GembaFaucet` (solc 0.8.27, OZ v5; `ReentrancyGuard` + `Pausable` + `Ownable2Step`):

- **`claimGMB()`** — sends `gmbDripAmount` (**0.1 GMB**) to the caller. Per-wallet **24h
  cooldown** (`lastGmbClaim`) **plus a global rolling-24h cap** (`gmbDailyCap`): no matter how
  many addresses a sybil controls, the faucet dispenses at most `gmbDailyCap` GMB per day, so
  the finite native reserve can never be drained. Reverts `CooldownActive` / `DailyCapReached`
  / `FaucetEmpty`.
- **`claimToken(token)`** — **mints** `dripAmount` (**10,000**, 6-dec) of a supported test
  stablecoin to the caller. The faucet is a **minter** on the test stablecoins, so it never
  custodies a token balance and can't "run dry" on stablecoins. Per-wallet, per-token 24h
  cooldown. Reverts `TokenNotSupported` / `CooldownActive`. (Test stablecoins are valueless,
  so they intentionally have **no** global daily cap — only the finite GMB reserve does.)
- **Views:** `gmbAvailableAt(user)`, `tokenAvailableAt(user,token)` (next-claim timestamp, 0 =
  now), `gmbRemainingToday()`, `supportedTokens()`.
- **Owner-only (founder EOA, Ownable2Step):** `setGmbDrip`, `setGmbDailyCap`, `configureToken`,
  `pause`/`unpause`, `withdrawGMB`, `recoverToken`. The faucet's GMB reserve is funded by
  sending GMB to its `receive()` (emits `GmbFunded`).

### Funding status (2026-06-27)
- GMB reserve: **10,000 GMB** (topped up from the founder). 0.1/claim ⇒ ~100,000 claims; the
  daily cap bounds the per-day outflow.
- Stablecoins: **minted on demand** (no pre-funding needed). The faucet holds minter rights on
  USDT `0xF616…1666`, USDC `0xc9af…50CF`, EURC `0x7Ff4…044e`.

## Who uses it

| Surface | Faucet |
|---|---|
| gembachain.io (landing faucet block) | `0x0147…` (GMB + 3 stablecoins) |
| GembaWin (`win.gembait.com/…/faucet`) | `0x0147…` |
| GembaEscrow (`escrow.gembait.com/…/faucet`) | `0x0147…` |
| **EduChain** | **own** GMB-only whitelist faucet `0x6056Cb44…0D47` (separate by design) |
| GembaTicket / GembaPass | no faucet (relayer-gas / custodial models) |

## Retired / dormant faucets (do not reuse)

- `0x2baE94C0…9584` — **dead** pre-regenesis address (no code on `gemba-testnet-1`). The old
  landing/GembaWin pointed here; all references repointed to `0x0147…`. Do not use.
- `0x0D16a7a4…74AB` — `GembaDripFaucet`, a **governance-owned** (Timelock) GMB-only reserve
  holding 10,000 GMB. No dApp links to it anymore. Its balance can **only** move via
  Governor+Timelock (CLAUDE.md §3.6 — reserves never leave except via governance; it cannot be
  key-swept). There is currently **no voting base** (vote supply = 0), so it sits dormant; the
  combo faucet was funded from the founder instead.
- `0x9406B634…4F56` — `Faucet.sol` EVM reserve mirror (0 GMB by design; the 30M lives in the
  Cosmos module — see below).

## The 30M public/municipal reserve (separate from this faucet)

The **30,000,000 GMB** Public/Municipal Reserve is **not** this faucet — it lives in the
**Cosmos `faucet` module account** `cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d` (a keyless
module account; receives the 40% fee split + slash redirects). Moving it to the EVM treasury
is the documented Cosmos→EVM "faucet seam" (a governance task — `docs/tokenomics-pending.md`).
The testnet drip faucet above is a small, separate convenience faucet for trying the network.

## Security audit (2026-06-27)

Full adversarial review — **secure by default, fail loud** (CLAUDE.md §11). Verdict: **no
exploitable findings.**

**Design defences:**
- **Reentrancy:** `nonReentrant` on every claim + value-moving owner function, *and* strict
  **checks-effects-interactions** — the cooldown + the daily-cap counter are written **before**
  any external call (native send / token mint). Double-protected.
- **Sybil / drain:** the global rolling-24h `gmbDailyCap` bounds total GMB outflow regardless
  of address count; the per-wallet cooldown bounds each address.
- **Front-running:** harmless — each address claims for itself under its own cooldown; the only
  griefing vector is exhausting the *daily cap* (a bounded, by-design limit that protects the
  reserve), never theft of another user's drip or the reserve.
- **Access control:** `Ownable2Step` (no single-step ownership stranding); all config/recovery
  is `onlyOwner`. **Pausable** guardian can halt claims.
- Native sends via OZ `Address.sendValue`; ERC-20 recovery via `SafeERC20`; custom errors with
  zero-address/zero-amount/bounds checks; no unbounded loops.

**Tests — `contracts/test/faucet/GembaFaucet.t.sol` (23 tests, all pass):** happy-path GMB +
token claims; cooldown cannot be bypassed by retry; **reentrancy attacker contracts** for both
`claimGMB` (re-enters from `receive()`) and `claimToken` (hostile token whose `mint()`
re-enters) — both **defeated**; non-reentrant contract recipients still claim fine; rejecting
recipients only revert themselves; **global daily cap bounds a sybil swarm** + resets after the
window; **front-running per-address isolation**; empty-reserve revert; full **access-control**
matrix (every owner fn rejects non-owners); **pause** blocks/unblocks claims; Ownable2Step
transfer; and a **fuzz** invariant that a claim never pays more than the configured drip.

**Static analysis:** Slither — clean (only informational detectors: `block.timestamp` use for
the cooldown, the `last == 0` "never-claimed" sentinel, and an OZ pragma-range note — none are
vulnerabilities).

**Live verification (2026-06-27):** a fresh wallet successfully claimed 0.1 GMB and 10,000 USDT
from `0x0147…` on the live `gemba-testnet-1`, with the cooldown correctly set afterwards.

To re-run: `cd contracts && forge test --match-path 'test/faucet/GembaFaucet.t.sol' -vv`.
