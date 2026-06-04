// Package tests holds the cross-module integration tests for the Phase 2 custom
// chain modules. The marquee test is TestSupplyInvariantOverBlocks: a permanent
// machine guarantee that with rewards actively streaming and fees splitting
// 60/40, the total GMB supply NEVER changes (zero-inflation invariant §3.1).
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
	rskeeper "github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/keeper"
	rstypes "github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

const (
	denom        = "agmb"
	usersAccount = "users"      // models fee-paying users
	valAccount   = "validators" // models the distribution payout sink
)

type harness struct {
	ctx  sdk.Context
	bank *gtu.BankFake
	rs   rskeeper.Keeper
	fs   fskeeper.Keeper
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	rsKey := storetypes.NewKVStoreKey(rstypes.StoreKey)
	fsKey := storetypes.NewKVStoreKey(fstypes.StoreKey)
	ctx := sdktestutil.DefaultContextWithKeys(
		map[string]*storetypes.KVStoreKey{rstypes.StoreKey: rsKey, fstypes.StoreKey: fsKey},
		map[string]*storetypes.TransientStoreKey{"t1": storetypes.NewTransientStoreKey("t1")},
		nil,
	)
	ctx = ctx.WithBlockHeight(10) // past the first-block streaming guard
	bank := gtu.NewBankFake()
	return &harness{
		ctx:  ctx,
		bank: bank,
		rs:   rskeeper.NewKeeper(rsKey, bank),
		fs:   fskeeper.NewKeeper(fsKey, bank),
	}
}

func coin(n int64) sdk.Coins { return sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(n))) }

// runBlock simulates one block's worth of the GembaBlockchain reward/fee cycle in
// the canonical order: collect fees -> feesplit -> rewardstreamer -> distribution.
func (h *harness) runBlock(t *testing.T, feePerBlock int64) {
	t.Helper()
	// 1. Fees collected during the block: users pay into the fee collector.
	require.NoError(t, h.bank.SendCoinsFromModuleToModule(h.ctx, usersAccount, authtypes.FeeCollectorName, coin(feePerBlock)))
	// 2. feesplit: 40% of fees -> faucet (BEFORE the reward is added).
	require.NoError(t, h.fs.BeginBlock(h.ctx))
	// 3. rewardstreamer: stream the validator reward into the fee collector.
	require.NoError(t, h.rs.BeginBlock(h.ctx))
	// 4. distribution (simulated): pay out everything left in the fee collector
	//    (60% of fees + the streamed reward) to validators/delegators.
	left := h.bank.BalanceOf(authtypes.FeeCollectorName, denom)
	if left.IsPositive() {
		require.NoError(t, h.bank.SendCoinsFromModuleToModule(h.ctx, authtypes.FeeCollectorName, valAccount, sdk.NewCoins(sdk.NewCoin(denom, left))))
	}
}

// TestSupplyInvariantOverBlocks is THE invariant: run many blocks with rewards
// streaming and fees splitting, and assert total supply is byte-for-byte constant
// at every block. If anyone ever makes the streamer mint, this test fails forever.
func TestSupplyInvariantOverBlocks(t *testing.T) {
	h := newHarness(t)

	// Genesis (one-time mint): 2000 reserve + 10000 with users = 12000 total.
	h.bank.FundModule(rstypes.ModuleName, coin(2000))
	h.bank.FundModule(usersAccount, coin(10000))

	require.NoError(t, h.rs.SetParams(h.ctx, rstypes.Params{
		Enabled: true, RewardDenom: denom, AnnualReward: math.NewInt(1000), BlocksPerYear: 10, // perBlock = 100
	}))
	require.NoError(t, h.fs.SetParams(h.ctx, fstypes.DefaultParams())) // 40% to faucet

	const initialSupply = int64(12000)
	require.Equal(t, initialSupply, h.bank.GetSupply(h.ctx, denom).Amount.Int64())

	const blocks = 10
	const feePerBlock = 50
	for i := 0; i < blocks; i++ {
		h.runBlock(t, feePerBlock)
		// THE INVARIANT, checked every single block:
		require.Equal(t, initialSupply, h.bank.GetSupply(h.ctx, denom).Amount.Int64(),
			"total supply changed at block %d — the streamer minted instead of recirculating", i+1)
	}

	// Conservation accounting after 10 blocks (reward 100/blk, fee 50/blk @ 40/60):
	require.Equal(t, int64(1000), h.bank.BalanceOf(rstypes.ModuleName, denom).Int64(), "reserve drained by 10*100")
	require.Equal(t, int64(200), h.bank.BalanceOf(fstypes.DefaultFaucetAccount, denom).Int64(), "faucet got 10*40% of 50")
	require.Equal(t, int64(1300), h.bank.BalanceOf(valAccount, denom).Int64(), "validators got 10*(60%*50 + 100)")
	require.Equal(t, int64(9500), h.bank.BalanceOf(usersAccount, denom).Int64(), "users paid 10*50 in fees")
	require.Equal(t, initialSupply, h.bank.GetSupply(h.ctx, denom).Amount.Int64())
}

// TestSupplyCheckDetectsMinting is the canary: it proves the supply metric used
// above is actually sensitive to minting, so the invariant test is non-trivial.
func TestSupplyCheckDetectsMinting(t *testing.T) {
	bank := gtu.NewBankFake()
	bank.FundModule(rstypes.ModuleName, coin(1000))
	before := bank.GetSupply(sdk.Context{}, denom).Amount

	bank.Mint(rstypes.ModuleName, coin(500)) // a rogue mint the modules cannot do

	after := bank.GetSupply(sdk.Context{}, denom).Amount
	require.Equal(t, int64(500), after.Sub(before).Int64(),
		"GetSupply must rise by exactly the minted amount — proves the invariant assertion can fail on a mint")
}

// TestDemo prints the block-by-block ledger as the in-process live demonstration
// that rewards flow without supply growth and fees split 60/40. Run with -v.
func TestDemo(t *testing.T) {
	h := newHarness(t)
	h.bank.FundModule(rstypes.ModuleName, coin(2000))
	h.bank.FundModule(usersAccount, coin(10000))
	require.NoError(t, h.rs.SetParams(h.ctx, rstypes.Params{
		Enabled: true, RewardDenom: denom, AnnualReward: math.NewInt(1000), BlocksPerYear: 10,
	}))
	require.NoError(t, h.fs.SetParams(h.ctx, fstypes.DefaultParams()))

	get := func(m string) int64 { return h.bank.BalanceOf(m, denom).Int64() }
	t.Logf("GembaBlockchain Phase 2 demo: reward=100/blk, fee=50/blk split 60/40")
	t.Logf("%-6s %10s %8s %12s %10s", "block", "reserve", "faucet", "validators", "SUPPLY")
	t.Logf("%-6s %10d %8d %12d %10d", "gen", get(rstypes.ModuleName), get(fstypes.DefaultFaucetAccount), get(valAccount), h.bank.GetSupply(h.ctx, denom).Amount.Int64())
	for i := 0; i < 5; i++ {
		h.runBlock(t, 50)
		t.Logf("%-6d %10d %8d %12d %10d", i+1, get(rstypes.ModuleName), get(fstypes.DefaultFaucetAccount), get(valAccount), h.bank.GetSupply(h.ctx, denom).Amount.Int64())
	}
	t.Logf("supply constant across all blocks => rewards recirculate, never minted (ADR-008)")
}
