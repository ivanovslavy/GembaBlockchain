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
	"github.com/ivanovslavy/GembaBlockchain/chain/x/feesplit/keeper"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/feesplit/types"
)

const denom = "agmb"

func setup(t *testing.T) (sdk.Context, keeper.Keeper, *gtu.BankFake) {
	t.Helper()
	key := storetypes.NewKVStoreKey(types.StoreKey)
	tkey := storetypes.NewTransientStoreKey("transient_feesplit")
	ctx := sdktestutil.DefaultContext(key, tkey)
	bank := gtu.NewBankFake()
	k := keeper.NewKeeper(key, bank)
	return ctx, k, bank
}

// TestSplit6040 verifies the canonical 60/40 split (CLAUDE.md §5.4).
func TestSplit6040(t *testing.T) {
	ctx, k, bank := setup(t)
	require.NoError(t, k.SetParams(ctx, types.DefaultParams())) // 0.40 to faucet

	// 1000 in fees collected.
	bank.FundModule(authtypes.FeeCollectorName, sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(1000))))

	moved, err := k.SplitFees(ctx)
	require.NoError(t, err)
	require.Equal(t, int64(400), moved.AmountOf(denom).Int64())

	// 40% -> faucet, 60% remains for distribution to validators.
	require.Equal(t, int64(400), bank.BalanceOf(types.DefaultFaucetAccount, denom).Int64())
	require.Equal(t, int64(600), bank.BalanceOf(authtypes.FeeCollectorName, denom).Int64())

	// Supply unchanged: a split is a move, never a mint.
	require.Equal(t, int64(1000), bank.GetSupply(ctx, denom).Amount.Int64())
}

// TestSplitTruncationConservesSupply checks odd amounts: dust stays with
// validators and no coins are created or destroyed.
func TestSplitTruncationConservesSupply(t *testing.T) {
	ctx, k, bank := setup(t)
	require.NoError(t, k.SetParams(ctx, types.DefaultParams()))

	// 7 agmb: 40% = 2.8 -> truncated to 2 to the faucet, 5 stays.
	bank.FundModule(authtypes.FeeCollectorName, sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(7))))
	moved, err := k.SplitFees(ctx)
	require.NoError(t, err)
	require.Equal(t, int64(2), moved.AmountOf(denom).Int64())
	require.Equal(t, int64(5), bank.BalanceOf(authtypes.FeeCollectorName, denom).Int64())
	require.Equal(t, int64(7), bank.GetSupply(ctx, denom).Amount.Int64())
}

// TestDisabledNoSplit verifies the off-switch leaves all fees with validators.
func TestDisabledNoSplit(t *testing.T) {
	ctx, k, bank := setup(t)
	p := types.DefaultParams()
	p.Enabled = false
	require.NoError(t, k.SetParams(ctx, p))
	bank.FundModule(authtypes.FeeCollectorName, sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(1000))))

	moved, err := k.SplitFees(ctx)
	require.NoError(t, err)
	require.True(t, moved.IsZero())
	require.Equal(t, int64(1000), bank.BalanceOf(authtypes.FeeCollectorName, denom).Int64())
	require.Equal(t, int64(0), bank.BalanceOf(types.DefaultFaucetAccount, denom).Int64())
}
