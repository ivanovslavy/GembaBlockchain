package keeper

import (
	"cosmossdk.io/log/v2"

	"github.com/cosmos/cosmos-sdk/codec"
	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/types"
)

// Keeper stores the governance-tunable validator-gate params.
type Keeper struct {
	cdc       codec.BinaryCodec
	storeKey  storetypes.StoreKey
	authority string // the gov module account; only it may UpdateParams
}

// NewKeeper builds the valgate keeper.
func NewKeeper(cdc codec.BinaryCodec, storeKey storetypes.StoreKey, authority string) Keeper {
	return Keeper{cdc: cdc, storeKey: storeKey, authority: authority}
}

// GetAuthority returns the gov authority address.
func (k Keeper) GetAuthority() string { return k.authority }

func (k Keeper) Logger(ctx sdk.Context) log.Logger {
	return ctx.Logger().With("module", "x/"+types.ModuleName)
}

// GetParams reads the module params (proto-encoded; default if unset).
func (k Keeper) GetParams(ctx sdk.Context) types.Params {
	bz := ctx.KVStore(k.storeKey).Get(types.ParamsKey)
	if bz == nil {
		return types.DefaultParams()
	}
	var p types.Params
	k.cdc.MustUnmarshal(bz, &p)
	return p
}

// SetParams validates and writes the module params.
func (k Keeper) SetParams(ctx sdk.Context, p types.Params) error {
	if err := p.Validate(); err != nil {
		return err
	}
	ctx.KVStore(k.storeKey).Set(types.ParamsKey, k.cdc.MustMarshal(&p))
	return nil
}
