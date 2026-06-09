package slashfunds_test

import (
	"context"
	"testing"

	"cosmossdk.io/math"
	sdk "github.com/cosmos/cosmos-sdk/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	"github.com/stretchr/testify/require"

	gtu "github.com/ivanovslavy/GembaBlockchain/chain/testutil"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/slashfunds"
)

const (
	denom  = "agmb"
	faucet = "faucet"
)

func coins(n int64) sdk.Coins { return sdk.NewCoins(sdk.NewCoin(denom, math.NewInt(n))) }

// The core invariant (§3.1, §5.6): a slash burns from the bonded pool, but the
// decorator must keep total supply UNCHANGED and deposit the slashed stake into
// the faucet reserve — punishing the validator by stake loss, not by destroying
// supply.
func TestSlashFromBondedPool_PreservesSupply_CreditsFaucet(t *testing.T) {
	ctx := context.Background()
	bank := gtu.NewBankFake()
	bank.FundModule(stakingtypes.BondedPoolName, coins(1000)) // a validator's bonded stake
	k := slashfunds.NewBankKeeper(bank, faucet)

	before := bank.GetSupply(ctx, denom).Amount
	require.NoError(t, k.BurnCoins(ctx, stakingtypes.BondedPoolName, coins(100))) // 10% slash

	require.Equal(t, before, bank.GetSupply(ctx, denom).Amount, "supply must be unchanged by slashing")
	require.Equal(t, int64(100), bank.BalanceOf(faucet, denom).Int64(), "slashed stake must land in the faucet")
	require.Equal(t, int64(900), bank.BalanceOf(stakingtypes.BondedPoolName, denom).Int64())
}

// Tombstone / double-sign slashes burn from the not-bonded pool too; same rule.
func TestSlashFromNotBondedPool_PreservesSupply_CreditsFaucet(t *testing.T) {
	ctx := context.Background()
	bank := gtu.NewBankFake()
	bank.FundModule(stakingtypes.NotBondedPoolName, coins(500))
	k := slashfunds.NewBankKeeper(bank, faucet)

	before := bank.GetSupply(ctx, denom).Amount
	require.NoError(t, k.BurnCoins(ctx, stakingtypes.NotBondedPoolName, coins(50)))

	require.Equal(t, before, bank.GetSupply(ctx, denom).Amount)
	require.Equal(t, int64(50), bank.BalanceOf(faucet, denom).Int64())
}

// A burn from a non-staking module is NOT redirected — it still burns and reduces
// supply. No such caller exists on this chain, but the pass-through must be
// faithful so we don't silently change unrelated bank behaviour.
func TestNonStakingBurn_PassesThrough(t *testing.T) {
	ctx := context.Background()
	bank := gtu.NewBankFake()
	bank.FundModule("erc20", coins(100))
	k := slashfunds.NewBankKeeper(bank, faucet)

	before := bank.GetSupply(ctx, denom).Amount
	require.NoError(t, k.BurnCoins(ctx, "erc20", coins(100)))

	require.True(t, bank.GetSupply(ctx, denom).Amount.LT(before), "non-staking burn must still reduce supply")
	require.Equal(t, int64(0), bank.BalanceOf(faucet, denom).Int64(), "non-staking burn must not touch the faucet")
}

// Canary: prove the model is sensitive — a raw burn from the bonded pool really
// does reduce supply (this is the default Cosmos behaviour that cost the testnet
// 10 GMB). It makes the redirect tests above meaningful.
func TestRawBurn_Canary_ReducesSupply(t *testing.T) {
	ctx := context.Background()
	bank := gtu.NewBankFake()
	bank.FundModule(stakingtypes.BondedPoolName, coins(1000))

	before := bank.GetSupply(ctx, denom).Amount
	require.NoError(t, bank.BurnCoins(ctx, stakingtypes.BondedPoolName, coins(10)))
	require.Equal(t, before.Sub(math.NewInt(10)), bank.GetSupply(ctx, denom).Amount,
		"a raw burn must reduce supply — otherwise the redirect tests prove nothing")
}

// Pass-through fidelity: a non-burn staking call still works through the embedded
// keeper (so wrapping the bank keeper doesn't break normal staking flows).
func TestNonBurnMethod_PassesThrough(t *testing.T) {
	ctx := context.Background()
	bank := gtu.NewBankFake()
	bank.FundModule(stakingtypes.NotBondedPoolName, coins(100))
	k := slashfunds.NewBankKeeper(bank, faucet)

	require.NoError(t, k.SendCoinsFromModuleToModule(ctx, stakingtypes.NotBondedPoolName, stakingtypes.BondedPoolName, coins(40)))
	require.Equal(t, int64(60), bank.BalanceOf(stakingtypes.NotBondedPoolName, denom).Int64())
	require.Equal(t, int64(40), bank.BalanceOf(stakingtypes.BondedPoolName, denom).Int64())
}

// An empty faucet module name is a wiring bug; fail loud rather than route slashed
// funds to a bogus account.
func TestNewBankKeeper_RejectsEmptyFaucet(t *testing.T) {
	require.Panics(t, func() { slashfunds.NewBankKeeper(gtu.NewBankFake(), "") })
}
