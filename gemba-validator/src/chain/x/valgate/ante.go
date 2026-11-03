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
	// Daily cap: skip in simulate; CHECK (never record) on real Check/Deliver. Rejecting an
	// over-cap delegation is a normal tx failure (the chain keeps running) — never a panic.
	// The charge itself is applied by DailyBondRecorder, the post-handler, which runs only if the
	// messages succeeded; see posthandler.go for why that split matters.
	if !simulate {
		if err := d.checkDailyBond(ctx, tx.GetMsgs()); err != nil {
			return ctx, err
		}
	}
	return next(ctx, tx, simulate)
}

// checkDailyBond refuses, early and cheaply, a transaction that would push any validator over the
// §6 per-validator daily bond-increase cap. It WRITES NOTHING: the charge is applied once, after
// execution, by DailyBondRecorder (posthandler.go).
//
// It sums per validator across the whole transaction, so two 30 GMB delegations to the same
// validator in one transaction are refused here too, not only by the post-handler.
func (d MinSelfBondDecorator) checkDailyBond(ctx sdk.Context, msgs []sdk.Msg) error {
	incs, err := collectBondIncreases(msgs, nil, 0)
	if err != nil {
		return err
	}
	for _, inc := range incs {
		if err := d.keeper.CheckDailyBond(ctx, inc.valoper, inc.amount); err != nil {
			return err
		}
	}
	return nil
}

// bondIncrease is one validator's total stake increase within a single transaction.
type bondIncrease struct {
	valoper sdk.ValAddress
	amount  math.Int
}

// collectBondIncreases walks the message tree — unwrapping authz MsgExec, which the router executes
// AFTER the ante phase (the canonical Cosmos bypass, audit finding #9) — and sums, PER VALIDATOR,
// how much the transaction would add to that validator's BONDED stake: MsgDelegate, and the
// destination of MsgBeginRedelegate. MsgCreateValidator's initial stake is the ENTRY (1k–10k,
// checked separately by checkMsgs), not a daily add.
//
// The result is an ordered slice and deliberately NOT a map: this runs inside the state machine,
// where iterating a map would let two honest nodes walk the same transaction in different orders.
func collectBondIncreases(msgs []sdk.Msg, acc []bondIncrease, depth int) ([]bondIncrease, error) {
	if depth > maxAuthzDepth {
		return nil, fmt.Errorf("authz MsgExec nesting too deep (max %d) — rejected by x/valgate", maxAuthzDepth)
	}
	add := func(addr string, amt math.Int) {
		va, err := sdk.ValAddressFromBech32(addr)
		if err != nil || amt.IsNil() {
			return // an unparseable validator or a nil amount is the staking module's error to report
		}
		for i := range acc {
			if acc[i].valoper.Equals(va) {
				acc[i].amount = acc[i].amount.Add(amt)
				return
			}
		}
		acc = append(acc, bondIncrease{valoper: va, amount: amt})
	}
	for _, msg := range msgs {
		switch m := msg.(type) {
		case *stakingtypes.MsgDelegate:
			add(m.ValidatorAddress, m.Amount.Amount)
		case *stakingtypes.MsgBeginRedelegate:
			add(m.ValidatorDstAddress, m.Amount.Amount)
		case *authz.MsgExec:
			inner, err := m.GetMessages()
			if err != nil {
				// fail closed: undecodable inner messages must not slip past the cap
				return nil, fmt.Errorf("x/valgate: cannot decode authz MsgExec inner messages: %w", err)
			}
			acc, err = collectBondIncreases(inner, acc, depth+1)
			if err != nil {
				return nil, err
			}
		}
	}
	return acc, nil
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
