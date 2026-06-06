package keeper

import (
	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BeginBlock streams the per-block validator reward.
//
// ORDERING (enforced in app wiring, see chain/README.md): this module's
// BeginBlocker must run AFTER x/feesplit (so the streamed reward is not subject
// to the 60/40 fee skim) and BEFORE x/distribution (so the streamed reward is in
// the fee collector when distribution allocates it to validators):
//
//	feesplit  ->  rewardstreamer  ->  distribution
func (k Keeper) BeginBlock(ctx sdk.Context) error {
	_, err := k.StreamRewards(ctx)
	return err
}
