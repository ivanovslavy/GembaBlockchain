package valgate_test

import (
	"context"
	"testing"

	"cosmossdk.io/math"
	sdk "github.com/cosmos/cosmos-sdk/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"
	"github.com/stretchr/testify/require"

	"github.com/ivanovslavy/GembaBlockchain/chain/x/valgate/keeper"
)

// mockStakingMsgServer counts Delegate/BeginRedelegate pass-throughs; embedding the interface
// satisfies stakingtypes.MsgServer (only the two overridden methods are exercised).
type mockStakingMsgServer struct {
	stakingtypes.MsgServer
	delegateCalls int
	redelegCalls  int
}

func (m *mockStakingMsgServer) Delegate(context.Context, *stakingtypes.MsgDelegate) (*stakingtypes.MsgDelegateResponse, error) {
	m.delegateCalls++
	return &stakingtypes.MsgDelegateResponse{}, nil
}

func (m *mockStakingMsgServer) BeginRedelegate(context.Context, *stakingtypes.MsgBeginRedelegate) (*stakingtypes.MsgBeginRedelegateResponse, error) {
	m.redelegCalls++
	return &stakingtypes.MsgBeginRedelegateResponse{}, nil
}

// SEC audit M1: the daily-bond cap is enforced on the precompile path by wrapping the staking
// MsgServer the precompile calls. Prove the wrapper rejects an over-cap delegate/redelegate BEFORE
// the inner server, and lets an under-cap one through.
func TestCapEnforcingStakingMsgServer_EnforcesDailyCap(t *testing.T) {
	ctx, k := setupKeeper(t) // DefaultParams → 50 GMB/day cap active
	g := math.NewIntFromUint64(1_000_000_000_000_000_000)
	val := sdk.ValAddress([]byte("val_address_20bytes!")).String()
	dst := sdk.ValAddress([]byte("dst_address_20bytes!")).String()

	inner := &mockStakingMsgServer{}
	srv := keeper.NewCapEnforcingStakingMsgServer(inner, k)

	del := func(gmb int64) *stakingtypes.MsgDelegate {
		return &stakingtypes.MsgDelegate{ValidatorAddress: val, Amount: sdk.NewCoin("agmb", math.NewInt(gmb).Mul(g))}
	}

	// 40 GMB — under the 50/day cap → passes through to the inner server.
	_, err := srv.Delegate(ctx, del(40))
	require.NoError(t, err)
	require.Equal(t, 1, inner.delegateCalls)

	// +20 GMB (day total 60 > 50) → REJECTED before the inner server (this is the fixed bypass).
	_, err = srv.Delegate(ctx, del(20))
	require.Error(t, err)
	require.Equal(t, 1, inner.delegateCalls, "over-cap precompile delegate must be blocked before the inner staking server")

	// A single 60 GMB redelegate to a fresh dst validator is also rejected up front.
	redel := &stakingtypes.MsgBeginRedelegate{
		ValidatorSrcAddress: val, ValidatorDstAddress: dst,
		Amount: sdk.NewCoin("agmb", math.NewInt(60).Mul(g)),
	}
	_, err = srv.BeginRedelegate(ctx, redel)
	require.Error(t, err)
	require.Equal(t, 0, inner.redelegCalls, "over-cap precompile redelegate must be blocked before the inner staking server")
}
