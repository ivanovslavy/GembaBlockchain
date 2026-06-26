package types_test

import (
	"testing"

	"cosmossdk.io/math"
	"github.com/stretchr/testify/require"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
)

func gmb(n int64) math.Int { return math.NewInt(n).Mul(math.NewIntFromUint64(1_000_000_000_000_000_000)) }

// TestDailyReward proves the §4 table: 1k→10, 5k→50, 10k→100, 20k→100 (cap holds above 10k).
func TestDailyReward(t *testing.T) {
	p := types.DefaultFormulaParams() // 1%/day, floor 10, cap 100 GMB
	cases := []struct {
		stakeGmb, wantGmb int64
	}{
		{1_000, 10},    // 1% = 10 → floor
		{900, 10},      // 1% = 9 → floor lifts to 10
		{5_000, 50},    // 1% = 50
		{10_000, 100},  // 1% = 100 → at the cap
		{20_000, 100},  // 1% = 200 → cap holds (no extra reward for hoarding)
		{1_000_000, 100}, // whale → still 100 (cap)
	}
	for _, c := range cases {
		got := p.DailyReward(gmb(c.stakeGmb))
		require.True(t, got.Equal(gmb(c.wantGmb)),
			"stake %d GMB → daily %s, want %d GMB", c.stakeGmb, got, c.wantGmb)
	}
}

// TestPerBlockReward: the daily reward is prorated across BlocksPerDay (floor division).
func TestPerBlockReward(t *testing.T) {
	p := types.DefaultFormulaParams() // 28,800 blocks/day
	// 10k validator → 100 GMB/day → 100e18 / 28800 per block.
	want := gmb(100).Quo(math.NewIntFromUint64(28_800))
	require.True(t, p.PerBlockReward(gmb(10_000)).Equal(want))
	// zero/negative stake → zero.
	require.True(t, p.PerBlockReward(math.ZeroInt()).IsZero())
}

func TestFormulaParamsValidate(t *testing.T) {
	require.NoError(t, types.DefaultFormulaParams().Validate())

	bad := types.DefaultFormulaParams()
	bad.CapPerDay = gmb(5) // cap < floor(10)
	require.Error(t, bad.Validate())

	bad2 := types.DefaultFormulaParams()
	bad2.BlocksPerDay = 0
	require.Error(t, bad2.Validate())

	bad3 := types.DefaultFormulaParams()
	bad3.RatePerDay = math.LegacyNewDec(-1)
	require.Error(t, bad3.Validate())
}
