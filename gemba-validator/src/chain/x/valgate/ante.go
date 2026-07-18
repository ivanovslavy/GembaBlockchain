package valgate

import (
	"fmt"

	"cosmossdk.io/math"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/x/authz"
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

// AnteHandle enforces (1) the min/max self-bond at validator creation and (2) the per-validator
// daily bond-increase cap (§6) for delegations to an existing validator.
func (d MinSelfBondDecorator) AnteHandle(ctx sdk.Context, tx sdk.Tx, simulate bool, next sdk.AnteHandler) (sdk.Context, error) {
	p := d.keeper.GetParams(ctx)
	if err := checkMsgs(tx.GetMsgs(), p.MinSelfBond, p.MaxSelfBond, 0); err != nil {
		return ctx, err
	}
	// Daily cap: skip in simulate; enforce on real Check/Deliver. Rejecting an over-cap delegation
	// is a normal tx failure (the chain keeps running) — never a panic.
	if !simulate {
		if err := d.enforceDailyBond(ctx, tx.GetMsgs(), 0); err != nil {
			return ctx, err
		}
	}
	return next(ctx, tx, simulate)
}

// enforceDailyBond walks the message tree (unwrapping authz MsgExec) and records/enforces the §6
// per-validator daily bond-increase cap for each delegation to an EXISTING validator (MsgDelegate,
// and the destination of MsgBeginRedelegate). MsgCreateValidator's initial stake is the ENTRY
// (1k–10k, handled above), not a daily add.
func (d MinSelfBondDecorator) enforceDailyBond(ctx sdk.Context, msgs []sdk.Msg, depth int) error {
	if depth > maxAuthzDepth {
		return fmt.Errorf("authz MsgExec nesting too deep (max %d) — rejected by x/valgate", maxAuthzDepth)
	}
	for _, msg := range msgs {
		switch m := msg.(type) {
		case *stakingtypes.MsgDelegate:
			if va, err := sdk.ValAddressFromBech32(m.ValidatorAddress); err == nil {
				if err := d.keeper.CheckAndRecordDailyBond(ctx, va, m.Amount.Amount); err != nil {
					return err
				}
			}
		case *stakingtypes.MsgBeginRedelegate:
			if va, err := sdk.ValAddressFromBech32(m.ValidatorDstAddress); err == nil {
				if err := d.keeper.CheckAndRecordDailyBond(ctx, va, m.Amount.Amount); err != nil {
					return err
				}
			}
		case *authz.MsgExec:
			inner, err := m.GetMessages()
			if err != nil {
				return fmt.Errorf("x/valgate: cannot decode authz MsgExec inner messages: %w", err)
			}
			if err := d.enforceDailyBond(ctx, inner, depth+1); err != nil {
				return err
			}
		}
	}
	return nil
}

// maxAuthzDepth bounds recursion so a deeply nested MsgExec cannot grief the ante handler.
const maxAuthzDepth = 6

// checkMsgs walks the message tree, unwrapping authz MsgExec so a MsgCreateValidator nested
// inside MsgExec (which authz routes AFTER the ante phase — the canonical Cosmos bypass,
// audit finding #9) is still subject to the self-bond floor.
func checkMsgs(msgs []sdk.Msg, min, max math.Int, depth int) error {
	if depth > maxAuthzDepth {
		return fmt.Errorf("authz MsgExec nesting too deep (max %d) — rejected by x/valgate", maxAuthzDepth)
	}
	capped := !max.IsNil() && max.IsPositive() // max == 0/nil means "no cap"
	for _, msg := range msgs {
		if cv, ok := msg.(*stakingtypes.MsgCreateValidator); ok {
			if cv.Value.Amount.LT(min) {
				return fmt.Errorf("validator self-bond %s is below the minimum %s (governance-set, x/valgate)", cv.Value.Amount, min)
			}
			// Also require the committed MinSelfDelegation >= floor so staking PERMANENTLY
			// enforces it: otherwise an operator creates at the floor then self-undelegates
			// down to MinSelfDelegation, making the floor a one-time lockup (audit finding #4).
			if cv.MinSelfDelegation.LT(min) {
				return fmt.Errorf("validator min_self_delegation %s is below the minimum %s (governance-set, x/valgate)", cv.MinSelfDelegation, min)
			}
			// Anti-domination cap (§5.2): reject a NEW validator entering with a self-bond above
			// the maximum, so no single party grabs an outsized share of consensus power at once.
			// Only at creation — existing validators may grow past it via ordinary delegation.
			if capped && cv.Value.Amount.GT(max) {
				return fmt.Errorf("validator self-bond %s exceeds the maximum %s allowed at creation (governance-set anti-domination cap, x/valgate)", cv.Value.Amount, max)
			}
		}
		if exec, ok := msg.(*authz.MsgExec); ok {
			inner, err := exec.GetMessages()
			if err != nil {
				// fail closed: if the nested messages can't be decoded, reject rather than
				// let a CreateValidator slip through unchecked.
				return fmt.Errorf("x/valgate: cannot decode authz MsgExec inner messages: %w", err)
			}
			if err := checkMsgs(inner, min, max, depth+1); err != nil {
				return err
			}
		}
	}
	return nil
}
