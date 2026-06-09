// Package testutil provides a faithful in-memory bank model used to test the
// custom chain modules without standing up a full Cosmos app.
//
// Fidelity is the whole point: the model tracks total supply as the SUM of all
// account balances. SendCoinsFromModuleToModule (and Undelegate/Delegate) MOVE
// coins between accounts, so they conserve supply by construction. Supply changes
// in exactly two places, both of which the production gemba modules cannot reach
// (their BankKeeper interfaces omit mint/burn): Mint INCREASES it, BurnCoins
// DECREASES it. Those two are the canaries — they let the supply-invariance tests
// prove that x/feesplit / x/rewardstreamer recirculate rather than mint, and that
// x/slashfunds redirects slashed stake to the faucet rather than burning it.
package testutil

import (
	"context"
	"fmt"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"
)

// BankFake implements the full x/staking BankKeeper surface (a superset of what
// feesplit / rewardstreamer need), so it can also back the x/slashfunds tests.
var _ stakingtypes.BankKeeper = (*BankFake)(nil)

// BankFake is an in-memory bank keeper keyed by account address string.
type BankFake struct {
	balances map[string]sdk.Coins
}

// NewBankFake returns an empty in-memory bank.
func NewBankFake() *BankFake {
	return &BankFake{balances: make(map[string]sdk.Coins)}
}

func (b *BankFake) get(addr sdk.AccAddress) sdk.Coins {
	c, ok := b.balances[addr.String()]
	if !ok {
		return sdk.NewCoins()
	}
	return c
}

func (b *BankFake) set(addr sdk.AccAddress, coins sdk.Coins) {
	b.balances[addr.String()] = coins
}

// FundModule credits a module account at genesis. This models the genesis mint;
// it is the ONLY supply-increasing operation available, and is test-setup only.
func (b *BankFake) FundModule(module string, coins sdk.Coins) {
	addr := authtypes.NewModuleAddress(module)
	b.set(addr, b.get(addr).Add(coins...))
}

// Mint increases supply out of thin air for a named account. It exists ONLY so
// tests can prove the invariant check is sensitive (a canary): the production
// modules have no access to it. Never used by module code.
func (b *BankFake) Mint(module string, coins sdk.Coins) {
	b.FundModule(module, coins)
}

// --- rewardstreamer/feesplit BankKeeper methods ---

func (b *BankFake) GetBalance(_ context.Context, addr sdk.AccAddress, denom string) sdk.Coin {
	return sdk.NewCoin(denom, b.get(addr).AmountOf(denom))
}

func (b *BankFake) GetAllBalances(_ context.Context, addr sdk.AccAddress) sdk.Coins {
	return b.get(addr)
}

// GetSupply is the total across ALL accounts: the model's source of truth for
// total supply. If any code path created coins, this would rise.
func (b *BankFake) GetSupply(_ context.Context, denom string) sdk.Coin {
	total := math.ZeroInt()
	for _, coins := range b.balances {
		total = total.Add(coins.AmountOf(denom))
	}
	return sdk.NewCoin(denom, total)
}

// SendCoinsFromModuleToModule moves coins between module accounts. It errors on
// insufficient funds, so it can never overdraw (and thus never create) coins.
func (b *BankFake) SendCoinsFromModuleToModule(_ context.Context, sender, recipient string, amt sdk.Coins) error {
	from := authtypes.NewModuleAddress(sender)
	to := authtypes.NewModuleAddress(recipient)

	fromBal := b.get(from)
	newFrom, neg := fromBal.SafeSub(amt...)
	if neg {
		return fmt.Errorf("insufficient funds: %s has %s, need %s", sender, fromBal, amt)
	}
	b.set(from, newFrom)
	b.set(to, b.get(to).Add(amt...))
	return nil
}

// BalanceOf is a test helper returning a module account's balance of a denom.
func (b *BankFake) BalanceOf(module, denom string) math.Int {
	return b.get(authtypes.NewModuleAddress(module)).AmountOf(denom)
}

// --- additional x/staking BankKeeper surface (also used by x/slashfunds tests) ---

// BurnCoins removes coins from a module account WITHOUT crediting anyone, so it
// REDUCES total supply — the supply-decreasing counterpart to Mint. The production
// gemba modules cannot reach it (their interfaces omit it); x/staking can (via
// slashing), which is exactly why x/slashfunds intercepts it. Errors (never
// overdraws) on insufficient funds.
func (b *BankFake) BurnCoins(_ context.Context, module string, amt sdk.Coins) error {
	addr := authtypes.NewModuleAddress(module)
	newBal, neg := b.get(addr).SafeSub(amt...)
	if neg {
		return fmt.Errorf("insufficient funds to burn: %s has %s, need %s", module, b.get(addr), amt)
	}
	b.set(addr, newBal)
	return nil
}

// LockedCoins models a bank with no vesting/locks.
func (b *BankFake) LockedCoins(_ context.Context, _ sdk.AccAddress) sdk.Coins {
	return sdk.NewCoins()
}

// SpendableCoins is the full balance (nothing is locked in the model).
func (b *BankFake) SpendableCoins(_ context.Context, addr sdk.AccAddress) sdk.Coins {
	return b.get(addr)
}

// UndelegateCoinsFromModuleToAccount moves coins from a module account to an
// address (supply-conserving).
func (b *BankFake) UndelegateCoinsFromModuleToAccount(_ context.Context, module string, addr sdk.AccAddress, amt sdk.Coins) error {
	from := authtypes.NewModuleAddress(module)
	newFrom, neg := b.get(from).SafeSub(amt...)
	if neg {
		return fmt.Errorf("insufficient funds: %s has %s, need %s", module, b.get(from), amt)
	}
	b.set(from, newFrom)
	b.set(addr, b.get(addr).Add(amt...))
	return nil
}

// DelegateCoinsFromAccountToModule moves coins from an address to a module
// account (supply-conserving).
func (b *BankFake) DelegateCoinsFromAccountToModule(_ context.Context, addr sdk.AccAddress, module string, amt sdk.Coins) error {
	to := authtypes.NewModuleAddress(module)
	newFrom, neg := b.get(addr).SafeSub(amt...)
	if neg {
		return fmt.Errorf("insufficient funds: %s has %s, need %s", addr, b.get(addr), amt)
	}
	b.set(addr, newFrom)
	b.set(to, b.get(to).Add(amt...))
	return nil
}
