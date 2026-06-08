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
func (k Keeper) BeginBlock(ctx sdk.Context) (err error) {
	// Fail soft like x/feesplit (audit finding #5): a bank error/panic must never halt the
	// chain — skipping one block's tail reward is supply-safe. recover() also catches panics,
	// not just returned errors.
	defer func() {
		if r := recover(); r != nil {
			ctx.Logger().Error("tailreward: StreamTailReward panicked; skipping this block", "panic", r)
			err = nil
		}
	}()
	if _, e := k.StreamTailReward(ctx); e != nil {
		ctx.Logger().Error("tailreward: StreamTailReward failed; skipping this block", "err", e)
	}
	return nil
}
