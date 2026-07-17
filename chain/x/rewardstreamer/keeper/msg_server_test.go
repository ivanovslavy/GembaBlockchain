package keeper_test

import (
	"testing"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
	authtypes "github.com/cosmos/cosmos-sdk/x/auth/types"
	govtypes "github.com/cosmos/cosmos-sdk/x/gov/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	"github.com/stretchr/testify/require"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/keeper"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

func govAuthority() string { return authtypes.NewModuleAddress(govtypes.ModuleName).String() }

func msgFrom(p types.FormulaParams, authority string) *types.MsgUpdateFormulaParams {
	return &types.MsgUpdateFormulaParams{
		Authority:      authority,
		Enabled:        p.Enabled,
		RatePerDay:     p.RatePerDay,
		FloorPerDay:    p.FloorPerDay,
		CapPerDay:      p.CapPerDay,
		BlocksPerDay:   p.BlocksPerDay,
		RewardDenom:    p.RewardDenom,
		MaxTotalPerDay: p.MaxTotalPerDay,
	}
}

// TestUpdateFormulaParams_RejectsNonGov: only the gov module account may retune the
// formula (audit M2) — any other signer, including the module's own address, is refused
// and state is untouched.
func TestUpdateFormulaParams_RejectsNonGov(t *testing.T) {
	ctx, k, _ := setup(t)
	ms := keeper.NewMsgServerImpl(k)
	before := k.GetFormulaParams(ctx)

	p := types.DefaultFormulaParams()
	p.CapPerDay = gmb(999)
	for _, bad := range []string{
		sdk.AccAddress([]byte("not-gov-------------")).String(),
		authtypes.NewModuleAddress(types.ModuleName).String(),
		"",
	} {
		_, err := ms.UpdateFormulaParams(ctx, msgFrom(p, bad))
		require.ErrorContains(t, err, "invalid authority")
	}
	require.Equal(t, before, k.GetFormulaParams(ctx), "rejected msg must not mutate params")
}

// TestUpdateFormulaParams_GovUpdates: the gov authority can retune every field at
// runtime and the new values persist (and validation still runs).
func TestUpdateFormulaParams_GovUpdates(t *testing.T) {
	ctx, k, _ := setup(t)
	ms := keeper.NewMsgServerImpl(k)

	p := types.FormulaParams{
		Enabled:        true,
		RatePerDay:     math.LegacyNewDecWithPrec(2, 2), // 0.02
		FloorPerDay:    gmb(5),
		CapPerDay:      gmb(50),
		BlocksPerDay:   36_000,
		RewardDenom:    denom,
		MaxTotalPerDay: gmb(5_479),
	}
	_, err := ms.UpdateFormulaParams(ctx, msgFrom(p, govAuthority()))
	require.NoError(t, err)
	require.Equal(t, p, k.GetFormulaParams(ctx))

	// Invalid params (cap < floor) are refused by SetFormulaParams' validation.
	bad := p
	bad.CapPerDay = gmb(1)
	_, err = ms.UpdateFormulaParams(ctx, msgFrom(bad, govAuthority()))
	require.Error(t, err)
	require.Equal(t, p, k.GetFormulaParams(ctx), "invalid msg must not mutate params")
}

// TestUpdateFormulaParams_KillSwitch is the M2 scenario end-to-end: governance passes
// enabled=false and the formula stream halts on the next block — no chain upgrade.
func TestUpdateFormulaParams_KillSwitch(t *testing.T) {
	ctx, k, bank := setup(t)
	bank.FundModule(types.ModuleName, sdk.NewCoins(sdk.NewCoin(denom, gmb(1_000_000))))

	msStaking := mockStaking{vals: []stakingtypes.Validator{valWith("val-10k-------------", 10_000)}}
	md := &mockDistr{alloc: map[string]math.Int{}}
	k = k.WithFormulaKeepers(msStaking, md)
	require.NoError(t, k.SetFormulaParams(ctx, types.DefaultFormulaParams()))
	require.True(t, k.FormulaActive(ctx), "formula runs before the kill-switch")

	off := types.DefaultFormulaParams()
	off.Enabled = false
	_, err := keeper.NewMsgServerImpl(k).UpdateFormulaParams(ctx, msgFrom(off, govAuthority()))
	require.NoError(t, err)
	require.False(t, k.FormulaActive(ctx), "gov kill-switch must halt the formula stream")

	reserveBefore := bank.BalanceOf(types.ModuleName, denom)
	streamed, err := k.StreamFormulaRewards(ctx)
	require.NoError(t, err)
	require.True(t, streamed.IsZero(), "disabled formula must stream nothing")
	require.Equal(t, reserveBefore, bank.BalanceOf(types.ModuleName, denom), "reserve untouched after kill-switch")
}
