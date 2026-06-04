package types

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

// BankKeeper is the subset of the bank keeper the reward streamer uses.
//
// IMPORTANT (zero-inflation invariant §3.1): this interface DELIBERATELY omits
// MintCoins and BurnCoins. The reward streamer is therefore *structurally
// incapable* of changing the total supply — it can only move pre-minted GMB out
// of the reserve via SendCoinsFromModuleToModule. Zero inflation is enforced here
// at the type level, not merely by convention. Do not widen this interface to
// add minting (docs/risks.md ADR-008).
type BankKeeper interface {
	GetBalance(ctx context.Context, addr sdk.AccAddress, denom string) sdk.Coin
	GetSupply(ctx context.Context, denom string) sdk.Coin
	SendCoinsFromModuleToModule(ctx context.Context, senderModule, recipientModule string, amt sdk.Coins) error
}

// AccountKeeper is the subset used to resolve the reserve module account address.
type AccountKeeper interface {
	GetModuleAddress(moduleName string) sdk.AccAddress
}
