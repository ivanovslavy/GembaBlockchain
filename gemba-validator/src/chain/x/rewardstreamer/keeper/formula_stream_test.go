package keeper_test

import (
	"context"
	"testing"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	"github.com/stretchr/testify/require"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

func gmb(n int64) math.Int { return math.NewInt(n).Mul(math.NewIntFromUint64(1_000_000_000_000_000_000)) }

func valWith(tag string, stakeGmb int64) stakingtypes.Validator {
	return stakingtypes.Validator{
		OperatorAddress: sdk.ValAddress([]byte(tag)).String(),
		Tokens:          gmb(stakeGmb),
	}
}

type mockStaking struct{ vals []stakingtypes.Validator }

func (m mockStaking) IterateBondedValidatorsByPower(_ context.Context, fn func(int64, stakingtypes.ValidatorI) bool) error {
	for i := range m.vals {
		if fn(int64(i), m.vals[i]) {
			break
		}
	}
	return nil
}

type mockDistr struct{ alloc map[string]math.Int }

func (m *mockDistr) AllocateTokensToValidator(_ context.Context, val stakingtypes.ValidatorI, tokens sdk.DecCoins) error {
	m.alloc[val.GetOperator()] = tokens.AmountOf(denom).TruncateInt()
	return nil
}

// TestStreamFormulaRewards proves the per-validator CAPPED allocation: a 20k validator gets the
// SAME per-block reward as a 10k one (cap holds), a 1k validator gets the floor — none get a
// proportional share. Supply is unchanged (coins only move reserve->distribution).
func TestStreamFormulaRewards(t *testing.T) {
	ctx, k, bank := setup(t)
	bank.FundModule(types.ModuleName, sdk.NewCoins(sdk.NewCoin(denom, gmb(1_000_000)))) // big reserve
	supplyBefore := bank.GetSupply(ctx, denom).Amount

	ms := mockStaking{vals: []stakingtypes.Validator{
		valWith("val-10k-------------", 10_000),
		valWith("val-20k-------------", 20_000),
		valWith("val-1k--------------", 1_000),
	}}
	md := &mockDistr{alloc: map[string]math.Int{}}
	k = k.WithFormulaKeepers(ms, md)
	require.NoError(t, k.SetFormulaParams(ctx, types.DefaultFormulaParams())) // 1%/day, 10–100 cap, 28800/day

	total, err := k.StreamFormulaRewards(ctx)
	require.NoError(t, err)
	require.True(t, total.IsPositive())

	fp := types.DefaultFormulaParams()
	want10k := fp.PerBlockReward(gmb(10_000))
	want20k := fp.PerBlockReward(gmb(20_000))
	want1k := fp.PerBlockReward(gmb(1_000))

	require.True(t, md.alloc[ms.vals[0].GetOperator()].Equal(want10k), "10k validator per-block")
	require.True(t, md.alloc[ms.vals[1].GetOperator()].Equal(want20k), "20k validator per-block")
	require.True(t, md.alloc[ms.vals[2].GetOperator()].Equal(want1k), "1k validator per-block")
	// THE cap: 20k and 10k get the SAME reward (both capped at 100/day), not proportional.
	require.True(t, md.alloc[ms.vals[1].GetOperator()].Equal(md.alloc[ms.vals[0].GetOperator()]),
		"20k must equal 10k (cap holds) — not double")
	// 1k gets the floor, less than the capped ones.
	require.True(t, md.alloc[ms.vals[2].GetOperator()].LT(md.alloc[ms.vals[0].GetOperator()]))

	// total moved = sum of allocations; supply unchanged (recirculation, never minted).
	require.True(t, total.Equal(want10k.Add(want20k).Add(want1k)))
	require.True(t, bank.GetSupply(ctx, denom).Amount.Equal(supplyBefore), "supply unchanged")
}

// TestStreamFormulaRewards_DisabledWhenNoKeepers: without injected keepers the formula is inert
// (BeginBlock falls back to the legacy stream); StreamFormulaRewards is a no-op.
func TestStreamFormulaRewards_DisabledWhenNoKeepers(t *testing.T) {
	ctx, k, bank := setup(t)
	bank.FundModule(types.ModuleName, sdk.NewCoins(sdk.NewCoin(denom, gmb(1000))))
	require.NoError(t, k.SetFormulaParams(ctx, types.DefaultFormulaParams()))
	amt, err := k.StreamFormulaRewards(ctx) // keepers not wired
	require.NoError(t, err)
	require.True(t, amt.IsZero())
	require.False(t, k.FormulaActive(ctx))
}
