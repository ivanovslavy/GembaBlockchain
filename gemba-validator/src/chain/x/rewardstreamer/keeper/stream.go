package keeper

import (
	"fmt"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

// StreamRewards moves this block's reward slice from the validator-reward reserve
// into the fee collector. It NEVER mints: it only transfers pre-minted GMB, so
// total supply is unchanged (zero-inflation invariant §3.1). When the reserve is
// exhausted it streams nothing and validators live on fees alone (CLAUDE.md §5.4).
// Returns the amount actually streamed this block.
func (k Keeper) StreamRewards(ctx sdk.Context) (math.Int, error) {
	params := k.GetParams(ctx)
	if !params.Enabled {
		return math.ZeroInt(), nil
	}

	// Don't stream on the very first block. At height 1 the distribution module
	// has no previous-block votes to allocate against, so it won't pay out the
	// fee collector that block; a reward streamed at height 1 would linger and be
	// picked up by the next block's feesplit (leaking the validator reward to the
	// faucet). From height 2 on, distribution drains the fee collector in the same
	// block the reward is added, so the reward reaches validators in full.
	if ctx.BlockHeight() <= 1 {
		return math.ZeroInt(), nil
	}

	perBlock := params.PerBlockReward()
	if !perBlock.IsPositive() {
		return math.ZeroInt(), nil
	}

	denom := params.RewardDenom
	available := k.bankKeeper.GetBalance(ctx, k.ReserveAddress(), denom).Amount
	if !available.IsPositive() {
		// Reserve depleted (~10 yrs in): the stream stops, fees take over.
		k.emit(ctx, math.ZeroInt(), available, true)
		return math.ZeroInt(), nil
	}

	amount := math.MinInt(perBlock, available)
	coins := sdk.NewCoins(sdk.NewCoin(denom, amount))

	// Transfer reserve -> fee collector. Distribution pays it out to validators
	// and delegators. This is the only state change: a move of pre-minted coins.
	if err := k.bankKeeper.SendCoinsFromModuleToModule(ctx, types.ModuleName, k.feeCollectorName, coins); err != nil {
		return math.ZeroInt(), fmt.Errorf("rewardstreamer: stream to fee collector failed: %w", err)
	}

	remaining := available.Sub(amount)
	k.emit(ctx, amount, remaining, remaining.IsZero())
	return amount, nil
}

func (k Keeper) emit(ctx sdk.Context, amount, reserveBalance math.Int, depleted bool) {
	ctx.EventManager().EmitEvent(sdk.NewEvent(
		types.EventTypeStreamReward,
		sdk.NewAttribute(types.AttributeKeyAmount, amount.String()),
		sdk.NewAttribute(types.AttributeKeyReserveBalance, reserveBalance.String()),
		sdk.NewAttribute(types.AttributeKeyDepleted, fmt.Sprintf("%t", depleted)),
	))
}
