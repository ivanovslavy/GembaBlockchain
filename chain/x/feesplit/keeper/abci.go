package keeper

import (
	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BeginBlock splits the previous block's collected fees 60/40.
//
// ORDERING (enforced in app wiring): feesplit -> rewardstreamer -> distribution.
func (k Keeper) BeginBlock(ctx sdk.Context) error {
	// Fail soft: a misconfigured FaucetAccount (or any bank error) must NOT halt the chain
	// mid-consensus (audit finding #5). Log and skip this block's split — no coins are minted
	// or lost, fees simply stay with validators for the block. Returning the error would be
	// fatal to BeginBlock.
	if _, err := k.SplitFees(ctx); err != nil {
		k.Logger(ctx).Error("feesplit: SplitFees failed; skipping this block's split", "err", err)
	}
	return nil
}
