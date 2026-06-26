package keeper

import (
	"encoding/json"

	"cosmossdk.io/log/v2"

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

// Keeper manages the validator-reward reserve stream.
type Keeper struct {
	storeKey storetypes.StoreKey
	// feeCollectorName is the module account rewards are streamed INTO (the SDK
	// fee collector), from where the distribution module pays validators.
	feeCollectorName string

	bankKeeper types.BankKeeper
	// Reward-formula keepers (regenesis §4). nil on a legacy build → BeginBlock falls back to the
	// fixed StreamRewards. Injected via WithFormulaKeepers in the app wiring.
	stakingKeeper types.FormulaStakingKeeper
	distrKeeper   types.FormulaDistrKeeper
}

// NewKeeper builds the reward streamer keeper.
func NewKeeper(storeKey storetypes.StoreKey, bk types.BankKeeper) Keeper {
	return Keeper{
		storeKey:         storeKey,
		feeCollectorName: authtypes.FeeCollectorName,
		bankKeeper:       bk,
	}
}

// WithFormulaKeepers injects the staking + distribution keepers the reward FORMULA needs (per-
// validator capped allocation). Called in the app wiring once both keepers exist. Returns a copy.
func (k Keeper) WithFormulaKeepers(sk types.FormulaStakingKeeper, dk types.FormulaDistrKeeper) Keeper {
	k.stakingKeeper = sk
	k.distrKeeper = dk
	return k
}

// GetFormulaParams reads the reward-formula params (JSON; default if unset).
func (k Keeper) GetFormulaParams(ctx sdk.Context) types.FormulaParams {
	bz := ctx.KVStore(k.storeKey).Get(types.FormulaParamsKey)
	if bz == nil {
		return types.DefaultFormulaParams()
	}
	var p types.FormulaParams
	if err := json.Unmarshal(bz, &p); err != nil {
		return types.DefaultFormulaParams()
	}
	return p
}

// SetFormulaParams validates + writes the reward-formula params (JSON).
func (k Keeper) SetFormulaParams(ctx sdk.Context, p types.FormulaParams) error {
	if err := p.Validate(); err != nil {
		return err
	}
	bz, err := json.Marshal(p)
	if err != nil {
		return err
	}
	ctx.KVStore(k.storeKey).Set(types.FormulaParamsKey, bz)
	return nil
}

// FormulaActive reports whether the reward FORMULA should drive rewards (params enabled + the
// staking/distribution keepers wired). Otherwise BeginBlock uses the legacy fixed stream.
func (k Keeper) FormulaActive(ctx sdk.Context) bool {
	return k.stakingKeeper != nil && k.distrKeeper != nil && k.GetFormulaParams(ctx).Enabled
}

// ReserveAddress is the module account that holds the validator-reward reserve.
func (k Keeper) ReserveAddress() sdk.AccAddress {
	return authtypes.NewModuleAddress(types.ModuleName)
}

func (k Keeper) Logger(ctx sdk.Context) log.Logger {
	return ctx.Logger().With("module", "x/"+types.ModuleName)
}

// GetParams reads the module params (JSON-encoded).
func (k Keeper) GetParams(ctx sdk.Context) types.Params {
	store := ctx.KVStore(k.storeKey)
	bz := store.Get(types.ParamsKey)
	if bz == nil {
		return types.DefaultParams()
	}
	var p types.Params
	if err := json.Unmarshal(bz, &p); err != nil {
		panic(err)
	}
	return p
}

// SetParams writes the module params.
func (k Keeper) SetParams(ctx sdk.Context, p types.Params) error {
	if err := p.Validate(); err != nil {
		return err
	}
	bz, err := json.Marshal(p)
	if err != nil {
		return err
	}
	ctx.KVStore(k.storeKey).Set(types.ParamsKey, bz)
	return nil
}
