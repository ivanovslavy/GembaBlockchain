package types

import (
	"fmt"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

// DefaultBlocksPerYear assumes ~2s blocks (CLAUDE.md §1).
const DefaultBlocksPerYear uint64 = 15_778_476

// DefaultRewardDenom is atto-GMB.
const DefaultRewardDenom = "agmb"


// DefaultParams returns a DISABLED tail with sane shape; governance enables and
// sizes it when the reserve nears depletion.
func DefaultParams() Params {
	return Params{
		Enabled:       false,
		RewardDenom:   DefaultRewardDenom,
		AnnualReward:  math.ZeroInt(),
		BlocksPerYear: DefaultBlocksPerYear,
	}
}

// PerBlockReward is the integer amount streamed each block (floor division).
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
