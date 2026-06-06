package valgate

import (
	"fmt"

	sdk "github.com/cosmos/cosmos-sdk/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/keeper"
)

// MinSelfBondDecorator rejects MsgCreateValidator whose self-delegation is below the
// governance-tunable Params.MinSelfBond. It is the §5.2 anti-spam validator floor.
type MinSelfBondDecorator struct {
	keeper keeper.Keeper
}

// NewMinSelfBondDecorator builds the ante decorator.
func NewMinSelfBondDecorator(k keeper.Keeper) MinSelfBondDecorator {
	return MinSelfBondDecorator{keeper: k}
}

// AnteHandle enforces the minimum self-bond at validator creation.
func (d MinSelfBondDecorator) AnteHandle(ctx sdk.Context, tx sdk.Tx, simulate bool, next sdk.AnteHandler) (sdk.Context, error) {
	min := d.keeper.GetParams(ctx).MinSelfBond
	for _, msg := range tx.GetMsgs() {
		if cv, ok := msg.(*stakingtypes.MsgCreateValidator); ok {
			if cv.Value.Amount.LT(min) {
				return ctx, fmt.Errorf("validator self-bond %s is below the minimum %s (governance-set, x/valgate)", cv.Value.Amount, min)
			}
		}
	}
	return next(ctx, tx, simulate)
}
