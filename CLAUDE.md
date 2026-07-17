# GembaBlockchain — Master Build Specification

> Single source of truth for the GembaBlockchain project. Written to be read by
> **Claude Code** as project instructions, and by humans as the design reference.
> If a design decision changes, **update this file first**, then change the code.
>
> **This is a decentralized, permissionless, public Proof-of-Stake L1.** Anyone
> with enough stake can validate; anyone can hold and send the native coin. No
> central operator can decide who participates. The founder gives technology to
> public institutions but they follow the same rules as everyone else — they get
> no special power.

> **⏭ REGENESIS PLANNED (locked 2026-06-26).** A full testnet regenesis (then mainnet) moves the
> economics to: capped validator reward `max(10, min(100, stake×1%))` GMB/day; min/max self-bond
> 1,000/10,000 at entry + **50 GMB/day** bond-increase cap; **~3s blocks** (timeout_commit 1s);
> **5 gwei** fee floor; faucet 0.1 GMB/day per-acct+per-IP; 2-tier governance (40/51 std, 51/66
> crit, 3-day period); the ~8M idle on validator accounts folded into the reward reserve; 4 genesis
> validators funded 10K each from the founder; **wallets (WA) preserved, contracts (CA) preserved
> via CREATE2**; auto-compound/auto-unjail are **off-chain scripts, not a protocol whitelist**. GMB
> stays no-inflation / no-liquidity, serving the Gemba ecosystem + any project that wants it. Authoritative
> spec: **[`docs/GembaBlockchain_Нова_Логика_Регенезис.md`](docs/GembaBlockchain_Нова_Логика_Регенезис.md)**
> (§0 locked decisions) — on conflict that doc wins for post-regenesis logic.

---

## 0. Working rules for Claude Code (read first, every session)

1. **Edit real files.** Always make changes by editing/creating files in the tree.
   Never just print code to chat.
2. **The concept must be visible in the code.** GembaBlockchain is a *fully
   transparent, permissionless, decentralized* PoS L1 whose native coin **Gemba
   (GMB)** is a utility coin inside an ecosystem (cheaper service access, workplace
   access control, tickets, perks), with the long-term goal of being run by the
   institutions and community that use it. Comments explain the *why*.
3. **Secrets only in `.env`.** Never hardcode private keys, validator/node keys,
   API keys, DB passwords, mnemonics. Never commit `.env`. A committed
   `.env.example` holds placeholders only. **This repo will be public on GitHub.**
4. **Work in stages.** Follow the phased plan (section 13). Finish and verify one
   phase before the next. Do not attempt the whole system at once.
5. **Keep this file and `/docs` current** in the same change that touches code.
6. **Small, reviewable commits** (conventional commits: `feat:`, `fix:`, `docs:`...).
7. **Do not reintroduce centralization.** No transfer allowlist, no KYC gate on
   validators, no privileged/permanent validator status, no governance "steward"
   with unilateral power, no admin key that can drain reserves. These were
   considered and **rejected** — see section 16.
8. **Preserve the hard invariants** (section 3): fixed supply, no minting after
   genesis, reserves never vote, founder never votes/validates with privilege,
   permissionless stake-only validator entry.
9. **Test before touching the real network.** Everything is built and tested on a
   **local devnet** (single-node, then multi-node) before any public launch.
10. **This stack is in active development.** Cosmos EVM is production-used but its
    v1 release follows an audit — pin a known-good version, read upstream release
    notes, and isolate our custom modules so upstream upgrades stay clean.
11. **Every Solidity contract MUST follow `docs/security-standards.md`** — secure by
    default, fail loud: CEI + `nonReentrant` on external-call/value functions; an
    event for every state change (indexed addresses/IDs); custom errors with
    zero-address/zero-amount/bounds validation at the function start; explicit
    access control on sensitive functions; checked, safe external calls. This is
    mandatory for new contracts and enforced retroactively on existing ones.
12. **Keep discoverability current.** After any change to a public web property
    (gembachain.io, swap.gembachain.io, explorer, dApps, new pages/links/products),
    **update SEO + AI metadata in the same change**: page `<meta>` (description, canonical,
    OG/Twitter with absolute images), JSON-LD structured data, `robots.txt`, and the AI
    files (`llms.txt`, `llms-full.txt`, `ai.txt`). **Always check whether `sitemap.xml`
    needs updating** (new/removed URLs, `lastmod`) and update it if so. The goal is
    professional, top-tier discoverability from search engines and AI systems.

---

## 1. Identity & core facts

| Field | Value |
|---|---|
| Network name | **GembaBlockchain** |
| Native coin | **Gemba**, ticker **GMB** (also the staking + gas coin) |
| Framework | **Cosmos SDK + Cosmos EVM module** (`github.com/cosmos/evm`), reference impl `evmd` |
| Consensus | **CometBFT** (BFT Proof-of-Stake), instant finality, no reorgs (~5 s blocks live; ~2 s is the tunable target) |
| Permissionless | Yes — anyone with stake ≥ threshold can validate; anyone can hold/send GMB |
| EVM-compatible | Full EVM: Solidity, `0x...` addresses, MetaMask, Foundry/Hardhat, ethers/viem, JSON-RPC |
| Cosmos chain-id | `gemba-1` (string) |
| EVM chainId | **821206** (EIP-155 integer; verified free on chainlist.org — 123321 was taken) |
| Account type | `eth_secp256k1`, SLIP-0044 coin type **60** (Ethereum standard → `0x` + MetaMask) |
| Block time | ~5 s live (CometBFT `timeout_commit`; ~2 s target, governance/upgrade-tunable) |
| Total supply | **fixed**, minted once at genesis, **never again** → 0% inflation |
| Gas / fees | real fees in GMB (EIP-1559); **low but non-zero, scaling with usage** — cheap per-tx, but aggregate fees are the long-run security budget (§16.8) |
| Block explorer | **Blockscout** self-hosted ("GembaScan"); optional Cosmos-side explorer (e.g. ping.pub) |
| License | code: Apache-2.0 (matches Cosmos EVM); docs: CC BY-SA 4.0 |

GMB is the **native coin** (like ATOM/ETH), defined in the genesis allocation —
**not** an ERC-20. Non-fungible things (workplace access, tickets) are separate
NFT contracts deployed on the chain.

