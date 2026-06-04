package types

import (
	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BankKeeper is the subset of the bank keeper the fee split uses.
//
// As with the reward streamer, this interface DELIBERATELY omits MintCoins /
// BurnCoins: the fee split can only move already-collected fees between module
// accounts, never change total supply (zero-inflation invariant §3.1).
type BankKeeper interface {
	GetAllBalances(ctx sdk.Context, addr sdk.AccAddress) sdk.Coins
	SendCoinsFromModuleToModule(ctx sdk.Context, senderModule, recipientModule string, amt sdk.Coins) error
}
