package types

import (
	"fmt"

	"cosmossdk.io/math"
)

// Params is the proto-generated type (params.pb.go), governance-tunable via
// MsgUpdateParams (audit finding #5 — see tx.proto + keeper/msg_server.go). Fields:
// Enabled, FaucetFeeRatio (LegacyDec), FaucetAccount. Stored JSON-encoded by the keeper;
// the generated json tags (enabled/faucet_fee_ratio/faucet_account) match the prior layout.

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
	// Pin the faucet account to the one REGISTERED module account (DefaultFaucetAccount).
	// A free-form name that isn't registered makes the bank keeper PANIC in SplitFees every
	// block — caught by the BeginBlock recover() but silently disabling the 40% fee->faucet
	// split until governance re-corrects it (pentest F-1). The faucet identity must not change
	// casually, so reject any other value here: a bad MsgUpdateParams fails loud at execution
	// (and validate-genesis catches a bad genesis), instead of failing silently every block.
	if p.Enabled && p.FaucetAccount != DefaultFaucetAccount {
		return fmt.Errorf("faucet_account must be %q (the registered faucet module account), got %q", DefaultFaucetAccount, p.FaucetAccount)
	}
	return nil
}
