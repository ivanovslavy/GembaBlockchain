# /chain — Cosmos EVM app (Go)

The GembaBlockchain node, built from `github.com/cosmos/evm` (reference impl
`evmd`) on CometBFT. This is where consensus, staking, slashing, the `gov` module,
genesis, and our **custom Go modules** live.

## What goes here

- **App wiring** — the Cosmos SDK app assembled with the Cosmos EVM module.
- **Genesis config** — `gemba-1`, EVM chainId **821206**, `eth_secp256k1` / coin
  type 60, ~2 s blocks, **mint inflation = 0**, native GMB allocation per
  `CLAUDE.md` §4.1. Public genesis *addresses* may be committed; keys/mnemonics
  must NOT (`.gitignore`).
- **Custom modules (the thin "Gemba layer", `CLAUDE.md` §5.4, §16.8):**
  - `ValidatorRewardStreamer` — streams ~2M GMB/yr from the pre-minted 20M
    validator reserve into the `distribution` module. **No minting** → zero
    inflation. Stops when the reserve is exhausted (~10 yrs).
  - **60/40 fee split** — custom fee distribution: 60% to validators/delegators,
    40% to the faucet.
  - **Tail reward** (post-reserve, §16.8) — recirculation-funded baseline
    validator reward (recycles fees, never mints) to defend the long-run security
    budget / bonded ratio after year ~10.

Isolate custom modules so upstream Cosmos EVM upgrades stay clean (`CLAUDE.md` §0.10,
ADR-006).

**Never commit:** `node_key.json`, `priv_validator_key.json`, keyrings, `.gembad/`
data. See root `.gitignore`.

## Phase

- **Phase 1 — DONE (local devnet).** No Go fork yet: we run the pinned upstream
  `cosmos/evm` `evmd` **v0.7.0** binary and bake GembaBlockchain's economics into
  genesis. See [`scripts/`](./scripts/) — single-node and 4-validator devnets,
  with every genesis anchor (zero inflation, non-zero fee floor per ADR-008a,
  chainId 821206, ~2 s blocks, §4.1 allocation) mapped to its spec section.
  Verified: MetaMask-connect RPC calls, a GMB transfer, a Solidity deploy, and
  4-validator BFT liveness with 1 validator down (§5.3).
- **Phase 2 — TODO (custom Go modules).** This is where we fork/extend `evmd`:
  the `ValidatorRewardStreamer`, the **60/40 fee split**, and the post-reserve
  **tail reward** (ADR-008 (b), recirculation-funded, never minted). Isolate them
  so upstream bumps stay clean (CLAUDE.md §0.10). **Scope reserved here — do not
  fake the tail reward with minting; zero inflation is an invariant (§3.1).**
