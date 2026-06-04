// Package testutil provides a faithful in-memory bank model used to test the
// custom chain modules without standing up a full Cosmos app.
//
// Fidelity is the whole point: the model tracks total supply as the SUM of all
// account balances. SendCoinsFromModuleToModule MOVES coins between accounts, so
// it conserves supply by construction; the ONLY way supply changes is the
// explicit Mint helper (which the production modules cannot call — their
// BankKeeper interfaces omit minting). This is what lets the supply-invariance
// test prove the reward streamer recirculates rather than mints.
package testutil

import (
	"fmt"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"
)

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

func (b *BankFake) GetBalance(_ sdk.Context, addr sdk.AccAddress, denom string) sdk.Coin {
	return sdk.NewCoin(denom, b.get(addr).AmountOf(denom))
}

func (b *BankFake) GetAllBalances(_ sdk.Context, addr sdk.AccAddress) sdk.Coins {
	return b.get(addr)
}

// GetSupply is the total across ALL accounts: the model's source of truth for
// total supply. If any code path created coins, this would rise.
func (b *BankFake) GetSupply(_ sdk.Context, denom string) sdk.Coin {
	total := math.ZeroInt()
	for _, coins := range b.balances {
		total = total.Add(coins.AmountOf(denom))
	}
	return sdk.NewCoin(denom, total)
}

// SendCoinsFromModuleToModule moves coins between module accounts. It errors on
// insufficient funds, so it can never overdraw (and thus never create) coins.
func (b *BankFake) SendCoinsFromModuleToModule(_ sdk.Context, sender, recipient string, amt sdk.Coins) error {
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
