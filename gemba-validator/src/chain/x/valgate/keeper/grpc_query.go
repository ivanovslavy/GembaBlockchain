package keeper

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/types"
)

// Params implements the Query/Params gRPC endpoint.
func (k Keeper) Params(goCtx context.Context, _ *types.QueryParamsRequest) (*types.QueryParamsResponse, error) {
	return &types.QueryParamsResponse{Params: k.GetParams(sdk.UnwrapSDKContext(goCtx))}, nil
}
