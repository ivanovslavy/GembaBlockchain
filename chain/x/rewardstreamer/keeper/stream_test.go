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
	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/keeper"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

const denom = "agmb"

func setup(t *testing.T) (sdk.Context, keeper.Keeper, *gtu.BankFake) {
	t.Helper()
	key := storetypes.NewKVStoreKey(types.StoreKey)
	tkey := storetypes.NewTransientStoreKey("transient_rewardstreamer")
	ctx := sdktestutil.DefaultContext(key, tkey)
	bank := gtu.NewBankFake()
	k := keeper.NewKeeper(key, bank)
	return ctx, k, bank
}

func testParams(annual int64, blocksPerYear uint64) types.Params {
	return types.Params{
		Enabled:       true,
		RewardDenom:   denom,
		AnnualReward:  math.NewInt(annual),
		BlocksPerYear: blocksPerYear,
	}
}

// TestStreamRecirculatesNeverMints is the core property: streaming moves coins
// from the reserve into the fee collector and leaves total supply UNCHANGED.
func TestStreamRecirculatesNeverMints(t *testing.T) {
	ctx, k, bank := setup(t)
	require.NoError(t, k.SetParams(ctx, testParams(1000, 10))) // perBlock = 100

	// Reserve pre-minted with 250; nothing anywhere else.
	bank.FundModule(types.ModuleName, sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(250))))
	require.Equal(t, int64(250), bank.GetSupply(ctx, denom).Amount.Int64())

	// Block 1: stream full per-block 100.
	amt, err := k.StreamRewards(ctx)
	require.NoError(t, err)
	require.Equal(t, int64(100), amt.Int64())
	require.Equal(t, int64(150), bank.BalanceOf(types.ModuleName, denom).Int64())
	require.Equal(t, int64(100), bank.BalanceOf(authtypes.FeeCollectorName, denom).Int64())
	require.Equal(t, int64(250), bank.GetSupply(ctx, denom).Amount.Int64(), "supply must not change")

	// Block 2.
	amt, err = k.StreamRewards(ctx)
	require.NoError(t, err)
	require.Equal(t, int64(100), amt.Int64())
	require.Equal(t, int64(50), bank.BalanceOf(types.ModuleName, denom).Int64())

	// Block 3: only 50 left -> streams the remainder, not the full 100.
	amt, err = k.StreamRewards(ctx)
	require.NoError(t, err)
	require.Equal(t, int64(50), amt.Int64())
	require.Equal(t, int64(0), bank.BalanceOf(types.ModuleName, denom).Int64())
	require.Equal(t, int64(250), bank.BalanceOf(authtypes.FeeCollectorName, denom).Int64())

	// Block 4: reserve exhausted -> streams nothing (validators live on fees).
	amt, err = k.StreamRewards(ctx)
	require.NoError(t, err)
	require.Equal(t, int64(0), amt.Int64())

	// Supply identical to genesis after all streaming.
	require.Equal(t, int64(250), bank.GetSupply(ctx, denom).Amount.Int64())
}

// TestDisabledStreamsNothing verifies the governance off-switch.
func TestDisabledStreamsNothing(t *testing.T) {
	ctx, k, bank := setup(t)
	p := testParams(1000, 10)
	p.Enabled = false
	require.NoError(t, k.SetParams(ctx, p))
	bank.FundModule(types.ModuleName, sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(250))))

	amt, err := k.StreamRewards(ctx)
	require.NoError(t, err)
	require.True(t, amt.IsZero())
	require.Equal(t, int64(250), bank.BalanceOf(types.ModuleName, denom).Int64())
}

// TestPerBlockReward checks the spec default sizing (~2,000,000 GMB/yr).
func TestPerBlockReward(t *testing.T) {
	p := types.DefaultParams()
	// 2,000,000 GMB * 1e18 / 15,778,476 blocks ≈ 1.2676e17 agmb/block.
	per := p.PerBlockReward()
	require.True(t, per.IsPositive())
	// annual must reconstruct to ~2,000,000 GMB within one block of rounding.
	yearly := per.Mul(math.NewIntFromUint64(p.BlocksPerYear))
	twoMillion := math.NewInt(2_000_000).Mul(math.NewIntFromUint64(1_000_000_000_000_000_000))
	diff := twoMillion.Sub(yearly)
	require.True(t, diff.IsPositive() || diff.IsZero(), "floor division never over-pays")
	require.True(t, diff.LT(per), "under-pay is at most one block's reward")
}
