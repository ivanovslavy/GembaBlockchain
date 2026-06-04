package keeper

import (
	"fmt"

	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/feesplit/types"
)

// SplitFees routes the faucet share (default 40%) of the fees currently in the
// fee collector to the faucet account, leaving the remainder (60%) for the
// distribution module to pay validators/delegators. Truncation dust stays in the
// fee collector (so it accrues to validators); nothing is minted or burned, so
// total supply is unchanged (§3.1). Returns the coins moved to the faucet.
//
// ORDERING: must run BEFORE x/rewardstreamer and x/distribution in the block, so
// it splits only fees — never the streamed validator reward (see chain/README.md).
func (k Keeper) SplitFees(ctx sdk.Context) (sdk.Coins, error) {
	params := k.GetParams(ctx)
	if !params.Enabled || params.FaucetFeeRatio.IsZero() {
		return sdk.NewCoins(), nil
	}

	balances := k.bankKeeper.GetAllBalances(ctx, k.FeeCollectorAddress())
	if balances.IsZero() {
		return sdk.NewCoins(), nil
	}

	faucetCoins := sdk.NewCoins()
	for _, c := range balances {
		share := params.FaucetFeeRatio.MulInt(c.Amount).TruncateInt()
		if share.IsPositive() {
			faucetCoins = faucetCoins.Add(sdk.NewCoin(c.Denom, share))
		}
	}
	if faucetCoins.IsZero() {
		return sdk.NewCoins(), nil
	}

	if err := k.bankKeeper.SendCoinsFromModuleToModule(ctx, authtypes.FeeCollectorName, params.FaucetAccount, faucetCoins); err != nil {
		return nil, fmt.Errorf("feesplit: send to faucet failed: %w", err)
	}

	ctx.EventManager().EmitEvent(sdk.NewEvent(
		types.EventTypeFeeSplit,
		sdk.NewAttribute(types.AttributeKeyFaucetShare, faucetCoins.String()),
		sdk.NewAttribute(types.AttributeKeyFaucetAcct, params.FaucetAccount),
	))
	return faucetCoins, nil
}
