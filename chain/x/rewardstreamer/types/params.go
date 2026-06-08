package types

import (
	"fmt"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

// DefaultBlocksPerYear assumes ~2s blocks (CLAUDE.md §1):
// 365.2425 days * 24h * 3600s / 2s ≈ 15,778,476 blocks/year.
const DefaultBlocksPerYear uint64 = 15_778_476

// DefaultRewardDenom is atto-GMB (the EVM/bank base denom, 18 decimals).
const DefaultRewardDenom = "agmb"


// DefaultParams returns the spec defaults: 2,000,000 GMB/year (CLAUDE.md §4.3).
func DefaultParams() Params {
	// 2,000,000 GMB * 1e18 = annual reserve release, in agmb.
	annual := math.NewInt(2_000_000).Mul(math.NewIntFromUint64(1_000_000_000_000_000_000))
	return Params{
		Enabled:       true,
		RewardDenom:   DefaultRewardDenom,
		AnnualReward:  annual,
		BlocksPerYear: DefaultBlocksPerYear,
	}
}

// PerBlockReward is the integer amount streamed each block (floor division, so
// the stream is always slightly conservative and never over-pays the reserve).
func (p Params) PerBlockReward() math.Int {
	if p.BlocksPerYear == 0 {
		return math.ZeroInt()
	}
	if p.AnnualReward.IsNil() || !p.AnnualReward.IsPositive() {
		return math.ZeroInt()
	}
	return p.AnnualReward.Quo(math.NewIntFromUint64(p.BlocksPerYear))
}

// Validate checks params are well-formed.
func (p Params) Validate() error {
	if err := sdk.ValidateDenom(p.RewardDenom); err != nil {
		return fmt.Errorf("invalid reward_denom: %w", err)
	}
	if p.AnnualReward.IsNil() || p.AnnualReward.IsNegative() {
		return fmt.Errorf("annual_reward must be non-negative, got %s", p.AnnualReward)
	}
	if p.BlocksPerYear == 0 {
		return fmt.Errorf("blocks_per_year must be positive")
	}
	return nil
}
