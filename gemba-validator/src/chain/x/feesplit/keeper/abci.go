package keeper

import (
	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BeginBlock splits the previous block's collected fees 60/40.
//
// ORDERING (enforced in app wiring): feesplit -> rewardstreamer -> distribution.
func (k Keeper) BeginBlock(ctx sdk.Context) error {
	_, err := k.SplitFees(ctx)
	return err
}
