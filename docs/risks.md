# GembaBlockchain — Risk & Decision Register

> **Format:** Architecture Decision Records (ADR). Each entry is a *conscious*
> trade-off, not an oversight. The canonical short list lives in `CLAUDE.md`
> §16; this file is the long form. If a decision changes, **update `CLAUDE.md`
> §16 first**, then this file, then the code.
>
> **Template per entry:** Status · Context · Decision · Consequences.
> **Status values:** `Accepted` (we live with it), `Accepted — gated`
> (accepted but blocks a later milestone until resolved), `Mitigated`
> (residual risk reduced by design), `Open` (needs a future decision).

---

## ADR-001 — Free transferability implies a market price we do not control

- **Status:** Accepted — gated (see ADR-009 / MiCA)
- **Context:** GMB is freely transferable on a permissionless chain. We do not
  run a DEX and do not redeem GMB for fiat, but nothing stops a third party from
  creating a liquidity pool. A market price may emerge that we neither set nor
  control. This is the price of real decentralization: a transfer allowlist
  would re-centralize the chain (rejected — see §16 of `CLAUDE.md`).
- **Decision:** Accept free transferability as a hard design property. Do **not**
  add a transfer allowlist, redemption desk, or operated market. Be honest in all
  docs that GMB is a *freely transferable utility coin*, not a closed-loop
  voucher.
- **Consequences:** A secondary market price can appear and move independently of
  any "intended" value. This **weakens the MiCA "limited-network / utility"
  argument** — GMB looks closer to a genuine crypto-asset than to a closed
  voucher. Classification **must** be confirmed with a Bulgarian fintech lawyer
  before any public sale (ADR-009).

---

## ADR-002 — Small early voting base

- **Status:** Mitigated
- **Context:** At launch ~90% of GMB sits in non-voting reserves and the founder
  is excluded from voting. The active voting base (staked circulating GMB) is
  therefore small early on, which would normally let a tiny group push proposals
  through unseen.
- **Decision:** Compensate **without a trusted human steward**, using only code:
  high quorum + supermajority (66–75%) + long timelock on treasury and upgrade
  proposals; hard rules baked into genesis; faucet grants by **formula**
  (automatic), so no authority is needed for funds to reach institutions.
- **Consequences:** Early governance is deliberately slow and hard to move. As
  GMB distributes the voting base grows and the bar can be relaxed by governance.
  No emergency human override exists for ordinary governance (only the pause-only
  multisig, ADR-004).

---

## ADR-003 — Liquidity reserve sets the initial price, then the market moves

- **Status:** Accepted
- **Context:** If/when governance decides to seed a liquidity pool, the initial
  pool ratio mechanically sets the *starting* price. The 10% liquidity reserve
  could in principle be used to lean against the market.
- **Decision:** The liquidity reserve exists to **support depth, not to dictate
  price**. It is a modest (10%), non-voting, governance + timelock-gated bucket.
  A 50% mega-reserve was considered and rejected as a systemic point of control.
- **Consequences:** We influence the *starting* price once and can support depth
  thereafter, but we do not and cannot peg the price. After seeding, price is
  market-driven.

---

## ADR-004 — Emergency multisig is residual centralization

- **Status:** Mitigated
- **Context:** An emergency guardian can halt a contract during an incident. Any
  such key is, by definition, a point of centralization.
- **Decision:** The emergency multisig can **only pause, never move or drain
  funds**. Its signers are **elected by governance and replaceable by
  governance**. This is bounded, revocable power — not a steward.
- **Consequences:** A residual trust assumption remains (the signer set could
  pause maliciously to grief the chain), but it cannot steal funds and can be
  rotated out. Accepted as the minimum viable incident response.

---

## ADR-005 — You cannot control already-distributed GMB

- **Status:** Accepted
- **Context:** Once GMB leaves a reserve into a recipient's wallet, free
  transferability means we cannot constrain what they do with it (e.g., a
  municipality handing GMB to ineligible parties).
- **Decision:** Put control on the **faucet's inflow** — the rate and condition
  of grants — never on tokens after they leave: formula-based grants + vesting +
  per-grant cap with governance approval above the cap. *Govern the tap, not the
  water already poured.*
- **Consequences:** Misuse of already-distributed GMB is possible and is not
  protocol-preventable. Abuse is throttled at the source (vesting is
  governance-revocable if abuse is observed) and absorbed socially/legally, not
  on-chain.

