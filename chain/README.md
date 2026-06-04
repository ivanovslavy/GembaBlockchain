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

Built in **Phase 1** (local devnet) and **Phase 2** (custom modules). Not yet
scaffolded with Go code — directory placeholder for Phase 0.
