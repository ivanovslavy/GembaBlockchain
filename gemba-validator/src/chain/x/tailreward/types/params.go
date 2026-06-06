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

// Params configures the tail reward. Stored as JSON (no protobuf dependency).
type Params struct {
	// Enabled turns the tail on/off. DEFAULT FALSE — the tail is dormant until
	// governance activates it (post-reserve, to defend the bonded ratio, ADR-008).
	Enabled bool `json:"enabled"`
	// RewardDenom is the coin streamed (GMB base denom).
	RewardDenom string `json:"reward_denom"`
	// AnnualReward is the total amount (base units) recirculated per year once
	// enabled. Governance sizes this to the recirculated-fee throughput; it is
	// bounded by the module account's balance, so it can never out-spend the
	// recirculation buffer (no mint, no deficit).
	AnnualReward math.Int `json:"annual_reward"`
	// BlocksPerYear divides AnnualReward into a per-block amount.
	BlocksPerYear uint64 `json:"blocks_per_year"`
}

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