---

## ADR-006 — Cosmos EVM is pre-v1 (audit pending)

- **Status:** Accepted — gated
- **Context:** `github.com/cosmos/evm` is production-used but its v1 release
  follows an external audit. Building on pre-v1 code carries upstream-change and
  unaudited-code risk.
- **Decision:** Pin a known-good version; read upstream release notes before any
  bump; **isolate our custom modules** (zero-inflation reward streamer, 60/40 fee
  split) so upstream upgrades stay clean. **Do not launch to the public** before
  the upstream audit lands and our own review is done.
- **Consequences:** Public launch is blocked on the upstream audit + our review.
  Devnet and testnet work proceed freely. Custom-module isolation costs some
  boilerplate but protects the upgrade path.

---

## ADR-007 — Censorship is not auto-slashable

- **Status:** Accepted
- **Context:** Only objectively, on-chain-provable faults can be slashed
  deterministically (double-signing/equivocation, downtime). Transaction
  censorship is **not** objectively provable on-chain.
- **Decision:** Slash only provable faults. Handle censorship at the
  **governance / social layer**, never via automatic slashing. Never promise
  automatic punishment for anything not deterministically provable on-chain.
- **Consequences:** A validator could selectively censor without triggering an
  automatic penalty. Mitigated by a large active set (a censored tx routes around
  a censoring validator), governance jailing, and social accountability.

---

## ADR-008 — Long-term security budget after the validator reserve is exhausted

- **Status:** Open → resolving (combination (a)+(b) below)
- **Context — the contradiction, stated plainly:**
  Two invariants collide with one design choice:
  1. *Fixed supply, zero inflation, no minting after genesis* (§3, §4.2).
  2. Validator rewards are funded from a **pre-minted 20M reserve for ~10 years**;
     after the reserve is depleted, *"validators live on fees"* (§4.3, §5.4, §5.5).
  3. Fees were described as *"negligible per-tx cost."*

  In Proof-of-Stake the **security budget** is the recurring value paid to
  validators that keeps bonded stake high; the cost to attack the chain scales
  with the *value of bonded stake*, which in turn depends on validators having a
  reason to keep capital bonded (rewards must at least cover opportunity cost +
  unbonding/slashing risk). If, after year ~10, the only reward is **negligible**
  fees and there is **no inflation lever** (the usual Cosmos dynamic-inflation
  knob is disabled), rational holders unbond, the **bonded ratio falls**, and the
  **cost-to-attack collapses**. This is the Bitcoin security-budget problem ported
  onto a fixed-supply PoS chain. Calling fees "negligible" *forever* is therefore
  inconsistent with "secure forever."

- **Decision — combination (a) + (b):**

  **(a) Fees carry a *real* security budget, scaling with usage.**
  Reframe gas pricing from "negligible per-tx" to **"low but non-zero, scaling
  with usage."** Per-transaction cost stays cheap (good UX for a utility chain),
  but the *aggregate* security budget = `fee_per_tx × tx_volume × GMB_price` grows
  with adoption. Because GembaBlockchain's value thesis is *use*, security scales
  with the very thing that gives GMB value. Security budget is meaningful **only
  in real value** — see ADR-008a (gas price in real value).

  **(b) A *tail* reward funded by recirculated fees, never by minting.**
  When the 20M reserve is exhausted, sustain a governance-tunable **baseline
  ("tail") validator reward by recycling already-circulating GMB** — e.g. routing
  a governance-set slice of the fee-funded reserves (a portion of the faucet's 40%
  fee inflow, and/or DAO-reserve surplus) back into the `distribution` module.
  This is **recirculation, not issuance**: no new GMB is created, so the
  fixed-supply / zero-inflation invariant (§3.1) is preserved exactly. The tail
  smooths the cliff at year ~10 instead of dropping security to fee-only overnight,
  and its rate is a governance parameter that can be raised if the bonded ratio
  falls below target.

  Mechanisms (a) and (b) are complementary: (a) ties long-run security to
  adoption; (b) provides a floor that does not depend on adoption arriving on
  schedule. Both respect zero inflation.

