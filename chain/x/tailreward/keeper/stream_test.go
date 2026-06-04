package keeper_test

import (
	"testing"

	"cosmossdk.io/math"

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdktestutil "github.com/cosmos/cosmos-sdk/testutil"
	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"

	"github.com/stretchr/testify/require"

	gtu "github.com/ivanovslavy/GembaBlockchain/chain/testutil"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/keeper"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/types"
)

const denom = "agmb"

func setup(t *testing.T) (sdk.Context, keeper.Keeper, *gtu.BankFake) {
	t.Helper()
	key := storetypes.NewKVStoreKey(types.StoreKey)
	tkey := storetypes.NewTransientStoreKey("transient_tailreward")
	ctx := sdktestutil.DefaultContext(key, tkey).WithBlockHeight(10) // past the first-block guard
	bank := gtu.NewBankFake()
	return ctx, keeper.NewKeeper(key, bank), bank
}

func enabled(annual int64, blocksPerYear uint64) types.Params {
	return types.Params{Enabled: true, RewardDenom: denom, AnnualReward: math.NewInt(annual), BlocksPerYear: blocksPerYear}
}

// TestTailRecirculatesNeverMints: streaming moves coins from the recirculation
// buffer into the fee collector and leaves total supply UNCHANGED.
func TestTailRecirculatesNeverMints(t *testing.T) {
	ctx, k, bank := setup(t)
	require.NoError(t, k.SetParams(ctx, enabled(1000, 10))) // perBlock = 100

	bank.FundModule(types.ModuleName, sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(250))))
	require.Equal(t, int64(250), bank.GetSupply(ctx, denom).Amount.Int64())

	amt, err := k.StreamTailReward(ctx)
	require.NoError(t, err)
	require.Equal(t, int64(100), amt.Int64())
	require.Equal(t, int64(150), bank.BalanceOf(types.ModuleName, denom).Int64())
	require.Equal(t, int64(100), bank.BalanceOf(authtypes.FeeCollectorName, denom).Int64())
	require.Equal(t, int64(250), bank.GetSupply(ctx, denom).Amount.Int64(), "supply must not change")

	_, _ = k.StreamTailReward(ctx) // block 2: -> buffer 50
	amt, err = k.StreamTailReward(ctx) // block 3: only 50 left -> streams 50
	require.NoError(t, err)
	require.Equal(t, int64(50), amt.Int64())
	require.Equal(t, int64(0), bank.BalanceOf(types.ModuleName, denom).Int64())

	amt, err = k.StreamTailReward(ctx) // buffer empty -> nothing
	require.NoError(t, err)
	require.True(t, amt.IsZero())

	require.Equal(t, int64(250), bank.GetSupply(ctx, denom).Amount.Int64())
}

// TestDisabledByDefaultStreamsNothing: the tail is dormant until governance enables it.
func TestDisabledByDefaultStreamsNothing(t *testing.T) {
	ctx, k, bank := setup(t)
	require.NoError(t, k.SetParams(ctx, types.DefaultParams())) // disabled
	bank.FundModule(types.ModuleName, sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(250))))

	amt, err := k.StreamTailReward(ctx)
	require.NoError(t, err)
	require.True(t, amt.IsZero())
	require.Equal(t, int64(250), bank.BalanceOf(types.ModuleName, denom).Int64())
}