---

## 2. Philosophy

GembaBlockchain is **Bulgaria's first blockchain** — a **public, decentralized
utility chain** built **for the good of society**, for public institutions and
private organizations to integrate and deliver services to their citizens and users.
Value comes from *use* (cheaper service access, workplace access control, event
tickets, employee perks), **not speculation**. The endgame is infrastructure **owned
and run by its participants**, including public institutions — but every participant,
including municipalities, follows the same on-chain rules. No participant has special
power.

**Not built for speculation or trading — by design.** GembaBlockchain **provides no
liquidity for GMB**, operates **no exchange/DEX**, and does not redeem GMB for fiat.
GMB exists to be *used*, not speculated on. There IS a **public Buy-GMB channel**
(`GembaPayDispenser`, §6) where anyone can buy GMB **via GembaPay at a fixed 1 GMB = 1 EUR** (the only way to buy GMB) **to USE** — Gemba dApp services at a 20%
discount (GembaPay, GembaEscrow, GembaWin, GembaTools, GembaKitchen, GembaSniperBot) or to
become a validator earning daily GMB rewards (themselves spendable on those services). This
sale is **non-commercial, made solely for the benefit of society** — a fixed-rate utility
channel, **NOT** a market, liquidity, or speculative offering. Mechanically it is the
gembachain.io "Buy GMB" UI → GembaPay backend → owner-only dispenser contract; **the on-chain
`GembaOnRamp` public-sale contract was REMOVED entirely (owner decision 2026-07-17)**. (We
cannot stop a third party creating a market — but we seed none ourselves; §8 & §16.1.)

- **Permissionless.** Anyone with enough GMB can validate. Anyone can hold and
  transfer GMB. No operator approves participants.
- **Founder holds no power over the network.** The founder wallet (5%) is a
  non-voting operations/sales treasury — like a central bank with no vote. This is
  what makes "decentralized / given to society" credible.
- **Honest about what GMB is.** GMB is a *freely transferable utility coin on a
  public chain*, **not** a closed-loop voucher. We run a fixed-rate Buy-GMB sale (via GembaPay) for
  *use* (§6), but operate **no DEX**, **seed no liquidity by design**, and do not redeem
  GMB for fiat; on a permissionless chain we **cannot** prevent a third party from
  creating a market, so a market price may emerge that we do not control. A conscious
  trade-off (section 16).

---

## 3. Invariants (must always hold)

1. **Fixed supply.** Minted once at genesis, never again. Validator rewards come
   from a pre-minted reserve, not new issuance ⇒ inflation is exactly 0%.
2. **Permissionless stake-only validator entry.** The only requirement to validate
   is bonding GMB ≥ the current threshold. No KYC, no approval, no whitelist.
3. **No privileged validators.** Genesis validators have no permanent advantage;
   same rules, same stake economics, can be out-ranked and replaced.
4. **Reserves never vote.** The contracts/accounts holding the faucet, foundation,
   DAO, validator and contingency reserves have zero voting power.
5. **Founder never votes and never validates with privilege.**
6. **No unilateral control of reserves.** Funds leave any reserve only via
   governance + timelock (and, for emergencies, a pause-only multisig — section 7).
7. **PII never goes on-chain** (section 10).

---

## 4. Tokenomics

### 4.1 Genesis allocation

Total supply **`N = 100,000,000 GMB` (100M)**, minted once at genesis. (Decided
2026-06-06: stay at 100M — a 100B increase was considered and **rejected**; proportions
below are authoritative.) Bucket #1 ("faucet") = the **Public/Municipal Reserve**, distinct
from the testnet *drip* faucet; the former liquidity reserve is the **Contingency Reserve**
(no liquidity by design, §8).

> **Reserve-contract funding status (UPDATED 2026-06-26 — verified on-chain):** the Solidity
> reserve contracts **ARE funded on the live testnet** (Governor/Timelock custody): Faucet **30M**,
> Foundation **15M**, DAO **10M**, Contingency **10M** = **65M**, all owned by the Timelock; the
> 20M validator reward reserve sits in the `x/rewardstreamer` module account (by design). So the
> earlier "reserves not yet in the Solidity contracts" note is **superseded** — they are funded.
> Two carry-over items for mainnet: (1) the reserve contracts are **not yet excluded from
> `GembaVotes`** (defense-in-depth gap — fix via governance `setExclusion` / a correct genesis),
> and (2) governance params are still testnet-loose (tighten for mainnet). Full verification +
> reconciliation: **[`docs/live-deployment-security-2026-06-26.md`](docs/live-deployment-security-2026-06-26.md)**;
> plan: **[`docs/tokenomics-pending.md`](docs/tokenomics-pending.md)**.

| Bucket | Share | GMB (N=100M) | Votes? | Purpose |
|---|---|---|---|---|
| **Public Reserve** (public/municipal) | 30% | 30,000,000 | No | grants to institutions by formula + vesting; refilled by 40% of fees. *The big public reserve — NOT the small public faucet (that is a separate 100k seeded by the founder, below).* |
| Validator rewards reserve (~10 yrs) | 20% | 20,000,000 | No | funds validator rewards with zero inflation |
| Foundation (development, audits) | 15% | 15,000,000 | No | dev funding via governance |
| DAO reserve (contingency) | 10% | 10,000,000 | No | unforeseen needs; released by governance; **a source for grants to early participants** (2026-06-29) |
| **Contingency reserve** *(непредвиден)* | 20% | 20,000,000 | No | unforeseen/strategic needs; released via governance + timelock. **Absorbs the former 10% client/circulation pool** (decision 2026-06-29); no liquidity is seeded (§8) |
| Founder / operations + sale | 5% | 5,000,000 | No (excluded) | from day 1 the founder seeds the OPEN channels from its **own** 5M (the 30M Public Reserve untouched): **100k → public faucet, ~40k → the 4 validators**; keeps ~4.86M working capital (sold via the GembaPay dispenser → discounted access; the dispenser is funded operationally from this stock) |