- **Cost-to-attack vs chain value (worked, illustrative — N = 100M GMB):**
  CometBFT BFT thresholds against the *bonded* set:
  - **Liveness halt:** acquire **> 1/3** of bonded stake (can stall finality).
  - **Safety violation / forge:** acquire **≥ 2/3** of bonded stake — and that
    stake is **slashed + tombstoned** on detection, so this cost is paid *and lost*.

  Assume a mature state: circulating supply ≈ 60M GMB (the rest still in
  non-voting reserves / vesting), **bonded ratio = 60%** ⇒ bonded ≈ 36M GMB, at an
  illustrative market price `p`:

  | Attack | Stake needed | Cost at p = $1 | Notes |
  |---|---|---|---|
  | Halt liveness (>1/3) | > 12M GMB | > $12M | before market slippage; attacker's stake slashable for equivocation |
  | Forge / double-finalize (≥2/3) | ≥ 24M GMB | ≥ $24M | stake is **lost** to slashing + tombstone on detection |

  Real cost is higher: buying 12–24M GMB on a thin market moves the price up
  (slippage), and bought stake is itself at risk. **Target: keep cost-to-attack a
  large multiple (≥ 3×) of the economic value secured** (TVL + value of access
  rights/tickets in flight + fee throughput).

- **Bonded ratio to maintain:**
  - **Target ~66%**, **floor ~50%**, **hard red line ~33%** — below 1/3 bonded,
    halting the chain becomes cheap.
  - With inflation disabled, Cosmos's usual *dynamic-inflation* lever that nudges
    the bonded ratio toward a goal **does not exist here**. Defending the bonded
    ratio is therefore an **explicit governance responsibility**, using the two
    levers above: the tail-reward rate (b) and the gas-price floor (a). Governance
    must monitor bonded ratio as a first-class health metric.

- **Consequences:**
  - "Negligible fees" is **retired** from the spec in favour of "low but non-zero,
    scaling with usage" (`CLAUDE.md` §1, §13 Phase 4, §16.8).
  - A new **tail-reward mechanism** (recirculation-only) is added to the custom
    chain modules' scope; it must be implemented and tested before the validator
    reserve approaches depletion, not at year 10.
  - Security now has an explicit, monitorable KPI (bonded ratio) and two
    governance levers, with zero inflation preserved throughout.

### ADR-008a — Gas price must be denominated in *real value*

- **Status:** Accepted (corollary of ADR-008)
- **Context:** The security budget in ADR-008 is `fee_per_tx × tx_volume ×
  GMB_price`. If GMB had no real value, the security budget would be ~0 regardless
  of fee settings; "non-zero gas" only secures the chain if a unit of gas is worth
  something real.
- **Decision:** Treat gas price as a value in **real terms**, not just a nominal
  GMB amount. Fees are kept low *per transaction* but never zero, and EIP-1559
  parameters are tuned so that aggregate fee value tracks usage. Record explicitly
  that the chain's security depends on GMB retaining real value through *use*
  (ADR-001 acknowledges a market price may also emerge).
- **Consequences:** Security and adoption are coupled by design — acceptable and
  intended for a utility chain. A prolonged collapse in GMB's real value would
  weaken security; the tail reward (ADR-008 (b)) is the recirculation-funded
  cushion against that, but it is a floor, not a guarantee.

### ADR-008b — Two distinct electorates (consensus vs treasury)

- **Status:** Accepted (recorded to prevent double-counting of power)
- **Context:** Power must not concentrate by being counted twice. The security
  budget pays validators; governance over money must not silently inherit that
  weight.
- **Decision:** Maintain **two separate electorates**, never merged:
  1. **Consensus / chain electorate** — voting power = **bonded (staked) GMB**, via
     the Cosmos `gov` module. Secures the chain, earns the security budget, and
     votes on consensus/staking/fee parameters. Reserves are not staked ⇒ do not
     vote; the founder does not stake-to-vote ⇒ excluded.
  2. **Treasury / contract electorate** — **1 GMB = 1 vote**, via the Solidity
     `Governor` + `Timelock`, with reserve-holding contracts explicitly excluded
     from `getVotes`. Controls the reserve/treasury contracts.

  Validating earns the *security budget* but grants **no extra treasury-governance
  weight**, and holding GMB for treasury votes grants no consensus power — so
  nobody becomes a "double plutocrat" (§5.7).
