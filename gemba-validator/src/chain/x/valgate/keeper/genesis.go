package keeper

import (
	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/types"
)

// InitGenesis sets the params from genesis.
func (k Keeper) InitGenesis(ctx sdk.Context, gs types.GenesisState) {
	if err := k.SetParams(ctx, gs.Params); err != nil {
		panic(err)
	}
}

// ExportGenesis exports the current params.
func (k Keeper) ExportGenesis(ctx sdk.Context) *types.GenesisState {
	return &types.GenesisState{Params: k.GetParams(ctx)}
}
