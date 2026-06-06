package tests

import (
	"testing"

	"cosmossdk.io/math"

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdktestutil "github.com/cosmos/cosmos-sdk/testutil"
	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"

	"github.com/stretchr/testify/require"

	gtu "github.com/ivanovslavy/GembaBlockchain/chain/testutil"
	fskeeper "github.com/ivanovslavy/GembaBlockchain/chain/x/feesplit/keeper"
	fstypes "github.com/ivanovslavy/GembaBlockchain/chain/x/feesplit/types"
	trkeeper "github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/keeper"
	trtypes "github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/types"
)

// TestTailRewardSupplyInvariant is the SAME machine guarantee as the reward
// streamer's, applied to the post-reserve tail reward (ADR-008b): with the tail
// recirculating GMB from its buffer and fees splitting, total supply is constant
// every block. If the tail ever minted instead of recirculating, this fails.
func TestTailRewardSupplyInvariant(t *testing.T) {
	trKey := storetypes.NewKVStoreKey(trtypes.StoreKey)
	fsKey := storetypes.NewKVStoreKey(fstypes.StoreKey)
	ctx := sdktestutil.DefaultContextWithKeys(
		map[string]*storetypes.KVStoreKey{trtypes.StoreKey: trKey, fstypes.StoreKey: fsKey},
		map[string]*storetypes.TransientStoreKey{"t1": storetypes.NewTransientStoreKey("t1")},
		nil,
	).WithBlockHeight(10)

	bank := gtu.NewBankFake()
	tr := trkeeper.NewKeeper(trKey, bank)
	fs := fskeeper.NewKeeper(fsKey, bank)

	// Genesis (one-time mint): 2000 in the recirculation buffer + 10000 with users.
	bank.FundModule(trtypes.ModuleName, coin(2000))
	bank.FundModule(usersAccount, coin(10000))
	const initialSupply = int64(12000)

	require.NoError(t, tr.SetParams(ctx, trtypes.Params{
		Enabled: true, RewardDenom: denom, AnnualReward: math.NewInt(1000), BlocksPerYear: 10, // perBlock = 100
	}))
	require.NoError(t, fs.SetParams(ctx, fstypes.DefaultParams()))
	require.Equal(t, initialSupply, bank.GetSupply(ctx, denom).Amount.Int64())

	const feePerBlock = 50
	for i := 0; i < 10; i++ {
		// fees collected; feesplit (40% -> faucet); tailreward (buffer -> fee collector);
		// distribution (drain fee collector -> validators).
		require.NoError(t, bank.SendCoinsFromModuleToModule(ctx, usersAccount, authtypes.FeeCollectorName, coin(feePerBlock)))
		require.NoError(t, fs.BeginBlock(ctx))
		require.NoError(t, tr.BeginBlock(ctx))
		left := bank.BalanceOf(authtypes.FeeCollectorName, denom)
		if left.IsPositive() {
			require.NoError(t, bank.SendCoinsFromModuleToModule(ctx, authtypes.FeeCollectorName, valAccount, sdk.NewCoins(sdk.NewCoin(denom, left))))
		}
		require.Equal(t, initialSupply, bank.GetSupply(ctx, denom).Amount.Int64(),
			"total supply changed at block %d — the tail reward minted instead of recirculating", i+1)
	}

	require.Equal(t, int64(1000), bank.BalanceOf(trtypes.ModuleName, denom).Int64(), "buffer drained 10*100")
	require.Equal(t, int64(200), bank.BalanceOf(fstypes.DefaultFaucetAccount, denom).Int64(), "faucet got 10*40% of 50")
	require.Equal(t, int64(1300), bank.BalanceOf(valAccount, denom).Int64(), "validators got 10*(60%*50 + 100)")
	require.Equal(t, initialSupply, bank.GetSupply(ctx, denom).Amount.Int64())
}
