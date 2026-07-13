package keeper

import (
	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/types"
)

// InitGenesis sets the params from genesis.
func (k Keeper) InitGenesis(ctx sdk.Context, gs types.GenesisState) {
	// SEC audit H1: a genesis that OMITS max_self_bond / max_daily_bond_increase parses them as a
	// nil math.Int. SetParams then marshals nil as "0" (a NON-nil zero), after which GetParams'
	// nil-backfill no longer fires and the caps read as 0 = "no cap" — silently disabling the §5.2
	// anti-domination cap and the §6 daily-bond cap from block 1. Default the OMITTED (nil) caps
	// here, while the JSON value is still nil, so a genesis that simply doesn't mention them still
	// ships with the intended caps. An operator who truly wants "no cap" must set an explicit large
	// value, not rely on omission.
	def := types.DefaultParams()
	if gs.Params.MaxSelfBond.IsNil() {
		gs.Params.MaxSelfBond = def.MaxSelfBond
	}
	if gs.Params.MaxDailyBondIncrease.IsNil() {
		gs.Params.MaxDailyBondIncrease = def.MaxDailyBondIncrease
	}
	if err := k.SetParams(ctx, gs.Params); err != nil {
		panic(err)
	}
}

// ExportGenesis exports the current params.
func (k Keeper) ExportGenesis(ctx sdk.Context) *types.GenesisState {
	return &types.GenesisState{Params: k.GetParams(ctx)}
}
