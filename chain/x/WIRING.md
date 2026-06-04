# Wiring the Gemba custom modules into the evmd app

The two Phase 2 modules — `x/rewardstreamer` and `x/feesplit` — are deliberately
**EVM-independent**: they depend only on cosmos-sdk, never on `cosmos/evm`. That is
the isolation `CLAUDE.md` §16.6 asks for: an upstream `cosmos/evm` bump cannot break
them, and they plug into the app's module manager with no EVM coupling.

This is the runbook for adding them to the evmd-derived `gembad` app (the node-side
integration that follows the unit/integration tests). The modules and their tests
are complete and green; these are the app.go edits to ship them on a live node.

## 1. Dependency

In the app's `go.mod`, require this module:

```
require github.com/ivanovslavy/GembaBlockchain/chain v0.0.0
replace  github.com/ivanovslavy/GembaBlockchain/chain => ../chain   // monorepo-local
```

## 2. Store keys

Add to `storetypes.NewKVStoreKeys(...)` in `NewExampleApp`:

```go
rewardstreamertypes.StoreKey,
feesplittypes.StoreKey,
```

## 3. Module accounts (maccPerms)

These module accounts must exist. **None need Minter/Burner permissions** — that is
the point (zero inflation, §3.1): they only ever hold and transfer pre-minted GMB.

| Account | Permissions | Holds |
|---|---|---|
| `rewardstreamer` | none (`nil`) | the 20M validator-reward reserve |
| `faucet` | none (`nil`) | the 30% public reserve + the 40% fee inflow |

`feesplit` holds no funds (it moves coins from `fee_collector` to `faucet`), so its
module account is optional. `fee_collector` already exists in every SDK app.

## 4. Keepers

The SDK `bankkeeper.BaseKeeper` already satisfies both modules' `BankKeeper`
interfaces (`GetBalance`, `GetSupply`, `GetAllBalances`, `SendCoinsFromModuleToModule`).
Construct after the bank keeper:

```go
app.RewardStreamerKeeper = rewardstreamerkeeper.NewKeeper(keys[rewardstreamertypes.StoreKey], app.BankKeeper)
app.FeeSplitKeeper       = feesplitkeeper.NewKeeper(keys[feesplittypes.StoreKey], app.BankKeeper)
```

## 5. Module manager + BEGIN-BLOCKER ORDER (critical)

Register the modules, then set the begin-blocker order so the split happens before
the rewards are added and all happen before distribution pays out:

```
... -> feesplit -> rewardstreamer -> tailreward -> distribution -> ...
```

(`x/tailreward` — ADR-008b — streams the post-reserve recirculation tail; it sits
with rewardstreamer, after feesplit and before distribution, and is disabled by
default until governance activates and funds it. Its module account needs no
mint/burn permission either.)

- **feesplit before rewardstreamer**: so the 40% faucet skim applies only to fees,
  never to the streamed validator reward.
- **rewardstreamer before distribution**: so the streamed reward is in
  `fee_collector` when distribution allocates it to validators/delegators.

```go
app.ModuleManager.SetOrderBeginBlockers(
    // ... upstream begin-blockers ...
    feesplittypes.ModuleName,
    rewardstreamertypes.ModuleName,
    distrtypes.ModuleName,
    // ... rest ...
)
```

Add both module names to `SetOrderInitGenesis(...)` and `SetOrderEndBlockers(...)`
(end-block order is irrelevant; neither has an EndBlocker).

## 6. Genesis

- Add default module genesis for both (params: 60/40 split; ~2,000,000 GMB/yr).
- In **bank** genesis, allocate the reserve to the module account addresses instead
  of placeholder keyring accounts: send 20,000,000 GMB to
  `authtypes.NewModuleAddress("rewardstreamer")` and the 30,000,000 GMB faucet
  bucket to `authtypes.NewModuleAddress("faucet")`. Update
  `chain/scripts/gemba.params.sh` / the genesis-patching `lib.sh` accordingly
  (the Phase 1 devnet currently funds `valreserve`/`faucet` keyring accounts; the
  wired node funds the module accounts).

## 7. Verify on a node

After wiring, the Phase 1 devnet scripts bring up the chain; then the same
properties the tests assert can be observed live: the `rewardstreamer` module
account balance falls each block, `fee_collector`/validator rewards rise, the
`faucet` account receives 40% of fees, and `gembad q bank total` is unchanged
across blocks (zero inflation).