- **Consequences:** Two ledgers of power to reason about, but neither can capture
  the other for free. This separation is a security property: an attacker who buys
  consensus stake does not thereby gain control of the treasury, and vice versa.

---

## ADR-009 — MiCA classification is an explicit launch blocker before public sale

- **Status:** Accepted — gated (**hard blocker**)
- **Context:** GMB is freely transferable (ADR-001), which weakens any
  "limited-network" or pure-utility exemption argument under the EU **Markets in
  Crypto-Assets (MiCA)** regulation. Selling GMB to the public in the EU without
  the correct classification (utility token vs asset-referenced/e-money token vs
  other crypto-asset) and any required white paper / authorisation could be an
  unauthorised offering. The founder is based in Bulgaria (EU).
- **Decision:** Treat MiCA classification as an **explicit, hard launch blocker**:
  - No **public sale** of GMB and no fiat-adjacent on-ramp marketing until GMB's
    MiCA classification is confirmed in writing by a **Bulgarian fintech lawyer**
    and any resulting obligations (white paper, disclosures, registration) are met.
  - Devnet, testnet, internal/closed grants to institutions by formula, and
    technical development are **not** blocked by this gate.
  - The on-ramp (Phase 6, GembaPay stablecoin → GMB) and any public sale flow are
    the milestones this blocker guards.
- **Consequences:** Phases 0–5 (and 7–8 technical work) proceed; the **public
  sale / open on-ramp does not ship** until legal sign-off. This is a deliberate
  schedule dependency, documented so it is not "discovered" late. Cross-reference:
  ADR-001 (why the exemption is weak), ADR-006 (the other hard pre-public-launch
  gate — upstream audit).

---

## ADR-010 — The chain is *de-facto centralized at genesis* (and how we exit it)

- **Status:** Accepted (transitional, with an explicit exit path)
- **Context — stated honestly:** Decentralization at block 0 is a *goal*, not an
  initial fact. At genesis the chain is **de-facto centralized**:
  - The **minimum 4 genesis validators run on the founder's 5 servers** (§5.3), so
    one operator effectively controls the entire active set initially.
  - **~90% of GMB is in reserves** and the founder holds 5%; the staked,
    circulating voting base is small (ADR-002), so the consensus electorate is
    thin and founder-adjacent in practice even though the founder is *formally*
    excluded from voting.
  - One team holds operational knowledge, keys, and infrastructure.

  Claiming "decentralized" while shipping this without disclosure would be
  dishonest and a reputational/legal risk.
- **Decision:** State the genesis condition plainly in public docs: **"permissionless
  by rule, centralized in practice at launch, decentralizing over time."** Bind
  ourselves to *mechanisms*, not promises, that make the centralization
  **transitional and irreversible-toward-openness**:
  - **Permissionless entry from block 0** — the active set opens to any staker
    under identical rules immediately; genesis validators have **no permanent
    privilege** and can be out-ranked/replaced (§5.2, §5.3).
  - **No protocol lever to re-close** entry: no allowlist, no KYC gate, no
    privileged/permanent validator status (§3.2, §3.3) — these are rejected in §16
    and must not be reintroduced.
  - **Distribution over time** widens both electorates: faucet grants by formula,
    client/circulation pool seeding liveness, founder stock recirculating via
    sales — all moving GMB out of founder-adjacent hands.
  - **Publish decentralization KPIs** and track them: number of independent
    validator operators, Nakamoto coefficient (min validators to halt), share of
    stake controlled by the top operator, bonded ratio (ties to ADR-008), and the
    founder's share of circulating GMB.
- **Consequences:** We carry honest "centralized-at-genesis" language in public
  materials, which is reputationally safer than overclaiming and is defensible
  because the *rules* are already open. The risk is that decentralization stalls
  if distribution is slow; the KPIs above make stalling visible, and the rejected
  re-centralization levers stay rejected so the only direction the design permits
  is *more* open, not less.

---

## Cross-reference: hard launch blockers (must clear before public launch)

| ADR | Blocker | Clears when |
|---|---|---|
| ADR-006 | Cosmos EVM pre-v1 / unaudited | Upstream audit lands **and** our own review is done |
| ADR-009 | MiCA classification | Written sign-off from a Bulgarian fintech lawyer + any required obligations met |
| ADR-008 | Long-term security budget | Tail-reward (recirculation) mechanism implemented + tested; bonded-ratio monitoring in place |
