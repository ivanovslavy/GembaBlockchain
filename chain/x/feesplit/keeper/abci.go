package keeper

import (
	"github.com/cosmos/cosmos-sdk/telemetry"
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
			// Observability (audit AU-1): a recurring skip silently disables the 40% fee->faucet
			// flow while blocks keep producing. Surface it as a Prometheus counter
			// (gemba_feesplit_skipped_blocks) so /monitoring can alert. Fail-soft is unchanged.
			telemetry.IncrCounter(1, "gemba", "feesplit", "skipped_blocks")
			err = nil
		}
	}()
	if _, e := k.SplitFees(ctx); e != nil {
		ctx.Logger().Error("feesplit: SplitFees failed; skipping this block's split", "err", e)
		telemetry.IncrCounter(1, "gemba", "feesplit", "skipped_blocks")
	}
	return nil
}
