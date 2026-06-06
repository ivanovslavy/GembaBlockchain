package types

import (
	"fmt"

	"cosmossdk.io/math"
)

// oneGmb is 10^18 agmb (GMB has 18 decimals).
var oneGmb = math.NewInt(1_000_000_000_000_000_000)

// DefaultMinSelfBondGmb is the launch minimum self-bond (CLAUDE.md §5.2).
const DefaultMinSelfBondGmb = 1000

// DefaultParams returns the launch params: 1,000 GMB minimum self-bond.
func DefaultParams() Params {
	return Params{MinSelfBond: math.NewInt(DefaultMinSelfBondGmb).Mul(oneGmb)}
}

// Validate checks the params are well-formed.
func (p Params) Validate() error {
	if p.MinSelfBond.IsNil() || p.MinSelfBond.IsNegative() {
		return fmt.Errorf("min_self_bond must be non-negative, got %s", p.MinSelfBond)
	}
	return nil
}

// DefaultGenesis returns the default genesis.
func DefaultGenesis() *GenesisState { return &GenesisState{Params: DefaultParams()} }

// Validate checks the genesis is well-formed.
func (gs GenesisState) Validate() error { return gs.Params.Validate() }
