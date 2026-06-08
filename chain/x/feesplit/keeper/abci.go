package keeper

import (
	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BeginBlock splits the previous block's collected fees 60/40.
//
// ORDERING (enforced in app wiring): feesplit -> rewardstreamer -> distribution.
func (k Keeper) BeginBlock(ctx sdk.Context) (err error) {
	// Fail soft: a misconfigured FaucetAccount (or any bank issue) must NOT halt the chain
	// mid-consensus. SendCoinsFromModuleToModule PANICS (does not return an error) when the
	// recipient module account is unregistered, so we recover from panics too — not just
	// returned errors (audit findings #5 + #2). Skipping a block's split mints/loses nothing;
	// fees simply stay with validators for that block.
	defer func() {
		if r := recover(); r != nil {
			ctx.Logger().Error("feesplit: SplitFees panicked; skipping this block's split", "panic", r)
			err = nil
		}
	}()
	if _, e := k.SplitFees(ctx); e != nil {
		ctx.Logger().Error("feesplit: SplitFees failed; skipping this block's split", "err", e)
	}
	return nil
}
