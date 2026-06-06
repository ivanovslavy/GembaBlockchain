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
}

// NewKeeper builds the reward streamer keeper.
func NewKeeper(storeKey storetypes.StoreKey, bk types.BankKeeper) Keeper {
	return Keeper{
		storeKey:         storeKey,
		feeCollectorName: authtypes.FeeCollectorName,
		bankKeeper:       bk,
	}
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
