package keeper

import (
	"fmt"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
	distrtypes "github.com/cosmos/cosmos-sdk/x/distribution/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

// StreamFormulaRewards pays each bonded validator its CAPPED per-block reward
// (max(floor, min(cap, stake×rate)) / blocksPerDay) from the pre-minted reserve — never minting.
// Unlike the legacy fixed stream (a lump split proportionally by the distribution module, which
// would over-reward big validators), this credits each validator DIRECTLY so the per-validator cap
// holds: above the cap point more stake buys only more VOTE, not more reward (regenesis §4).
//
// Supply-safe: it only moves pre-minted GMB reserve->distribution and allocates it (§3.1). When the
// reserve can't cover the full round it scales the allocations down pro-rata (and stops at empty).
func (k Keeper) StreamFormulaRewards(ctx sdk.Context) (math.Int, error) {
	fp := k.GetFormulaParams(ctx)
	if !fp.Enabled || k.stakingKeeper == nil || k.distrKeeper == nil {
		return math.ZeroInt(), nil
	}
	// Like the legacy stream: skip height 1 (distribution has no prior-block votes yet).
	if ctx.BlockHeight() <= 1 {
		return math.ZeroInt(), nil
	}
	denom := fp.RewardDenom
	reserve := k.bankKeeper.GetBalance(ctx, k.ReserveAddress(), denom).Amount
	if !reserve.IsPositive() {
		return math.ZeroInt(), nil // reserve depleted → fees take over (§5.4)
	}

	type alloc struct {
		val stakingtypes.ValidatorI
		amt math.Int
	}
	var allocs []alloc
	total := math.ZeroInt()
	if err := k.stakingKeeper.IterateBondedValidatorsByPower(ctx, func(_ int64, v stakingtypes.ValidatorI) bool {
		pb := fp.PerBlockReward(v.GetTokens())
		if pb.IsPositive() {
			allocs = append(allocs, alloc{v, pb})
			total = total.Add(pb)
		}
		return false // keep iterating
	}); err != nil {
		return math.ZeroInt(), err
	}
	if !total.IsPositive() {
		return math.ZeroInt(), nil
	}

	// Reserve nearly empty: scale each allocation down pro-rata so we never overspend.
	if total.GT(reserve) {
		scaled := math.ZeroInt()
		for i := range allocs {
			allocs[i].amt = allocs[i].amt.Mul(reserve).Quo(total)
			scaled = scaled.Add(allocs[i].amt)
		}
		total = scaled
		if !total.IsPositive() {
			return math.ZeroInt(), nil
		}
	}

	// Move the round's total reserve -> distribution module, then credit each validator's pool.
	if err := k.bankKeeper.SendCoinsFromModuleToModule(
		ctx, types.ModuleName, distrtypes.ModuleName, sdk.NewCoins(sdk.NewCoin(denom, total)),
	); err != nil {
		return math.ZeroInt(), fmt.Errorf("rewardstreamer: move reserve->distribution failed: %w", err)
	}
	for _, a := range allocs {
		if !a.amt.IsPositive() {
			continue
		}
		dc := sdk.NewDecCoinsFromCoins(sdk.NewCoin(denom, a.amt))
		if err := k.distrKeeper.AllocateTokensToValidator(ctx, a.val, dc); err != nil {
			return math.ZeroInt(), fmt.Errorf("rewardstreamer: allocate to validator failed: %w", err)
		}
	}
	return total, nil
}
