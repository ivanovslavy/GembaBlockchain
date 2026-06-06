package keeper

import (
	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BeginBlock streams the per-block tail reward.
//
// ORDERING (enforced in app wiring): like x/rewardstreamer, this runs AFTER
// x/feesplit (so the streamed tail is not subject to the 60/40 fee skim) and
// BEFORE x/distribution (so it is in the fee collector when distribution pays
// validators):  feesplit -> rewardstreamer -> tailreward -> distribution.
func (k Keeper) BeginBlock(ctx sdk.Context) error {
	_, err := k.StreamTailReward(ctx)
	return err
}
