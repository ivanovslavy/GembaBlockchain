package keeper

import (
	"context"
	"fmt"

	"cosmossdk.io/math"
	sdk "github.com/cosmos/cosmos-sdk/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"
)

// Hooks implements stakingtypes.StakingHooks. Its only non-trivial hook is
// AfterValidatorCreated, which enforces the §5.2 min-self-bond floor at the staking-keeper
// layer — so it covers BOTH validator-creation paths on an EVM chain: a Cosmos
// MsgCreateValidator AND the EVM staking precompile (0x…0800), which calls staking
// CreateValidator directly during EVM execution, after the ante phase (audit finding #1).
// The ante decorator stays as defense-in-depth for the Cosmos path.
type Hooks struct{ k Keeper }

var _ stakingtypes.StakingHooks = Hooks{}

// Hooks returns the staking hooks wrapper. Register it in the app's staking SetHooks set.
func (k Keeper) Hooks() Hooks { return Hooks{k: k} }

// AfterValidatorCreated rejects a validator whose committed MinSelfDelegation is below the
// governance floor. The SDK already enforces Value.Amount >= MinSelfDelegation at creation
// (MsgCreateValidator), so MinSelfDelegation >= floor implies the self-bond >= floor, and the
// floor is permanently enforced by staking on later self-undelegation (closes finding #4 too).
func (h Hooks) AfterValidatorCreated(ctx context.Context, valAddr sdk.ValAddress) error {
	p := h.k.GetParams(sdk.UnwrapSDKContext(ctx))
	min := p.MinSelfBond
	val, err := h.k.stakingKeeper.GetValidator(ctx, valAddr)
	if err != nil {
		return err
	}
	if val.MinSelfDelegation.LT(min) {
		return fmt.Errorf(
			"validator min_self_delegation %s is below the minimum %s (governance-set, x/valgate; enforced on Cosmos and EVM-precompile paths)",
			val.MinSelfDelegation, min,
		)
	}
	// Anti-domination cap (§5.2): at creation val.Tokens is the initial self-bond (no other
	// delegators yet). Reject if it exceeds the max. 0/nil = no cap. Covers the precompile path.
	if max := p.MaxSelfBond; !max.IsNil() && max.IsPositive() && !val.Tokens.IsNil() && val.Tokens.GT(max) {
		return fmt.Errorf(
			"validator self-bond %s exceeds the maximum %s allowed at creation (governance-set anti-domination cap, x/valgate; Cosmos + EVM-precompile paths)",
			val.Tokens, max,
		)
	}
	return nil
}

// --- remaining StakingHooks methods are no-ops ---

func (Hooks) BeforeValidatorModified(context.Context, sdk.ValAddress) error { return nil }
func (Hooks) AfterValidatorRemoved(context.Context, sdk.ConsAddress, sdk.ValAddress) error {
	return nil
}
func (Hooks) AfterValidatorBonded(context.Context, sdk.ConsAddress, sdk.ValAddress) error {
	return nil
}
func (Hooks) AfterValidatorBeginUnbonding(context.Context, sdk.ConsAddress, sdk.ValAddress) error {
	return nil
}
func (Hooks) BeforeDelegationCreated(context.Context, sdk.AccAddress, sdk.ValAddress) error {
	return nil
}
func (Hooks) BeforeDelegationSharesModified(context.Context, sdk.AccAddress, sdk.ValAddress) error {
	return nil
}
func (Hooks) BeforeDelegationRemoved(context.Context, sdk.AccAddress, sdk.ValAddress) error {
	return nil
}
func (Hooks) AfterDelegationModified(context.Context, sdk.AccAddress, sdk.ValAddress) error {
	return nil
}
func (Hooks) BeforeValidatorSlashed(context.Context, sdk.ValAddress, math.LegacyDec) error {
	return nil
}
func (Hooks) AfterUnbondingInitiated(context.Context, uint64) error { return nil }