> **🔻 ALLOCATION + OPEN-DISTRIBUTION UPDATE (decided 2026-06-29).** The former **10% client/
> circulation pool is folded into the Contingency reserve (now 20%)**. New split: **30 Public
> Reserve / 20 validator-rewards / 15 foundation / 10 DAO / 20 contingency / 5 founder = 100M.**
> **The chain is decentralized and openly distributable from day 1** — the reserves are *public,
> non-voting, and held in readiness to be distributed, not hoarded*, and GMB reaches anyone via
> **OPEN channels seeded by the founder's OWN 5% on day 1 (the 30M Public Reserve is untouched):**
> - **Public faucet (100k)** — the tested `GembaFaucet`; **0.1 GMB/day per account**, permissionless — if it runs low the founder tops it up (or it is refilled from the Public Reserve).
> - **Public Buy-GMB sale** — via GembaPay + `GembaPayDispenser` (fixed 1 GMB = 1 EUR, funded
>   operationally from the founder stock); anyone buys GMB to USE Gemba dApps at a 20%
>   discount or to become a validator (non-commercial, for society — §6/§16.1). *(The on-chain
>   `GembaOnRamp` contract + its 160k genesis seed were removed 2026-07-17.)*
> - **Validators (~40k)** — the 4 genesis validators' self-bond; entry is permissionless for all.
> - Plus formula grants to institutions (Public Reserve) and ecosystem/early grants (DAO).
> Anyone with a clear purpose can get starter GMB from block 0; the rest stays in public reserves
> ready to be distributed as participants arrive. The voting base widens as GMB distributes; until
> then governance is protected by high quorum + supermajority + long timelock (§16.2).

Founder originally contributed 10 of 15 points (+2% faucet, +1% foundation, +4% DAO, +3%
contingency, keeping 5%); the 2026-06-29 update folds the 10% circulation into contingency.

**Only circulating, staked GMB votes** (section 7). All reserves are held in
non-voting contracts/accounts.

> **Founder holding (5%) — funds the open channels, then is trading stock.** On day 1 the founder
> seeds the public faucet (100k) and the 4 validators (~40k) **from its own 5M** — the 30M Public
> Reserve is never touched. The remaining ~4.86M is the **trading stock** (sold via the GembaPay
> dispenser to give clients discounted access; recirculates; **non-voting**); the dispenser is
> funded from it operationally, as sales demand. There is **no separate circulation pool** — GMB
> enters circulation via the faucet, the Buy-GMB dispenser, validator rewards and
> DAO/Public-Reserve grants, not a standing bucket.

### 4.2 Zero inflation, no burn

- Supply fixed at `N` forever. **No minting after genesis** — set the Cosmos
  `mint` module inflation to **0** (disable inflationary issuance).
- Validator rewards are **funded from the pre-minted 20M validator reserve**, not
  from new issuance (section 5.4). When the reserve is depleted (~10 yrs),
  validators live on fees.
- **No burn.** Spent GMB recirculates (section 6); burning in this model only
  shrinks the usable pool.

### 4.3 Validator reward sizing

- The 20M reserve pays out **~2,000,000 GMB/year for ~10 years**, then fee-only.
- Think in annual terms (block-time independent). Implemented via the
  `distribution` module fed by a **custom reserve-release module** (section 5.4),
  not by per-block inflation.

---

## 5. Consensus & validators (Cosmos EVM + CometBFT PoS)

### 5.1 Why this stack

QBFT was rejected because it is built for a small, known validator set (~30 cap) —
that is not permissionless. CometBFT PoS gives **permissionless entry into a large
active set**, EVM compatibility, instant finality, and a sovereign chain we fully
control (validator set, governance, fees).

### 5.2 Becoming / staying a validator

- **Stake-only entry, no KYC.** Bond GMB ≥ the current **minimum self-bond** and you
  are in the active set. No approval, no identity check. (If a specific institution
  ever needs to know who validates its data, that is an **off-chain legal contract**,
  never a protocol gate.)
- **Minimum self-bond (anti-spam floor).** A small minimum self-delegation is enforced
  at validator creation (testnet launch: **1,000 GMB** — reachable from the drip faucet
  in ~10 days). It stops trivial 0.001-GMB validators without being a real barrier
  (~0.001% of supply). Enforced by a custom ante decorator reading a
  **governance-tunable parameter** — raise/lower it later by an `x/consensus`-style
  `MsgUpdateParams` gov proposal, no chain restart needed (the §5.2 "growing threshold").
- **Active set cap.** CometBFT communication is O(n²), so the active set has a
  configurable `MaxValidators` (launch: **150**). Entry is permissionless and ranked by
  stake: above the cap you are a candidate that rotates in when your bonded stake
  out-ranks an active validator. Being out-ranked is **not** being kicked — you keep
  your stake, stay a registered validator, and re-enter by bonding more; no slashing.
  `MaxValidators` is itself governance-tunable (raise it as the network matures).
  "Unlimited" = permissionless + ranked, not literally infinite simultaneous validators.
- **Sybil resistance = the stake itself.** Running 10 validators costs 10× the
  stake in real bonded GMB. Power is never free; it is bought with locked capital,
  same as everyone. This is the design, not a bug — it is *why* nobody (including a
  municipality) can flood the validator set cheaply.
- **Growing threshold (optional).** A minimum-stake parameter may rise over time
  via governance to keep validator quality up as the chain matures.

### 5.3 Genesis validators

