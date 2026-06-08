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
func (k Keeper) BeginBlock(ctx sdk.Context) (err error) {
	// Fail soft like x/feesplit (audit finding #5): a bank error/panic must never halt the
	// chain — skipping one block's reward is supply-safe. recover() also catches panics
	// (e.g. an unexpected SendRestriction), not just returned errors.
	defer func() {
		if r := recover(); r != nil {
			ctx.Logger().Error("rewardstreamer: StreamRewards panicked; skipping this block", "panic", r)
			err = nil
		}
	}()
	if _, e := k.StreamRewards(ctx); e != nil {
		ctx.Logger().Error("rewardstreamer: StreamRewards failed; skipping this block", "err", e)
	}
	return nil
}
