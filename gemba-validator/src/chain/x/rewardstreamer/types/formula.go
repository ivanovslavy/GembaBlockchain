package types

import (
	"fmt"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

// FormulaParams drives the regenesis reward model (§4 of the regenesis spec): each validator earns
// max(floor, min(cap, stake × rate)) GMB per day, streamed from the pre-minted reserve (never
// minted). Capping the reward decouples "income" from "stake size" above the cap point — more
// stake buys only more VOTE, not more reward — and bounds the reserve's daily drain.
//
// Stored under its own key (not the legacy proto Params) so it carries cleanly across genesis and
// can be made gov-tunable without disturbing the existing MsgUpdateParams wire format.
type FormulaParams struct {
	Enabled      bool           `json:"enabled"`
	RatePerDay   math.LegacyDec `json:"rate_per_day"`   // e.g. 0.01 = 1% of stake per day
	FloorPerDay  math.Int       `json:"floor_per_day"`  // agmb — minimum daily reward (10 GMB)
	CapPerDay    math.Int       `json:"cap_per_day"`    // agmb — maximum daily reward (100 GMB)
	BlocksPerDay uint64         `json:"blocks_per_day"` // ~28,800 at ~3s blocks (for per-block proration)
	RewardDenom  string         `json:"reward_denom"`   // agmb
	// MaxTotalPerDay is the AGGREGATE daily budget across ALL validators (agmb; 0 = no aggregate
	// cap). The per-validator cap alone lets total drain scale with validator count (N×cap/day),
	// so 150 validators at the 100 GMB cap would drain the 20M reserve in ~3.6y instead of the
	// intended ~10y (SEC audit M4). This ceiling pins the runway: below the budget every validator
	// gets its full formula reward (no change at small N); once the sum would exceed the budget all
	// allocations scale down pro-rata so the aggregate never exceeds it. Default ≈ 2M GMB/year.
	MaxTotalPerDay math.Int `json:"max_total_per_day"`
}

const oneGMB = 1_000_000_000_000_000_000

// DefaultFormulaParams: 1%/day, floor 10 GMB, cap 100 GMB, 28,800 blocks/day (~3s blocks),
// aggregate budget 5,479 GMB/day (≈ 2,000,000 GMB/year = the ~10-year runway on the 20M reserve).
func DefaultFormulaParams() FormulaParams {
	g := math.NewIntFromUint64(oneGMB)
	return FormulaParams{
		Enabled:        true,
		RatePerDay:     math.LegacyNewDecWithPrec(1, 2), // 0.01
		FloorPerDay:    math.NewInt(10).Mul(g),
		CapPerDay:      math.NewInt(100).Mul(g),
		BlocksPerDay:   28_800,
		RewardDenom:    "agmb",
		MaxTotalPerDay: math.NewInt(5_479).Mul(g), // ≈ 2M GMB/year
	}
}

// DailyReward returns the capped daily reward (agmb) for a validator with `stake` agmb bonded:
// max(floor, min(cap, stake × rate)). Deterministic (integer truncation).
func (p FormulaParams) DailyReward(stake math.Int) math.Int {
	if stake.IsNil() || !stake.IsPositive() {
		return math.ZeroInt()
	}
	r := math.LegacyNewDecFromInt(stake).Mul(p.RatePerDay).TruncateInt()
	if r.LT(p.FloorPerDay) {
		r = p.FloorPerDay
	}
	if r.GT(p.CapPerDay) {
		r = p.CapPerDay
	}
	return r
}

// PerBlockReward prorates the daily reward across BlocksPerDay (floor division — conservative,
// never over-pays the reserve). Per-block, per-validator amount in agmb.
func (p FormulaParams) PerBlockReward(stake math.Int) math.Int {
	if p.BlocksPerDay == 0 {
		return math.ZeroInt()
	}
	return p.DailyReward(stake).Quo(math.NewIntFromUint64(p.BlocksPerDay))
}

// MaxTotalPerBlock is the AGGREGATE per-block budget ceiling across all validators (agmb), i.e.
// MaxTotalPerDay prorated across BlocksPerDay. Zero/nil MaxTotalPerDay → zero (interpreted as "no
// aggregate cap" by the streamer). Deterministic floor division (SEC audit M4).
func (p FormulaParams) MaxTotalPerBlock() math.Int {
	if p.MaxTotalPerDay.IsNil() || !p.MaxTotalPerDay.IsPositive() || p.BlocksPerDay == 0 {
		return math.ZeroInt()
	}
	return p.MaxTotalPerDay.Quo(math.NewIntFromUint64(p.BlocksPerDay))
}

// Validate checks the formula params are well-formed.
func (p FormulaParams) Validate() error {
	if err := sdk.ValidateDenom(p.RewardDenom); err != nil {
		return fmt.Errorf("invalid reward_denom: %w", err)
	}
	if p.RatePerDay.IsNil() || p.RatePerDay.IsNegative() {
		return fmt.Errorf("rate_per_day must be non-negative, got %s", p.RatePerDay)
	}
	if p.FloorPerDay.IsNil() || p.FloorPerDay.IsNegative() {
		return fmt.Errorf("floor_per_day must be non-negative")
	}
	if p.CapPerDay.IsNil() || p.CapPerDay.IsNegative() {
		return fmt.Errorf("cap_per_day must be non-negative")
	}
	if !p.CapPerDay.IsZero() && p.CapPerDay.LT(p.FloorPerDay) {
		return fmt.Errorf("cap_per_day %s must be >= floor_per_day %s", p.CapPerDay, p.FloorPerDay)
	}
	if p.BlocksPerDay == 0 {
		return fmt.Errorf("blocks_per_day must be positive")
	}
	if p.MaxTotalPerDay.IsNil() || p.MaxTotalPerDay.IsNegative() {
		return fmt.Errorf("max_total_per_day must be non-negative (0 = no aggregate cap)")
	}
	return nil
}