- **Minimum 4 at genesis** (run on the founder's 5 servers). BFT needs `N ≥ 3f+1`:
  with 4 validators the chain tolerates 1 going down and **keeps producing blocks**.
  With 2 validators a single failure **halts** the chain — so 2 is not viable.
- Genesis validators have **no permanent privilege**: same stake rules, can be
  out-ranked/replaced. They exist only because *someone* must be in the block-0 set;
  the set opens to everyone immediately under the same policy.

### 5.4 Validator rewards (zero-inflation mechanism)

Validators earn from two sources, **neither of which mints new GMB**:
1. **Transaction fees.** Cosmos EVM uses EIP-1559; the base fee is **distributed to
   validators/delegators (not burned)**. We customize fee distribution to a
   **60/40 split**: 60% to validators/delegators, **40% to the faucet** (section 6).
   This is a custom fee-distribution hook / module — not the default.
2. **Reserve-funded block reward.** A **custom module** streams ~2M GMB/year from
   the 20M validator reserve into the `distribution` module, paid to the active set
   (proportional to stake/blocks). Funded from a pre-minted account ⇒ no inflation.
   Stops when the reserve is exhausted (~10 yrs) ⇒ fees take over.

### 5.5 Exit lifecycle

`Active → unbond → unbonding period (cooldown) → tokens returned`

- Unbonding starts a **cooldown** (Cosmos `staking` UnbondingTime, e.g. 7–21 days).
  This is the **slashing window**: misbehavior discovered during it can still be
  punished.
- **Clean exit** ⇒ full bonded stake returns to the validator. Stake does **not**
  go to the faucet on an honest exit.
- **Liveness guard.** The active set must not drop below the BFT minimum (≥ 4); the
  protocol/governance keeps enough validators bonded.

### 5.6 Slashing (Cosmos/Ethereum-style — not reinvented)

| Offence | Punishment | Detection |
|---|---|---|
| Double-signing / equivocation | major slash + jail/tombstone | objective, on-chain provable |
| Downtime / liveness | minor slash + jail | objective |
| Censorship | **not** auto-slashable | not objectively provable on-chain → governance/social layer |

**Slashed stake → the faucet** (the public reserve), **never burned**. Slashing
punishes the validator by **loss of its bonded stake**, not by destroying supply:
the forfeited GMB is redirected to the faucet, so total supply stays fixed at
100M (§3.1, §4.2). Default Cosmos slashing *burns* slashed tokens — that would
break the fixed-supply invariant (it already cost the testnet 10 GMB once, a 1%
downtime slash of val-3, before this was fixed). We override it with
**`chain/x/slashfunds`**, a thin decorator on the bank keeper handed to
`x/staking` that intercepts the slash burn (`BurnCoins` from the bonded /
not-bonded pools) and `SendCoinsFromModuleToModule`s it to the faucet instead —
the same zero-burn principle as `x/feesplit`. Covered by a supply-invariance test
(slash → supply unchanged, coins appear in the faucet). See ADR-013.
Never promise automatic punishment for anything not deterministically provable
on-chain.

### 5.7 Power separation

**Consensus power ≠ governance power.** Bonded GMB grants the right to validate and
earn; governance voting is a separate accounting (section 7). Validators do not get
extra governance weight just for validating, or they become double plutocrats.

---

## 6. Circulation & grants to institutions

```
 faucet  --grant (formula + vesting)-->  institutions & clients  --pay fees-->  fee split
   ^                                                                       |     |
   |                                                                60% -> validators
   +-------------------------- 40% of fees -------------------------------- +
```

- An institution receives GMB from the faucet via **a formula tied to real use**
  (e.g. proportional to the fees its activity generates), not a lump sum.
- **40% of all fees flow back into the faucet**, so it does not run dry.
- Top-ups: small automatic grants by formula; a **large grant requires governance
  + timelock** (the community sees it and can block during the delay).
- **Streaming/vesting**, not one big transfer — a grant drips over time and is
  governance-revocable if abuse is seen.

### Controlling abuse — the honest boundary

Two different fears, two different answers:

- **"A municipality spins up many validators."** Not a threat here: entry is pure
  stake (section 5.2). 10 validators = 10× the bonded GMB. They buy power with
  locked capital like anyone; no free Sybil.
- **"A municipality hands GMB to people who shouldn't get it."** GMB is **freely
  transferable** (a deliberate choice). Once it is in the municipality's wallet, we
  **cannot** control what it does with it without breaking free transferability.
  Therefore control is **on the faucet — the rate and condition of inflow**, not on
  already-spent tokens: formula-based grants + vesting + per-grant cap with
  governance approval above the cap. You govern the *tap*, not the water already
  poured.

Reserves that hold supply (faucet, foundation, DAO, validator, contingency) are the
critical attack surface: they are **non-voting**, **no one holds a unilateral key**
to them, withdrawals go only through governance + timelock, grants leave by on-chain
formula, and the emergency multisig can only **pause**, never drain (section 7).

---

## 7. Governance

Two layers, clearly separated:

**A. Chain-level governance — Cosmos `gov` module.** Consensus/staking/fee
parameters. Voting power = **bonded (staked) GMB**. Reserves are not staked ⇒ they
do not vote naturally. Founder does not stake-to-vote ⇒ excluded.

**B. Treasury/contract governance — Solidity Governor + Timelock.** Controls the
reserve contracts (faucet, foundation, DAO, contingency) and protocol contracts.
- **1 GMB = 1 vote**, with reserve-holding contracts **explicitly excluded** from
  `getVotes`.
- Flow is **code only**, no steward: propose → vote (quorum + threshold) → queue in
  **Timelock** (delayed execution) → after the delay **anyone** can execute. No
  privileged signer keeps the system running.
- **Higher bar for treasury & upgrades:** high quorum + supermajority (66–75%) +
  long timelock. Minor params may pass on simple majority.
- **Emergency multisig = pause only.** It can halt a contract during an incident,
  **never** move/drain funds. Its signers are **elected by governance and
  replaceable** by governance. This is bounded, revocable power — not a steward.

**Scope limit:** on-chain governance controls contracts, treasuries and chain
parameters. Changing the chain's own binary/consensus rules is a **coordinated
node-operator upgrade** (social coordination, documented as a runbook in `/docs`).

**Early-stage honesty:** at launch ~90% of GMB is in non-voting reserves and the
founder is excluded, so the voting base is small. We compensate **without a trusted
human**: high quorum + supermajority + long timelock so a small early base cannot
push anything harmful unseen; hard rules baked into genesis; and faucet grants by
**formula** (automatic), so no authority is needed for funds to reach institutions.
The voting base grows as GMB distributes.

---

## 8. Contingency reserve (10%) — *резерв за непредвидени нужди*

> Replaces the former "liquidity reserve". **GembaBlockchain provides no liquidity
> for GMB and operates no DEX/exchange by design** — it is not built for speculation
> or trading (§2, §16.1). So there is **no liquidity-seeding bucket**. The 10% is held
> instead as a **contingency reserve for unforeseen needs**.

- **Purpose:** a non-voting reserve for **unforeseen / strategic needs** the chain may
  face, released **only via Governor + Timelock**. Not for market-making, not for
  price support — we seed no liquidity.
- Holding it as a separate, modest (10%), non-voting, governance-gated bucket keeps it
  from being a systemic point of control.
- **Note (overlaps the DAO contingency reserve §4.1 #4):** both are now
  contingency-style buckets. Whether to keep them distinct (DAO-directed vs general
  unforeseen) or merge into one 20% reserve is an open tokenomics decision —
  `docs/tokenomics-pending.md`.

---

## 9. Smart contracts (Solidity, on the EVM)

Use **Foundry** (preferred) or Hardhat. Upgradeable where governance must evolve
them (proxy + Timelock). Staking/slashing/gov-of-chain live in **Cosmos modules**;
treasuries and app logic live in **Solidity**.

| Contract | Responsibility |
|---|---|
| `Governor` + `Timelock` | treasury/contract governance; 1-GMB-1-vote excluding reserve contracts; quorum, supermajority, delay |
| `PublicReserve` — the **Public Reserve** contract (`src/reserves/PublicReserve.sol`) | the 30% public/municipal reserve; intake of 40% of fees; formula + vesting grants; per-grant + rolling-window cap; owner = Timelock, pause-only EmergencyPause |
| `GembaFaucet` | the small **public faucet** — anyone claims a little GMB, permissionlessly; seeded 100k from the founder on day 1 (the tested testnet contract) |
| `GembaPayDispenser` (+ `GmbCollector`) | the **Buy-GMB sale channel** — gembachain.io "Buy GMB" UI → GembaPay backend → owner-only dispenser at a fixed 1 GMB = 1 EUR, for USE (Gemba dApps @20% off + validator entry); funded operationally from the founder stock; non-commercial, for society (§6). *The on-chain `GembaOnRamp` public-sale contract was REMOVED 2026-07-17.* |
| `FoundationTreasury` | dev funding, released by governance |
| `DAOReserve` | contingency funds, released by governance |
| `ContingencyReserve` *(renamed from `LiquidityReserve.sol`)* | holds the **20%** contingency GMB (incl. the folded circulation, 2026-06-29) for unforeseen/strategic needs; released only by governance + timelock. **No liquidity is seeded (§8).** |
| `EmergencyPause` (multisig) | pause-only guardian; governance-elected, replaceable; cannot move funds |
| `AccessControlNFT` | ERC-721/1155 capability tokens for workplace access (no PII) |
| `Paymaster` | sponsored gas so an institution funds employees' fees from one wallet (meta-tx relay first; ERC-4337 later) |
| `Ticketing` | ERC-1155 event tickets (GembaTicket-style) — later phase |

> **Not Solidity — chain-level (Go/Cosmos module) customizations:** the
> `ValidatorRewardStreamer` (streams ~2M GMB/yr from the 20M validator reserve into
> the `distribution` module — §5.4), the 60/40 fee split to the faucet, and the
> post-reserve **tail reward** (§16.8, recirculation-funded, never minted) all live
> in Go modules, not Solidity. There is no Besu-style `miningbeneficiary` contract
> here. They are listed in §15 (Custom chain logic), not in this contract table.

> **Optional developer DEX tooling (`contracts/src/dex/`) — NOT project-operated.**
> `gembaswap/` is the **official Uniswap V2 renamed 1:1** (`UniswapV2`→`GembaSwap`,
> core 0.5.16 + periphery 0.6.6, full Router02 ABI, pair init-hash recomputed) — nothing
> abbreviated. Plus `WGMB` (wrapped native), a **pure-native-GMB pool** (`GembaNativePool`
> — holds native GMB directly, no WGMB), and a `LiquidityLocker`. These are
> **permissionless reference contracts for ecosystem developers to deploy for their OWN
> ERC-20 tokens** (bootstrap/test their token's liquidity). This does **not** contradict
> "we operate no DEX / seed no GMB liquidity" (§2, §8, §16.1): the project deploys/operates
> none of these and seeds no GMB market; a third party deploying a market is the §16.1
> reality we already accept. See `contracts/src/dex/README.md`.

---

## 10. Access control & GDPR

- On-chain: an **anonymous capability NFT** = "this credential may enter zone X".
- Off-chain (PostgreSQL, your stack, row-level security): employee identity, the
  mapping identity → NFT, and all access logs.
- **Never** put PII or physical-access logs on-chain — immutability conflicts with
  the GDPR right to erasure. The identity→NFT bridge is the real PII point; guard it
  with RLS. On-chain stays verifiable; private data stays deletable off-chain.

---

## 11. Networking

- **Node-to-node:** CometBFT P2P, default **TCP 26656** (authenticated/encrypted via
  the node key). Peers found via **seeds / persistent_peers** in `config.toml`.
  Optionally run nodes over **WireGuard/VPN** for isolation.
- **Cosmos RPC** (26657), **gRPC** (9090), **REST/API** (1317).
- **EVM JSON-RPC** (8545 HTTP / 8546 WS) — where MetaMask, Foundry, ethers/viem and
  GembaPay talk to the chain.
- Put public-facing RPC/JSON-RPC **behind Apache reverse proxy + Let's Encrypt =
  HTTPS** (existing DevOps stack). Permissionless networking ≠ unprotected: rate-limit
  and TLS-terminate the public endpoints.
- **State growth:** continuous ~5 s blocks ⇒ configure Cosmos **pruning** (e.g.
  `pruning = "custom"` with sane keep-recent/interval) and document archive vs
  pruned node disk needs for institutions running a node.

### MetaMask network parameters

```
Network name:    GembaBlockchain
RPC URL:         https://rpc.gemba<...>     (EVM JSON-RPC behind the reverse proxy)
Chain ID:        821206
Currency symbol: GMB
Block explorer:  https://scan.gemba<...>    (Blockscout / GembaScan)
```

Addresses are standard `0x...` (eth_secp256k1, coin type 60) — MetaMask works out of
the box.

> **⚙️ LIVE TESTNET RPC ENDPOINTS (operational — read this before debugging any RPC issue).**
> The public EVM JSON-RPC is **`https://rpc1.gembascan.io`** (PRIMARY) with
> **`rpc2`/`rpc3.gembascan.io`** as fallbacks. These run **ON the Contabo validator servers**
> (`rpc1`→**.83**, `rpc2`→**.84**, `rpc3`→**.82**), reverse-proxied behind Cloudflare.
> **The RPC is NOT on the `.162` host** — `.162` serves only the websites/dApps (gembachain.io,
> swap, gembapay, addresses, …) and runs **no chain node**. The archive node (`.148.137`) is **archive-only**; **GembaScan/Blockscout was MOVED to its own box `213.136.85.32`** (Contabo VPS 20 NVMe) on 2026-06-29, reaching the archive over a private autossh tunnel — see `docs/public-rpc-topology.md` / `docs/SERVER-TOPOLOGY.md`. The RPC domain is **`*.gembascan.io`**
> — **`rpc.gembachain.io` is not a valid host; do not use it.** Mainnet follows the same model
> (RPC on beefier validators, never on the archive/explorer host). See `docs/public-rpc-topology.md`.
>
> **MAINNET RPC (decided 2026-07-17):** fresh subdomains **`gmb1`/`gmb2`/`gmb3.gembascan.io`**
> (`gmb1`→**.82**, `gmb2`→**.83**, `gmb3`→**.84**) — deliberately DIFFERENT from the testnet's
> `rpc1/2/3` so a stale wallet/integration config can never silently hit the other network;
> `rpc1/2/3` stay testnet-only until the testnet is decommissioned.

---

## 12. Block explorer — "GembaScan" (Blockscout)

- Self-host **Blockscout** (open-source Etherscan/Polygonscan equivalent) via Docker
  for the **EVM side** — supports sovereign/permissioned and public EVM chains.
- Provides **Etherscan-compatible API** + REST v2 + GraphQL + WebSocket, Solidity
  contract verification, and **API keys** issued from the instance for code
  integration; self-hosted ⇒ you control rate limits.
- Optional **Cosmos-side explorer** (e.g. ping.pub) for staking/governance/validator
  views, since those live in Cosmos modules, not the EVM.
- **Live (Phase 7 done).** GembaScan runs on a **dedicated box** — testnet: **`213.136.85.32`**
  (Contabo VPS 20 NVMe, since 2026-06-29), reading a separate archive node over a private tunnel;
  **never co-located with a validator or the archive's heavy serving load** (§11,
  `docs/public-rpc-topology.md`, `docs/SERVER-TOPOLOGY.md`).

---

## 13. Phased build plan (do not do all at once)

- **Phase 0 — Scaffolding.** Monorepo (section 14), `.env.example`, `.gitignore`,
  `README.md`, `/docs`. No secrets committed.
- **Phase 1 — Local devnet.** Build from `evmd`/`cosmos/evm`: set `gemba-1` +
  EVM chainId **821206**, eth_secp256k1 / coin type 60, ~5 s blocks (2 s target), **mint
  inflation = 0**, native GMB genesis alloc per section 4.1. Single node first, then
  a 4-validator local multi-node. Verify MetaMask connects and a GMB transfer + a
  Solidity deploy work.
- **Phase 2 — Custom chain modules.** Reserve-funded validator reward streamer
  (zero-inflation), 60/40 fee-distribution split to the faucet. Verify rewards flow
  without inflation and fees split correctly on devnet. *Done: `chain/x/rewardstreamer`
  + `chain/x/feesplit` (EVM-independent, mint/burn-free interfaces), wired into the
  `gembad` binary (`chain/gembad`) and demonstrated live on single-node and
  4-validator devnets — supply constant, fee split 60/40.*
- **Phase 3 — Treasury & governance contracts.** `Governor` + `Timelock`, `PublicReserve`,
  `FoundationTreasury`, `DAOReserve`, `ContingencyReserve` (renamed from
  `LiquidityReserve` — no liquidity by design, §8), `EmergencyPause`; reserve
  contracts excluded from voting; formula + vesting grant logic. **Follow
  `docs/phase3-treasury-principles.md`: tests first, funding last (no contract
  funded before unit + invariant/fuzz + Slither; reserves audited before mainnet
  genesis); upgrade authority is Governor+Timelock only, never an EOA; design the
  Cosmos↔EVM faucet seam before coding it.** *Done: OZ-v5 contracts in `contracts/src`
  (UUPS reserves, Timelock-only upgrades, supermajority Governor, pause-only
  EmergencyPause), 36 Foundry tests incl. invariant/fuzz, Slither triaged
  (`contracts/SECURITY.md`); seam proven on devnet (`SeamProbe`). All UNFUNDED.*
- **Phase 4 — Fees & sponsored gas.** Tune EIP-1559 params for **low but non-zero
  cost that scales with usage** (cheap per-tx, real aggregate security budget — §16.8);
  `Paymaster` (meta-tx relay first) so institutions sponsor employees' gas. *Done:
  feemarket params (1 gwei floor, elasticity 2) demonstrated live — base fee at the
  floor when idle, climbing 1→3 gwei under load, decaying after
  (`chain/gembad/demo-feemarket.sh`). `GembaForwarder` (EIP-2771) + `WorkplaceCheckIn`
  in `contracts/src/paymaster`; live devnet demo: an employee with 0 GMB makes a
  successful, correctly-attributed tx whose gas the relayer pays
  (`contracts/script/SponsoredDemo.s.sol`). Relayer is per-institution, not a chain
  dependency (ADR-011). 41 Foundry tests, Slither triaged.*
- **Phase 5 — Access control.** `AccessControlNFT` + off-chain PII/log backend
  (Node/Express + PostgreSQL RLS), GDPR split. *Done: soulbound ERC-1155 capability
  NFT (no PII on-chain, issuer-gated, 7 Foundry tests) in `contracts/src/access`;
  off-chain backend in `services/access-control` — PostgreSQL schema with `FORCE`
  RLS isolating each institution's identity rows, Express API, GDPR erasure
  (on-chain revoke + off-chain delete), 8 unit tests + an RLS integration test.*
- **Phase 6 — Buy-GMB (GembaPay).** GembaPay → GMB purchase flow (no fiat redemption;
  no DEX operated by us). *Done: `GembaPayDispenser` + `GmbCollector`
  (`contracts/src/onramp`) — the gembachain.io "Buy GMB" UI → GembaPay backend →
  owner-only dispenser at a fixed 1 GMB = 1 EUR; Ownable2Step + Pausable +
  `nonReentrant`; 19+12 Foundry tests; live on the testnet
  (`docs/gembapay-gmb-dispenser.md`).* It sells GMB to anyone **to USE**: Gemba dApp
  services at a 20% discount (GembaPay, GembaEscrow, GembaWin, GembaTools, GembaKitchen,
  GembaSniperBot) or to become a validator earning daily GMB rewards. **Non-commercial,
  made solely for the benefit of society** — not a market/liquidity/speculative offering
  (§2, §16.1). Institutions also receive GMB via closed formula grants (Public Reserve, Phase 3).
  **The original on-chain `GembaOnRamp` public-sale contract (+ its 160k genesis seed) was
  REMOVED entirely — owner decision 2026-07-17;** the dispenser is the only sale channel.
- **Phase 7 — Explorer.** Blockscout / GembaScan + API keys; optional Cosmos explorer.
  *Done: `explorer/` — pinned Blockscout docker-compose + `envs/backend.env`
  (Etherscan-compatible API, self-issued API keys, contract verification via
  `verify/*.standard.json`), **pointed at a dedicated ARCHIVE node** (pruning
  nothing) — never a pruned validator (§11). Verified live against the gembad
  archive node: historical blocks/receipts, historical account state
  (`eth_getBalance` at old heights), and internal-tx traces
  (`debug_traceBlockByNumber`) — exactly what Blockscout indexes. Optional ping.pub
  Cosmos config in `explorer/ping-pub`. (Running the Blockscout containers needs
  Docker.)*
- **Phase 8 — Tickets & perks.** `Ticketing` ERC-1155, employee-bonus flows. *Done:
  `GembaTicketing` (events as ERC-1155: create/issue/buy/redeem, supply caps, GMB
  sales) + `GembaPerks` (institution pays GMB bonuses + grants perk tickets) in
  `contracts/src/tickets`. Security standards (CEI + nonReentrant on mint/value
  paths, events, custom errors). 24 Foundry tests incl. reentrancy + invariant/fuzz
  (minted ≤ maxSupply; no pool drain); Slither triaged. Live devnet demo
  (`script/TicketingDemo.s.sol`): issue, paid buy, GMB bonus + perk ticket, redeem.*
- **Phase 9 — Hardening.** Seeds/persistent peers, monitoring, pruning, backups,
  validator key management (KMS/Vault/`tmkms`), runbooks (halt recovery, coordinated
  upgrade), security review / audit before public launch. *Technical part done: the
  post-reserve **tail reward** (`x/tailreward`, ADR-008b — recirculation, no mint,
  supply-invariant tested + live); `/monitoring` (Prometheus + the **bonded-ratio**
  security metric & ADR-008 alerts at 66/50/33); `docs/runbooks/` (peers & pruning
  validator-vs-archive, tmkms key mgmt, backups, halt recovery, coordinated
  upgrade). The **security audit (ADR-006)** remains the founder's separate, non-code
  track and a hard launch blocker (§16).*
- **Public testnet (mainnet dress rehearsal).** `gemba-testnet-1` (distinct chain-id
  + EVM chainId 821207, valueless tokens): `chain/testnet` (genesis generator,
  verified locally as a 5-validator network producing blocks), `services/testnet-faucet`
  (rate-limited drip of test GMB, verified live), and `docs/runbooks/testnet-deploy.md`
  + `testnet-launch-checklist.md` for the 5 geo-separated Hetzner validators. Same
  binary/economics as mainnet; run for weeks before planning the public launch.
  **Testnet → mainnet transition (DECIDED 2026-06-29):** the public testnet is **not** kept running
  alongside mainnet. When mainnet is prepared, `gemba-testnet-1` is **stopped and its servers
  (validators + archive `.137` + the dedicated explorer box `213.136.85.32`) are reused for `gemba-1`**
  — no separate fleet is bought. Ongoing upgrade testing thereafter runs **locally on the `.100`
  (jellyfin) box as an on-demand 4-validator testnet**, spun up from the genesis generators only to
  rehearse a binary/consensus upgrade before it touches the value-bearing mainnet, then torn down.
  Details: `docs/public-rpc-topology.md`, `docs/SERVER-TOPOLOGY.md`.

---

## 14. Repository structure & secret hygiene

```
GembaBlockchain/
  CLAUDE.md            # this file — source of truth
  README.md
  .env.example         # placeholders only (committed)
  .gitignore           # ignores .env, keys, mnemonics, node data
  /chain/              # Cosmos EVM app (Go): app wiring, custom modules, genesis, config; node keys NOT committed
  /contracts/          # Foundry/Hardhat Solidity (governor, treasuries, NFTs, paymaster)
  /services/           # Node.js/Express backends (purchase-backend, access-control API, indexers)
  /frontend/           # React
  /explorer/           # Blockscout docker setup
  /docs/               # detailed specs & runbooks (halt recovery, upgrades, risks)
```

**Always in `.env` / secret store, never committed:** validator consensus keys,
node keys, account mnemonics, GembaPay/API keys, RPC credentials, DB passwords.
Public genesis **addresses** are fine to commit; the **private keys/mnemonics**
behind them are not. `.gitignore` covers `.env`, `*.key`, `*mnemonic*`, keyrings,
and node data/`.gembad` dirs.

---

## 15. Tech stack summary

| Layer | Tool |
|---|---|
| Chain | Cosmos SDK + Cosmos EVM (`cosmos/evm`, `evmd`) on CometBFT — Go |
| Custom chain logic | Go modules: zero-inflation `ValidatorRewardStreamer` (reserve → distribution), 60/40 fee split, post-reserve recirculation-funded **tail reward** (§16.8) |
| Smart contracts | Solidity (Foundry preferred) |
| Backend services | Node.js / Express |
| Frontend | React |
| Explorer | Blockscout (Docker), optional ping.pub |
| Infra | Hetzner (5 servers as first validators), Docker, systemd, Apache reverse proxy, Cloudflare DNS, Let's Encrypt |

> GembaBlockchain = Cosmos EVM (off-the-shelf permissionless PoS + EVM) **+** a thin
> Gemba layer: two small Go modules (zero-inflation rewards, fee split) and the
> Solidity treasury/governance/app contracts. We do not write a blockchain from
> scratch.

---

## 16. Risks & conscious trade-offs (recorded on purpose)

These are **chosen**, not overlooked. Documented so they are not later flagged as
contradictions.

1. **Free transferability ⇒ possible market price we don't control.** GMB is freely
   transferable on a permissionless chain. We do not run a DEX, **seed no liquidity
   ourselves by design**, and do not redeem to fiat, but a third party *can* create a
   liquidity pool. A market price may emerge.
   Accepted. GembaBlockchain seeds no liquidity and runs no exchange. It DOES run a
   **fixed-rate Buy-GMB sale** (via GembaPay + `GembaPayDispenser`, §6) and a small
   **public faucet** so anyone can obtain GMB **to use** — this is **non-commercial, made
   for the benefit of society** (Gemba dApp services at a 20% discount + validator entry
   with daily GMB rewards), NOT a market, liquidity, or speculative offering. Institutions
   also receive GMB via closed formula grants. Built for *use*, not trading. (A third
   party could still create a market; that is outside our control.)
2. **Small early voting base.** ~90% of GMB sits in non-voting reserves at launch.
   Mitigated by high quorum + supermajority + long timelock + formula-based (not
   discretionary) grants, and by the base growing as GMB distributes. No human steward.
3. **No liquidity provided — by design.** The former liquidity reserve is removed;
   GembaBlockchain seeds **no** liquidity and runs no exchange (§2, §8). We do not even
   set an initial pool ratio. Any market is purely third-party (§16.1) and its price is
   entirely outside our control. The freed 10% is now a contingency reserve (§8).
4. **Emergency multisig is residual centralization.** It can only pause, never drain;
   governance elects and can replace its signers. Bounded and revocable.
5. **You cannot control already-distributed GMB.** Control is on the faucet's
   inflow (formula + vesting + governance cap), never on tokens after they leave.
6. **Cosmos EVM is pre-v1 (audit pending).** Pin a known-good version; isolate custom
   modules; do not launch to the public before the upstream audit and our own review.
7. **Censorship is not auto-slashable** — only objectively provable faults are
   (double-sign, downtime). Censorship is handled at the governance/social layer.
8. **Long-term security budget (after the ~10-yr validator reserve runs out).**
   *The contradiction:* fixed supply + zero inflation + "validators live on fees"
   means that if fees stay *negligible forever*, the post-year-10 security budget
   collapses, the bonded ratio falls, and the chain gets cheap to attack (the
   Bitcoin security-budget problem on a fixed-supply PoS chain). *Resolution =
   combination (a)+(b), both zero-inflation-preserving:*
   **(a)** fees carry a **real** security budget — gas is **low but non-zero,
   scaling with usage**, so cheap per-tx yet aggregate `fee × volume × GMB-value`
   grows with adoption (security tied to *use*, which is GMB's value thesis);
   **(b)** a governance-tunable **tail reward funded by recirculated fees, never
   by minting** (recycling a slice of the faucet's 40% fee inflow / DAO surplus
   back into `distribution`) — smooths the year-10 cliff while keeping §3.1 intact.
   *Cost-to-attack vs value:* CometBFT needs **>1/3** bonded to halt, **≥2/3** to
   forge (and that stake is slashed); keep **cost-to-attack ≥ 3× value secured**.
   *Bonded ratio to maintain:* target **~66%**, floor **~50%**, red line **~33%**;
   with inflation off there is no dynamic-inflation lever, so defending the bonded
   ratio is an explicit governance duty (levers: tail-reward rate + gas floor).
   Two corollaries recorded on purpose: **gas price is measured in *real value***
   (security is ~0 if GMB is worthless, however gas is set), and the **two
   electorates stay separate** — the *consensus electorate* (bonded GMB, earns the
   security budget, votes chain params via `gov`) vs the *treasury electorate*
   (1 GMB = 1 vote in the Solidity Governor, excludes reserves); validating earns
   the security budget but grants **no** treasury weight, so no double plutocrats
   (§5.7). Full ADRs in `/docs/risks.md` (ADR-008, 008a, 008b).
9. **Decentralized by rule + openly distributable from day 1.** The network is
   permissionless from block 0 and GMB is publicly obtainable from day 1 (a small
   **public faucet** + the **public Buy-GMB sale via GembaPay**, §4.1) — so it is **not**
   a closed or centralized launch. Stated plainly: at genesis the 4 validators run on the
   founder's servers and ~95% of GMB sits in **public, non-voting reserves held in
   readiness to be distributed — not hoarded**; the founder is excluded from voting.
   Decentralization is bound to *mechanisms, not promises*: permissionless validator
   entry from block 0, a day-1 public faucet + Buy-GMB sale anyone can use, no protocol
   lever to re-close entry (the rejected allowlist/KYC/privileged-validator levers
   stay rejected), reserves distributed via OPEN channels (faucet, the dispenser, validator
   rewards, formula/DAO grants) that widen both electorates, and **published
   decentralization KPIs** (independent operators, Nakamoto coefficient, top-operator
   stake share, bonded ratio, founder share of circulating GMB). Full ADR:
   `/docs/risks.md` (ADR-010).
10. **Meta-tx relayer is an institution's operational dependency, not the chain's.**
   The Phase 4 `Paymaster` (sponsored gas) uses a meta-tx relay: an institution's
   relayer submits its employees' txs and pays the gas, so an employee needs no GMB.
   Risks: relayer trust (it can censor/delay) and single-point-of-failure (relayer
   down ⇒ that institution's sponsored employees can't submit *through it*). These
   are **per-institution operational** risks, **not** chain/consensus risks: each
   institution runs its own relayer for its own employees; one relayer's failure or
   censorship affects only that institution, never GembaBlockchain. Critically, an
   employee can always **submit directly on-chain themselves** (with a little GMB) —
   the relayer is a convenience, not the only path, and the chain has no protocol
   dependency on any relayer. **Explicitly NOT a launch blocker** (unlike ADR-006/
   008/009). Full ADR: `/docs/risks.md` (ADR-011).

> **Hard launch blockers (do not ship a public launch until all clear):**
> **Upstream audit** — Cosmos EVM pre-v1 (risk 6, ADR-006).
> **Security-budget tail** — recirculation tail-reward implemented + tested and
> bonded-ratio monitoring live (risk 8, ADR-008). Devnet/testnet and closed
> formula-based institutional grants are **not** blocked by these gates.
