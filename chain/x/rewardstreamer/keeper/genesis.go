package keeper

import (
	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

// InitGenesis sets module params from genesis.
func (k Keeper) InitGenesis(ctx sdk.Context, gs types.GenesisState) {
	if err := k.SetParams(ctx, gs.Params); err != nil {
		panic(err)
	}
	// SEC audit M2: persist FormulaParams (store key 0x02) from genesis so the reward formula
	// survives export/import instead of silently resetting to build-time defaults on any
	// upgrade/regenesis. Omitted in JSON → defaults (ResolvedFormulaParams).
	if err := k.SetFormulaParams(ctx, gs.ResolvedFormulaParams()); err != nil {
		panic(err)
	}
}

// ExportGenesis returns the module's genesis state.
func (k Keeper) ExportGenesis(ctx sdk.Context) *types.GenesisState {
	return &types.GenesisState{
		Params:        k.GetParams(ctx),
		FormulaParams: k.GetFormulaParams(ctx),
	}
}
