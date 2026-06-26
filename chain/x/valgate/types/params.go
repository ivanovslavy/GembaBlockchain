package types

import (
	"fmt"

	"cosmossdk.io/math"
)

// oneGmb is 10^18 agmb (GMB has 18 decimals).
var oneGmb = math.NewInt(1_000_000_000_000_000_000)

// DefaultMinSelfBondGmb is the launch minimum self-bond (CLAUDE.md §5.2).
const DefaultMinSelfBondGmb = 1000

// DefaultMaxSelfBondGmb is the launch MAXIMUM self-bond at validator creation — the
// anti-domination cap (§5.2). A new validator may enter with at most this self-stake, so no
// single party can grab an outsized share at once. Existing validators may still grow past it
// via ordinary delegation (e.g. auto-compounding). Governance-tunable; 0 = no cap.
const DefaultMaxSelfBondGmb = 10000

// DefaultParams returns the launch params: 1,000 GMB min, 10,000 GMB max self-bond at creation.
func DefaultParams() Params {
	return Params{
		MinSelfBond: math.NewInt(DefaultMinSelfBondGmb).Mul(oneGmb),
		MaxSelfBond: math.NewInt(DefaultMaxSelfBondGmb).Mul(oneGmb),
	}
}

// Validate checks the params are well-formed.
func (p Params) Validate() error {
	if p.MinSelfBond.IsNil() || p.MinSelfBond.IsNegative() {
		return fmt.Errorf("min_self_bond must be non-negative, got %s", p.MinSelfBond)
	}
	// max_self_bond: nil/0 = no cap. If set, it must be non-negative and >= the minimum.
	if !p.MaxSelfBond.IsNil() {
		if p.MaxSelfBond.IsNegative() {
			return fmt.Errorf("max_self_bond must be non-negative, got %s", p.MaxSelfBond)
		}
		if p.MaxSelfBond.IsPositive() && p.MaxSelfBond.LT(p.MinSelfBond) {
			return fmt.Errorf("max_self_bond %s must be >= min_self_bond %s", p.MaxSelfBond, p.MinSelfBond)
		}
	}
	return nil
}

// DefaultGenesis returns the default genesis.
func DefaultGenesis() *GenesisState { return &GenesisState{Params: DefaultParams()} }

// Validate checks the genesis is well-formed.
func (gs GenesisState) Validate() error { return gs.Params.Validate() }
