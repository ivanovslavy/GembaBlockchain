package valgate

import (
	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/keeper"
)

// DailyBondRecorder applies the §6 per-validator daily bond-increase charge AFTER a transaction's
// messages have run, and only if they SUCCEEDED.
//
// WHY THIS IS NOT IN THE ANTE. The cap used to be checked and recorded in one step, in the ante.
// Ante state writes are deliberately kept when a message later fails — that is how gas and the
// account sequence survive a failed transaction — so a delegation that passed the ante and then
// reverted still burned the validator's entire day. Found on a devnet on 2026-10-03: a delegation
// failed with `insufficient funds`, the stake did not move, and the counter read a full 50 of
// 50 GMB. Eighteen such rejections in a row had already been logged on the live testnet without
// anyone noticing what they cost.
//
// A post-handler is the right place because baseapp runs it in the SAME store branch as the
// messages: both are committed only if both succeed, and both are reverted if either fails. So the
// charge is now atomic with the delegation it pays for. baseapp also returns before the
// post-handler in CheckTx mode, which means the §6 counter is no longer written during CheckTx at
// all — closing our half of the stale-cached-counter failure that froze validator .83 for thirteen
// days (docs/runbooks/validator-binary-refresh-2026-10.md).
//
// The ante still CHECKS the cap (read-only), so an over-cap delegation is refused in the mempool
// without executing anything. The EVM staking precompile keeps its own check-and-record inside
// CapEnforcingStakingMsgServer: that path runs during EVM execution, where the statedb journal
// already unwinds the charge if the call reverts, and it never reaches this decorator — a
// precompile delegation arrives as MsgEthereumTx, which carries no MsgDelegate to walk. Each path
// is therefore charged exactly once.
type DailyBondRecorder struct {
	keeper keeper.Keeper
}

// NewDailyBondRecorder builds the post-handler decorator. Chain it into the app's post-handler.
func NewDailyBondRecorder(k keeper.Keeper) DailyBondRecorder {
	return DailyBondRecorder{keeper: k}
}

var _ sdk.PostDecorator = DailyBondRecorder{}

// PostHandle records the day's bond increases for every validator the transaction bonded to.
func (d DailyBondRecorder) PostHandle(ctx sdk.Context, tx sdk.Tx, simulate, success bool, next sdk.PostHandler) (sdk.Context, error) {
	// simulate: the ante skips the cap in simulate as well, so estimating gas never charges anyone.
	// !success: the messages failed and their state is being thrown away — charging the day for a
	// delegation that never happened is the whole defect this decorator removes.
	if !simulate && success {
		incs, err := collectBondIncreases(tx.GetMsgs(), nil, 0)
		if err != nil {
			return ctx, err
		}
		for _, inc := range incs {
			// Check AND record: the ante's check was read-only and ran against pre-execution state,
			// so this is the authoritative one. An error here reverts the messages too (baseapp
			// discards the whole branch when a post-handler fails), which is the correct, fail-closed
			// outcome for a transaction that would exceed the cap.
			if err := d.keeper.CheckAndRecordDailyBond(ctx, inc.valoper, inc.amount); err != nil {
				return ctx, err
			}
		}
	}
	return next(ctx, tx, simulate, success)
}
