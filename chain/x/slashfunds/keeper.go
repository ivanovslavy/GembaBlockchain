// Package slashfunds keeps GembaBlockchain's supply fixed at 100M across slashing.
//
// Default Cosmos slashing BURNS the slashed stake: x/staking's Slash calls
// BankKeeper.BurnCoins on the bonded / not-bonded pools, which destroys those
// coins and lowers total supply. That contradicts two GembaBlockchain invariants —
// fixed supply / never burn (CLAUDE.md §3.1, §4.2) and "slashed stake → the
// faucet" (§5.6). On the live testnet this already cost 10 GMB once (a 1% downtime
// slash of val-3 burned 1% of its 1,000 GMB), dropping supply from 100,000,000 to
// 99,999,990 — see docs/risks.md ADR-013.
//
// This package fixes it with a thin decorator around the bank keeper handed to
// x/staking. The staking keeper's ONLY BurnCoins calls come from Slash
// (burnBondedTokens / burnNotBondedTokens, against the bonded / not-bonded pools),
// so we intercept exactly those and SendCoinsFromModuleToModule the slashed coins
// to the faucet (public/municipal) reserve instead of burning them. Every other
// bank method passes straight through. Nothing is minted or burned — the same
// zero-burn principle x/feesplit applies to fees.
//
// Slashing still PUNISHES the validator: it loses its bonded stake exactly as
// before (its delegation is reduced before the burn step). We only change where
// the forfeited coins go — to the public reserve, not to nowhere — so the
// deterrent is identical while supply stays whole and the loss becomes a public
// good (§6). The decorator has no mint/burn power of its own; it can only move
// already-existing coins between module accounts.
package slashfunds

import (
	"context"

	sdk "github.com/cosmos/cosmos-sdk/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"
)

// BankKeeper decorates the bank keeper given to x/staking. It satisfies
// stakingtypes.BankKeeper by embedding the real keeper and overrides only
// BurnCoins, redirecting slashing burns to the faucet reserve.
type BankKeeper struct {
	stakingtypes.BankKeeper // embedded: every method except BurnCoins passes through

	faucetModule string
}

// compile-time guarantee that the decorator is still a valid staking bank keeper.
var _ stakingtypes.BankKeeper = BankKeeper{}

// Event emitted every time a slash burn is redirected to the faucet instead of
// destroying supply. It exists for two reasons:
//   - Observability: a slash→faucet redirect now shows up in the block results, so
//     the zero-burn behaviour (§3.1, §5.6) is verifiable on-chain without guessing.
//   - Binary verifiability: this event-type string sits on the LIVE redirect path
//     (unlike the startup panic guard, which the compiler dead-code-eliminates
//     because faucetModule is a non-empty constant). So `grep slash_redirected` on
//     the binary actually proves slashfunds is wired in — see the pentest P-4 note.
const (
	EventTypeSlashRedirected = "slash_redirected"
	AttributeKeySourcePool   = "source_pool"   // bonded / not-bonded pool the burn came from
	AttributeKeyFaucet       = "faucet_module" // reserve the slashed stake was moved to
	AttributeKeyAmount       = "amount"
)

// NewBankKeeper wraps inner so that a slash (BurnCoins from the staking pools) is
// redirected to faucetModule instead of destroying supply. faucetModule must be a
// registered module account — the same "faucet" reserve x/feesplit feeds
// (feesplittypes.DefaultFaucetAccount).
func NewBankKeeper(inner stakingtypes.BankKeeper, faucetModule string) BankKeeper {
	if faucetModule == "" {
		// A wiring mistake here would silently route slashed funds to an empty
		// module name; fail loud at startup instead.
		panic("slashfunds: faucetModule must not be empty")
	}
	return BankKeeper{BankKeeper: inner, faucetModule: faucetModule}
}

// BurnCoins intercepts burns from the staking bonded / not-bonded pools — i.e.
// slashing — and moves the coins to the faucet reserve instead of burning them,
// so total supply is unchanged (§3.1, §5.6). A burn from any other module (none
// exist on this chain today) is forwarded to the real bank keeper unchanged.
func (k BankKeeper) BurnCoins(ctx context.Context, moduleName string, amt sdk.Coins) error {
	if moduleName == stakingtypes.BondedPoolName || moduleName == stakingtypes.NotBondedPoolName {
		if err := k.BankKeeper.SendCoinsFromModuleToModule(ctx, moduleName, k.faucetModule, amt); err != nil {
			return err
		}
		// Emit an observable, non-elidable marker on the redirect path: this is what
		// proves — both on-chain and in the shipped binary — that the slash landed in
		// the faucet instead of being burned (the startup panic guard is compiled out).
		sdk.UnwrapSDKContext(ctx).EventManager().EmitEvent(
			sdk.NewEvent(
				EventTypeSlashRedirected,
				sdk.NewAttribute(AttributeKeySourcePool, moduleName),
				sdk.NewAttribute(AttributeKeyFaucet, k.faucetModule),
				sdk.NewAttribute(AttributeKeyAmount, amt.String()),
			),
		)
		return nil
	}
	return k.BankKeeper.BurnCoins(ctx, moduleName, amt)
}
