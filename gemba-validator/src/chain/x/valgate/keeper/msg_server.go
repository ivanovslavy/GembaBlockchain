package keeper

import (
	"context"
	"fmt"

	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/types"
)

type msgServer struct{ Keeper }

// NewMsgServerImpl returns the Msg server for the valgate module.
func NewMsgServerImpl(k Keeper) types.MsgServer { return &msgServer{Keeper: k} }

// UpdateParams sets the validator-gate params (gov authority only).
func (m msgServer) UpdateParams(goCtx context.Context, msg *types.MsgUpdateParams) (*types.MsgUpdateParamsResponse, error) {
	if m.authority != msg.Authority {
		return nil, fmt.Errorf("invalid authority: expected %s, got %s", m.authority, msg.Authority)
	}
	ctx := sdk.UnwrapSDKContext(goCtx)
	if err := m.SetParams(ctx, msg.Params); err != nil {
		return nil, err
	}
	return &types.MsgUpdateParamsResponse{}, nil
}
