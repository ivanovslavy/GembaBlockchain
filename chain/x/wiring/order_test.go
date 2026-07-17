package wiring_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	distrtypes "github.com/cosmos/cosmos-sdk/x/distribution/types"

	feesplittypes "github.com/ivanovslavy/GembaBlockchain/chain/x/feesplit/types"
	rewardstreamertypes "github.com/ivanovslavy/GembaBlockchain/chain/x/rewardstreamer/types"
	tailrewardtypes "github.com/ivanovslavy/GembaBlockchain/chain/x/tailreward/types"
	"github.com/ivanovslavy/GembaBlockchain/chain/x/wiring"
)

// the order the (patched) evmd app.go actually resolves — other modules interleave.
func goodOrder() []string {
	return []string{
		"mint", "ibc", "transfer", "erc20", "feemarket", "evm",
		feesplittypes.ModuleName, rewardstreamertypes.ModuleName, tailrewardtypes.ModuleName,
		distrtypes.ModuleName, "slashing", "evidence", "staking", "auth", "bank", "gov",
	}
}

func TestValidateBeginBlockOrder_Good(t *testing.T) {
	require.NoError(t, wiring.ValidateBeginBlockOrder(goodOrder()))
}

func TestValidateBeginBlockOrder_Violations(t *testing.T) {
	// distribution running BEFORE the money-routing chain (the exact L1 scenario).
	bad := []string{
		"mint", distrtypes.ModuleName,
		feesplittypes.ModuleName, rewardstreamertypes.ModuleName, tailrewardtypes.ModuleName,
	}
	require.ErrorContains(t, wiring.ValidateBeginBlockOrder(bad), "must run before")

	// rewardstreamer streaming before feesplit splits the previous block's fees.
	bad = goodOrder()
	bad[6], bad[7] = bad[7], bad[6] // swap feesplit <-> rewardstreamer
	require.ErrorContains(t, wiring.ValidateBeginBlockOrder(bad), "must run before")

	// a module missing from the order entirely.
	var missing []string
	for _, m := range goodOrder() {
		if m != tailrewardtypes.ModuleName {
			missing = append(missing, m)
		}
	}
	require.ErrorContains(t, wiring.ValidateBeginBlockOrder(missing), "missing")

	// a duplicate entry (would run twice).
	require.ErrorContains(t,
		wiring.ValidateBeginBlockOrder(append(goodOrder(), feesplittypes.ModuleName)),
		"twice")
}
