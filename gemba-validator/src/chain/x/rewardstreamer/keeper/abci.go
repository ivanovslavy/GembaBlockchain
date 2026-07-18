package keeper

import (
	"github.com/cosmos/cosmos-sdk/telemetry"
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
			// Observability (audit AU-1): a recurring skip silently halts the validator-reward
			// stream while blocks keep producing. Surface it (gemba_rewardstreamer_skipped_blocks)
			// so /monitoring can alert. Fail-soft is unchanged.
			telemetry.IncrCounter(1, "gemba", "rewardstreamer", "skipped_blocks")
			err = nil
		}
	}()
	// Regenesis §4: when the reward FORMULA is active (params enabled + staking/distr keepers
	// wired) use the per-validator capped payout; otherwise fall back to the legacy fixed stream
	// (keeps existing devnets + tests working unchanged).
	if k.FormulaActive(ctx) {
		if _, e := k.StreamFormulaRewards(ctx); e != nil {
			ctx.Logger().Error("rewardstreamer: StreamFormulaRewards failed; skipping this block", "err", e)
			telemetry.IncrCounter(1, "gemba", "rewardstreamer", "skipped_blocks")
		}
	} else if _, e := k.StreamRewards(ctx); e != nil {
		ctx.Logger().Error("rewardstreamer: StreamRewards failed; skipping this block", "err", e)
		telemetry.IncrCounter(1, "gemba", "rewardstreamer", "skipped_blocks")
	}
	return nil
}
