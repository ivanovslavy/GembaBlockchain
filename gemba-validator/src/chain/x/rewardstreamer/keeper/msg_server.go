package keeper

import (
	"context"
	"fmt"

	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"
	govtypes "github.com/cosmos/cosmos-sdk/x/gov/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

type msgServer struct{ Keeper }

// NewMsgServerImpl returns the Msg server for the rewardstreamer module.
func NewMsgServerImpl(k Keeper) types.MsgServer { return &msgServer{Keeper: k} }

// UpdateParams sets the module params. Only the gov module account (the deterministic
// governance authority) may call it (audit finding #5).
func (m msgServer) UpdateParams(goCtx context.Context, msg *types.MsgUpdateParams) (*types.MsgUpdateParamsResponse, error) {
	authority := authtypes.NewModuleAddress(govtypes.ModuleName).String()
	if msg.Authority != authority {
		return nil, fmt.Errorf("invalid authority: expected %s (gov), got %s", authority, msg.Authority)
	}
	ctx := sdk.UnwrapSDKContext(goCtx)
	if err := m.SetParams(ctx, msg.Params); err != nil {
		return nil, err
	}
	return &types.MsgUpdateParamsResponse{}, nil
}

// UpdateFormulaParams sets the reward-FORMULA params at runtime — the governance
// kill-switch / retune lever for the reward stream (audit M2): enabled=false halts
// formula payouts on the next block, no chain upgrade needed. Gov-only, like
// UpdateParams; validation happens inside SetFormulaParams.
func (m msgServer) UpdateFormulaParams(goCtx context.Context, msg *types.MsgUpdateFormulaParams) (*types.MsgUpdateFormulaParamsResponse, error) {
	authority := authtypes.NewModuleAddress(govtypes.ModuleName).String()
	if msg.Authority != authority {
		return nil, fmt.Errorf("invalid authority: expected %s (gov), got %s", authority, msg.Authority)
	}
	ctx := sdk.UnwrapSDKContext(goCtx)
	p := types.FormulaParams{
		Enabled:        msg.Enabled,
		RatePerDay:     msg.RatePerDay,
		FloorPerDay:    msg.FloorPerDay,
		CapPerDay:      msg.CapPerDay,
		BlocksPerDay:   msg.BlocksPerDay,
		RewardDenom:    msg.RewardDenom,
		MaxTotalPerDay: msg.MaxTotalPerDay,
	}
	if err := m.SetFormulaParams(ctx, p); err != nil {
		return nil, err
	}
	ctx.EventManager().EmitEvent(sdk.NewEvent(
		types.EventTypeUpdateFormulaParams,
		sdk.NewAttribute(types.AttributeKeyAuthority, msg.Authority),
		sdk.NewAttribute(types.AttributeKeyEnabled, fmt.Sprintf("%t", msg.Enabled)),
	))
	return &types.MsgUpdateFormulaParamsResponse{}, nil
}
