package types

import (
	"fmt"

	"cosmossdk.io/math"
)

// Params configures the fee split. Stored as JSON (no protobuf dependency).
type Params struct {
	// Enabled turns the split on/off (governance-tunable).
	Enabled bool `json:"enabled"`
	// FaucetFeeRatio is the fraction of collected fees routed to the faucet.
	// CLAUDE.md §5.4: 40% to the faucet, 60% to validators/delegators.
	FaucetFeeRatio math.LegacyDec `json:"faucet_fee_ratio"`
	// FaucetAccount is the module account that receives the faucet share.
	FaucetAccount string `json:"faucet_account"`
}

// DefaultParams returns the spec default 60/40 split (CLAUDE.md §5.4).
func DefaultParams() Params {
	return Params{
		Enabled:        true,
		FaucetFeeRatio: math.LegacyNewDecWithPrec(40, 2), // 0.40
		FaucetAccount:  DefaultFaucetAccount,
	}
}

// Validate checks params are well-formed.
func (p Params) Validate() error {
	if p.FaucetFeeRatio.IsNil() {
		return fmt.Errorf("faucet_fee_ratio must not be nil")
	}
	if p.FaucetFeeRatio.IsNegative() || p.FaucetFeeRatio.GT(math.LegacyOneDec()) {
		return fmt.Errorf("faucet_fee_ratio must be in [0,1], got %s", p.FaucetFeeRatio)
	}
	if p.Enabled && p.FaucetAccount == "" {
		return fmt.Errorf("faucet_account must be set when enabled")
	}
	return nil
}
