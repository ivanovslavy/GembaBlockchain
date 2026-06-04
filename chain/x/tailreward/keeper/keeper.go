package keeper

import (
	"encoding/json"

	"cosmossdk.io/log/v2"

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/types"
)

// Keeper manages the post-reserve tail reward (recirculation buffer → validators).
type Keeper struct {
	storeKey         storetypes.StoreKey
	feeCollectorName string
	bankKeeper       types.BankKeeper
}

// NewKeeper builds the tail reward keeper.
func NewKeeper(storeKey storetypes.StoreKey, bk types.BankKeeper) Keeper {
	return Keeper{
		storeKey:         storeKey,
		feeCollectorName: authtypes.FeeCollectorName,
		bankKeeper:       bk,
	}
}

// BufferAddress is the module account that holds the recirculation buffer
// (funded by governance from fee-funded reserves).
func (k Keeper) BufferAddress() sdk.AccAddress {
	return authtypes.NewModuleAddress(types.ModuleName)
}

func (k Keeper) Logger(ctx sdk.Context) log.Logger {
	return ctx.Logger().With("module", "x/"+types.ModuleName)
}

// GetParams reads the module params (JSON-encoded).
func (k Keeper) GetParams(ctx sdk.Context) types.Params {
	bz := ctx.KVStore(k.storeKey).Get(types.ParamsKey)
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
