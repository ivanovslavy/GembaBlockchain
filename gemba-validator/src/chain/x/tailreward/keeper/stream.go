package keeper

import (
	"fmt"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/types"
)

// StreamTailReward moves this block's tail slice from the recirculation buffer
// into the fee collector. It NEVER mints: it only transfers pre-existing,
// recirculated GMB, so total supply is unchanged (zero-inflation invariant §3.1).
// When the buffer is empty it streams nothing until governance refills it from the
// fee-funded reserves. Returns the amount actually streamed this block.
func (k Keeper) StreamTailReward(ctx sdk.Context) (math.Int, error) {
	params := k.GetParams(ctx)
	if !params.Enabled {
		return math.ZeroInt(), nil
	}

	// Don't stream on the very first block (same reasoning as x/rewardstreamer:
	// distribution has no prior-block votes at height 1, so a height-1 reward would
	// linger and be skimmed by feesplit).
	if ctx.BlockHeight() <= 1 {
		return math.ZeroInt(), nil
	}

	perBlock := params.PerBlockReward()
	if !perBlock.IsPositive() {
		return math.ZeroInt(), nil
	}

	denom := params.RewardDenom
	available := k.bankKeeper.GetBalance(ctx, k.BufferAddress(), denom).Amount
	if !available.IsPositive() {
		k.emit(ctx, math.ZeroInt(), available, true)
		return math.ZeroInt(), nil
	}

	amount := math.MinInt(perBlock, available)
	coins := sdk.NewCoins(sdk.NewCoin(denom, amount))

	// Transfer buffer -> fee collector. Distribution pays it to validators. Only a
	// move of pre-existing (recirculated) coins; no minting.
	if err := k.bankKeeper.SendCoinsFromModuleToModule(ctx, types.ModuleName, k.feeCollectorName, coins); err != nil {
		return math.ZeroInt(), fmt.Errorf("tailreward: stream to fee collector failed: %w", err)
	}

	remaining := available.Sub(amount)
	k.emit(ctx, amount, remaining, remaining.IsZero())
	return amount, nil
}

func (k Keeper) emit(ctx sdk.Context, amount, bufferBalance math.Int, depleted bool) {
	ctx.EventManager().EmitEvent(sdk.NewEvent(
		types.EventTypeTailReward,
		sdk.NewAttribute(types.AttributeKeyAmount, amount.String()),
		sdk.NewAttribute(types.AttributeKeyBufferBalance, bufferBalance.String()),
		sdk.NewAttribute(types.AttributeKeyDepleted, fmt.Sprintf("%t", depleted)),
	))
}
