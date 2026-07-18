package keeper

import (
	"context"
	"fmt"

	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"
	govtypes "github.com/cosmos/cosmos-sdk/x/gov/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/types"
)

type msgServer struct{ Keeper }

// NewMsgServerImpl returns the Msg server for the tailreward module.
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
