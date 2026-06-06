package types

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BankKeeper is the subset of the bank keeper the tail reward uses.
//
// IMPORTANT (zero-inflation invariant §3.1): like the reward streamer, this
// interface DELIBERATELY omits MintCoins and BurnCoins. The tail reward is
// therefore *structurally incapable* of changing total supply — it can only move
// pre-existing, recirculated GMB out of its buffer via SendCoinsFromModuleToModule.
// Zero inflation is enforced here at the type level. Do not widen this interface
// to add minting (docs/risks.md ADR-008).
type BankKeeper interface {
	GetBalance(ctx context.Context, addr sdk.AccAddress, denom string) sdk.Coin
	GetSupply(ctx context.Context, denom string) sdk.Coin
	SendCoinsFromModuleToModule(ctx context.Context, senderModule, recipientModule string, amt sdk.Coins) error
}
